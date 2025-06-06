/*-------------------------------------------------------------------------
 *
 * plisql.h		- Definitions for the PL/iSQL
 *			  procedural language
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/plisql.h
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#ifndef PLISQL_H
#define PLISQL_H

#include "access/xact.h"
#include "commands/event_trigger.h"
#include "commands/trigger.h"
#include "executor/spi.h"
#include "utils/expandedrecord.h"
#include "utils/typcache.h"
#include "utils/packagecache.h"


/**********************************************************************
 * Definitions
 **********************************************************************/

/* define our text domain for translations */
#undef TEXTDOMAIN
#define TEXTDOMAIN PG_TEXTDOMAIN("plisql")

#undef _
#define _(x) dgettext(TEXTDOMAIN, x)

/*
 * Compiler's namespace item types
 */
typedef enum PLiSQL_nsitem_type
{
	PLISQL_NSTYPE_LABEL,		/* block label */
	PLISQL_NSTYPE_VAR,			/* scalar variable */
	PLISQL_NSTYPE_REC,			/* composite variable */
	PLISQL_NSTYPE_SUBPROC_FUNC,	/* subproc function */
	PLISQL_NSTYPE_SUBPROC_PROC	/* subproc proc */
} PLiSQL_nsitem_type;

/*
 * A PLISQL_NSTYPE_LABEL stack entry must be one of these types
 */
typedef enum PLiSQL_label_type
{
	PLISQL_LABEL_BLOCK,		/* DECLARE/BEGIN block */
	PLISQL_LABEL_LOOP,			/* looping construct */
	PLISQL_LABEL_OTHER			/* anything else */
} PLiSQL_label_type;

/*
 * Datum array node types
 */
typedef enum PLiSQL_datum_type
{
	PLISQL_DTYPE_VAR,
	PLISQL_DTYPE_ROW,
	PLISQL_DTYPE_REC,
	PLISQL_DTYPE_RECFIELD,
	PLISQL_DTYPE_PROMISE,
	PLISQL_DTYPE_PACKAGE_DATUM,
} PLiSQL_datum_type;

/*
 * DTYPE_PROMISE datums have these possible ways of computing the promise
 */
typedef enum PLiSQL_promise_type
{
	PLISQL_PROMISE_NONE = 0,	/* not a promise, or promise satisfied */
	PLISQL_PROMISE_TG_NAME,
	PLISQL_PROMISE_TG_WHEN,
	PLISQL_PROMISE_TG_LEVEL,
	PLISQL_PROMISE_TG_OP,
	PLISQL_PROMISE_TG_RELID,
	PLISQL_PROMISE_TG_TABLE_NAME,
	PLISQL_PROMISE_TG_TABLE_SCHEMA,
	PLISQL_PROMISE_TG_NARGS,
	PLISQL_PROMISE_TG_ARGV,
	PLISQL_PROMISE_TG_EVENT,
	PLISQL_PROMISE_TG_TAG
} PLiSQL_promise_type;

/*
 * Variants distinguished in PLiSQL_type structs
 */
typedef enum PLiSQL_type_type
{
	PLISQL_TTYPE_SCALAR,		/* scalar types and domains */
	PLISQL_TTYPE_REC,			/* composite types, including RECORD */
	PLISQL_TTYPE_PSEUDO		/* pseudotypes */
} PLiSQL_type_type;

/*
 * Execution tree node types
 */
typedef enum PLiSQL_stmt_type
{
	PLISQL_STMT_BLOCK,
	PLISQL_STMT_ASSIGN,
	PLISQL_STMT_IF,
	PLISQL_STMT_CASE,
	PLISQL_STMT_LOOP,
	PLISQL_STMT_WHILE,
	PLISQL_STMT_FORI,
	PLISQL_STMT_FORS,
	PLISQL_STMT_FORC,
	PLISQL_STMT_FOREACH_A,
	PLISQL_STMT_EXIT,
	PLISQL_STMT_RETURN,
	PLISQL_STMT_RETURN_NEXT,
	PLISQL_STMT_RETURN_QUERY,
	PLISQL_STMT_RAISE,
	PLISQL_STMT_ASSERT,
	PLISQL_STMT_EXECSQL,
	PLISQL_STMT_DYNEXECUTE,
	PLISQL_STMT_DYNFORS,
	PLISQL_STMT_GETDIAG,
	PLISQL_STMT_OPEN,
	PLISQL_STMT_FETCH,
	PLISQL_STMT_CLOSE,
	PLISQL_STMT_PERFORM,
	PLISQL_STMT_CALL,
	PLISQL_STMT_COMMIT,
	PLISQL_STMT_ROLLBACK
} PLiSQL_stmt_type;

/*
 * Execution node return codes
 */
enum
{
	PLISQL_RC_OK,
	PLISQL_RC_EXIT,
	PLISQL_RC_RETURN,
	PLISQL_RC_CONTINUE
};

/*
 * GET DIAGNOSTICS information items
 */
typedef enum PLiSQL_getdiag_kind
{
	PLISQL_GETDIAG_ROW_COUNT,
	PLISQL_GETDIAG_ROUTINE_OID,
	PLISQL_GETDIAG_CONTEXT,
	PLISQL_GETDIAG_ERROR_CONTEXT,
	PLISQL_GETDIAG_ERROR_DETAIL,
	PLISQL_GETDIAG_ERROR_HINT,
	PLISQL_GETDIAG_RETURNED_SQLSTATE,
	PLISQL_GETDIAG_COLUMN_NAME,
	PLISQL_GETDIAG_CONSTRAINT_NAME,
	PLISQL_GETDIAG_DATATYPE_NAME,
	PLISQL_GETDIAG_MESSAGE_TEXT,
	PLISQL_GETDIAG_TABLE_NAME,
	PLISQL_GETDIAG_SCHEMA_NAME
} PLiSQL_getdiag_kind;

