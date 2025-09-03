/*-------------------------------------------------------------------------
 *
 * view.c
 *	  use rewrite rules to construct views
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/commands/view.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/relation.h"
#include "access/xact.h"
#include "access/table.h"
#include "catalog/heap.h"
#include "catalog/indexing.h"
#include "catalog/namespace.h"
#include "catalog/pg_force_view.h"
#include "catalog/pg_rewrite.h"		
#include "commands/tablecmds.h"
#include "commands/view.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "parser/analyze.h"
#include "parser/parser.h"
#include "parser/parse_relation.h"
#include "rewrite/rewriteDefine.h"
#include "rewrite/rewriteHandler.h"
#include "rewrite/rewriteSupport.h"
#include "utils/builtins.h"
#include "utils/syscache.h"
#include "utils/lsyscache.h"
#include "utils/guc.h"
#include "utils/ora_compatible.h"
#include "utils/rel.h"
#include "utils/regproc.h"

static void checkViewColumns(TupleDesc newdesc, TupleDesc olddesc);

/*---------------------------------------------------------------------
 * DefineVirtualRelation
 *
 * Create a view relation and use the rules system to store the query
 * for the view.
 *
 * EventTriggerAlterTableStart must have been called already.
 *---------------------------------------------------------------------
 */
static ObjectAddress
DefineVirtualRelation(RangeVar *relation, List *tlist, bool replace,
					  List *options, Query *viewParse)
{
	Oid			viewOid;
	LOCKMODE	lockmode;
	List	   *attrList;
	ListCell   *t;

	/*
	 * create a list of ColumnDef nodes based on the names and types of the
	 * (non-junk) targetlist items from the view's SELECT list.
	 */
	attrList = NIL;
	foreach(t, tlist)
	{
		TargetEntry *tle = (TargetEntry *) lfirst(t);

		if (!tle->resjunk)
		{
			ColumnDef  *def = makeColumnDef(tle->resname,
											exprType((Node *) tle->expr),
											exprTypmod((Node *) tle->expr),
											exprCollation((Node *) tle->expr));

			/*
			 * It's possible that the column is of a collatable type but the
			 * collation could not be resolved, so double-check.
			 */
			if (type_is_collatable(exprType((Node *) tle->expr)))
			{
				if (!OidIsValid(def->collOid))
					ereport(ERROR,
							(errcode(ERRCODE_INDETERMINATE_COLLATION),
							 errmsg("could not determine which collation to use for view column \"%s\"",
									def->colname),
							 errhint("Use the COLLATE clause to set the collation explicitly.")));
			}
			else
				Assert(!OidIsValid(def->collOid));

			attrList = lappend(attrList, def);
		}
	}

	/*
	 * Look up, check permissions on, and lock the creation namespace; also
	 * check for a preexisting view with the same name.  This will also set
	 * relation->relpersistence to RELPERSISTENCE_TEMP if the selected
	 * namespace is temporary.
	 */
	lockmode = replace ? AccessExclusiveLock : NoLock;
	(void) RangeVarGetAndCheckCreationNamespace(relation, lockmode, &viewOid);

	if (ORA_PARSER == compatible_db &&
		OidIsValid(viewOid) &&
		rel_is_force_view(viewOid))
	{
		if (replace)
		{
			ObjectAddress address;

			make_view_valid(tlist, viewOid, options, viewParse);
			ObjectAddressSet(address, RelationRelationId, viewOid);
			return address;
		}
	}

	if (OidIsValid(viewOid) && replace)
	{
		Relation	rel;
		TupleDesc	descriptor;
		List	   *atcmds = NIL;
		AlterTableCmd *atcmd;
		ObjectAddress address;

		/* Relation is already locked, but we must build a relcache entry. */
		rel = relation_open(viewOid, NoLock);

		/* Make sure it *is* a view. */
		if (rel->rd_rel->relkind != RELKIND_VIEW)
			ereport(ERROR,
					(errcode(ERRCODE_WRONG_OBJECT_TYPE),
					 errmsg("\"%s\" is not a view",
							RelationGetRelationName(rel))));

		/* Also check it's not in use already */
		CheckTableNotInUse(rel, "CREATE OR REPLACE VIEW");

		/*
		 * Due to the namespace visibility rules for temporary objects, we
		 * should only end up replacing a temporary view with another
		 * temporary view, and similarly for permanent views.
		 */
		Assert(relation->relpersistence == rel->rd_rel->relpersistence);

		/*
		 * Create a tuple descriptor to compare against the existing view, and
		 * verify that the old column list is an initial prefix of the new
		 * column list.
		 */
		descriptor = BuildDescForRelation(attrList);
		checkViewColumns(descriptor, rel->rd_att);

		/*
		 * If new attributes have been added, we must add pg_attribute entries
		 * for them.  It is convenient (although overkill) to use the ALTER
		 * TABLE ADD COLUMN infrastructure for this.
		 *
		 * Note that we must do this before updating the query for the view,
		 * since the rules system requires that the correct view columns be in
		 * place when defining the new rules.
		 *
		 * Also note that ALTER TABLE doesn't run parse transformation on
		 * AT_AddColumnToView commands.  The ColumnDef we supply must be ready
		 * to execute as-is.
		 */
		if (list_length(attrList) > rel->rd_att->natts)
		{
			ListCell   *c;
			int			skip = rel->rd_att->natts;

			foreach(c, attrList)
			{
				if (skip > 0)
				{
					skip--;
					continue;
				}
				atcmd = makeNode(AlterTableCmd);
				atcmd->subtype = AT_AddColumnToView;
				atcmd->def = (Node *) lfirst(c);
				atcmds = lappend(atcmds, atcmd);
			}

			/* EventTriggerAlterTableStart called by ProcessUtilitySlow */
			AlterTableInternal(viewOid, atcmds, true);

			/* Make the new view columns visible */
			CommandCounterIncrement();
		}

		/*
		 * Update the query for the view.
		 *
		 * Note that we must do this before updating the view options, because
		 * the new options may not be compatible with the old view query (for
		 * example if we attempt to add the WITH CHECK OPTION, we require that
		 * the new view be automatically updatable, but the old view may not
		 * have been).
		 */
		StoreViewQuery(viewOid, viewParse, replace);

		/* Make the new view query visible */
		CommandCounterIncrement();

		/*
		 * Update the view's options.
		 *
		 * The new options list replaces the existing options list, even if
		 * it's empty.
		 */
		atcmd = makeNode(AlterTableCmd);
		atcmd->subtype = AT_ReplaceRelOptions;
		atcmd->def = (Node *) options;
		atcmds = list_make1(atcmd);

		/* EventTriggerAlterTableStart called by ProcessUtilitySlow */
		AlterTableInternal(viewOid, atcmds, true);

		/*
		 * There is very little to do here to update the view's dependencies.
		 * Most view-level dependency relationships, such as those on the
		 * owner, schema, and associated composite type, aren't changing.
		 * Because we don't allow changing type or collation of an existing
		 * view column, those dependencies of the existing columns don't
		 * change either, while the AT_AddColumnToView machinery took care of
		 * adding such dependencies for new view columns.  The dependencies of
		 * the view's query could have changed arbitrarily, but that was dealt
		 * with inside StoreViewQuery.  What remains is only to check that
		 * view replacement is allowed when we're creating an extension.
		 */
		ObjectAddressSet(address, RelationRelationId, viewOid);

		recordDependencyOnCurrentExtension(&address, true);

		/*
		 * Seems okay, so return the OID of the pre-existing view.
		 */
		relation_close(rel, NoLock);	/* keep the lock! */

		return address;
	}
	else
	{
		CreateStmt *createStmt = makeNode(CreateStmt);
		ObjectAddress address;

		/*
		 * Set the parameters for keys/inheritance etc. All of these are
		 * uninteresting for views...
		 */
		createStmt->relation = relation;
		createStmt->tableElts = attrList;
		createStmt->inhRelations = NIL;
		createStmt->constraints = NIL;
		createStmt->options = options;
		createStmt->oncommit = ONCOMMIT_NOOP;
		createStmt->tablespacename = NULL;
		createStmt->if_not_exists = false;

		/*
		 * Create the relation (this will error out if there's an existing
		 * view, so we don't need more code to complain if "replace" is
		 * false).
		 */
		address = DefineRelation(createStmt, RELKIND_VIEW, InvalidOid, NULL,
								 NULL);
		Assert(address.objectId != InvalidOid);

		/* Make the new view relation visible */
		CommandCounterIncrement();

		/* Store the query for the view */
		StoreViewQuery(address.objectId, viewParse, replace);

		return address;
	}
}

