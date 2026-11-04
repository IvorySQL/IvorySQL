/*-------------------------------------------------------------------------
 *
 * parse_unpivot.c
 *	  parse analysis for Oracle-compatible UNPIVOT
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/backend/parser/parse_unpivot.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "mb/pg_wchar.h"
#include "nodes/bitmapset.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/parsenodes.h"
#include "nodes/primnodes.h"
#include "optimizer/clauses.h"
#include "optimizer/optimizer.h"
#include "parser/analyze.h"
#include "parser/parse_clause.h"
#include "parser/parse_coerce.h"
#include "parser/parse_node.h"
#include "parser/parse_relation.h"
#include "parser/parse_type.h"
#include "parser/scansup.h"
#include "rewrite/rewriteManip.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/ora_compatible.h"
#include "utils/syscache.h"
#include "utils/timestamp.h"

typedef struct UnpivotItemInfo
{
	List	   *attnos;			/* INTEGER list of source columns */
	List	   *types;			/* OID list of source column types */
	List	   *collids;		/* OID list of source column collations */
	List	   *typmods;		/* INTEGER list of source column typmods */
	List	   *labels;			/* one label expression per descriptor */
	List	   *label_types;	/* OID list of label expression types */
	List	   *label_collids;	/* OID list of label expression collations */
	List	   *label_typmods;	/* INTEGER list of label typmods */
	bool		implicit_labels;	/* labels derived from value column names */
	ParseLoc	location;
} UnpivotItemInfo;

typedef enum UnpivotStringFamily
{
	UNPIVOT_STRING_NONE,
	UNPIVOT_STRING_BOUNDED,
	UNPIVOT_STRING_NCHAR_BOUNDED,
	UNPIVOT_STRING_CLOB,
	UNPIVOT_STRING_NCLOB
} UnpivotStringFamily;

/* DSINTERVAL typmods use the high byte for days and low byte for seconds. */
#define UNPIVOT_DSINTERVAL_RANGE_MASK		0x7FFF
#define UNPIVOT_DSINTERVAL_PRECISION_MASK	0xFF

/* Maximum declared length for Oracle CHAR and VARCHAR2 types. */
#define UNPIVOT_MAX_CHAR_LENGTH				32767

static SelectStmt *makeUnpivotSourceSelect(Node *source);
static SelectStmt *makeUnpivotBranch(RangeUnpivot *ru,
									 UnpivotItemInfo *item,
									 const char *source_alias,
									 Oid *descriptor_types,
									 Oid *measure_types,
									 int32 *descriptor_typmods,
									 int32 *measure_typmods,
									 bool *descriptor_nchar,
									 bool *measure_nchar);
static SelectStmt *makeUnpivotUnion(List *branches);
static Node *makeUnpivotNullFilter(const char *source_alias, List *attnos,
								   ParseLoc location);
static NullTest *makeUnpivotNotNullTest(Node *arg, ParseLoc location);
static ColumnRef *makeUnpivotColumnRef(const char *relname,
									   const char *colname,
									   ParseLoc location);
static ResTarget *makeUnpivotTarget(Node *val, const char *name,
									ParseLoc location);
static void appendUnpivotTarget(List **targetlist, const char *relname,
								const char *colname, const char *name,
								ParseLoc location);
static Node *makeUnpivotCast(Node *arg, Oid type, int32 typmod,
							 ParseLoc location);
static Node *makeUnpivotCollate(Node *arg, ParseLoc location);
static char *getUnpivotColumnName(ParseState *pstate, Node *value,
								  ParseLoc location);
static List *makeUnpivotImplicitLabels(ParseState *pstate,
									   RangeUnpivot *ru,
									   RangeUnpivotInItem *item);
static List *getUnpivotExplicitLabels(ParseState *pstate,
									  RangeUnpivot *ru,
									  RangeUnpivotInItem *item);
static Oid	analyzeUnpivotLabel(ParseState *pstate, Node *label,
								ParseLoc location, bool *is_null,
								int32 *typmod, Oid *collid);
static bool unpivotLabelNonconstantWalker(Node *node, void *context);
static Oid	selectUnpivotCommonType(ParseState *pstate, List *types,
									List *collids, ParseLoc location,
									bool label_context, Oid nchar_collid,
									bool *is_nchar);
static int32 selectUnpivotCommonTypmod(Oid common_type, List *types,
									   List *typmods);
static UnpivotStringFamily classifyUnpivotStringType(Oid type, Oid base,
													 Oid collid,
													 bool label_context,
													 Oid nchar_collid);
static Oid	getUnpivotBaseTypeAndTypmod(Oid type, int32 *typmod);
static int	findUnpivotSourceColumn(List *targetlist, const char *name);
static void checkUnpivotOutputName(ParseState *pstate, List **names,
								   const char *name, ParseLoc location);

/*
 * transformRangeUnpivot
 *		Transform a raw RangeUnpivot into a subquery RTE.
 *
 * The source is read once and each IN item becomes one branch of a lateral
 * UNION ALL.  UNPIVOT clauses are represented as nested RangeUnpivot nodes,
 * so a later clause naturally consumes the output of an earlier one.
 */