/*
 * RAISE statement options
 */
typedef enum PLiSQL_raise_option_type
{
	PLISQL_RAISEOPTION_ERRCODE,
	PLISQL_RAISEOPTION_MESSAGE,
	PLISQL_RAISEOPTION_DETAIL,
	PLISQL_RAISEOPTION_HINT,
	PLISQL_RAISEOPTION_COLUMN,
	PLISQL_RAISEOPTION_CONSTRAINT,
	PLISQL_RAISEOPTION_DATATYPE,
	PLISQL_RAISEOPTION_TABLE,
	PLISQL_RAISEOPTION_SCHEMA
} PLiSQL_raise_option_type;

/*
 * Behavioral modes for plpgsql variable resolution
 */
typedef enum PLiSQL_resolve_option
{
	PLISQL_RESOLVE_ERROR,		/* throw error if ambiguous */
	PLISQL_RESOLVE_VARIABLE,	/* prefer plpgsql var to table column */
	PLISQL_RESOLVE_COLUMN		/* prefer table column to plpgsql var */
} PLiSQL_resolve_option;


/**********************************************************************
 * Node and structure definitions
 **********************************************************************/

/*
 * Postgres data type
 */
typedef struct PLiSQL_type
{
	char	   *typname;		/* (simple) name of the type */
	Oid			typoid;			/* OID of the data type */
	PLiSQL_type_type ttype;	/* PLISQL_TTYPE_ code */
	int16		typlen;			/* stuff copied from its pg_type entry */
	bool		typbyval;
	char		typtype;
	Oid			collation;		/* from pg_type, but can be overridden */
	bool		typisarray;		/* is "true" array, or domain over one */
	int32		atttypmod;		/* typmod (taken from someplace else) */
	/* Remaining fields are used only for named composite types (not RECORD) */
	TypeName   *origtypname;	/* type name as written by user */
	TypeCacheEntry *tcache;		/* typcache entry for composite type */
	uint64		tupdesc_id;		/* last-seen tupdesc identifier */
} PLiSQL_type;

/*
 * SQL Query to plan and execute
 */
typedef struct PLiSQL_expr
{
	char	   *query;			/* query string, verbatim from function body */
	RawParseMode parseMode;		/* raw_parser() mode to use */
	SPIPlanPtr	plan;			/* plan, or NULL if not made yet */
	Bitmapset  *paramnos;		/* all dnos referenced by this query */

	/* function containing this expr (not set until we first parse query) */
	struct PLiSQL_function *func;

	/* namespace chain visible to this expr */
	struct PLiSQL_nsitem *ns;

	/* fields for "simple expression" fast-path execution: */
	Expr	   *expr_simple_expr;	/* NULL means not a simple expr */
	Oid			expr_simple_type;	/* result type Oid, if simple */
	int32		expr_simple_typmod; /* result typmod, if simple */
	bool		expr_simple_mutable;	/* true if simple expr is mutable */

	/*
	 * These fields are used to optimize assignments to expanded-datum
	 * variables.  If this expression is the source of an assignment to a
	 * simple variable, target_param holds that variable's dno; else it's -1.
	 * If we match a Param within expr_simple_expr to such a variable, that
	 * Param's address is stored in expr_rw_param; then expression code
	 * generation will allow the value for that Param to be passed read/write.
	 */
	int			target_param;	/* dno of assign target, or -1 if none */
	Param	   *expr_rw_param;	/* read/write Param within expr, if any */

	/*
	 * If the expression was ever determined to be simple, we remember its
	 * CachedPlanSource and CachedPlan here.  If expr_simple_plan_lxid matches
	 * current LXID, then we hold a refcount on expr_simple_plan in the
	 * current transaction.  Otherwise we need to get one before re-using it.
	 */
	CachedPlanSource *expr_simple_plansource;	/* extracted from "plan" */
	CachedPlan *expr_simple_plan;	/* extracted from "plan" */
	LocalTransactionId expr_simple_plan_lxid;

	/*
	 * if expr is simple AND prepared in current transaction,
	 * expr_simple_state and expr_simple_in_use are valid. Test validity by
	 * seeing if expr_simple_lxid matches current LXID.  (If not,
	 * expr_simple_state probably points at garbage!)
	 */
	ExprState  *expr_simple_state;	/* eval tree for expr_simple_expr */
	bool		expr_simple_in_use; /* true if eval tree is active */
	LocalTransactionId expr_simple_lxid;
} PLiSQL_expr;

/*
 * Generic datum array item
 *
 * PLiSQL_datum is the common supertype for PLiSQL_var, PLiSQL_row,
 * PLiSQL_rec, and PLiSQL_recfield.
 */
typedef struct PLiSQL_datum
{
	PLiSQL_datum_type dtype;
	int			dno;
	Oid			pkgoid;
} PLiSQL_datum;

/*
 * Scalar or composite variable
 *
 * The variants PLiSQL_var, PLiSQL_row, and PLiSQL_rec share these
 * fields.
 */
typedef struct PLiSQL_variable
{
	PLiSQL_datum_type dtype;
	int			dno;
	Oid			pkgoid;
	char	   *refname;
	int			lineno;
	bool		isconst;
	bool		notnull;
	PLiSQL_expr *default_val;
} PLiSQL_variable;