/*
 * CreateForceVirtualPlaceholder
 *
 * This function creates a placeholder for a force view. If a view with the same
 * name already exists and is a force view, it simply returns its address. If
 * "replace" is specified, it marks the metadata for update. If the existing view
 * is a regular view, it can be invalidated if "replace" is true, otherwise it
 * does nothing. If no view exists, a new placeholder view is created.
 */
static ObjectAddress
CreateForceVirtualPlaceholder(RangeVar *relation, bool replace, List *options, bool *need_update)
{
	Oid			viewOid;
	LOCKMODE	lockmode;
	CreateStmt *createStmt = makeNode(CreateStmt);
	List	   *attrList;

	/* Force views do not have a target list */
	attrList = NIL;

	/*
	 * Acquire the appropriate lock and check for an existing view in the target
	 * namespace. This also updates relpersistence if the namespace is temporary.
	 */
	lockmode = replace ? AccessExclusiveLock : NoLock;
	(void) RangeVarGetAndCheckCreationNamespace(relation, lockmode, &viewOid);

	/*
	 * If an existing force view is found, return its address.
	 * If "replace" is requested, indicate that metadata should be updated.
	 */
	if (OidIsValid(viewOid) && rel_is_force_view(viewOid))
	{
		ObjectAddress address;

		ObjectAddressSet(address, RelationRelationId, viewOid);
		*need_update = replace;
		return address;
	}

	/* If a regular view exists, handle replacement or return its address */
	if (OidIsValid(viewOid))
	{
		if (replace)
		{
			ObjectAddress address;

			make_view_invalid(viewOid);
			ObjectAddressSet(address, RelationRelationId, viewOid);
			*need_update = true;
			return address;
		}
		else
		{
			ObjectAddress address;

			ObjectAddressSet(address, RelationRelationId, viewOid);
			*need_update = false;
			return address;
		}
	}
	else
	{
		ObjectAddress address;

		/*
		 * Set up the parameters for the new placeholder view.
		 * Keys, inheritance, and constraints are not relevant for force views.
		 */
		createStmt->relation = relation;
		createStmt->tableElts = attrList;
		createStmt->inhRelations = NIL;
		createStmt->constraints = NIL;
		createStmt->options = options;
		createStmt->oncommit = ONCOMMIT_NOOP;
		createStmt->tablespacename = NULL;
		createStmt->if_not_exists = false;

		address = DefineRelation(createStmt, RELKIND_VIEW, InvalidOid, NULL, NULL);
		Assert(address.objectId != InvalidOid);
		*need_update = true;
		return address;
	}
}