ParseNamespaceItem *
transformRangeUnpivot(ParseState *pstate, RangeUnpivot *ru)
{
	SelectStmt *source_query;
	Query	   *analyzed_source;
	List	   *items = NIL;
	Bitmapset  *all_attnos = NULL;
	List	   *branches = NIL;
	List	   *output_names = NIL;
	ListCell   *lc;
	int			natts;
	int			nmeasures;
	int			ndescriptors;
	char	   *source_alias = "unpivot_source";
	char	   *values_alias = "unpivot_values";
	Oid			nchar_collid = get_oracle_nchar_collation_oid(true);

	/* Analyze the source once and reuse the resulting Query below. */
	source_query = makeUnpivotSourceSelect(copyObject(ru->source));
	analyzed_source = parse_sub_analyze((Node *) source_query, pstate,
										NULL, false, true);

	/*
	 * The source Query is embedded one level below the Query built here, so
	 * references to its parent ParseState must move outward by one level.
	 */
	IncrementVarSublevelsUp((Node *) analyzed_source, 1, 1);

	natts = 0;
	foreach(lc, analyzed_source->targetList)
	{
		TargetEntry *tle = lfirst_node(TargetEntry, lc);

		if (tle->resjunk)
			continue;
		natts++;
	}

	if (natts == 0)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("UNPIVOT source must expose at least one column"),
				 parser_errposition(pstate, ru->location)));

	nmeasures = list_length(ru->measure_names);
	ndescriptors = list_length(ru->descriptor_names);

	/*
	 * Resolve each IN item against the source output.  Each tuple must have
	 * one source column for every measure.
	 */
	foreach(lc, ru->items)
	{
		RangeUnpivotInItem *item = lfirst_node(RangeUnpivotInItem, lc);
		UnpivotItemInfo *info = palloc0(sizeof(UnpivotItemInfo));
		ListCell   *value_lc;

		if (list_length(item->value_columns) != nmeasures)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("UNPIVOT IN tuple has %d columns, expected %d",
							list_length(item->value_columns), nmeasures),
					 parser_errposition(pstate, item->location)));

		foreach(value_lc, item->value_columns)
		{
			char	   *colname;
			int			source_attno;
			TargetEntry *source_tle;
			Oid			type;
			int32		typmod;

			colname = getUnpivotColumnName(pstate, lfirst(value_lc),
										   item->location);
			source_attno = findUnpivotSourceColumn(analyzed_source->targetList,
												   colname);
			if (source_attno == 0)
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_COLUMN),
						 errmsg("column \"%s\" does not exist in UNPIVOT source",
								colname),
						 parser_errposition(pstate, item->location)));
			if (source_attno < 0)
				ereport(ERROR,
						(errcode(ERRCODE_AMBIGUOUS_COLUMN),
						 errmsg("column reference \"%s\" is ambiguous in UNPIVOT source",
								colname),
						 parser_errposition(pstate, item->location)));

			info->attnos = lappend_int(info->attnos, source_attno);
			source_tle = lfirst_node(TargetEntry,
									 list_nth_cell(analyzed_source->targetList,
												   source_attno - 1));
			type = exprType((Node *) source_tle->expr);
			typmod = exprTypmod((Node *) source_tle->expr);
			type = getUnpivotBaseTypeAndTypmod(type, &typmod);
			info->types = lappend_oid(info->types, type);
			info->typmods = lappend_int(info->typmods, typmod);
			info->collids = lappend_oid(info->collids,
										exprCollation((Node *) source_tle->expr));
			all_attnos = bms_add_member(all_attnos, source_attno);
		}

		info->location = item->location;
		if (item->labels == NIL)
		{
			info->labels = makeUnpivotImplicitLabels(pstate, ru, item);
			info->implicit_labels = true;
		}
		else
			info->labels = getUnpivotExplicitLabels(pstate, ru, item);
		foreach(value_lc, info->labels)
		{
			bool		is_null;
			Oid			label_type;
			Oid			label_collid;
			int32		label_typmod;

			label_type = analyzeUnpivotLabel(pstate, lfirst(value_lc),
											 item->location, &is_null,
											 &label_typmod, &label_collid);

			/*
			 * An untyped NULL can adopt the common type of the other labels.
			 * A non-NULL unknown literal is a character value instead; use an
			 * invalid OID only as an internal marker for the former.
			 */
			if (is_null && label_type == UNKNOWNOID)
				label_type = InvalidOid;
			info->label_types = lappend_oid(info->label_types, label_type);
			info->label_collids = lappend_oid(info->label_collids,
											  label_collid);
			info->label_typmods = lappend_int(info->label_typmods,
											  label_typmod);
		}
		items = lappend(items, info);
	}

	{
		Oid		   *descriptor_types =
			palloc(sizeof(Oid) * ndescriptors);
		Oid		   *measure_types = palloc(sizeof(Oid) * nmeasures);
		int32	   *descriptor_typmods =
			palloc(sizeof(int32) * ndescriptors);
		int32	   *measure_typmods =
			palloc(sizeof(int32) * nmeasures);
		bool	   *descriptor_nchar =
			palloc0(sizeof(bool) * ndescriptors);
		bool	   *measure_nchar =
			palloc0(sizeof(bool) * nmeasures);
		int			j;

		for (j = 0; j < ndescriptors; j++)
		{
			List	   *types = NIL;
			List	   *collids = NIL;
			List	   *typmods = NIL;
			ListCell   *item_lc;
			bool		all_implicit = true;

			foreach(item_lc, items)
			{
				UnpivotItemInfo *item = lfirst(item_lc);

				if (!item->implicit_labels)
					all_implicit = false;
				types = lappend_oid(types,
									list_nth_oid(item->label_types, j));
				collids = lappend_oid(collids,
									  list_nth_oid(item->label_collids, j));
				typmods = lappend_int(typmods,
									  list_nth_int(item->label_typmods,
												   j));
			}
			descriptor_types[j] =
				selectUnpivotCommonType(pstate, types, collids,
										ru->location, true, nchar_collid,
										&descriptor_nchar[j]);
			if (all_implicit &&
				(descriptor_types[j] == ORAVARCHARBYTEOID ||
				 descriptor_types[j] == ORAVARCHARCHAROID))
				descriptor_types[j] =
					nls_length_semantics == NLS_LENGTH_CHAR ?
					ORACHARCHAROID : ORACHARBYTEOID;
			descriptor_typmods[j] =
				selectUnpivotCommonTypmod(descriptor_types[j],
										  types, typmods);
		}

		for (j = 0; j < nmeasures; j++)
		{
			List	   *types = NIL;
			List	   *collids = NIL;
			List	   *typmods = NIL;
			ListCell   *item_lc;

			foreach(item_lc, items)
			{
				UnpivotItemInfo *item = lfirst(item_lc);

				types = lappend_oid(types, list_nth_oid(item->types, j));
				collids = lappend_oid(collids,
									  list_nth_oid(item->collids, j));
				typmods = lappend_int(typmods,
									  list_nth_int(item->typmods, j));
			}
			measure_types[j] =
				selectUnpivotCommonType(pstate, types, collids,
										ru->location, false, nchar_collid,
										&measure_nchar[j]);
			measure_typmods[j] =
				selectUnpivotCommonTypmod(measure_types[j],
										  types, typmods);
		}

		foreach(lc, items)
		{
			UnpivotItemInfo *item = lfirst(lc);

			branches = lappend(branches,
							   makeUnpivotBranch(ru, item, source_alias,
												 descriptor_types,
												 measure_types,
												 descriptor_typmods,
												 measure_typmods,
												 descriptor_nchar,
												 measure_nchar));
		}
	}

	{
		RangeSubselect *values_rte = makeNode(RangeSubselect);
		SelectStmt *final_select = makeNode(SelectStmt);
		ParseState *final_pstate;
		ParseNamespaceItem *source_nsitem;
		Alias	   *source_rt_alias;
		Query	   *query;
		List	   *values_colnames = NIL;
		List	   *generated_names = NIL;
		int			source_attno;
		int			i;

		for (i = 1; i <= ndescriptors; i++)
			values_colnames = lappend(values_colnames,
									  makeString(psprintf("unpivot_key%d", i)));
		for (i = 1; i <= nmeasures; i++)
			values_colnames = lappend(values_colnames,
									  makeString(psprintf("unpivot_value%d", i)));

		values_rte->lateral = true;
		values_rte->subquery = (Node *) makeUnpivotUnion(branches);
		values_rte->alias = makeAlias(values_alias, values_colnames);
		source_attno = 0;

		for (i = 1; i <= natts; i++)
			generated_names = lappend(generated_names,
									  makeString(psprintf("unpivot_c%d", i)));

		/*
		 * Add the already analyzed source to the final Query's parse state.
		 * This avoids re-running parse analysis for every enclosing UNPIVOT
		 * clause, which would otherwise grow exponentially with the length of
		 * a chained UNPIVOT expression.
		 */
		final_pstate = make_parsestate(pstate);
		final_pstate->p_resolve_unknowns = true;
		source_rt_alias = makeAlias(source_alias, generated_names);
		source_nsitem = addRangeTableEntryForSubquery(
													  final_pstate,
													  analyzed_source,
													  source_rt_alias,
													  false,
													  true);
		addNSItemToQuery(final_pstate, source_nsitem, true, true, true);

		/*
		 * Preserve all source columns not named in any IN tuple.  The
		 * generated aliases avoid problems with quoted or duplicate source
		 * names.
		 */
		foreach(lc, analyzed_source->targetList)
		{
			TargetEntry *tle = lfirst_node(TargetEntry, lc);

			if (tle->resjunk)
				continue;
			source_attno++;
			if (bms_is_member(source_attno, all_attnos))
				continue;

			checkUnpivotOutputName(pstate, &output_names, tle->resname,
								   ru->location);
			appendUnpivotTarget(&final_select->targetList,
								source_alias,
								psprintf("unpivot_c%d", source_attno),
								tle->resname,
								ru->location);
		}

		i = 0;
		foreach(lc, ru->descriptor_names)
		{
			const char *name = strVal(lfirst(lc));

			i++;
			checkUnpivotOutputName(pstate, &output_names, name,
								   ru->location);
			appendUnpivotTarget(&final_select->targetList,
								values_alias,
								psprintf("unpivot_key%d", i),
								name,
								ru->location);
		}

		i = 0;
		foreach(lc, ru->measure_names)
		{
			const char *name = strVal(lfirst(lc));

			i++;
			checkUnpivotOutputName(pstate, &output_names, name,
								   ru->location);
			appendUnpivotTarget(&final_select->targetList,
								values_alias,
								psprintf("unpivot_value%d", i),
								name,
								ru->location);
		}

		final_select->fromClause = list_make1(values_rte);

		query = transformStmt(final_pstate, (Node *) final_select);
		free_parsestate(final_pstate);
		return addRangeTableEntryForSubquery(pstate, query, ru->alias,
											 false, true);
	}
}