/*
 * Scalar variable
 *
 * DTYPE_VAR and DTYPE_PROMISE datums both use this struct type.
 * A PROMISE datum works exactly like a VAR datum for most purposes,
 * but if it is read without having previously been assigned to, then
 * a special "promised" value is computed and assigned to the datum
 * before the read is performed.  This technique avoids the overhead of
 * computing the variable's value in cases where we expect that many
 * functions will never read it.
 */
typedef struct PLiSQL_var
{
	PLiSQL_datum_type dtype;
	int			dno;
	Oid			pkgoid;
	char	   *refname;
	int			lineno;
	bool		isconst;
	bool		notnull;
	PLiSQL_expr *default_val;
	/* end of PLiSQL_variable fields */

	PLiSQL_type *datatype;

	/*
	 * Variables declared as CURSOR FOR <query> are mostly like ordinary
	 * scalar variables of type refcursor, but they have these additional
	 * properties:
	 */
	PLiSQL_expr *cursor_explicit_expr;
	int			cursor_explicit_argrow;
	int			cursor_options;

	/* Fields below here can change at runtime */

	Datum		value;
	bool		isnull;
	bool		freeval;

	/*
	 * The promise field records which "promised" value to assign if the
	 * promise must be honored.  If it's a normal variable, or the promise has
	 * been fulfilled, this is PLISQL_PROMISE_NONE.
	 */
	PLiSQL_promise_type promise;
} PLiSQL_var;

/*
 * Row variable - this represents one or more variables that are listed in an
 * INTO clause, FOR-loop targetlist, cursor argument list, etc.  We also use
 * a row to represent a function's OUT parameters when there's more than one.
 *
 * Note that there's no way to name the row as such from PL/pgSQL code,
 * so many functions don't need to support these.
 *
 * That also means that there's no real name for the row variable, so we
 * conventionally set refname to "(unnamed row)".  We could leave it NULL,
 * but it's too convenient to be able to assume that refname is valid in
 * all variants of PLiSQL_variable.
 *
 * isconst, notnull, and default_val are unsupported (and hence
 * always zero/null) for a row.  The member variables of a row should have
 * been checked to be writable at compile time, so isconst is correctly set
 * to false.  notnull and default_val aren't applicable.
 */
typedef struct PLiSQL_row
{
	PLiSQL_datum_type dtype;
	int			dno;
	Oid			pkgoid;
	char	   *refname;
	int			lineno;
	bool		isconst;
	bool		notnull;
	PLiSQL_expr *default_val;
	/* end of PLiSQL_variable fields */

	/*
	 * rowtupdesc is only set up if we might need to convert the row into a
	 * composite datum, which currently only happens for OUT parameters.
	 * Otherwise it is NULL.
	 */
	TupleDesc	rowtupdesc;

	int			nfields;
	char	  **fieldnames;
	int		   *varnos;
} PLiSQL_row;

/*
 * Record variable (any composite type, including RECORD)
 */
typedef struct PLiSQL_rec
{
	PLiSQL_datum_type dtype;
	int			dno;
	Oid			pkgoid;
	char	   *refname;
	int			lineno;
	bool		isconst;
	bool		notnull;
	PLiSQL_expr *default_val;
	/* end of PLiSQL_variable fields */

	/*
	 * Note: for non-RECORD cases, we may from time to time re-look-up the
	 * composite type, using datatype->origtypname.  That can result in
	 * changing rectypeid.
	 */

	PLiSQL_type *datatype;		/* can be NULL, if rectypeid is RECORDOID */
	Oid			rectypeid;		/* declared type of variable */
	/* RECFIELDs for this record are chained together for easy access */
	int			firstfield;		/* dno of first RECFIELD, or -1 if none */

	/* Fields below here can change at runtime */

	/* We always store record variables as "expanded" records */
	ExpandedRecordHeader *erh;
} PLiSQL_rec;

/*
 * Field in record
 */
typedef struct PLiSQL_recfield
{
	PLiSQL_datum_type dtype;
	int			dno;
	/* end of PLiSQL_datum fields */

	Oid			pkgoid;

	char	   *fieldname;		/* name of field */
	int			recparentno;	/* dno of parent record */
	int			nextfield;		/* dno of next child, or -1 if none */
	uint64		rectupledescid; /* record's tupledesc ID as of last lookup */
	ExpandedRecordFieldInfo finfo;	/* field's attnum and type info */
	/* if rectupledescid == INVALID_TUPLEDESC_IDENTIFIER, finfo isn't valid */
} PLiSQL_recfield;

/*
 * Item in the compilers namespace tree
 */
typedef struct PLiSQL_nsitem
{
	PLiSQL_nsitem_type itemtype;

	/*
	 * For labels, itemno is a value of enum PLiSQL_label_type. For other
	 * itemtypes, itemno is the associated PLiSQL_datum's dno.
	 */
	int			itemno;
	struct PLiSQL_nsitem *prev;
	List		*subprocfunc;
	char		name[FLEXIBLE_ARRAY_MEMBER];	/* nul-terminated string */
} PLiSQL_nsitem;

/*
 * Generic execution node
 */
typedef struct PLiSQL_stmt
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;

	/*
	 * Unique statement ID in this function (starting at 1; 0 is invalid/not
	 * set).  This can be used by a profiler as the index for an array of
	 * per-statement metrics.
	 */
	unsigned int stmtid;
} PLiSQL_stmt;

/*
 * One EXCEPTION condition name
 */
typedef struct PLiSQL_condition
{
	int			sqlerrstate;	/* SQLSTATE code */
	char	   *condname;		/* condition name (for debugging) */
	struct PLiSQL_condition *next;
} PLiSQL_condition;

/*
 * EXCEPTION block
 */