/*
 * Verify that the columns associated with proposed new view definition match
 * the columns of the old view.  This is similar to equalRowTypes(), with code
 * added to generate specific complaints.  Also, we allow the new view to have
 * more columns than the old.
 */
static void
checkViewColumns(TupleDesc newdesc, TupleDesc olddesc)
{
	int			i;

	if (newdesc->natts < olddesc->natts)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TABLE_DEFINITION),
				 errmsg("cannot drop columns from view")));

	for (i = 0; i < olddesc->natts; i++)
	{
		Form_pg_attribute newattr = TupleDescAttr(newdesc, i);
		Form_pg_attribute oldattr = TupleDescAttr(olddesc, i);

		/* XXX msg not right, but we don't support DROP COL on view anyway */
		if (newattr->attisdropped != oldattr->attisdropped)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TABLE_DEFINITION),
					 errmsg("cannot drop columns from view")));

		if (strcmp(NameStr(newattr->attname), NameStr(oldattr->attname)) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TABLE_DEFINITION),
					 errmsg("cannot change name of view column \"%s\" to \"%s\"",
							NameStr(oldattr->attname),
							NameStr(newattr->attname)),
					 errhint("Use ALTER VIEW ... RENAME COLUMN ... to change name of view column instead.")));

		/*
		 * We cannot allow type, typmod, or collation to change, since these
		 * properties may be embedded in Vars of other views/rules referencing
		 * this one.  Other column attributes can be ignored.
		 */
		if (newattr->atttypid != oldattr->atttypid ||
			newattr->atttypmod != oldattr->atttypmod)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TABLE_DEFINITION),
					 errmsg("cannot change data type of view column \"%s\" from %s to %s",
							NameStr(oldattr->attname),
							format_type_with_typemod(oldattr->atttypid,
													 oldattr->atttypmod),
							format_type_with_typemod(newattr->atttypid,
													 newattr->atttypmod))));

		/*
		 * At this point, attcollations should be both valid or both invalid,
		 * so applying get_collation_name unconditionally should be fine.
		 */
		if (newattr->attcollation != oldattr->attcollation)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TABLE_DEFINITION),
					 errmsg("cannot change collation of view column \"%s\" from \"%s\" to \"%s\"",
							NameStr(oldattr->attname),
							get_collation_name(oldattr->attcollation),
							get_collation_name(newattr->attcollation))));
	}

	/*
	 * We ignore the constraint fields.  The new view desc can't have any
	 * constraints, and the only ones that could be on the old view are
	 * defaults, which we are happy to leave in place.
	 */
}

static void
DefineViewRules(Oid viewOid, Query *viewParse, bool replace)
{
	/*
	 * Set up the ON SELECT rule.  Since the query has already been through
	 * parse analysis, we use DefineQueryRewrite() directly.
	 */
	DefineQueryRewrite(pstrdup(ViewSelectRuleName),
					   viewOid,
					   NULL,
					   CMD_SELECT,
					   true,
					   replace,
					   list_make1(viewParse));

	/*
	 * Someday: automatic ON INSERT, etc
	 */
}

/*
 * DefineView
 *		Execute a CREATE VIEW command.
 */