/*
 * checkUnpivotZeroLengthColumns
 *		Reject zero-length descriptor columns in Oracle CTAS.
 *
 * An UNPIVOT descriptor whose labels are all NULL remains usable in a SELECT,
 * where its type is VARCHAR2 with VARHDRSZ as the typmod.  Oracle cannot create
 * a table column from that type, so validate the transformed target list before
 * CTAS proceeds.
 */
void
checkUnpivotZeroLengthColumns(const Query *query)
{
	ListCell   *lc;

	foreach(lc, query->targetList)
	{
		TargetEntry *tle = lfirst_node(TargetEntry, lc);
		Oid			type;

		if (tle->resjunk)
			continue;
		type = exprType((Node *) tle->expr);
		if (exprTypmod((Node *) tle->expr) == VARHDRSZ &&
			(type == ORAVARCHARBYTEOID || type == ORAVARCHARCHAROID))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TABLE_DEFINITION),
					 errmsg("zero-length columns are not allowed")));
	}
}

static SelectStmt *
makeUnpivotSourceSelect(Node *source)
{
	SelectStmt *select = makeNode(SelectStmt);
	ColumnRef  *star = makeNode(ColumnRef);
	ResTarget  *target = makeNode(ResTarget);

	star->fields = list_make1(makeNode(A_Star));
	star->location = -1;
	target->val = (Node *) star;
	target->location = -1;
	select->targetList = list_make1(target);
	select->fromClause = list_make1(source);
	return select;
}