typedef struct PLiSQL_exception_block
{
	int			sqlstate_varno;
	int			sqlerrm_varno;
	List	   *exc_list;		/* List of WHEN clauses */
} PLiSQL_exception_block;

/*
 * One EXCEPTION ... WHEN clause
 */
typedef struct PLiSQL_exception
{
	int			lineno;
	PLiSQL_condition *conditions;
	List	   *action;			/* List of statements */
} PLiSQL_exception;

/*
 * Block of statements
 */
typedef struct PLiSQL_stmt_block
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	List	   *body;			/* List of statements */
	int			n_initvars;		/* Length of initvarnos[] */
	int		   *initvarnos;		/* dnos of variables declared in this block */
	PLiSQL_exception_block *exceptions;
} PLiSQL_stmt_block;

/*
 * Assign statement
 */
typedef struct PLiSQL_stmt_assign
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	int			varno;
	PLiSQL_expr *expr;
} PLiSQL_stmt_assign;

/*
 * PERFORM statement
 */
typedef struct PLiSQL_stmt_perform
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *expr;
} PLiSQL_stmt_perform;

/*
 * CALL statement
 */
typedef struct PLiSQL_stmt_call
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *expr;
	bool		is_call;
	PLiSQL_variable *target;
} PLiSQL_stmt_call;

/*
 * COMMIT statement
 */
typedef struct PLiSQL_stmt_commit
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	bool		chain;
} PLiSQL_stmt_commit;

/*
 * ROLLBACK statement
 */
typedef struct PLiSQL_stmt_rollback
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	bool		chain;
} PLiSQL_stmt_rollback;

/*
 * GET DIAGNOSTICS item
 */
typedef struct PLiSQL_diag_item
{
	PLiSQL_getdiag_kind kind;	/* id for diagnostic value desired */
	int			target;			/* where to assign it */
} PLiSQL_diag_item;

/*
 * GET DIAGNOSTICS statement
 */
typedef struct PLiSQL_stmt_getdiag
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	bool		is_stacked;		/* STACKED or CURRENT diagnostics area? */
	List	   *diag_items;		/* List of PLiSQL_diag_item */
} PLiSQL_stmt_getdiag;

/*
 * IF statement
 */
typedef struct PLiSQL_stmt_if
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *cond;			/* boolean expression for THEN */
	List	   *then_body;		/* List of statements */
	List	   *elsif_list;		/* List of PLiSQL_if_elsif structs */
	List	   *else_body;		/* List of statements */
} PLiSQL_stmt_if;

/*
 * one ELSIF arm of IF statement
 */
typedef struct PLiSQL_if_elsif
{
	int			lineno;
	PLiSQL_expr *cond;			/* boolean expression for this case */
	List	   *stmts;			/* List of statements */
} PLiSQL_if_elsif;

/*
 * CASE statement
 */
typedef struct PLiSQL_stmt_case
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *t_expr;		/* test expression, or NULL if none */
	int			t_varno;		/* var to store test expression value into */
	List	   *case_when_list; /* List of PLiSQL_case_when structs */
	bool		have_else;		/* flag needed because list could be empty */
	List	   *else_stmts;		/* List of statements */
} PLiSQL_stmt_case;

/*
 * one arm of CASE statement
 */
typedef struct PLiSQL_case_when
{
	int			lineno;
	PLiSQL_expr *expr;			/* boolean expression for this case */
	List	   *stmts;			/* List of statements */
} PLiSQL_case_when;

/*
 * Unconditional LOOP statement
 */
typedef struct PLiSQL_stmt_loop
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	List	   *body;			/* List of statements */
} PLiSQL_stmt_loop;

/*
 * WHILE cond LOOP statement
 */
typedef struct PLiSQL_stmt_while
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	PLiSQL_expr *cond;
	List	   *body;			/* List of statements */
} PLiSQL_stmt_while;

/*
 * FOR statement with integer loopvar
 */
typedef struct PLiSQL_stmt_fori
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	PLiSQL_var *var;
	PLiSQL_expr *lower;
	PLiSQL_expr *upper;
	PLiSQL_expr *step;			/* NULL means default (ie, BY 1) */
	int			reverse;
	List	   *body;			/* List of statements */
} PLiSQL_stmt_fori;

/*
 * PLiSQL_stmt_forq represents a FOR statement running over a SQL query.
 * It is the common supertype of PLiSQL_stmt_fors, PLiSQL_stmt_forc
 * and PLiSQL_stmt_dynfors.
 */
typedef struct PLiSQL_stmt_forq
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	PLiSQL_variable *var;		/* Loop variable (record or row) */
	List	   *body;			/* List of statements */
} PLiSQL_stmt_forq;

/*
 * FOR statement running over SELECT
 */
typedef struct PLiSQL_stmt_fors
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	PLiSQL_variable *var;		/* Loop variable (record or row) */
	List	   *body;			/* List of statements */
	/* end of fields that must match PLiSQL_stmt_forq */
	PLiSQL_expr *query;
} PLiSQL_stmt_fors;

/*
 * FOR statement running over cursor
 */
typedef struct PLiSQL_stmt_forc
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	PLiSQL_variable *var;		/* Loop variable (record or row) */
	List	   *body;			/* List of statements */
	/* end of fields that must match PLiSQL_stmt_forq */
	int			curvar;
	PLiSQL_expr *argquery;		/* cursor arguments if any */
} PLiSQL_stmt_forc;

/*
 * FOR statement running over EXECUTE
 */
typedef struct PLiSQL_stmt_dynfors
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	PLiSQL_variable *var;		/* Loop variable (record or row) */
	List	   *body;			/* List of statements */
	/* end of fields that must match PLiSQL_stmt_forq */
	PLiSQL_expr *query;
	List	   *params;			/* USING expressions */
} PLiSQL_stmt_dynfors;