ObjectAddress
DefineView(ViewStmt *stmt, const char *queryString,
		   int stmt_location, int stmt_len)
{
	RawStmt    *rawstmt;
	Query	   *viewParse;
	RangeVar   *view;
	ListCell   *cell;
	bool		check_option;
	bool		compile_failed = false;
	ObjectAddress address;

	/*
	 * Run parse analysis to convert the raw parse tree to a Query.  Note this
	 * also acquires sufficient locks on the source table(s).
	 */
	rawstmt = makeNode(RawStmt);
	rawstmt->stmt = stmt->query;
	rawstmt->stmt_location = stmt_location;
	rawstmt->stmt_len = stmt_len;

	PG_TRY();
	{
		viewParse = parse_analyze_fixedparams(rawstmt, queryString, NULL, 0, NULL);
	}
	PG_CATCH();
	{
		if (ORA_PARSER == compatible_db && stmt->force)
		{
			compile_failed = true;
			FlushErrorState();
		}
		else
			PG_RE_THROW();
	}
	PG_END_TRY();


	/*
	 * When a force view fails to compile, handle the following scenarios:
	 *   1. If no view exists with the given name, create a placeholder entry
	 *      in pg_class and record the failed view's metadata in pg_force_view.
	 *   2. If a valid view already exists with the same name, do nothing unless
	 *      the replace option is specified; if replace is requested, overwrite
	 *      the existing view and mark the new force view as invalid.
	 *   3. If an invalid view exists with the same name, do nothing unless
	 *      the replace option is specified; if replace is requested, update
	 *      the metadata in pg_force_view for the new view definition.
	 */
	if (stmt->force && compile_failed)
	{
		bool	need_store;

		/* NOTE: The grammar does not prevent SELECT INTO in this case */
		view = copyObject(stmt->view);		/* avoid modifying the original command */

		address = CreateForceVirtualPlaceholder(view, stmt->replace, stmt->options, &need_store);

		CommandCounterIncrement();

		/* Insert or update the pg_force_view catalog as needed */
		if (need_store)
		{
			char	ident_case;

			if (identifier_case_switch == NORMAL)
				ident_case = IDENT_CASE_NORMAL;
			else if (identifier_case_switch == INTERCHANGE)
				ident_case = IDENT_CASE_INTERCHANGE;
			else if (identifier_case_switch == LOWERCASE)
				ident_case = IDENT_CASE_LOWERCASE;
			else
			{
				/* This branch should not be reached unless identifier_case_switch is extended */
				ident_case = IDENT_CASE_UNDEFINE;	/* silence compiler warning */
				elog(ERROR, "Unexpected identifier_case_switch value");
			}

			StoreForceViewQuery(address.objectId, stmt->replace, ident_case, stmt->stmt_literal ? stmt->stmt_literal : queryString);
		}

		/* Oracle issues a warning in this situation */
		elog(WARNING, "View created with compilation errors");
		return address;
	}

	/*
	 * The grammar should ensure that the result is a single SELECT Query.
	 * However, it doesn't forbid SELECT INTO, so we have to check for that.
	 */
	if (!IsA(viewParse, Query))
		elog(ERROR, "unexpected parse analysis result");
	if (viewParse->utilityStmt != NULL &&
		IsA(viewParse->utilityStmt, CreateTableAsStmt))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("views must not contain SELECT INTO")));
	if (viewParse->commandType != CMD_SELECT)
		elog(ERROR, "unexpected parse analysis result");

	/*
	 * Check for unsupported cases.  These tests are redundant with ones in
	 * DefineQueryRewrite(), but that function will complain about a bogus ON
	 * SELECT rule, and we'd rather the message complain about a view.
	 */
	if (viewParse->hasModifyingCTE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("views must not contain data-modifying statements in WITH")));

	/*
	 * If the user specified the WITH CHECK OPTION, add it to the list of
	 * reloptions.
	 */
	if (stmt->withCheckOption == LOCAL_CHECK_OPTION)
		stmt->options = lappend(stmt->options,
								makeDefElem("check_option",
											(Node *) makeString("local"), -1));
	else if (stmt->withCheckOption == CASCADED_CHECK_OPTION)
		stmt->options = lappend(stmt->options,
								makeDefElem("check_option",
											(Node *) makeString("cascaded"), -1));

	/*
	 * Check that the view is auto-updatable if WITH CHECK OPTION was
	 * specified.
	 */
	check_option = false;

	foreach(cell, stmt->options)
	{
		DefElem    *defel = (DefElem *) lfirst(cell);

		if (strcmp(defel->defname, "check_option") == 0)
			check_option = true;
	}

	/*
	 * If the check option is specified, look to see if the view is actually
	 * auto-updatable or not.
	 */
	if (check_option)
	{
		const char *view_updatable_error =
		view_query_is_auto_updatable(viewParse, true);

		if (view_updatable_error)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("WITH CHECK OPTION is supported only on automatically updatable views"),
					 errhint("%s", _(view_updatable_error))));
	}

	/*
	 * If a list of column names was given, run through and insert these into
	 * the actual query tree. - thomas 2000-03-08
	 */
	if (stmt->aliases != NIL)
	{
		ListCell   *alist_item = list_head(stmt->aliases);
		ListCell   *targetList;

		foreach(targetList, viewParse->targetList)
		{
			TargetEntry *te = lfirst_node(TargetEntry, targetList);

			/* junk columns don't get aliases */
			if (te->resjunk)
				continue;
			te->resname = pstrdup(strVal(lfirst(alist_item)));
			alist_item = lnext(stmt->aliases, alist_item);
			if (alist_item == NULL)
				break;			/* done assigning aliases */
		}

		if (alist_item != NULL)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("CREATE VIEW specifies more column "
							"names than columns")));
	}

	/* Unlogged views are not sensible. */
	if (stmt->view->relpersistence == RELPERSISTENCE_UNLOGGED)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("views cannot be unlogged because they do not have storage")));

	/*
	 * If the user didn't explicitly ask for a temporary view, check whether
	 * we need one implicitly.  We allow TEMP to be inserted automatically as
	 * long as the CREATE command is consistent with that --- no explicit
	 * schema name.
	 */
	view = copyObject(stmt->view);	/* don't corrupt original command */
	if (view->relpersistence == RELPERSISTENCE_PERMANENT
		&& isQueryUsingTempRelation(viewParse))
	{
		view->relpersistence = RELPERSISTENCE_TEMP;
		ereport(NOTICE,
				(errmsg("view \"%s\" will be a temporary view",
						view->relname)));
	}

	/*
	 * Create the view relation
	 *
	 * NOTE: if it already exists and replace is false, the xact will be
	 * aborted.
	 */
	address = DefineVirtualRelation(view, viewParse->targetList,
									stmt->replace, stmt->options, viewParse);

	return address;
}