static SelectStmt *
makeUnpivotBranch(RangeUnpivot *ru, UnpivotItemInfo *item,
				  const char *source_alias, Oid *descriptor_types,
				  Oid *measure_types, int32 *descriptor_typmods,
				  int32 *measure_typmods, bool *descriptor_nchar,
				  bool *measure_nchar)
{
	SelectStmt *branch = makeNode(SelectStmt);
	ListCell   *lc;
	int			i;

	i = 0;
	foreach(lc, item->labels)
	{
		Node	   *value;

		i++;
		value = makeUnpivotCast(copyObject(lfirst(lc)),
								descriptor_types[i - 1],
								descriptor_typmods[i - 1],
								item->location);
		if (descriptor_nchar[i - 1])
			value = makeUnpivotCollate(value, item->location);
		branch->targetList = lappend(branch->targetList,
									 makeUnpivotTarget(value,
													   psprintf("unpivot_key%d", i),
													   item->location));
	}

	i = 0;
	foreach(lc, item->attnos)
	{
		Node	   *value;
		int			attno = lfirst_int(lc);

		i++;
		value = makeUnpivotCast((Node *) makeUnpivotColumnRef(
															  source_alias,
															  psprintf("unpivot_c%d", attno),
															  item->location),
								measure_types[i - 1],
								measure_typmods[i - 1],
								item->location);
		if (measure_nchar[i - 1])
			value = makeUnpivotCollate(value, item->location);
		branch->targetList = lappend(branch->targetList,
									 makeUnpivotTarget(value,
													   psprintf("unpivot_value%d", i),
													   item->location));
	}

	if (!ru->include_nulls)
		branch->whereClause = makeUnpivotNullFilter(source_alias,
													item->attnos,
													ru->location);
	return branch;
}

static SelectStmt *
makeUnpivotUnion(List *branches)
{
	SelectStmt *result;
	ListCell   *lc;

	Assert(branches != NIL);
	result = linitial_node(SelectStmt, branches);
	for_each_from(lc, branches, 1)
	{
		SelectStmt *setop = makeNode(SelectStmt);

		setop->op = SETOP_UNION;
		setop->all = true;
		setop->larg = result;
		setop->rarg = lfirst_node(SelectStmt, lc);
		result = setop;
	}
	return result;
}

static Node *
makeUnpivotNullFilter(const char *source_alias, List *attnos,
					  ParseLoc location)
{
	List	   *tests = NIL;
	ListCell   *lc;

	foreach(lc, attnos)
	{
		Node	   *ref = (Node *) makeUnpivotColumnRef(
														source_alias, psprintf("unpivot_c%d", lfirst_int(lc)), location);

		tests = lappend(tests, makeUnpivotNotNullTest(ref, location));
	}
	Assert(tests != NIL);
	return (Node *) makeBoolExpr(OR_EXPR, tests, location);
}

static NullTest *
makeUnpivotNotNullTest(Node *arg, ParseLoc location)
{
	NullTest   *test = makeNode(NullTest);

	test->arg = (Expr *) arg;
	test->nulltesttype = IS_NOT_NULL;
	test->argisrow = false;
	test->location = location;
	return test;
}

static ColumnRef *
makeUnpivotColumnRef(const char *relname, const char *colname,
					 ParseLoc location)
{
	ColumnRef  *ref = makeNode(ColumnRef);

	if (relname != NULL)
		ref->fields = list_make2(makeString(pstrdup(relname)),
								 makeString(pstrdup(colname)));
	else
		ref->fields = list_make1(makeString(pstrdup(colname)));
	ref->location = location;
	return ref;
}