/*
 * FOREACH item in array loop
 */
typedef struct PLiSQL_stmt_foreach_a
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	char	   *label;
	int			varno;			/* loop target variable */
	int			slice;			/* slice dimension, or 0 */
	PLiSQL_expr *expr;			/* array expression */
	List	   *body;			/* List of statements */
} PLiSQL_stmt_foreach_a;

/*
 * OPEN a curvar
 */
typedef struct PLiSQL_stmt_open
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	int			curvar;
	int			cursor_options;
	PLiSQL_expr *argquery;
	PLiSQL_expr *query;
	PLiSQL_expr *dynquery;
	List	   *params;			/* USING expressions */
} PLiSQL_stmt_open;

/*
 * FETCH or MOVE statement
 */
typedef struct PLiSQL_stmt_fetch
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_variable *target;	/* target (record or row) */
	int			curvar;			/* cursor variable to fetch from */
	FetchDirection direction;	/* fetch direction */
	long		how_many;		/* count, if constant (expr is NULL) */
	PLiSQL_expr *expr;			/* count, if expression */
	bool		is_move;		/* is this a fetch or move? */
	bool		returns_multiple_rows;	/* can return more than one row? */
} PLiSQL_stmt_fetch;

/*
 * CLOSE curvar
 */
typedef struct PLiSQL_stmt_close
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	int			curvar;
} PLiSQL_stmt_close;

/*
 * EXIT or CONTINUE statement
 */
typedef struct PLiSQL_stmt_exit
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	bool		is_exit;		/* Is this an exit or a continue? */
	char	   *label;			/* NULL if it's an unlabeled EXIT/CONTINUE */
	PLiSQL_expr *cond;
} PLiSQL_stmt_exit;

/*
 * RETURN statement
 */
typedef struct PLiSQL_stmt_return
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *expr;
	int			retvarno;
} PLiSQL_stmt_return;

/*
 * RETURN NEXT statement
 */
typedef struct PLiSQL_stmt_return_next
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *expr;
	int			retvarno;
} PLiSQL_stmt_return_next;

/*
 * RETURN QUERY statement
 */
typedef struct PLiSQL_stmt_return_query
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *query;		/* if static query */
	PLiSQL_expr *dynquery;		/* if dynamic query (RETURN QUERY EXECUTE) */
	List	   *params;			/* USING arguments for dynamic query */
} PLiSQL_stmt_return_query;

/*
 * RAISE statement
 */
typedef struct PLiSQL_stmt_raise
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	int			elog_level;
	char	   *condname;		/* condition name, SQLSTATE, or NULL */
	char	   *message;		/* old-style message format literal, or NULL */
	List	   *params;			/* list of expressions for old-style message */
	List	   *options;		/* list of PLiSQL_raise_option */
} PLiSQL_stmt_raise;

/*
 * RAISE statement option
 */
typedef struct PLiSQL_raise_option
{
	PLiSQL_raise_option_type opt_type;
	PLiSQL_expr *expr;
} PLiSQL_raise_option;

/*
 * ASSERT statement
 */
typedef struct PLiSQL_stmt_assert
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *cond;
	PLiSQL_expr *message;
} PLiSQL_stmt_assert;

/*
 * Generic SQL statement to execute
 */
typedef struct PLiSQL_stmt_execsql
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *sqlstmt;
	bool		mod_stmt;		/* is the stmt INSERT/UPDATE/DELETE/MERGE? */
	bool		mod_stmt_set;	/* is mod_stmt valid yet? */
	bool		into;			/* INTO supplied? */
	bool		strict;			/* INTO STRICT flag */
	PLiSQL_variable *target;	/* INTO target (record or row) */
} PLiSQL_stmt_execsql;

/*
 * Dynamic SQL string to execute
 */
typedef struct PLiSQL_stmt_dynexecute
{
	PLiSQL_stmt_type cmd_type;
	int			lineno;
	unsigned int stmtid;
	PLiSQL_expr *query;		/* string expression */
	bool		into;			/* INTO supplied? */
	bool		strict;			/* INTO STRICT flag */
	PLiSQL_variable *target;	/* INTO target (record or row) */
	List	   *params;			/* USING expressions */
} PLiSQL_stmt_dynexecute;

/*
 * Hash lookup key for functions
 */
typedef struct PLiSQL_func_hashkey
{
	Oid			funcOid;

	bool		isTrigger;		/* true if called as a DML trigger */
	bool		isEventTrigger; /* true if called as an event trigger */

	/* be careful that pad bytes in this struct get zeroed! */

	/*
	 * For a trigger function, the OID of the trigger is part of the hash key
	 * --- we want to compile the trigger function separately for each trigger
	 * it is used with, in case the rowtype or transition table names are
	 * different.  Zero if not called as a DML trigger.
	 */
	Oid			trigOid;

	/*
	 * We must include the input collation as part of the hash key too,
	 * because we have to generate different plans (with different Param
	 * collations) for different collation settings.
	 */
	Oid			inputCollation;

	/*
	 * We include actual argument types in the hash key to support polymorphic
	 * PLpgSQL functions.  Be careful that extra positions are zeroed!
	 */
	Oid			argtypes[FUNC_MAX_ARGS];
} PLiSQL_func_hashkey;

/*
 * Trigger type
 */
typedef enum PLiSQL_trigtype
{
	PLISQL_DML_TRIGGER,
	PLISQL_EVENT_TRIGGER,
	PLISQL_NOT_TRIGGER
} PLiSQL_trigtype;