/*
 * Use the rules system to store the query for the view.
 */
void
StoreViewQuery(Oid viewOid, Query *viewParse, bool replace)
{
	/*
	 * Now create the rules associated with the view.
	 */
	DefineViewRules(viewOid, viewParse, replace);
}
/*
 * StoreForceViewQuery
 *
 * Save or update the SQL definition and identifier case for a force view in pg_force_view.
 * If the view already exists and 'replace' is true, update its metadata.
 */
void
StoreForceViewQuery(Oid viewOid, bool replace, char ident_case ,const char *queryString)
{
	Datum		values[Natts_pg_force_view];
	bool		nulls[Natts_pg_force_view];
	bool		replaces[Natts_pg_force_view];
	HeapTuple	tup,
				oldtup;
	Relation	pg_force_view_desc;

	MemSet(nulls, false, sizeof(nulls));

	values[Anum_pg_force_view_fvoid - 1] = ObjectIdGetDatum(viewOid);
	values[Anum_pg_force_view_ident_case - 1] = CharGetDatum(ident_case);
	values[Anum_pg_force_view_source - 1] = CStringGetTextDatum(queryString);

	/*
	 * Insert or update the pg_force_view catalog entry.
	 */
	pg_force_view_desc = table_open(ForceViewRelationId, RowExclusiveLock);

	/*
	 * Check if a tuple for this view already exists.
	 */
	oldtup = SearchSysCache1(FORCEVIEWOID, ObjectIdGetDatum(viewOid));

	if (HeapTupleIsValid(oldtup))
	{
		if (!replace)
			ereport(ERROR,
					(errcode(ERRCODE_DUPLICATE_OBJECT),
					 errmsg("force view \"%s\" already exists",
							get_rel_name(viewOid))));

		MemSet(replaces, false, sizeof(replaces));
		replaces[Anum_pg_force_view_source - 1] = true;
		replaces[Anum_pg_force_view_ident_case - 1] = true;

		tup = heap_modify_tuple(oldtup, RelationGetDescr(pg_force_view_desc),
								values, nulls, replaces);

		CatalogTupleUpdate(pg_force_view_desc, &tup->t_self, tup);

		ReleaseSysCache(oldtup);
	}
	else
	{
		tup = heap_form_tuple(pg_force_view_desc->rd_att, values, nulls);
		CatalogTupleInsert(pg_force_view_desc, tup);
	}

	heap_freetuple(tup);
	table_close(pg_force_view_desc, RowExclusiveLock);
}

/*
 * DeleteForceView
 *
 * Remove the pg_force_view entry for the given OID, if it exists.
 */
void
DeleteForceView(Oid forceviewid)
{
	Relation	force_view_rel;
	HeapTuple	tup;

	force_view_rel = table_open(ForceViewRelationId, RowExclusiveLock);

	tup = SearchSysCache1(FORCEVIEWOID, ObjectIdGetDatum(forceviewid));

	#if 0
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for force view %u", forceviewid);
	#endif

	if (!HeapTupleIsValid(tup))
	{
		table_close(force_view_rel, RowExclusiveLock);
		return;	
	}

	CatalogTupleDelete(force_view_rel, &tup->t_self);
	ReleaseSysCache(tup);
	table_close(force_view_rel, RowExclusiveLock);
}

/*
 * rel_is_force_view
 *
 *		Given an OID checks whether a relation is a force view.
 */
bool
rel_is_force_view(Oid relid)
{
	if (IsUnderPostmaster &&
		get_rel_relkind(relid) == RELKIND_VIEW)
	{
		HeapTuple	tuple;

		tuple = SearchSysCache2(RULERELNAME, ObjectIdGetDatum(relid), CStringGetDatum("_RETURN"));
		if (HeapTupleIsValid(tuple))
		{
			ReleaseSysCache(tuple);
			return false;
		}
		else
			return true;
	}
	else
		return false;
}