static ResTarget *
makeUnpivotTarget(Node *val, const char *name, ParseLoc location)
{
	ResTarget  *target = makeNode(ResTarget);

	target->val = val;
	target->name = name ? pstrdup(name) : NULL;
	target->indirection = NIL;
	target->location = location;
	return target;
}

static void
appendUnpivotTarget(List **targetlist, const char *relname,
					const char *colname, const char *name,
					ParseLoc location)
{
	Node	   *ref = (Node *) makeUnpivotColumnRef(relname, colname,
													location);

	*targetlist = lappend(*targetlist,
						  makeUnpivotTarget(ref, name, location));
}

static Node *
makeUnpivotCast(Node *arg, Oid type, int32 typmod, ParseLoc location)
{
	TypeCast   *cast = makeNode(TypeCast);

	cast->arg = arg;
	cast->typeName = makeTypeNameFromOid(type, typmod);
	cast->location = location;
	return (Node *) cast;
}

static Node *
makeUnpivotCollate(Node *arg, ParseLoc location)
{
	CollateClause *collate = makeNode(CollateClause);

	collate->arg = arg;
	collate->collname = list_make2(makeString("sys"),
								   makeString("nchar_cs"));
	collate->location = location;
	return (Node *) collate;
}

static char *
getUnpivotColumnName(ParseState *pstate, Node *value, ParseLoc location)
{
	ColumnRef  *ref;
	Node	   *field;

	if (!IsA(value, ColumnRef))
		elog(ERROR, "invalid UNPIVOT value column");
	ref = castNode(ColumnRef, value);
	if (list_length(ref->fields) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("UNPIVOT value must be a simple column name"),
				 parser_errposition(pstate, location)));
	field = linitial(ref->fields);
	if (!IsA(field, String))
		elog(ERROR, "invalid UNPIVOT value column");
	return strVal(field);
}

static List *
makeUnpivotImplicitLabels(ParseState *pstate, RangeUnpivot *ru,
						  RangeUnpivotInItem *item)
{
	StringInfoData label;
	List	   *labels = NIL;
	ListCell   *lc;
	int			i;

	initStringInfo(&label);
	foreach(lc, item->value_columns)
	{
		ColumnRef  *ref = castNode(ColumnRef, lfirst(lc));
		const char *name = strVal(linitial(ref->fields));
		const char *source = pstate->p_sourcetext;
		bool		quoted = false;

		if (source != NULL && ref->location >= 0)
		{
			const char *token = source + ref->location;

			quoted = token[0] == '"' ||
				((token[0] == 'u' || token[0] == 'U') &&
				 token[1] == '&' && token[2] == '"');
		}

		if (label.len > 0)
			appendStringInfoChar(&label, '_');
		if (quoted)
			appendStringInfoString(&label, name);
		else
			appendStringInfoString(&label,
								   upcase_identifier(name, strlen(name),
													 false, true));
	}

	for (i = 0; i < list_length(ru->descriptor_names); i++)
		labels = lappend(labels,
						 makeStringConst(pstrdup(label.data), item->location));
	return labels;
}

static List *
getUnpivotExplicitLabels(ParseState *pstate, RangeUnpivot *ru,
						 RangeUnpivotInItem *item)
{
	Node	   *label = linitial(item->labels);
	List	   *labels;

	if (IsA(label, RowExpr))
		labels = castNode(RowExpr, label)->args;
	else
		labels = list_make1(label);

	if (list_length(labels) != list_length(ru->descriptor_names))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("UNPIVOT label list has %d values, expected %d",
						list_length(labels),
						list_length(ru->descriptor_names)),
				 parser_errposition(pstate, item->location)));
	return labels;
}

static Oid
analyzeUnpivotLabel(ParseState *pstate, Node *label, ParseLoc location,
					bool *is_null, int32 *typmod, Oid *collid)
{
	SelectStmt *select = makeNode(SelectStmt);
	ResTarget  *target = makeNode(ResTarget);
	ParseState *label_pstate;
	Query	   *query;
	TargetEntry *tle;
	Node	   *expr;
	Oid			type;

	target->val = copyObject(label);
	target->location = location;
	select->targetList = list_make1(target);

	label_pstate = make_parsestate(NULL);
	label_pstate->p_sourcetext = pstate->p_sourcetext;
	query = parse_sub_analyze((Node *) select, label_pstate, NULL,
							  false, false);
	tle = linitial_node(TargetEntry, query->targetList);
	expr = (Node *) tle->expr;

	if (query->hasAggs ||
		query->hasWindowFuncs ||
		query->hasTargetSRFs ||
		contain_var_clause(expr) ||
		contain_subplans(expr) ||
		contain_mutable_functions(expr) ||
		unpivotLabelNonconstantWalker(expr, NULL))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("non-constant expression is not allowed for UNPIVOT labels"),
				 parser_errposition(pstate, location)));

	type = exprType(expr);
	*is_null = IsA(expr, Const) && castNode(Const, expr)->constisnull;
	*typmod = exprTypmod(expr);
	*collid = exprCollation(expr);

	/*
	 * Unknown literals have no typmod, but their contents determine the
	 * descriptor width.  Record that width so the common string typmod does
	 * not unnecessarily fall back to an unbounded VARCHAR2.
	 */
	if (type == UNKNOWNOID && !*is_null && IsA(expr, Const))
	{
		char	   *value = DatumGetCString(castNode(Const, expr)->constvalue);
		int			length;

		length = nls_length_semantics == NLS_LENGTH_CHAR ?
			pg_mbstrlen(value) : strlen(value);
		*typmod = VARHDRSZ + length;
	}
	else if (type != UNKNOWNOID)
		type = getUnpivotBaseTypeAndTypmod(type, typmod);
	free_parsestate(label_pstate);
	return type;
}