/*
 * Complete compiled function
 */
typedef struct PLiSQL_function
{
	char	   *fn_signature;
	Oid			fn_oid;
	TransactionId fn_xmin;
	ItemPointerData fn_tid;
	PLiSQL_trigtype fn_is_trigger;
	Oid			fn_input_collation;
	PLiSQL_func_hashkey *fn_hashkey;	/* back-link to hashtable key */
	MemoryContext fn_cxt;

	Oid			fn_rettype;
	int			fn_rettyplen;
	bool		fn_retbyval;
	bool		fn_retistuple;
	bool		fn_retisdomain;
	bool		fn_retset;
	bool		fn_readonly;
	char		fn_prokind;

	int			fn_nargs;
	int			fn_argvarnos[FUNC_MAX_ARGS];
	int			out_param_varno;
	int			found_varno;
	int			new_varno;
	int			old_varno;

	PLiSQL_resolve_option resolve_option;

	bool		print_strict_params;

	/* extra checks */
	int			extra_warnings;
	int			extra_errors;

	/* the datums representing the function's local variables */
	int			ndatums;
	PLiSQL_datum **datums;
	Size		copiable_size;	/* space for locally instantiated datums */

	int			nsubprocfuncs;
	struct PLiSQL_subproc_function **subprocfuncs;

	PackageCacheItem	*item;	/* if this function comes from a package */
	List				*funclist;	/* functions list which references to package */
	List				*pkgcachelist;	/* references to package'cache list */
	char				*namelabel;		/* for label */

	/* function body parsetree */
	PLiSQL_stmt_block *action;

	/* data derived while parsing body */
	unsigned int nstatements;	/* counter for assigning stmtids */
	bool		requires_procedure_resowner;	/* contains CALL or DO? */

	/* these fields change when the function is used */
	struct PLiSQL_execstate *cur_estate;
	unsigned long use_count;
} PLiSQL_function;

typedef struct plisql_hashent
{
	PLiSQL_func_hashkey key;
	PLiSQL_function *function;
} plisql_HashEnt;

/*
 * Runtime execution data
 */
typedef struct PLiSQL_execstate
{
	PLiSQL_function *func;		/* function being executed */

	TriggerData *trigdata;		/* if regular trigger, data about firing */
	EventTriggerData *evtrigdata;	/* if event trigger, data about firing */

	Datum		retval;
	bool		retisnull;
	Oid			rettype;		/* type of current retval */
	bool		retpkgvar;		/* ret comes from a package'var */

	Oid			fn_rettype;		/* info about declared function rettype */
	bool		retistuple;
	bool		retisset;

	bool		readonly_func;
	bool		atomic;

	char	   *exitlabel;		/* the "target" label of the current EXIT or
								 * CONTINUE stmt, if any */
	ErrorData  *cur_error;		/* current exception handler's error */

	Tuplestorestate *tuple_store;	/* SRFs accumulate results here */
	TupleDesc	tuple_store_desc;	/* descriptor for tuples in tuple_store */
	MemoryContext tuple_store_cxt;
	ResourceOwner tuple_store_owner;
	ReturnSetInfo *rsi;

	int			found_varno;

	/*
	 * The datums representing the function's local variables.  Some of these
	 * are local storage in this execstate, but some just point to the shared
	 * copy belonging to the PLiSQL_function, depending on whether or not we
	 * need any per-execution state for the datum's dtype.
	 */
	int			ndatums;
	PLiSQL_datum **datums;
	/* context containing variable values (same as func's SPI_proc context) */
	MemoryContext datum_context;

	/*
	 * paramLI is what we use to pass local variable values to the executor.
	 * It does not have a ParamExternData array; we just dynamically
	 * instantiate parameter data as needed.  By convention, PARAM_EXTERN
	 * Params have paramid equal to the dno of the referenced local variable.
	 */
	ParamListInfo paramLI;

	/* EState and resowner to use for "simple" expression evaluation */
	EState	   *simple_eval_estate;
	ResourceOwner simple_eval_resowner;

	/* if running nonatomic procedure or DO block, resowner to use for CALL */
	ResourceOwner procedure_resowner;

	/* lookup table to use for executing type casts */
	HTAB	   *cast_hash;

	/* memory context for statement-lifespan temporary values */
	MemoryContext stmt_mcontext;	/* current stmt context, or NULL if none */
	MemoryContext stmt_mcontext_parent; /* parent of current context */

	/* temporary state for results from evaluation of query or expr */
	SPITupleTable *eval_tuptable;
	uint64		eval_processed;
	ExprContext *eval_econtext; /* for executing simple expressions */

	/* status information for error context reporting */
	PLiSQL_stmt *err_stmt;		/* current stmt */
	PLiSQL_variable *err_var;	/* current variable, if in a DECLARE section */
	const char *err_text;		/* additional state info */

	void	   *plugin_info;	/* reserved for use by optional plugin */
} PLiSQL_execstate;