/*
 * get_force_view_def
 *
 * Retrieve the SQL definition string for a force view from pg_force_view.
 */
char *
get_force_view_def(Oid viewoid)
{
	HeapTuple	tup;
	Datum		view_source;
	bool		isnull;
	char		*source;

	tup = SearchSysCache1(FORCEVIEWOID, ObjectIdGetDatum(viewoid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for force view %u", viewoid);

	view_source = SysCacheGetAttr(FORCEVIEWOID, tup,
									 Anum_pg_force_view_source,
									 &isnull);
	if (isnull)
		elog(ERROR, "the definition of force view %u is lost", viewoid);

	source = TextDatumGetCString(view_source);
	ReleaseSysCache(tup);
	return source;
}

/*
 * compile_force_view_internal
 *
 * Attempt to parse and validate the SQL for a force view, updating its metadata if successful.
 * Returns true on success, false if parsing fails.
 */
static bool
compile_force_view_internal(ViewStmt *stmt, const char *queryString, Oid viewoid)
{
	RawStmt    *rawstmt;
	Query	   *viewParse;
	RangeVar   *view;
	ListCell   *cell;
	bool		check_option;

	/*
	 * Parse the SQL statement and analyze it.
	 */
	rawstmt = makeNode(RawStmt);
	rawstmt->stmt = stmt->query;
	rawstmt->stmt_location = 0;
	rawstmt->stmt_len = 0;

	PG_TRY();
	{
		viewParse = parse_analyze_fixedparams(rawstmt, queryString, NULL, 0, NULL);
	}
	PG_CATCH();
	{
		FlushErrorState();
		return false;
	}
	PG_END_TRY();

	/*
	 * Ensure the result is a valid SELECT query for a view.
	 */
	if (!IsA(viewParse, Query))
		elog(ERROR, "unexpected parse analysis result");
	if (viewParse->utilityStmt != NULL &&
		IsA(viewParse->utilityStmt, CreateTableAsStmt))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("views must not contain SELECT INTO")));
	if (viewParse->commandType != CMD_SELECT)
		elog(ERROR, "unexpected parse analysis result");

	/*
	 * Disallow modifying CTEs in views.
	 */
	if (viewParse->hasModifyingCTE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("views must not contain data-modifying statements in WITH")));

	/*
	 * Add WITH CHECK OPTION if requested.
	 */
	if (stmt->withCheckOption == LOCAL_CHECK_OPTION)
		stmt->options = lappend(stmt->options,
								makeDefElem("check_option",
											(Node *) makeString("local"), -1));
	else if (stmt->withCheckOption == CASCADED_CHECK_OPTION)
		stmt->options = lappend(stmt->options,
								makeDefElem("check_option",
											(Node *) makeString("cascaded"), -1));

	/*
	 * Validate auto-updatability if WITH CHECK OPTION is present.
	 */
	check_option = false;

	foreach(cell, stmt->options)
	{
		DefElem    *defel = (DefElem *) lfirst(cell);

		if (strcmp(defel->defname, "check_option") == 0)
			check_option = true;
	}

	if (check_option)
	{
		const char *view_updatable_error =
		view_query_is_auto_updatable(viewParse, true);

		if (view_updatable_error)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("WITH CHECK OPTION is supported only on automatically updatable views"),
					 errhint("%s", _(view_updatable_error))));
	}

	/*
	 * Assign column aliases if provided.
	 */
	if (stmt->aliases != NIL)
	{
		ListCell   *alist_item = list_head(stmt->aliases);
		ListCell   *targetList;

		foreach(targetList, viewParse->targetList)
		{
			TargetEntry *te = lfirst_node(TargetEntry, targetList);

			/* junk columns don't get aliases */
			if (te->resjunk)
				continue;
			te->resname = pstrdup(strVal(lfirst(alist_item)));
			alist_item = lnext(stmt->aliases, alist_item);
			if (alist_item == NULL)
				break;			/* done assigning aliases */
		}

		if (alist_item != NULL)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("CREATE VIEW specifies more column "
							"names than columns")));
	}

	/* Disallow unlogged and global temp views. */
	if (stmt->view->relpersistence == RELPERSISTENCE_UNLOGGED)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("views cannot be unlogged because they do not have storage")));

	/*
	 * Automatically mark as TEMP if required by referenced relations.
	 */
	view = copyObject(stmt->view);	/* don't corrupt original command */
	if (view->relpersistence == RELPERSISTENCE_PERMANENT
		&& isQueryUsingTempRelation(viewParse))
	{
		view->relpersistence = RELPERSISTENCE_TEMP;
		ereport(NOTICE,
				(errmsg("view \"%s\" will be a temporary view",
						view->relname)));
	}

	make_view_valid(viewParse->targetList, viewoid, stmt->options, viewParse);
	return true;
}

/*
 * compile_force_view
 *
 * Try to compile a force view from its stored definition.
 * Returns true if successful, false otherwise.
 */