static bool
unpivotLabelNonconstantWalker(Node *node, void *context)
{
	if (node == NULL)
		return false;

	switch (nodeTag(node))
	{
		case T_SQLValueFunction:
		case T_Param:
		case T_SubLink:
		case T_CurrentOfExpr:
		case T_NextValueExpr:
		case T_RownumExpr:
			return true;
		default:
			return expression_tree_walker(node, unpivotLabelNonconstantWalker,
										  context);
	}
}

static Oid
selectUnpivotCommonType(ParseState *pstate, List *types, List *collids,
						ParseLoc location, bool label_context,
						Oid nchar_collid, bool *is_nchar)
{
	TYPCATEGORY category = 0;
	bool		have_float = false;
	bool		have_double = false;
	bool		have_timestamp = false;
	bool		have_timestamptz = false;
	bool		have_timestampltz = false;
	bool		have_time = false;
	bool		have_timetz = false;
	bool		have_date = false;
	bool		have_unknown = false;
	bool		have_oracle_datetime = false;
	bool		have_raw = false;
	bool		have_long_raw = false;
	bool		have_blob = false;
	bool		have_yminterval = false;
	bool		have_dsinterval = false;
	bool		have_interval = false;
	UnpivotStringFamily string_family = UNPIVOT_STRING_NONE;
	Oid			first_base = InvalidOid;
	ListCell   *type_lc;
	ListCell   *collid_lc;

	Assert(types != NIL);
	Assert(list_length(types) == list_length(collids));
	*is_nchar = false;

	forboth(type_lc, types, collid_lc, collids)
	{
		Oid			type = lfirst_oid(type_lc);
		Oid			collid = lfirst_oid(collid_lc);
		Oid			base;
		int32		typmod = -1;
		TYPCATEGORY base_category;
		bool		preferred;

		if (type == InvalidOid)
			continue;
		base = getUnpivotBaseTypeAndTypmod(type, &typmod);
		if (base == UNKNOWNOID)
		{
			have_unknown = true;
			continue;
		}

		get_type_category_preferred(base, &base_category, &preferred);
		if (category == 0)
		{
			category = base_category;
			first_base = base;
		}
		else if (category != base_category)
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("UNPIVOT types %s and %s cannot be matched",
							format_type_be(first_base), format_type_be(base)),
					 parser_errposition(pstate, location)));

		if (base_category == TYPCATEGORY_STRING)
		{
			UnpivotStringFamily family;

			family = classifyUnpivotStringType(type, base, collid,
											   label_context, nchar_collid);
			if (string_family == UNPIVOT_STRING_NONE)
				string_family = family;
			else if (string_family != family)
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg((string_family == UNPIVOT_STRING_NCHAR_BOUNDED ||
								 family == UNPIVOT_STRING_NCHAR_BOUNDED) ?
								"UNPIVOT character sets cannot be matched" :
								"UNPIVOT character types cannot be matched"),
						 parser_errposition(pstate, location)));
		}
		else if (base_category == TYPCATEGORY_NUMERIC)
		{
			if (base == BINARY_DOUBLEOID || base == FLOAT8OID)
				have_double = true;
			else if (base == BINARY_FLOATOID || base == FLOAT4OID)
				have_float = true;
		}
		else if (base_category == TYPCATEGORY_DATETIME)
		{
			if (base == TIMESTAMPTZOID || base == ORATIMESTAMPTZOID)
				have_timestamptz = true;
			else if (base == ORATIMESTAMPLTZOID)
				have_timestampltz = true;
			else if (base == TIMESTAMPOID || base == ORATIMESTAMPOID)
				have_timestamp = true;
			else if (base == TIMEOID)
				have_time = true;
			else if (base == TIMETZOID)
				have_timetz = true;
			else if (base == DATEOID || base == ORADATEOID)
				have_date = true;
			if (base == ORADATEOID ||
				base == ORATIMESTAMPOID ||
				base == ORATIMESTAMPTZOID ||
				base == ORATIMESTAMPLTZOID)
				have_oracle_datetime = true;
		}
		else if (base == RAWOID)
			have_raw = true;
		else if (base == LONG_RAWOID)
			have_long_raw = true;
		else if (base == BLOBOID)
			have_blob = true;
		else if (base == YMINTERVALOID)
			have_yminterval = true;
		else if (base == DSINTERVALOID)
			have_dsinterval = true;
		else if (base == INTERVALOID)
			have_interval = true;
		else
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("UNPIVOT type %s is not supported",
							format_type_be(type)),
					 parser_errposition(pstate, location)));
	}

	/*
	 * An untyped string literal is a character value, not a value that can
	 * adapt to an arbitrary type.  PostgreSQL normally leaves it UNKNOWN and
	 * lets the surrounding expression choose a type, but Oracle rejects a
	 * descriptor label group that mixes character literals with numbers or
	 * dates.  Resolve that ambiguity here, during parse analysis.
	 */
	if (have_unknown && category != 0 &&
		category != TYPCATEGORY_STRING)
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("UNPIVOT character and %s types cannot be matched",
						format_type_be(first_base)),
				 parser_errposition(pstate, location)));

	if (category == 0)
		return nls_length_semantics == NLS_LENGTH_CHAR ?
			ORAVARCHARCHAROID : ORAVARCHARBYTEOID;
	if (category == TYPCATEGORY_NUMERIC)
	{
		if (have_double)
			return BINARY_DOUBLEOID;
		if (have_float)
			return BINARY_FLOATOID;
		return NUMBEROID;
	}
	if (category == TYPCATEGORY_STRING)
	{
		if (string_family == UNPIVOT_STRING_CLOB)
			return CLOBOID;
		if (string_family == UNPIVOT_STRING_NCLOB)
			return NCLOBOID;
		if (string_family == UNPIVOT_STRING_NCHAR_BOUNDED)
			*is_nchar = true;
		return nls_length_semantics == NLS_LENGTH_CHAR ?
			ORAVARCHARCHAROID : ORAVARCHARBYTEOID;
	}
	if (category == TYPCATEGORY_DATETIME)
	{
		if (have_time || have_timetz)
		{
			if (have_timestamp || have_timestamptz ||
				have_timestampltz || have_date)
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg("UNPIVOT date/time types cannot be matched"),
						 parser_errposition(pstate, location)));
			return have_timetz ? TIMETZOID : TIMEOID;
		}
		if (have_timestampltz)
			return ORATIMESTAMPLTZOID;
		if (have_timestamptz)
			return have_oracle_datetime ? ORATIMESTAMPTZOID : TIMESTAMPTZOID;
		if (have_timestamp)
			return have_oracle_datetime ? ORATIMESTAMPOID : TIMESTAMPOID;
		return have_oracle_datetime ? ORADATEOID : DATEOID;
	}
	if (category == TYPCATEGORY_BOOLEAN)
		return BOOLOID;
	if (category == TYPCATEGORY_USER)
	{
		if (have_raw && !have_long_raw && !have_blob)
			return RAWOID;
		if (have_long_raw && !have_raw && !have_blob)
			return LONG_RAWOID;
		if (have_blob && !have_raw && !have_long_raw)
			return BLOBOID;
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("UNPIVOT binary types cannot be matched"),
				 parser_errposition(pstate, location)));
	}
	if (category == TYPCATEGORY_TIMESPAN)
	{
		if (have_yminterval && !have_dsinterval && !have_interval)
			return YMINTERVALOID;
		if (have_dsinterval && !have_yminterval && !have_interval)
			return DSINTERVALOID;
		if (have_interval && !have_yminterval && !have_dsinterval)
			return INTERVALOID;
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("UNPIVOT interval types cannot be matched"),
				 parser_errposition(pstate, location)));
	}

	ereport(ERROR,
			(errcode(ERRCODE_DATATYPE_MISMATCH),
			 errmsg("UNPIVOT types cannot be matched"),
			 parser_errposition(pstate, location)));
	return InvalidOid;
}