/*
 * A PLiSQL_plugin structure represents an instrumentation plugin.
 * To instrument PL/pgSQL, a plugin library must access the rendezvous
 * variable "PLiSQL_plugin" and set it to point to a PLiSQL_plugin struct.
 * Typically the struct could just be static data in the plugin library.
 * We expect that a plugin would do this at library load time (_PG_init()).
 * It must also be careful to set the rendezvous variable back to NULL
 * if it is unloaded (_PG_fini()).
 *
 * This structure is basically a collection of function pointers --- at
 * various interesting points in pl_exec.c, we call these functions
 * (if the pointers are non-NULL) to give the plugin a chance to watch
 * what we are doing.
 *
 * func_setup is called when we start a function, before we've initialized
 * the local variables defined by the function.
 *
 * func_beg is called when we start a function, after we've initialized
 * the local variables.
 *
 * func_end is called at the end of a function.
 *
 * stmt_beg and stmt_end are called before and after (respectively) each
 * statement.
 *
 * Also, immediately before any call to func_setup, PL/pgSQL fills in the
 * remaining fields with pointers to some of its own functions, allowing the
 * plugin to invoke those functions conveniently.  The exposed functions are:
 *		plisql_exec_error_callback
 *		exec_assign_expr
 *		exec_assign_value
 *		exec_eval_datum
 *		exec_cast_value
 * (plisql_exec_error_callback is not actually meant to be called by the
 * plugin, but rather to allow it to identify PL/iSQL error context stack
 * frames.  The others are useful for debugger-like plugins to examine and
 * set variables.)
 */
typedef struct PLiSQL_plugin
{
	/* Function pointers set up by the plugin */
	void		(*func_setup) (PLiSQL_execstate *estate, PLiSQL_function *func);
	void		(*func_beg) (PLiSQL_execstate *estate, PLiSQL_function *func);
	void		(*func_end) (PLiSQL_execstate *estate, PLiSQL_function *func);
	void		(*stmt_beg) (PLiSQL_execstate *estate, PLiSQL_stmt *stmt);
	void		(*stmt_end) (PLiSQL_execstate *estate, PLiSQL_stmt *stmt);

	/* Function pointers set by PL/pgSQL itself */
	void		(*error_callback) (void *arg);
	void		(*assign_expr) (PLiSQL_execstate *estate,
								PLiSQL_datum *target,
								PLiSQL_expr *expr);
	void		(*assign_value) (PLiSQL_execstate *estate,
								 PLiSQL_datum *target,
								 Datum value, bool isNull,
								 Oid valtype, int32 valtypmod);
	void		(*eval_datum) (PLiSQL_execstate *estate, PLiSQL_datum *datum,
							   Oid *typeId, int32 *typetypmod,
							   Datum *value, bool *isnull);
	Datum		(*cast_value) (PLiSQL_execstate *estate,
							   Datum value, bool *isnull,
							   Oid valtype, int32 valtypmod,
							   Oid reqtype, int32 reqtypmod);
} PLiSQL_plugin;

/*
 * Struct types used during parsing
 */

typedef struct PLword
{
	char	   *ident;			/* palloc'd converted identifier */
	bool		quoted;			/* Was it double-quoted? */
} PLword;

typedef struct PLcword
{
	List	   *idents;			/* composite identifiers (list of String) */
} PLcword;

typedef struct PLwdatum
{
	PLiSQL_datum *datum;		/* referenced variable */
	char	   *ident;			/* valid if simple name */
	bool		quoted;
	List	   *idents;			/* valid if composite name */
	int			nname_used;		/* to find datum, we match idents n names */
} PLwdatum;

/**********************************************************************
 * Global variable declarations
 **********************************************************************/

typedef enum
{
	IDENTIFIER_LOOKUP_NORMAL,	/* normal processing of var names */
	IDENTIFIER_LOOKUP_DECLARE,	/* In DECLARE --- don't look up names */
	IDENTIFIER_LOOKUP_EXPR		/* In SQL expression --- special case */
} IdentifierLookup;

extern IdentifierLookup plisql_IdentifierLookup;

extern int	plisql_variable_conflict;

extern bool plisql_print_strict_params;

extern bool plisql_check_asserts;

/* extra compile-time and run-time checks */
#define PLISQL_XCHECK_NONE						0
#define PLISQL_XCHECK_SHADOWVAR				(1 << 1)
#define PLISQL_XCHECK_TOOMANYROWS				(1 << 2)
#define PLISQL_XCHECK_STRICTMULTIASSIGNMENT	(1 << 3)
#define PLISQL_XCHECK_ALL						((int) ~0)

extern int	plisql_extra_warnings;
extern int	plisql_extra_errors;

extern bool plisql_check_syntax;
extern bool plisql_DumpExecTree;

extern PLiSQL_stmt_block *plisql_parse_result;

extern int	plisql_nDatums;
extern PLiSQL_datum **plisql_Datums;

extern int datums_last;

extern int datums_alloc;

extern char *plisql_error_funcname;

extern PLiSQL_function *plisql_curr_compile;
extern MemoryContext plisql_compile_tmp_cxt;

extern PLiSQL_plugin **plisql_plugin_ptr;

/**********************************************************************
 * Function declarations
 **********************************************************************/

/*
 * Functions in pl_comp.c
 */
extern PGDLLEXPORT PLiSQL_function *plisql_compile(FunctionCallInfo fcinfo,
													 bool forValidator);

extern PLiSQL_function *plisql_compile_inline(char *proc_source);
extern PGDLLEXPORT void plisql_parser_setup(struct ParseState *pstate,
								 PLiSQL_expr *expr);
extern bool plisql_parse_word(char *word1, const char *yytxt, bool lookup,
							   PLwdatum *wdatum, PLword *word);
extern bool plisql_parse_dblword(char *word1, char *word2,
								  PLwdatum *wdatum, PLcword *cword);
extern bool plisql_parse_tripword(char *word1, char *word2, char *word3,
								   PLwdatum *wdatum, PLcword *cword);
extern PLiSQL_type *plisql_parse_wordtype(char *ident);
extern PLiSQL_type *plisql_parse_cwordtype(List *idents);
extern PLiSQL_type *plisql_parse_wordrowtype(char *ident);
extern PLiSQL_type *plisql_parse_cwordrowtype(List *idents);
extern PGDLLEXPORT PLiSQL_type *plisql_build_datatype(Oid typeOid, int32 typmod,
											Oid collation,
											TypeName *origtypname);