bool
compile_force_view(Oid viewoid)
{
	bool		res = false;
	bool		isnull;
	char		*fview_querystring;
	Datum		view_source;
	List	   *raw_parsetree_list;
	RawStmt    *rs;
	Node		*node;
	HeapTuple	tup;

	if (!rel_is_force_view(viewoid))
		return true;

	/* Fetch the stored SQL for the force view. */
	tup = SearchSysCache1(FORCEVIEWOID, ObjectIdGetDatum(viewoid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for force view %u", viewoid);

	view_source = SysCacheGetAttr(FORCEVIEWOID, tup,
									 Anum_pg_force_view_source,
									 &isnull);
	if (isnull)
		elog(ERROR, "the definition of force view %u is lost", viewoid);

	fview_querystring = TextDatumGetCString(view_source);
	ReleaseSysCache(tup);

	/* Parse the SQL into a raw parse tree. */
	raw_parsetree_list = raw_parser(fview_querystring, RAW_PARSE_DEFAULT);
	if (list_length(raw_parsetree_list) != 1)
		elog(ERROR, "The definition of force view is wrong");

	rs = linitial_node(RawStmt, raw_parsetree_list);
	node = rs->stmt;
	if (node->type != T_ViewStmt)
		elog(ERROR, "force view %u compile fail due to metadata wrong", viewoid);
	
	/*
	 * Compile the view definition.
	 * Errors are not suppressed, so users can diagnose problems.
	 */
	res = compile_force_view_internal((ViewStmt *) node, fview_querystring, viewoid);
	pfree(fview_querystring);

	return res;
}

/* 
 * make_view_invalid
 *
 *		Make a view to force view, which is an invalid state.
 *		Currently, the invalidation of a view cannot be issued explicitly. 
 *		In most cases, it is caused by the deletion of dependent objects.
 */
bool
make_view_invalid(Oid viewid)
{
	Relation	viewrel;
	Relation	relation;
	HeapTuple	tuple;
	StringInfo	buf;
	Form_pg_class classForm;
	Datum		viewdef;
	Oid			ruleoid = InvalidOid;
	bool		isnull;

	if (rel_is_force_view(viewid))
		return true;

	/*
	 * TODO:
	 * This interface cannot be used directly, because the definition
	 * of this view must be with a schema, otherwise other sessions
	 * cannot compile the view, except the session that created the view.
	 */
	viewdef = DirectFunctionCall1(pg_get_viewdef, ObjectIdGetDatum(viewid));
	viewrel = relation_open(viewid, AccessExclusiveLock);
	CheckTableNotInUse(viewrel, "INVALID VIEW");

	/*
	 * 1.pg_attribute
	 * Create or replace force view maybe change targetlist of view.
	 */
	DeleteAttributeTuples(viewid);

	/*
	 *  2.pg_class
	 * Update the relhasrules and relnatts of pg_class.
	 */
	relation = table_open(RelationRelationId, RowExclusiveLock);
	tuple = SearchSysCacheCopy1(RELOID, ObjectIdGetDatum(viewid));
	if (!HeapTupleIsValid(tuple))
		elog(ERROR, "cache lookup failed for relation %u", viewid);
	classForm = (Form_pg_class) GETSTRUCT(tuple);
	classForm->relhasrules = false;
	classForm->relnatts = 0;
	CatalogTupleUpdate(relation, &tuple->t_self, tuple);
	heap_freetuple(tuple);
	table_close(relation, RowExclusiveLock);

	/*
	 * Close relcache entry, but *keep* AccessExclusiveLock on the relation
	 * until transaction commit.  This ensures no one else will try to do
	 * something with the doomed relation.
	 */
	relation_close(viewrel, NoLock);

	/*
	 * 3.pg_rewrite
	 * Only delete the _RETURN rule of view.
	 * Are other non-SELECT type rules considered for deletion?
	 */
	relation = table_open(RewriteRelationId, RowExclusiveLock);
	tuple = SearchSysCache2(RULERELNAME, ObjectIdGetDatum(viewid), CStringGetDatum("_RETURN"));
	if (!HeapTupleIsValid(tuple)) /* should not happen */
		elog(ERROR, "Unable to get the view's rules when invalid the view");
	ruleoid = heap_getattr(tuple, Anum_pg_rewrite_oid, RelationGetDescr(relation), &isnull);
	if (isnull)
		elog(ERROR, "Unable to get the view rule's OID when invalid the view");
	CatalogTupleDelete(relation, &tuple->t_self);
	ReleaseSysCache(tuple);
	table_close(relation, RowExclusiveLock);

	/*
	 * 4.pg_depend
	 * Get rid of old dependencies for the rule of this force view.
	 */
	deleteDependencyRecordsFor(RewriteRelationId, ruleoid, false);

	/*
	 * 5.pg_force_view
	 * Store the definition of force view.
	 */
	buf = makeStringInfo();
	appendStringInfoString(buf, "CREATE FORCE VIEW ");
	appendStringInfoString(buf, quote_identifier(get_namespace_name(get_rel_namespace(viewid))));
	appendStringInfoChar(buf, '.');
	appendStringInfoString(buf, quote_identifier(get_rel_name(viewid)));
	appendStringInfoString(buf, " AS \n");
	appendStringInfoString(buf, TextDatumGetCString(viewdef));

	/*
	 * When invalidating the view, we do not obtain the view definition directly
	 * from the query text entered by the user, but obtain it through pg_get_viewdef.
	 * Therefore, the correctness of the meaning of double quotes in obtaining the view
	 * definition should depend on pg_get_viewdef, so we use IDENT_CASE_UNDEFINE directly.
	 */
	StoreForceViewQuery(viewid, false, IDENT_CASE_UNDEFINE, buf->data);

	/* Make change visible */
	CommandCounterIncrement();

	return true;
}

/*
 * make_view_valid
 *
 * Transform a force view into a valid view by updating its catalog entries and definition.
 * Returns true if the operation succeeds or is unnecessary.
 */
bool
make_view_valid(List *tlist, Oid viewOid, List *options, Query *viewParse)
{
	Relation	rel;
	Relation	relation;
	HeapTuple	tuple;
	Form_pg_class classForm;
	TupleDesc	descriptor;
	List	   *atcmds = NIL;
	AlterTableCmd *atcmd;
	List	   *attrList;
	ListCell   *t;

	if (!rel_is_force_view(viewOid))
		return true;

	/*
	 * Build a list of ColumnDef nodes from the target list.
	 */
	attrList = NIL;
	foreach(t, tlist)
	{
		TargetEntry *tle = (TargetEntry *) lfirst(t);

		if (!tle->resjunk)
		{
			ColumnDef  *def = makeColumnDef(tle->resname,
											exprType((Node *) tle->expr),
											exprTypmod((Node *) tle->expr),
											exprCollation((Node *) tle->expr));

			/*
			 * Ensure collation is valid for collatable types.
			 */
			if (type_is_collatable(exprType((Node *) tle->expr)))
			{
				if (!OidIsValid(def->collOid))
					ereport(ERROR,
							(errcode(ERRCODE_INDETERMINATE_COLLATION),
							 errmsg("could not determine which collation to use for view column \"%s\"",
									def->colname),
							 errhint("Use the COLLATE clause to set the collation explicitly.")));
			}
			else
				Assert(!OidIsValid(def->collOid));

			attrList = lappend(attrList, def);
		}
	}

	rel = relation_open(viewOid, AccessExclusiveLock);

	/* Confirm the relation is a view. */
	if (rel->rd_rel->relkind != RELKIND_VIEW)
		ereport(ERROR,
				(errcode(ERRCODE_WRONG_OBJECT_TYPE),
				 errmsg("\"%s\" is not a view",
						RelationGetRelationName(rel))));

	/* Ensure the view is not currently in use. */
	CheckTableNotInUse(rel, "COMPILE FORCE VIEW");

	/*
	 * Compare the new and old column lists.
	 */
	descriptor = BuildDescForRelation(attrList);
	checkViewColumns(descriptor, rel->rd_att);

	/*
	 * Add new columns if needed using ALTER TABLE infrastructure.
	 */
	if (list_length(attrList) > rel->rd_att->natts)
	{
		ListCell   *c;
		int			skip = rel->rd_att->natts;

		foreach(c, attrList)
		{
			if (skip > 0)
			{
				skip--;
				continue;
			}
			atcmd = makeNode(AlterTableCmd);
			atcmd->subtype = AT_AddColumnToView;
			atcmd->def = (Node *) lfirst(c);
			atcmds = lappend(atcmds, atcmd);
		}

		AlterTableInternal(viewOid, atcmds, true);

		/* Make the new view columns visible */
		CommandCounterIncrement();
	}

	/*
	 * Update the view's query and options.
	 */
	StoreViewQuery(viewOid, viewParse, false);

	/* Make the new view query visible */
	CommandCounterIncrement();

	atcmd = makeNode(AlterTableCmd);
	atcmd->subtype = AT_ReplaceRelOptions;
	atcmd->def = (Node *) options;
	atcmds = list_make1(atcmd);

	AlterTableInternal(viewOid, atcmds, true);
	relation_close(rel, NoLock);	/* keep the lock! */

	/* Update pg_class to indicate rules are present. */
	relation = table_open(RelationRelationId, RowExclusiveLock);
	tuple = SearchSysCacheCopy1(RELOID, ObjectIdGetDatum(viewOid));
	if (!HeapTupleIsValid(tuple))
		elog(ERROR, "cache lookup failed for relation %u", viewOid);
	classForm = (Form_pg_class) GETSTRUCT(tuple);
	classForm->relhasrules = true;
	CatalogTupleUpdate(relation, &tuple->t_self, tuple);
	heap_freetuple(tuple);
	table_close(relation, RowExclusiveLock);

	DeleteForceView(viewOid);

	/* Make all changes visible */
	CommandCounterIncrement();

	return true;
}