static UnpivotStringFamily
classifyUnpivotStringType(Oid type, Oid base, Oid collid,
						  bool label_context, Oid nchar_collid)
{
	if (base == NCLOBOID)
		return UNPIVOT_STRING_NCLOB;
	if (base == CLOBOID || base == LONGOID ||
		(!label_context && base == TEXTOID))
		return UNPIVOT_STRING_CLOB;

	if (base == UNKNOWNOID)
		return UNPIVOT_STRING_NONE;
	if (OidIsValid(nchar_collid) && collid == nchar_collid)
		return UNPIVOT_STRING_NCHAR_BOUNDED;
	return UNPIVOT_STRING_BOUNDED;
}

/*
 * Strip ordinary domains while preserving Oracle's domain-backed types and
 * return the applicable typmod.  RAW, BLOB, CLOB, LONG, LONG RAW, and NCLOB
 * are implemented as domains over PostgreSQL types, but their domain OIDs
 * carry UNPIVOT family semantics.
 */
static Oid
getUnpivotBaseTypeAndTypmod(Oid type, int32 *typmod)
{
	for (;;)
	{
		HeapTuple	tuple;
		Form_pg_type typeform;
		Oid			basetype;

		if (type == RAWOID || type == LONG_RAWOID || type == BLOBOID ||
			type == CLOBOID || type == LONGOID || type == NCLOBOID)
			return type;

		tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(type));
		if (!HeapTupleIsValid(tuple))
			elog(ERROR, "cache lookup failed for type %u", type);
		typeform = (Form_pg_type) GETSTRUCT(tuple);
		if (typeform->typtype != TYPTYPE_DOMAIN)
		{
			ReleaseSysCache(tuple);
			return type;
		}
		if (*typmod < 0)
			*typmod = typeform->typtypmod;
		basetype = typeform->typbasetype;
		ReleaseSysCache(tuple);
		type = basetype;
	}
}

/*
 * Select the common typmod for types whose Oracle result keeps a maximum
 * length or fractional-second precision.  NUMBER precision is deliberately
 * omitted because Oracle drops it for an UNPIVOT measure.
 */