extern PLiSQL_type *plisql_build_datatype_arrayof(PLiSQL_type *dtype);
extern PLiSQL_variable *plisql_build_variable(const char *refname, int lineno,
												PLiSQL_type *dtype,
												bool add2namespace);
extern PLiSQL_rec *plisql_build_record(const char *refname, int lineno,
										 PLiSQL_type *dtype, Oid rectypeid,
										 bool add2namespace);
extern PLiSQL_recfield *plisql_build_recfield(PLiSQL_rec *rec,
												const char *fldname);
extern PGDLLEXPORT int	plisql_recognize_err_condition(const char *condname,
											bool allow_sqlstate);
extern PLiSQL_condition *plisql_parse_err_condition(char *condname);
extern void plisql_adddatum(PLiSQL_datum *newdatum);
extern int	plisql_add_initdatums(int **varnos);
extern void plisql_HashTableInit(void);

extern void plisql_resolve_polymorphic_argtypes(int numargs,
												 Oid *argtypes, char *argmodes,
												 Node *call_expr, bool forValidator,
												 const char *proname);
extern void add_parameter_name(PLiSQL_nsitem_type itemtype, int itemno, const char *name);
extern PLiSQL_row *build_row_from_vars(PLiSQL_variable **vars, int numvars);
extern void add_dummy_return(PLiSQL_function *function);
extern void plisql_start_datums(void);
extern void plisql_compile_error_callback(void *arg);
extern void plisql_finish_datums(PLiSQL_function *function);

extern void delete_function(PLiSQL_function *func);

/*
 * Functions in pl_exec.c
 */
extern Datum plisql_exec_function(PLiSQL_function *func,
								   FunctionCallInfo fcinfo,
								   EState *simple_eval_estate,
								   ResourceOwner simple_eval_resowner,
								   ResourceOwner procedure_resowner,
								   bool atomic);
extern HeapTuple plisql_exec_trigger(PLiSQL_function *func,
									  TriggerData *trigdata);
extern void plisql_exec_event_trigger(PLiSQL_function *func,
									   EventTriggerData *trigdata);
extern void plisql_xact_cb(XactEvent event, void *arg);
extern void plisql_subxact_cb(SubXactEvent event, SubTransactionId mySubid,
							   SubTransactionId parentSubid, void *arg);
extern PGDLLEXPORT Oid	plisql_exec_get_datum_type(PLiSQL_execstate *estate,
										PLiSQL_datum *datum);
extern void plisql_exec_get_datum_type_info(PLiSQL_execstate *estate,
											 PLiSQL_datum *datum,
											 Oid *typeId, int32 *typMod,
											 Oid *collation);

extern void plisql_assign_in_global_var(PLiSQL_execstate *estate,
													 PLiSQL_execstate *parestate,
													 int dno);
extern void plisql_assign_out_global_var(PLiSQL_execstate *estate,
										 PLiSQL_execstate *parestate,
										 int dno,
										 int spilevel);


/*
 * Functions for namespace handling in pl_funcs.c
 */
extern void plisql_ns_init(void);
extern void plisql_set_ns(PLiSQL_nsitem *cur);
extern void plisql_ns_push(const char *label,
							PLiSQL_label_type label_type);
extern void plisql_ns_pop(void);
extern PLiSQL_nsitem *plisql_ns_top(void);
extern void plisql_ns_additem(PLiSQL_nsitem_type itemtype, int itemno, const char *name);
extern PGDLLEXPORT PLiSQL_nsitem *plisql_ns_lookup(PLiSQL_nsitem *ns_cur, bool localmode,
										 const char *name1, const char *name2,
										 const char *name3, int *names_used);
extern PLiSQL_nsitem *plisql_ns_lookup_label(PLiSQL_nsitem *ns_cur,
											   const char *name);
extern PLiSQL_nsitem *plisql_ns_find_nearest_loop(PLiSQL_nsitem *ns_cur);

/*
 * Other functions in pl_funcs.c
 */
extern PGDLLEXPORT const char *plisql_stmt_typename(PLiSQL_stmt *stmt);
extern const char *plisql_getdiag_kindname(PLiSQL_getdiag_kind kind);
extern void plisql_free_function_memory(PLiSQL_function *func,
							int start_datum, int start_inlinefunc);
extern void plisql_dumptree(PLiSQL_function *func, int start_datum, int start_subprocfunc); 

/*
 * Scanner functions in pl_scanner.c
 */
extern int	plisql_base_yylex(void);
extern int	plisql_yylex(void);
extern int	plisql_token_length(void);
extern void plisql_push_back_token(int token);
extern bool plisql_token_is_unreserved_keyword(int token);
extern void plisql_append_source_text(StringInfo buf,
									   int startlocation, int endlocation);
extern int	plisql_peek(void);
extern void plisql_peek2(int *tok1_p, int *tok2_p, int *tok1_loc,
						  int *tok2_loc);
extern int	plisql_scanner_errposition(int location);
extern void plisql_yyerror(const char *message) pg_attribute_noreturn();
extern int	plisql_location_to_lineno(int location);
extern int	plisql_latest_lineno(void);
extern void plisql_scanner_init(const char *str);
extern void plisql_scanner_finish(void);
extern void *plisql_get_yylex_global_proper(void);
extern void plisql_recover_yylex_global_proper(void *yylex_data);


/*
 * Externs in gram.y
 */
extern int	plisql_yyparse(void);

#endif							/* PLPGSQL_H */