static int32
selectUnpivotCommonTypmod(Oid common_type, List *types, List *typmods)
{
	Oid			base = getBaseType(common_type);
	TYPCATEGORY category;
	bool		preferred;
	int32		result = -1;
	ListCell   *type_lc;
	ListCell   *typmod_lc;
	bool		all_null_labels = true;
	int			first_fields = -1;
	int			max_leading_precision = 0;
	int			max_second_precision = 0;

	foreach(type_lc, types)
	{
		if (lfirst_oid(type_lc) != InvalidOid)
		{
			all_null_labels = false;
			break;
		}
	}
	if (all_null_labels)
		return VARHDRSZ;

	if (common_type == RAWOID || common_type == LONG_RAWOID)
	{
		forboth(type_lc, types, typmod_lc, typmods)
		{
			int32		typmod;

			if (lfirst_oid(type_lc) == InvalidOid)
				continue;
			typmod = lfirst_int(typmod_lc);
			if (typmod < 0)
				return -1;
			if (typmod > result)
				result = typmod;
		}
		return result;
	}

	if (common_type == YMINTERVALOID || common_type == DSINTERVALOID)
	{
		forboth(type_lc, types, typmod_lc, typmods)
		{
			int32		typmod;
			int			fields;
			int			precision;

			if (lfirst_oid(type_lc) == InvalidOid)
				continue;
			typmod = lfirst_int(typmod_lc);
			if (typmod < 0)
				return -1;
			fields = INTERVAL_RANGE(typmod);
			if (first_fields < 0)
				first_fields = fields;
			else if (first_fields != fields)
				return -1;

			if (common_type == YMINTERVALOID)
				precision = INTERVAL_PRECISION(typmod);
			else
				precision = (typmod >> 8) &
					UNPIVOT_DSINTERVAL_PRECISION_MASK;
			if (precision > max_leading_precision)
				max_leading_precision = precision;
			if (common_type == DSINTERVALOID)
			{
				int			second_precision =
					typmod & UNPIVOT_DSINTERVAL_PRECISION_MASK;

				if (second_precision > max_second_precision)
					max_second_precision = second_precision;
			}
		}

		if (common_type == YMINTERVALOID)
			return INTERVAL_TYPMOD(max_leading_precision, first_fields);
		return ((first_fields & UNPIVOT_DSINTERVAL_RANGE_MASK) << 16) |
			((max_leading_precision & UNPIVOT_DSINTERVAL_PRECISION_MASK) << 8) |
			(max_second_precision & UNPIVOT_DSINTERVAL_PRECISION_MASK);
	}

	get_type_category_preferred(base, &category, &preferred);
	(void) preferred;

	if (category == TYPCATEGORY_DATETIME &&
		common_type != DATEOID && common_type != ORADATEOID)
	{
		forboth(type_lc, types, typmod_lc, typmods)
		{
			int32		typmod;

			if (lfirst_oid(type_lc) == InvalidOid)
				continue;
			typmod = lfirst_int(typmod_lc);
			if (typmod < 0)
			{
				Oid			base_type = getBaseType(lfirst_oid(type_lc));

				if (base_type != DATEOID && base_type != ORADATEOID)
					return -1;
				continue;
			}
			if (typmod > result)
				result = typmod;
		}
		return result;
	}

	if (category != TYPCATEGORY_STRING)
		return -1;

	forboth(type_lc, types, typmod_lc, typmods)
	{
		Oid			type;
		int32		typmod;

		type = lfirst_oid(type_lc);
		if (type == InvalidOid)
			continue;
		typmod = lfirst_int(typmod_lc);
		if (typmod < 0)
			return -1;

		/*
		 * CHAR-semantic and BYTE-semantic Oracle types share a typmod
		 * representation but count different units.  Convert a character
		 * bound to a conservative byte bound when the common type is BYTE
		 * based.
		 */
		if (common_type == ORAVARCHARBYTEOID &&
			type != ORACHARBYTEOID && type != ORAVARCHARBYTEOID)
		{
			int			maxlen = pg_database_encoding_max_length();
			int32		charlen = typmod - VARHDRSZ;

			if (charlen > UNPIVOT_MAX_CHAR_LENGTH / maxlen)
				return -1;
			typmod = VARHDRSZ + charlen * maxlen;
		}
		if (typmod > result)
			result = typmod;
	}

	return result;
}

static int
findUnpivotSourceColumn(List *targetlist, const char *name)
{
	ListCell   *lc;
	int			found = 0;

	foreach(lc, targetlist)
	{
		TargetEntry *tle = lfirst_node(TargetEntry, lc);

		if (tle->resjunk || tle->resname == NULL)
			continue;
		if (strcmp(tle->resname, name) == 0)
		{
			if (found != 0)
				return -1;
			found = tle->resno;
		}
	}
	return found;
}

static void
checkUnpivotOutputName(ParseState *pstate, List **names, const char *name,
					   ParseLoc location)
{
	ListCell   *lc;

	foreach(lc, *names)
	{
		if (strcmp((const char *) lfirst(lc), name) == 0)
			ereport(ERROR,
					(errcode(ERRCODE_DUPLICATE_ALIAS),
					 errmsg("UNPIVOT output column \"%s\" specified more than once",
							name),
					 parser_errposition(pstate, location)));
	}
	*names = lappend(*names, pstrdup(name));
}
