%{
/*-------------------------------------------------------------------------
 *
 * pl_gram.y			- Parser for the PL/iSQL procedural language
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_gram.y
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "parser/parser.h"
#include "parser/parse_type.h"
#include "oracle_parser/ora_scanner.h"
#include "parser/scansup.h"
#include "utils/builtins.h"

#include "plisql.h"

#include "pl_subproc_function.h"

#include "pl_package.h"
#include "pg_config.h"

#include "utils/ora_compatible.h"

/* Location tracking support --- simpler than bison's default */
#define YYLLOC_DEFAULT(Current, Rhs, N) \
	do { \
		if (N) \
			(Current) = (Rhs)[1]; \
		else \
			(Current) = (Rhs)[0]; \
	} while (0)

/*
 * Bison doesn't allocate anything that needs to live across parser calls,
 * so we can easily have it use palloc instead of malloc.  This prevents
 * memory leaks if we error out during parsing.
 */
#define YYMALLOC palloc
#define YYFREE   pfree


typedef struct
{
	int			location;
} sql_error_callback_arg;

#define parser_errposition(pos)  plisql_scanner_errposition(pos)

union YYSTYPE;					/* need forward reference for tok_is_keyword */

static	bool			tok_is_keyword(int token, union YYSTYPE *lval,
									   int kw_token, const char *kw_str);
static	void			word_is_not_variable(PLword *word, int location);
static	void			cword_is_not_variable(PLcword *cword, int location);
static	void			current_token_is_not_variable(int tok);
static	PLiSQL_expr	*read_sql_construct(int until,
											int until2,
											int until3,
											const char *expected,
											RawParseMode parsemode,
											bool isexpression,
											bool valid_sql,
											int *startloc,
											int *endtoken);
static	PLiSQL_expr	*read_sql_expression(int until,
											 const char *expected);
static	PLiSQL_expr	*read_sql_expression2(int until, int until2,
											  const char *expected,
											  int *endtoken);
static	PLiSQL_expr	*read_sql_stmt(void);
static	PLiSQL_type	*read_datatype(int tok);
static	PLiSQL_stmt	*make_execsql_stmt(int firsttoken, int location);
static	PLiSQL_stmt_fetch *read_fetch_direction(void);
static	void			 complete_direction(PLiSQL_stmt_fetch *fetch,
											bool *check_FROM);
static	PLiSQL_stmt	*make_return_stmt(int location);
static	PLiSQL_stmt	*make_return_next_stmt(int location);
static	PLiSQL_stmt	*make_return_query_stmt(int location);
static  PLiSQL_stmt	*make_case(int location, PLiSQL_expr *t_expr,
								   List *case_when_list, List *else_stmts);
static	char			*NameOfDatum(PLwdatum *wdatum);
static	void			 check_assignable(PLiSQL_datum *datum, int location);
static void check_packagedatum_assignable(PLiSQL_pkg_datum *datum,
											int location);

static	void			 read_into_target(PLiSQL_variable **target,
										  bool *strict);
static	PLiSQL_row		*read_into_scalar_list(char *initial_name,
											   PLiSQL_datum *initial_datum,
											   int initial_location);
static	PLiSQL_row		*make_scalar_list1(char *initial_name,
										   PLiSQL_datum *initial_datum,
										   int lineno, int location);
static	void			 check_sql_expr(const char *stmt,
										RawParseMode parseMode, int location);
static	void			 plisql_sql_error_callback(void *arg);
static	PLiSQL_type	*parse_datatype(const char *string, int location);
static	void			 check_labels(const char *start_label,
									  const char *end_label,
									  int end_location);
static	PLiSQL_expr	*read_cursor_args(PLiSQL_var *cursor,
										  int until);
static	List			*read_raise_options(void);
static	void			check_raise_parameters(PLiSQL_stmt_raise *stmt);
static	PLiSQL_expr		*build_call_expr(int firsttoken, int location);
%}

%expect 0
%name-prefix="plisql_yy"
%locations

%union
{
		ora_core_YYSTYPE			core_yystype;
		/* these fields must match ora_core_YYSTYPE: */
		int						ival;
		char					*str;
		const char				*keyword;

		PLword					word;
		PLcword					cword;
		PLwdatum				wdatum;
		bool					boolean;
		Oid						oid;
		struct
		{
			char *name;
			int  lineno;
		}						varname;
		struct
		{
			char *name;
			int  lineno;
			PLiSQL_datum   *scalar;
			PLiSQL_datum   *row;
		}						forvariable;
		struct
		{
			char *label;
			int  n_initvars;
			int  *initvarnos;
			bool popname;
		}						declhdr;
		struct
		{
			List *stmts;
			char *end_label;
			int   end_label_location;
		}						loop_body;
		List					*list;
		PLiSQL_type			*dtype;
		PLiSQL_datum			*datum;
		PLiSQL_var				*var;
		PLiSQL_expr			*expr;
		PLiSQL_stmt			*stmt;
		PLiSQL_condition		*condition;
		PLiSQL_exception		*exception;
		PLiSQL_exception_block	*exception_block;
		PLiSQL_nsitem			*nsitem;
		PLiSQL_diag_item		*diagitem;
		PLiSQL_stmt_fetch		*fetch;
		PLiSQL_case_when		*casewhen;
		PLiSQL_function_argitem *func_argitem;
		PLiSQL_subproc_function *subproc_func;
		PLiSQL_subprocfunc_proper *func_proper;
		AccessProperItem *access_proper_item;
		AccessProperItemType access_proper_kind;
}

%type <declhdr> decl_sect
%type <varname> decl_varname
%type <boolean>	decl_const decl_notnull exit_type
%type <expr>	decl_defval decl_cursor_query
%type <dtype>	decl_datatype
%type <oid>		decl_collate
%type <datum>	decl_cursor_args
%type <list>	decl_cursor_arglist
%type <nsitem>	decl_aliasitem

%type <expr>	expr_until_semi
%type <expr>	expr_until_then expr_until_loop opt_expr_until_when
%type <expr>	opt_exitcond

%type <var>		cursor_variable
%type <datum>	decl_cursor_arg
%type <forvariable>	for_variable
%type <ival>	foreach_slice
%type <stmt>	for_control

%type <str>		any_identifier opt_block_label opt_loop_label opt_label
%type <str>		option_value

%type <list>	proc_sect stmt_elsifs stmt_else
%type <loop_body>	loop_body
%type <stmt>	proc_stmt pl_block
%type <stmt>	stmt_assign stmt_if stmt_loop stmt_while stmt_exit
%type <stmt>	stmt_return stmt_raise stmt_assert stmt_execsql
%type <stmt>	stmt_dynexecute stmt_for stmt_perform stmt_call stmt_getdiag
%type <stmt>	stmt_open stmt_fetch stmt_move stmt_close stmt_null
%type <stmt>	stmt_commit stmt_rollback
%type <stmt>	stmt_case stmt_foreach_a

%type <list>	proc_exceptions
%type <exception_block> exception_sect
%type <exception>	proc_exception
%type <condition>	proc_conditions proc_condition

%type <casewhen>	case_when
%type <list>	case_when_list opt_case_else

%type <boolean>	getdiag_area_opt
%type <list>	getdiag_list
%type <diagitem> getdiag_list_item
%type <datum>	getdiag_target
%type <ival>	getdiag_item

%type <ival>	opt_scrollable
%type <fetch>	opt_fetch_direction

%type <ival>	opt_transaction_chain

%type <keyword>	unreserved_keyword

%type <keyword> unit_name_keyword
%type <str> ora_function_name unit_name authid_user extral_unit_name
%type <list> func_arg_list func_args procedure_properties_list accessor_list
%type <list> function_result_cache_relies data_source procedure_properties
%type <list> function_properite_list function_properties
%type <func_argitem> func_arg_item
%type <subproc_func>function_heading procedure_heading
%type <func_proper> function_properite_item invoker_rights_clause
%type <func_proper> procedure_properite_item accessible_by_clause default_collation_clause
%type <access_proper_item> accessor
%type <access_proper_kind> unit_kind
%type <keyword> ora_function_is_as
%type <ival> arg_mode
%type <expr> arg_decl_defval
%type <boolean> function_arg_nocopy

%type <stmt> ora_outermost_pl_block
%type <declhdr> ora_decl_sect
%type <boolean> opt_ora_decl_stmts

%type <stmt> ora_pl_package
%type <str> ora_first_opt_block_label
%type <boolean> opt_ora_decl_start

/*
 * Basic non-keyword token types.  These are hard-wired into the core lexer.
 * They must be listed first so that their numeric codes do not depend on
 * the set of keywords.  Keep this list in sync with backend/parser/ora_gram.y!
 *
 * Some of these are not directly referenced in this file, but they must be
 * here anyway.
 */
%token <str>	IDENT UIDENT FCONST SCONST USCONST BCONST XCONST Op
%token <str>	BFCONST	BDCONST
%token <ival>	ICONST PARAM
%token			TYPECAST DOT_DOT COLON_EQUALS EQUALS_GREATER
%token			LESS_EQUALS GREATER_EQUALS NOT_EQUALS LESS_LESS GREATER_GREATER

/*
 * Other tokens recognized by plisql's lexer interface layer (pl_scanner.c).
 */
%token <word>		T_WORD		/* unrecognized simple identifier */
%token <cword>		T_CWORD		/* unrecognized composite identifier */
%token <wdatum>		T_DATUM		/* a VAR, ROW, REC, or RECFIELD variable */

/*
 * Keyword tokens.  Some of these are reserved and some are not;
 * see pl_scanner.c for info.  Be sure unreserved keywords are listed
 * in the "unreserved_keyword" production below.
 */
%token <keyword>	K_ABSOLUTE
%token <keyword>	K_ACCESSIBLE
%token <keyword>	K_ALIAS
%token <keyword>	K_ALL
%token <keyword>	K_AND
%token <keyword>	K_ARRAY
%token <keyword>	K_AS
%token <keyword>	K_ASSERT
%token <keyword>	K_AUTHID
%token <keyword>	K_BACKWARD
%token <keyword>	K_BEGIN
%token <keyword>	K_BY
%token <keyword>	K_CALL
%token <keyword>	K_CASE
%token <keyword>	K_CHAIN
%token <keyword>	K_CLOSE
%token <keyword>	K_COLLATE
%token <keyword>	K_COLLATION
%token <keyword>	K_COLUMN
%token <keyword>	K_COLUMN_NAME
%token <keyword>	K_COMMIT
%token <keyword>	K_CONSTANT
%token <keyword>	K_CONSTRAINT
%token <keyword>	K_CONSTRAINT_NAME
%token <keyword>	K_CONTINUE
%token <keyword>	K_CURRENT
%token <keyword>	K_CURRENT_USER
%token <keyword>	K_CURSOR
%token <keyword>	K_DATATYPE
%token <keyword>	K_DEBUG
%token <keyword>	K_DECLARE
%token <keyword>	K_DEFAULT
%token <keyword>	K_DEFINER
%token <keyword>	K_DETAIL
%token <keyword>	K_DETERMINISTIC
%token <keyword>	K_DIAGNOSTICS
%token <keyword>	K_DO
%token <keyword>	K_DUMP
%token <keyword>	K_ELSE
%token <keyword>	K_ELSIF
%token <keyword>	K_END
%token <keyword>	K_ERRCODE
%token <keyword>	K_ERROR
%token <keyword>	K_EXCEPTION
%token <keyword>	K_EXECUTE
%token <keyword>	K_EXIT
%token <keyword>	K_FETCH
%token <keyword>	K_FIRST
%token <keyword>	K_FOR
%token <keyword>	K_FOREACH
%token <keyword>	K_FORWARD
%token <keyword>	K_FROM
%token <keyword>	K_FUNCTION
%token <keyword>	K_GET
%token <keyword>	K_HINT
%token <keyword>	K_IF
%token <keyword>	K_IMPORT
%token <keyword>	K_IN
%token <keyword>	K_INFO
%token <keyword>	K_INSERT
%token <keyword>	K_INTO
%token <keyword>	K_IS
%token <keyword>	K_LAST
%token <keyword>	K_LOG
%token <keyword>	K_LOOP
%token <keyword>	K_MERGE
%token <keyword>	K_MESSAGE
%token <keyword>	K_MESSAGE_TEXT
%token <keyword>	K_MOVE
%token <keyword>	K_NEXT
%token <keyword>	K_NO
%token <keyword>	K_NOCOPY
%token <keyword>	K_NOT
%token <keyword>	K_NOTICE
%token <keyword>	K_NULL
%token <keyword>	K_OPEN
%token <keyword>	K_OPTION
%token <keyword>	K_OR
%token <keyword>	K_OUT
%token <keyword>	K_PACKAGE
%token <keyword>	K_PARALLEL_ENABLE
%token <keyword>	K_PERFORM
%token <keyword>	K_PG_CONTEXT
%token <keyword>	K_PG_DATATYPE_NAME
%token <keyword>	K_PG_EXCEPTION_CONTEXT
%token <keyword>	K_PG_EXCEPTION_DETAIL
%token <keyword>	K_PG_EXCEPTION_HINT
%token <keyword>	K_PIPELINED
%token <keyword>	K_PG_ROUTINE_OID
%token <keyword>	K_PRINT_STRICT_PARAMS
%token <keyword>	K_PRIOR
%token <keyword>	K_PROCEDURE
%token <keyword>	K_QUERY
%token <keyword>	K_RAISE
%token <keyword>	K_RELATIVE
%token <keyword>	K_RELIES_ON
%token <keyword>	K_RESULT_CACHE
%token <keyword>	K_RETURN
%token <keyword>	K_RETURNED_SQLSTATE
%token <keyword>	K_REVERSE
%token <keyword>	K_ROLLBACK
%token <keyword>	K_ROW_COUNT
%token <keyword>	K_ROWTYPE
%token <keyword>	K_SCHEMA
%token <keyword>	K_SCHEMA_NAME
%token <keyword>	K_SCROLL
%token <keyword>	K_SLICE
%token <keyword>	K_SQLSTATE
%token <keyword>	K_STACKED
%token <keyword>	K_STRICT
%token <keyword>	K_TABLE
%token <keyword>	K_TABLE_NAME
%token <keyword>	K_THEN
%token <keyword>	K_TO
%token <keyword>	K_TRIGGER
%token <keyword>	K_TYPE
%token <keyword>	K_USE_COLUMN
%token <keyword>	K_USE_VARIABLE
%token <keyword>	K_USING
%token <keyword>	K_USING_NLS_COMP
%token <keyword>	K_VARIABLE_CONFLICT
%token <keyword>	K_WARNING
%token <keyword>	K_WHEN
%token <keyword>	K_WHILE

%%

pl_function		: comp_options ora_outermost_pl_block opt_semi
					{
						plisql_parse_result = (PLiSQL_stmt_block *) $2;
					}
				| comp_options ora_pl_package opt_semi
					{
						plisql_parse_result = (PLiSQL_stmt_block *) $2;
					}
				;

comp_options	:
				| comp_options comp_option
				;

comp_option		: '#' K_OPTION K_DUMP
					{
						plisql_DumpExecTree = true;
					}
				| '#' K_PRINT_STRICT_PARAMS option_value
					{
						if (strcmp($3, "on") == 0)
							plisql_curr_compile->print_strict_params = true;
						else if (strcmp($3, "off") == 0)
							plisql_curr_compile->print_strict_params = false;
						else
							elog(ERROR, "unrecognized print_strict_params option %s", $3);
					}
				| '#' K_VARIABLE_CONFLICT K_ERROR
					{
						plisql_curr_compile->resolve_option = PLISQL_RESOLVE_ERROR;
					}
				| '#' K_VARIABLE_CONFLICT K_USE_VARIABLE
					{
						plisql_curr_compile->resolve_option = PLISQL_RESOLVE_VARIABLE;
					}
				| '#' K_VARIABLE_CONFLICT K_USE_COLUMN
					{
						plisql_curr_compile->resolve_option = PLISQL_RESOLVE_COLUMN;
					}
				;

option_value : T_WORD
				{
					$$ = $1.ident;
				}
			 | unreserved_keyword
				{
					$$ = pstrdup($1);
				}

opt_semi		:
				| ';'
				;

ora_outermost_pl_block		: ora_decl_sect K_BEGIN proc_sect exception_sect K_END opt_label
		{
			PLiSQL_stmt_block *new;

			/* package specification doesn't be allowed to include begin */
			if (plisql_compile_packageitem != NULL &&
				!plisql_compile_packageitem->finish_compile_special)
				yyerror("syntax error for package specificaion have a body");

			/* we only consider package body level */
			if (plisql_compile_packageitem != NULL &&
				cur_compile_func_level == 0)
			{
				plisql_check_package_refcursor_var(-1);
				plisql_compile_packageitem->last_globaldno =
							plisql_get_package_last_globaldno($4 == NULL ? -1 : $4->sqlstate_varno,
											$4 == NULL ? -1 : $4->sqlerrm_varno);
			}

			new = palloc0(sizeof(PLiSQL_stmt_block));

			new->cmd_type = PLISQL_STMT_BLOCK;
			new->lineno 	= plisql_location_to_lineno(@2);
			new->stmtid 	= ++plisql_curr_compile->nstatements;
			new->label		= $1.label;
			new->n_initvars = $1.n_initvars;
			new->initvarnos = $1.initvarnos;
			new->body 	= $3;
			new->exceptions = $4;

			check_labels($1.label, $6, @6);
			/*
			 * no decalre keyword, we don't add lable block namespace
			 */
			if ($1.popname)
				plisql_ns_pop();

			$$ = (PLiSQL_stmt *)new;
		}
	;

/*
 * package and its body define for which
 * has no init block
 */
ora_pl_package: ora_decl_sect K_END opt_label
			{
				PLiSQL_stmt_block *new;

				if (plisql_compile_packageitem == NULL)
					yyerror("syntax error");

				new = palloc0(sizeof(PLiSQL_stmt_block));

				new->cmd_type	= PLISQL_STMT_BLOCK;
				new->lineno		= plisql_location_to_lineno(@2);
				new->stmtid		= ++plisql_curr_compile->nstatements;
				new->label	= $1.label;
				new->n_initvars = $1.n_initvars;
				new->initvarnos = $1.initvarnos;

				plisql_compile_packageitem->special_cur = plisql_ns_top();
				plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
				/* Remember variables declared in decl_stmts */
				check_labels($1.label, $3, @3);
				plisql_check_package_refcursor_var(-1);
				plisql_compile_packageitem->last_globaldno =
										plisql_get_package_last_globaldno(-1, -1);
				if (!plisql_compile_packageitem->finish_compile_special)
					plisql_compile_packageitem->status =
								plisql_set_package_compile_status();
				/*
				 * no decalre keyword, we don't add lable block namespace
				 */
				if ($1.popname)
					plisql_ns_pop();

				$$ = (PLiSQL_stmt *)new;
			}
;

ora_decl_sect: ora_first_opt_block_label opt_ora_decl_start
				{
					if ($2)
					{
						if ($1 == NULL)
						{
							plisql_ns_push(NULL, PLISQL_LABEL_BLOCK);
						}
					}
				}
				opt_ora_decl_stmts
				{
					if ($4)
					{
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
						$$.label	  = ($1 == NULL ?  plisql_curr_compile->namelabel : $1);
						if ($2 && $1 == NULL)
							$$.popname = true;
						else
							$$.popname = false;
						/* Remember variables declared in decl_stmts */
						$$.n_initvars = plisql_add_initdatums(&($$.initvarnos));
					}
					else
					{
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
						$$.label	  = ($1 == NULL ?  plisql_curr_compile->namelabel : $1);
						$$.n_initvars = 0;
						if ($2 && $1 == NULL)
							$$.popname = true;
						else
							$$.popname = false;
						$$.initvarnos = NULL;
					}
				}
		;

ora_first_opt_block_label:
					{
						$$ = NULL;
					}
				| LESS_LESS any_identifier GREATER_GREATER
					{
						plisql_ns_push($2, PLISQL_LABEL_BLOCK);
						$$ = $2;
					}
				;

opt_ora_decl_start: K_DECLARE
					{
						/* Forget any variables created before block */
						plisql_add_initdatums(NULL);
						/*
						 * Disable scanner lookup of identifiers while
						 * we process the decl_stmts
						 */
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
						$$ = true;
					}
				| /*EMPTY*/
					{
						/* Forget any variables created before block */
						plisql_add_initdatums(NULL);
						/*
						 * Disable scanner lookup of identifiers while
						 * we process the decl_stmts
						 */
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
						$$ = false;
					}
				;

opt_ora_decl_stmts:
			ora_decl_stmts
				{
					$$ = true;
				}
			| /*EMPTY*/
				{
					$$ = false;
				}

ora_decl_stmts: ora_decl_stmts ora_decl_stmt
			| ora_decl_stmt
			;

ora_decl_stmt: decl_statement
			;


pl_block		: decl_sect K_BEGIN proc_sect exception_sect K_END opt_label
					{
						PLiSQL_stmt_block *new;

						new = palloc0(sizeof(PLiSQL_stmt_block));

						new->cmd_type	= PLISQL_STMT_BLOCK;
						new->lineno		= plisql_location_to_lineno(@2);
						new->stmtid		= ++plisql_curr_compile->nstatements;
						new->label		= $1.label;
						new->n_initvars = $1.n_initvars;
						new->initvarnos = $1.initvarnos;
						new->body		= $3;
						new->exceptions	= $4;

						check_labels($1.label, $6, @6);
						plisql_ns_pop();

						$$ = (PLiSQL_stmt *)new;
					}
				;


decl_sect		: opt_block_label
					{
						/* done with decls, so resume identifier lookup */
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
						$$.label	  = $1;
						$$.n_initvars = 0;
						$$.initvarnos = NULL;
					}
				| opt_block_label decl_start
					{
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
						$$.label	  = $1;
						$$.n_initvars = 0;
						$$.initvarnos = NULL;
					}
				| opt_block_label decl_start decl_stmts
					{
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
						$$.label	  = $1;
						/* Remember variables declared in decl_stmts */
						$$.n_initvars = plisql_add_initdatums(&($$.initvarnos));
					}
				;

decl_start		: K_DECLARE
					{
						/* Forget any variables created before block */
						plisql_add_initdatums(NULL);
						/*
						 * Disable scanner lookup of identifiers while
						 * we process the decl_stmts
						 */
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
					}
				;

decl_stmts		: decl_stmts decl_stmt
				| decl_stmt
				;

decl_stmt		: decl_statement
				| K_DECLARE
					{
						/* We allow useless extra DECLAREs */
					}
				| LESS_LESS any_identifier GREATER_GREATER
					{
						/*
						 * Throw a helpful error if user tries to put block
						 * label just before BEGIN, instead of before DECLARE.
						 */
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("block label must be placed before DECLARE, not after"),
								 parser_errposition(@1)));
					}
				;

decl_statement	: decl_varname decl_const decl_datatype decl_collate decl_notnull decl_defval
					{
						PLiSQL_variable	*var;

						/*
						 * If a collation is supplied, insert it into the
						 * datatype.  We assume decl_datatype always returns
						 * a freshly built struct not shared with other
						 * variables.
						 */
						if (OidIsValid($4))
						{
							if (!OidIsValid($3->collation))
								ereport(ERROR,
										(errcode(ERRCODE_DATATYPE_MISMATCH),
										 errmsg("collations are not supported by type %s",
												format_type_be($3->typoid)),
										 parser_errposition(@4)));
							$3->collation = $4;
						}

						var = plisql_build_variable($1.name, $1.lineno,
													 $3, true);
						var->isconst = $2;
						var->notnull = $5;
						var->default_val = $6;

						/*
						 * The combination of NOT NULL without an initializer
						 * can't work, so let's reject it at compile time.
						 */
						if (var->notnull && var->default_val == NULL)
							ereport(ERROR,
									(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
									 errmsg("variable \"%s\" must have a default value, since it's declared NOT NULL",
											var->refname),
									 parser_errposition(@5)));
					}
				| decl_varname K_ALIAS K_FOR decl_aliasitem ';'
					{
						plisql_ns_additem($4->itemtype,
										   $4->itemno, $1.name);
					}
				| decl_varname opt_scrollable K_CURSOR
					{ plisql_ns_push($1.name, PLISQL_LABEL_OTHER); }
				  decl_cursor_args decl_is_for decl_cursor_query
					{
						PLiSQL_var *new;

						/* pop local namespace for cursor args */
						plisql_ns_pop();

						new = (PLiSQL_var *)
							plisql_build_variable($1.name, $1.lineno,
												   plisql_build_datatype(REFCURSOROID,
																		  -1,
																		  InvalidOid,
																		  NULL),
												   true);

						new->cursor_explicit_expr = $7;
						if ($5 == NULL)
							new->cursor_explicit_argrow = -1;
						else
							new->cursor_explicit_argrow = $5->dno;
						new->cursor_options = CURSOR_OPT_FAST_PLAN | $2;
					}
				/* function or procedure declare or define */
				| function_heading function_properties ';'
					{
						/* check does it duplicate declare */
						if ($1->has_declare)
							yyerror("duplicate declaration");
						$1->has_declare = true;
						/* check function properties */
						plisql_check_subprocfunc_properties($1, $2, true);
						if ($2 != NIL)
							list_free($2);
					}
				| function_heading function_properties ora_function_is_as
					{
						int found_varno = plisql_curr_compile->found_varno;

						plisql_check_subprocfunc_properties($1,$2, false);
						if ($2 != NIL)
							list_free($2);

						$1->lastoutsubprocfno = plisql_nsubprocFuncs;
						plisql_push_subproc_func();
						$1->global_cur = plisql_ns_top();
						plisql_ns_push($1->func_name, PLISQL_LABEL_BLOCK);
						plisql_start_subproc_func();
						plisql_curr_compile = $1->function;
						$1->lastassignvardno = plisql_nDatums;
						plisql_build_variable_from_funcargs($1, true, NULL, found_varno);
						plisql_add_initdatums(NULL);
					}
				ora_outermost_pl_block ';'
					{
						StringInfoData ds;

						plisql_set_subprocfunc_action($1, (PLiSQL_stmt_block *) $5);
						plisql_ns_pop();
						plisql_finish_datums($1->function);
						plisql_finish_subproc_func($1->function);
						plisql_pop_subproc_func();
						initStringInfo(&ds);
						plisql_append_source_text(&ds, @5 + 2, @6);
						$1->src = ds.data;
						$1->lastoutvardno = plisql_nDatums;
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
					}
				| procedure_heading procedure_properties ';'
					{
						/* check does it duplicate declare */
						if ($1->has_declare)
							yyerror("duplicate declaration");
						plisql_check_subprocfunc_properties($1,$2, false);
						if ($2 != NIL)
							list_free($2);
						$1->has_declare = true;
						$1->properties = $2;
					}
				| procedure_heading procedure_properties ora_function_is_as
					{
						int found_varno = plisql_curr_compile->found_varno;

						plisql_check_subprocfunc_properties($1,$2, false);
						if ($2 != NIL)
							list_free($2);

						$1->lastoutsubprocfno = plisql_nsubprocFuncs;
						plisql_push_subproc_func();
						$1->global_cur = plisql_ns_top();
						plisql_ns_push($1->func_name, PLISQL_LABEL_BLOCK);
						plisql_start_subproc_func();
						plisql_curr_compile = $1->function;
						$1->lastassignvardno = plisql_nDatums;
						plisql_build_variable_from_funcargs($1, true, NULL, found_varno);
						plisql_add_initdatums(NULL);
					}
				ora_outermost_pl_block ';'
					{
						StringInfoData ds;

						plisql_set_subprocfunc_action($1, (PLiSQL_stmt_block *) $5);
						plisql_ns_pop();
						plisql_finish_datums($1->function);
						plisql_finish_subproc_func($1->function);
						plisql_pop_subproc_func();
						initStringInfo(&ds);
						plisql_append_source_text(&ds, @5 + 2, @6);
						$1->src = ds.data;
						$1->lastoutvardno = plisql_nDatums;
						plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
					}
				;

opt_scrollable :
					{
						$$ = 0;
					}
				| K_NO K_SCROLL
					{
						$$ = CURSOR_OPT_NO_SCROLL;
					}
				| K_SCROLL
					{
						$$ = CURSOR_OPT_SCROLL;
					}
				;

decl_cursor_query :
					{
						$$ = read_sql_stmt();
					}
				;

decl_cursor_args :
					{
						$$ = NULL;
					}
				| '(' decl_cursor_arglist ')'
					{
						PLiSQL_row *new;
						int			i;
						ListCell   *l;

						new = palloc0(sizeof(PLiSQL_row));
						new->dtype = PLISQL_DTYPE_ROW;
						new->refname = "(unnamed row)";
						new->lineno = plisql_location_to_lineno(@1);
						new->rowtupdesc = NULL;
						new->nfields = list_length($2);
						new->fieldnames = palloc(new->nfields * sizeof(char *));
						new->varnos = palloc(new->nfields * sizeof(int));

						i = 0;
						foreach (l, $2)
						{
							PLiSQL_variable *arg = (PLiSQL_variable *) lfirst(l);
							Assert(!arg->isconst);
							new->fieldnames[i] = arg->refname;
							new->varnos[i] = arg->dno;
							i++;
						}
						list_free($2);

						plisql_adddatum((PLiSQL_datum *) new);
						$$ = (PLiSQL_datum *) new;
					}
				;

decl_cursor_arglist : decl_cursor_arg
					{
						$$ = list_make1($1);
					}
				| decl_cursor_arglist ',' decl_cursor_arg
					{
						$$ = lappend($1, $3);
					}
				;

decl_cursor_arg : decl_varname decl_datatype
					{
						$$ = (PLiSQL_datum *)
							plisql_build_variable($1.name, $1.lineno,
												   $2, true);
					}
				;

decl_is_for		:	K_IS |		/* Oracle */
					K_FOR;		/* SQL standard */

decl_aliasitem	: T_WORD
					{
						PLiSQL_nsitem *nsi;

						nsi = plisql_ns_lookup(plisql_ns_top(), false,
												$1.ident, NULL, NULL,
												NULL);
						if (nsi == NULL)
							ereport(ERROR,
									(errcode(ERRCODE_UNDEFINED_OBJECT),
									 errmsg("variable \"%s\" does not exist",
											$1.ident),
									 parser_errposition(@1)));
						$$ = nsi;
					}
				| unreserved_keyword
					{
						PLiSQL_nsitem *nsi;

						nsi = plisql_ns_lookup(plisql_ns_top(), false,
												$1, NULL, NULL,
												NULL);
						if (nsi == NULL)
							ereport(ERROR,
									(errcode(ERRCODE_UNDEFINED_OBJECT),
									 errmsg("variable \"%s\" does not exist",
											$1),
									 parser_errposition(@1)));
						$$ = nsi;
					}
				| T_CWORD
					{
						PLiSQL_nsitem *nsi;

						if (list_length($1.idents) == 2)
							nsi = plisql_ns_lookup(plisql_ns_top(), false,
													strVal(linitial($1.idents)),
													strVal(lsecond($1.idents)),
													NULL,
													NULL);
						else if (list_length($1.idents) == 3)
							nsi = plisql_ns_lookup(plisql_ns_top(), false,
													strVal(linitial($1.idents)),
													strVal(lsecond($1.idents)),
													strVal(lthird($1.idents)),
													NULL);
						else
							nsi = NULL;
						if (nsi == NULL)
							ereport(ERROR,
									(errcode(ERRCODE_UNDEFINED_OBJECT),
									 errmsg("variable \"%s\" does not exist",
											NameListToString($1.idents)),
									 parser_errposition(@1)));
						$$ = nsi;
					}
				;

decl_varname	: T_WORD
					{
						$$.name = $1.ident;
						$$.lineno = plisql_location_to_lineno(@1);
						/*
						 * Check to make sure name isn't already declared
						 * in the current block.
						 */
						if (plisql_ns_lookup(plisql_ns_top(), true,
											  $1.ident, NULL, NULL,
											  NULL) != NULL)
							yyerror("duplicate declaration");

						if (plisql_curr_compile->extra_warnings & PLISQL_XCHECK_SHADOWVAR ||
							plisql_curr_compile->extra_errors & PLISQL_XCHECK_SHADOWVAR)
						{
							PLiSQL_nsitem *nsi;
							nsi = plisql_ns_lookup(plisql_ns_top(), false,
													$1.ident, NULL, NULL, NULL);
							if (nsi != NULL)
								ereport(plisql_curr_compile->extra_errors & PLISQL_XCHECK_SHADOWVAR ? ERROR : WARNING,
										(errcode(ERRCODE_DUPLICATE_ALIAS),
										 errmsg("variable \"%s\" shadows a previously defined variable",
												$1.ident),
										 parser_errposition(@1)));
						}

					}
				| unreserved_keyword
					{
						$$.name = pstrdup($1);
						$$.lineno = plisql_location_to_lineno(@1);
						/*
						 * Check to make sure name isn't already declared
						 * in the current block.
						 */
						if (plisql_ns_lookup(plisql_ns_top(), true,
											  $1, NULL, NULL,
											  NULL) != NULL)
							yyerror("duplicate declaration");

						if (plisql_curr_compile->extra_warnings & PLISQL_XCHECK_SHADOWVAR ||
							plisql_curr_compile->extra_errors & PLISQL_XCHECK_SHADOWVAR)
						{
							PLiSQL_nsitem *nsi;
							nsi = plisql_ns_lookup(plisql_ns_top(), false,
													$1, NULL, NULL, NULL);
							if (nsi != NULL)
								ereport(plisql_curr_compile->extra_errors & PLISQL_XCHECK_SHADOWVAR ? ERROR : WARNING,
										(errcode(ERRCODE_DUPLICATE_ALIAS),
										 errmsg("variable \"%s\" shadows a previously defined variable",
												$1),
										 parser_errposition(@1)));
						}

					}
				;

decl_const		:
					{ $$ = false; }
				| K_CONSTANT
					{ $$ = true; }
				;

decl_datatype	:
					{
						/*
						 * If there's a lookahead token, read_datatype() will
						 * consume it, and then we must tell bison to forget
						 * it.
						 */
						$$ = read_datatype(yychar);
						yyclearin;
					}
				;

decl_collate	:
					{ $$ = InvalidOid; }
				| K_COLLATE T_WORD
					{
						$$ = get_collation_oid(list_make1(makeString($2.ident)),
											   false);
					}
				| K_COLLATE unreserved_keyword
					{
						$$ = get_collation_oid(list_make1(makeString(pstrdup($2))),
											   false);
					}
				| K_COLLATE T_CWORD
					{
						$$ = get_collation_oid($2.idents, false);
					}
				;

decl_notnull	:
					{ $$ = false; }
				| K_NOT K_NULL
					{ $$ = true; }
				;

decl_defval		: ';'
					{ $$ = NULL; }
				| decl_defkey
					{
						$$ = read_sql_expression(';', ";");
					}
				;

decl_defkey		: assign_operator
				| K_DEFAULT
				;

function_heading	: K_FUNCTION ora_function_name func_args K_RETURN decl_datatype
						{
							PLiSQL_subproc_function *subprocfunc;

							subprocfunc = plisql_build_subproc_function($2, $3, $5, @2); 

							$$ = subprocfunc;
						}
						;
function_properties :	function_properite_list { $$ = $1; }
					|	{ $$ = NIL; }
					;

function_properite_list: function_properite_item
						{
							$$ = list_make1($1);
						}
						|function_properite_list function_properite_item
						{
							$$ = lappend($1, $2);
						}
						;

function_properite_item : K_DETERMINISTIC
						{
							PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

							proper->proper_type = FUNC_PROPER_DETERMINISTIC;

							$$ = proper;
						}
					| K_RESULT_CACHE function_result_cache_relies
						{
							PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

							/* anonymous blocks doesn't support result cache */
							if ((cur_compile_func_level != 0 &&
								plisql_saved_compile[0]->fn_oid == InvalidOid) ||
								(cur_compile_func_level == 0 && plisql_curr_compile->fn_oid == InvalidOid))
								yyerror("RESULT_CACHE is disallowed on subprograms in anonymous blocks");

							proper->proper_type = FUNC_PROPER_RESULT_CACHE;
							proper->value = $2;

							$$ = proper;
						}
					| K_PARALLEL_ENABLE
						{
							PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

							proper->proper_type = FUNC_PROPER_PARALLEL_ENABLE;

							$$ = proper;
						}
					| K_PIPELINED
						{
							PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

							proper->proper_type = FUNC_PROPER_PIPELINED;

							$$ = proper;
						}
					;

function_result_cache_relies : K_RELIES_ON '(' data_source ')'
								{
									$$ = $3;
								}
							| { $$ = NIL; }
							;

data_source : ora_function_name
					{
						$$ = list_make1(makeString($1));
					}
				|data_source ',' ora_function_name
					{
						$$ = lappend($1, makeString($3));
					}
				;

procedure_heading : K_PROCEDURE ora_function_name func_args
						{
							PLiSQL_subproc_function *subprocfunc;

							subprocfunc = plisql_build_subproc_function($2, $3, NULL, @2); 

							$$ = subprocfunc;
						}
						;

procedure_properties: procedure_properties_list { $$ = $1; }
					| { $$ = NIL; }
				;

procedure_properties_list: procedure_properite_item { $$ = list_make1($1); }
					| procedure_properties_list procedure_properite_item
						{
							$$ = lappend($1, $2);
						}
				;

procedure_properite_item: accessible_by_clause	{ $$ = $1;}
					|default_collation_clause 	{ $$ = $1;}
					|invoker_rights_clause			{ $$ = $1;}
					;

accessible_by_clause: K_ACCESSIBLE K_BY '(' accessor_list ')'
						{
							PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

							yyerror("Only schema-level programs allow ACCESSIBLE BY");
							proper->proper_type = PROC_PROPER_ACCESSIBLE_BY;
							proper->value = (void *) $4;

							$$ = proper;
						}
					;

accessor_list: accessor { $$ = list_make1($1); }
				|accessor_list ',' accessor { $$ = lappend($1, $3); }
				;

accessor: unit_kind unit_name unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = $1;
					acproper->schema_name = $2;
					acproper->unit_name = $3;

					$$ = acproper;
				}
			|unit_name unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = access_proper_unknow;
					acproper->schema_name = $1;
					acproper->unit_name = $2;

					$$ = acproper;
				}
			|unit_kind unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = $1;
					acproper->schema_name = NULL;
					acproper->unit_name = $2;

					$$ = acproper;
				}
			| unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = access_proper_unknow;
					acproper->schema_name = NULL;
					acproper->unit_name = $1;

					$$ = acproper;
				}
			|unit_kind extral_unit_name extral_unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = $1;
					acproper->schema_name = $2;
					acproper->unit_name = $3;

					$$ = acproper;
				}
			|unit_kind extral_unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = $1;
					acproper->schema_name = NULL;
					acproper->unit_name = $2;

					$$ = acproper;
				}
			|extral_unit_name
				{
					AccessProperItem *acproper = (AccessProperItem *) palloc0(sizeof(AccessProperItem));

					acproper->proper_type = access_proper_unknow;
					acproper->schema_name = NULL;
					acproper->unit_name = $1;

					$$ = acproper;
				}
			;

unit_name:	T_WORD
				{
					$$ = $1.ident;

				}
			| unit_name_keyword
				{
					$$ = pstrdup($1);
				}
		;

unit_kind: K_FUNCTION { $$ = access_proper_function; }
			|K_PROCEDURE { $$ = access_proper_procedure; }
			|K_PACKAGE	{ $$ = access_proper_package; }
			|K_TRIGGER	{ $$ = access_proper_trigger; }
			|K_TYPE 	{ $$ = access_proper_type; }
		;

extral_unit_name:
			K_PACKAGE { $$ = pstrdup($1);}
			|K_TRIGGER { $$ = pstrdup($1);}
			|K_TYPE { $$ = pstrdup($1);}
		;

default_collation_clause: K_DEFAULT K_COLLATION K_USING_NLS_COMP
					{
						PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

						proper->proper_type = PROC_PROPER_DEFAULT_COLLATION;
						proper->value = (void *) pstrdup($3);

						$$ = proper;
					}
				;

invoker_rights_clause: K_AUTHID authid_user
					{
						PLiSQL_subprocfunc_proper *proper = palloc0(sizeof(PLiSQL_subprocfunc_proper));

						yyerror("Only schema-level programs allow AUTHID");

						proper->proper_type = PROC_PROPER_INVOKER_RIGHT;
						proper->value = (void *) $2;

						$$ = proper;
					}
				;

authid_user: K_CURRENT_USER { $$ = pstrdup($1); }
				|K_DEFINER		{ $$ = pstrdup($1); }
			;

ora_function_name : T_WORD
					{
						$$ = $1.ident;

					}
				| unreserved_keyword
					{
						$$ = pstrdup($1);
					}
				;

function_arg_nocopy:
					K_NOCOPY	{ $$ = true; }
					| { $$ = false; }
				;

ora_function_is_as:
					K_IS		{ $$ = $1; }
					|K_AS 	{ $$ = $1; }
				;

func_args:
					'(' func_arg_list ')' { $$ = $2; }
					|'(' ')'	{ $$ = NIL; }
					| { $$ = NIL; }
					;

func_arg_list:
					func_arg_item
						{
							$$ = list_make1($1);
						}
					| func_arg_list ',' func_arg_item
						{
							$$ = lappend($1, $3);
						}
					;

func_arg_item:
					ora_function_name arg_mode function_arg_nocopy decl_datatype arg_decl_defval
						{
							PLiSQL_function_argitem *new = NULL;

							if ($2 != ARGMODE_IN && $5 != NULL)
								yyerror("OUT and IN OUT formal parameters may not have default expressions");

							if ($3 && $2 == ARGMODE_IN)
								yyerror("only out mode argument allow to have nocopy proper");

							new = (PLiSQL_function_argitem *) palloc0(sizeof(PLiSQL_function_argitem));
							new->argname = $1;
							new->type = $4;
							new->argmode = $2;
							new->defexpr = $5;
							new->nocopy = $3;
							$$ = new;
						}
					;

arg_mode:
					K_IN	{ $$ = ARGMODE_IN; }
					|K_IN K_OUT { $$ = ARGMODE_INOUT; }
					|K_OUT	{ $$ = ARGMODE_OUT; }
					| { $$ = ARGMODE_IN; }
					;

arg_decl_defval:	decl_defkey
						{
							int token;

							$$ =	read_sql_expression2(',', ')', ", or )", &token);
							plisql_push_back_token(token);
						}
					| { $$ = NULL; }
				;



/*
 * Ada-based PL/iSQL uses := for assignment and variable defaults, while
 * the SQL standard uses equals for these cases and for GET
 * DIAGNOSTICS, so we support both.  FOR and OPEN only support :=.
 */
assign_operator	: '='
				| COLON_EQUALS
				;

proc_sect		:
					{ $$ = NIL; }
				| proc_sect proc_stmt
					{
						/* don't bother linking null statements into list */
						if ($2 == NULL)
							$$ = $1;
						else
							$$ = lappend($1, $2);
					}
				;

proc_stmt		: pl_block ';'
						{ $$ = $1; }
				| stmt_assign
						{ $$ = $1; }
				| stmt_if
						{ $$ = $1; }
				| stmt_case
						{ $$ = $1; }
				| stmt_loop
						{ $$ = $1; }
				| stmt_while
						{ $$ = $1; }
				| stmt_for
						{ $$ = $1; }
				| stmt_foreach_a
						{ $$ = $1; }
				| stmt_exit
						{ $$ = $1; }
				| stmt_return
						{ $$ = $1; }
				| stmt_raise
						{ $$ = $1; }
				| stmt_assert
						{ $$ = $1; }
				| stmt_execsql
						{ $$ = $1; }
				| stmt_dynexecute
						{ $$ = $1; }
				| stmt_perform
						{ $$ = $1; }
				| stmt_call
						{ $$ = $1; }
				| stmt_getdiag
						{ $$ = $1; }
				| stmt_open
						{ $$ = $1; }
				| stmt_fetch
						{ $$ = $1; }
				| stmt_move
						{ $$ = $1; }
				| stmt_close
						{ $$ = $1; }
				| stmt_null
						{ $$ = $1; }
				| stmt_commit
						{ $$ = $1; }
				| stmt_rollback
						{ $$ = $1; }
				;

stmt_perform	: K_PERFORM
					{
						PLiSQL_stmt_perform *new;
						int			startloc;

						new = palloc0(sizeof(PLiSQL_stmt_perform));
						new->cmd_type = PLISQL_STMT_PERFORM;
						new->lineno   = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						plisql_push_back_token(K_PERFORM);

						/*
						 * Since PERFORM isn't legal SQL, we have to cheat to
						 * the extent of substituting "SELECT" for "PERFORM"
						 * in the parsed text.  It does not seem worth
						 * inventing a separate parse mode for this one case.
						 * We can't do syntax-checking until after we make the
						 * substitution.
						 */
						new->expr = read_sql_construct(';', 0, 0, ";",
													   RAW_PARSE_DEFAULT,
													   false, false,
													   &startloc, NULL);
						/* overwrite "perform" ... */
						memcpy(new->expr->query, " SELECT", 7);
						/* left-justify to get rid of the leading space */
						memmove(new->expr->query, new->expr->query + 1,
								strlen(new->expr->query));
						/* offset syntax error position to account for that */
						check_sql_expr(new->expr->query, new->expr->parseMode,
									   startloc + 1);

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_call		: K_DO
					{
						/* use the same structures as for CALL, for simplicity */
						PLiSQL_stmt_call *new;

						new = palloc0(sizeof(PLiSQL_stmt_call));
						new->cmd_type = PLISQL_STMT_CALL;
						new->lineno = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						plisql_push_back_token(K_DO);
						new->expr = read_sql_stmt();
						new->is_call = false;

						/* Remember we may need a procedure resource owner */
						plisql_curr_compile->requires_procedure_resowner = true;

						$$ = (PLiSQL_stmt *)new;

					}
			| K_CALL
					{
						PLiSQL_stmt_call *new;

                                                new = palloc0(sizeof(PLiSQL_stmt_call));
                                                new->cmd_type = PLISQL_STMT_CALL;
                                                new->lineno = plisql_location_to_lineno(@1);
                                                new->stmtid = ++plisql_curr_compile->nstatements;
                                                plisql_push_back_token(K_CALL);
                                                new->expr = read_sql_stmt();
                                                new->is_call = true;

                                                /* Remember we may need a procedure resource owner */
                                                plisql_curr_compile->requires_procedure_resowner = true;

                                                $$ = (PLiSQL_stmt *)new;
					}
				;

stmt_assign		: T_DATUM
					{
						PLiSQL_stmt_assign *new;
						RawParseMode pmode;

						/* see how many names identify the datum */
						switch ($1.ident ? 1 : list_length($1.idents))
						{
							case 1:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN1;
								break;
							case 2:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN2;
								break;
							case 3:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN3;
								break;
							default:
								elog(ERROR, "unexpected number of names");
								pmode = 0; /* keep compiler quiet */
						}

						check_assignable($1.datum, @1);
						new = palloc0(sizeof(PLiSQL_stmt_assign));
						new->cmd_type = PLISQL_STMT_ASSIGN;
						new->lineno   = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->varno = $1.datum->dno;
						/* Push back the head name to include it in the stmt */
						plisql_push_back_token(T_DATUM);
						new->expr = read_sql_construct(';', 0, 0, ";",
													   pmode,
													   false, true,
													   NULL, NULL);

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_getdiag	: K_GET getdiag_area_opt K_DIAGNOSTICS getdiag_list ';'
					{
						PLiSQL_stmt_getdiag	 *new;
						ListCell		*lc;

						new = palloc0(sizeof(PLiSQL_stmt_getdiag));
						new->cmd_type = PLISQL_STMT_GETDIAG;
						new->lineno   = plisql_location_to_lineno(@1);
						new->stmtid	  = ++plisql_curr_compile->nstatements;
						new->is_stacked = $2;
						new->diag_items = $4;

						/*
						 * Check information items are valid for area option.
						 */
						foreach(lc, new->diag_items)
						{
							PLiSQL_diag_item *ditem = (PLiSQL_diag_item *) lfirst(lc);

							switch (ditem->kind)
							{
								/* these fields are disallowed in stacked case */
								case PLISQL_GETDIAG_ROW_COUNT:
								case PLISQL_GETDIAG_ROUTINE_OID:
									if (new->is_stacked)
										ereport(ERROR,
												(errcode(ERRCODE_SYNTAX_ERROR),
												 errmsg("diagnostics item %s is not allowed in GET STACKED DIAGNOSTICS",
														plisql_getdiag_kindname(ditem->kind)),
												 parser_errposition(@1)));
									break;
								/* these fields are disallowed in current case */
								case PLISQL_GETDIAG_ERROR_CONTEXT:
								case PLISQL_GETDIAG_ERROR_DETAIL:
								case PLISQL_GETDIAG_ERROR_HINT:
								case PLISQL_GETDIAG_RETURNED_SQLSTATE:
								case PLISQL_GETDIAG_COLUMN_NAME:
								case PLISQL_GETDIAG_CONSTRAINT_NAME:
								case PLISQL_GETDIAG_DATATYPE_NAME:
								case PLISQL_GETDIAG_MESSAGE_TEXT:
								case PLISQL_GETDIAG_TABLE_NAME:
								case PLISQL_GETDIAG_SCHEMA_NAME:
									if (!new->is_stacked)
										ereport(ERROR,
												(errcode(ERRCODE_SYNTAX_ERROR),
												 errmsg("diagnostics item %s is not allowed in GET CURRENT DIAGNOSTICS",
														plisql_getdiag_kindname(ditem->kind)),
												 parser_errposition(@1)));
									break;
								/* these fields are allowed in either case */
								case PLISQL_GETDIAG_CONTEXT:
									break;
								default:
									elog(ERROR, "unrecognized diagnostic item kind: %d",
										 ditem->kind);
									break;
							}
						}

						$$ = (PLiSQL_stmt *)new;
					}
				;

getdiag_area_opt :
					{
						$$ = false;
					}
				| K_CURRENT
					{
						$$ = false;
					}
				| K_STACKED
					{
						$$ = true;
					}
				;

getdiag_list : getdiag_list ',' getdiag_list_item
					{
						$$ = lappend($1, $3);
					}
				| getdiag_list_item
					{
						$$ = list_make1($1);
					}
				;

getdiag_list_item : getdiag_target assign_operator getdiag_item
					{
						PLiSQL_diag_item *new;

						new = palloc(sizeof(PLiSQL_diag_item));
						new->target = $1->dno;
						new->kind = $3;

						$$ = new;
					}
				;

getdiag_item :
					{
						int	tok = yylex();

						if (tok_is_keyword(tok, &yylval,
										   K_ROW_COUNT, "row_count"))
							$$ = PLISQL_GETDIAG_ROW_COUNT;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_ROUTINE_OID, "pg_routine_oid"))
							$$ = PLISQL_GETDIAG_ROUTINE_OID;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_CONTEXT, "pg_context"))
							$$ = PLISQL_GETDIAG_CONTEXT;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_EXCEPTION_DETAIL, "pg_exception_detail"))
							$$ = PLISQL_GETDIAG_ERROR_DETAIL;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_EXCEPTION_HINT, "pg_exception_hint"))
							$$ = PLISQL_GETDIAG_ERROR_HINT;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_EXCEPTION_CONTEXT, "pg_exception_context"))
							$$ = PLISQL_GETDIAG_ERROR_CONTEXT;
						else if (tok_is_keyword(tok, &yylval,
												K_COLUMN_NAME, "column_name"))
							$$ = PLISQL_GETDIAG_COLUMN_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_CONSTRAINT_NAME, "constraint_name"))
							$$ = PLISQL_GETDIAG_CONSTRAINT_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_DATATYPE_NAME, "pg_datatype_name"))
							$$ = PLISQL_GETDIAG_DATATYPE_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_MESSAGE_TEXT, "message_text"))
							$$ = PLISQL_GETDIAG_MESSAGE_TEXT;
						else if (tok_is_keyword(tok, &yylval,
												K_TABLE_NAME, "table_name"))
							$$ = PLISQL_GETDIAG_TABLE_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_SCHEMA_NAME, "schema_name"))
							$$ = PLISQL_GETDIAG_SCHEMA_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_RETURNED_SQLSTATE, "returned_sqlstate"))
							$$ = PLISQL_GETDIAG_RETURNED_SQLSTATE;
						else
							yyerror("unrecognized GET DIAGNOSTICS item");
					}
				;

getdiag_target	: T_DATUM
					{
						/*
						 * In principle we should support a getdiag_target
						 * that is an array element, but for now we don't, so
						 * just throw an error if next token is '['.
						 */
						if (is_row_record_datum($1.datum) || 
							plisql_peek() == '[')
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("\"%s\" is not a scalar variable",
											NameOfDatum(&($1))),
									 parser_errposition(@1)));
						check_assignable($1.datum, @1);
						$$ = $1.datum;
					}
				| T_WORD
					{
						/* just to give a better message than "syntax error" */
						word_is_not_variable(&($1), @1);
					}
				| T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($1), @1);
					}
				;

stmt_if			: K_IF expr_until_then proc_sect stmt_elsifs stmt_else K_END K_IF ';'
					{
						PLiSQL_stmt_if *new;

						new = palloc0(sizeof(PLiSQL_stmt_if));
						new->cmd_type	= PLISQL_STMT_IF;
						new->lineno		= plisql_location_to_lineno(@1);
						new->stmtid		= ++plisql_curr_compile->nstatements;
						new->cond		= $2;
						new->then_body	= $3;
						new->elsif_list = $4;
						new->else_body  = $5;

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_elsifs		:
					{
						$$ = NIL;
					}
				| stmt_elsifs K_ELSIF expr_until_then proc_sect
					{
						PLiSQL_if_elsif *new;

						new = palloc0(sizeof(PLiSQL_if_elsif));
						new->lineno = plisql_location_to_lineno(@2);
						new->cond   = $3;
						new->stmts  = $4;

						$$ = lappend($1, new);
					}
				;

stmt_else		:
					{
						$$ = NIL;
					}
				| K_ELSE proc_sect
					{
						$$ = $2;
					}
				;

stmt_case		: K_CASE opt_expr_until_when case_when_list opt_case_else K_END K_CASE ';'
					{
						$$ = make_case(@1, $2, $3, $4);
					}
				;

opt_expr_until_when	:
					{
						PLiSQL_expr *expr = NULL;
						int	tok = yylex();

						if (tok != K_WHEN)
						{
							plisql_push_back_token(tok);
							expr = read_sql_expression(K_WHEN, "WHEN");
						}
						plisql_push_back_token(K_WHEN);
						$$ = expr;
					}
				;

case_when_list	: case_when_list case_when
					{
						$$ = lappend($1, $2);
					}
				| case_when
					{
						$$ = list_make1($1);
					}
				;

case_when		: K_WHEN expr_until_then proc_sect
					{
						PLiSQL_case_when *new = palloc(sizeof(PLiSQL_case_when));

						new->lineno	= plisql_location_to_lineno(@1);
						new->expr	= $2;
						new->stmts	= $3;
						$$ = new;
					}
				;

opt_case_else	:
					{
						$$ = NIL;
					}
				| K_ELSE proc_sect
					{
						/*
						 * proc_sect could return an empty list, but we
						 * must distinguish that from not having ELSE at all.
						 * Simplest fix is to return a list with one NULL
						 * pointer, which make_case() must take care of.
						 */
						if ($2 != NIL)
							$$ = $2;
						else
							$$ = list_make1(NULL);
					}
				;

stmt_loop		: opt_loop_label K_LOOP loop_body
					{
						PLiSQL_stmt_loop *new;

						new = palloc0(sizeof(PLiSQL_stmt_loop));
						new->cmd_type = PLISQL_STMT_LOOP;
						new->lineno   = plisql_location_to_lineno(@2);
						new->stmtid   = ++plisql_curr_compile->nstatements;
						new->label	  = $1;
						new->body	  = $3.stmts;

						check_labels($1, $3.end_label, $3.end_label_location);
						plisql_ns_pop();

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_while		: opt_loop_label K_WHILE expr_until_loop loop_body
					{
						PLiSQL_stmt_while *new;

						new = palloc0(sizeof(PLiSQL_stmt_while));
						new->cmd_type = PLISQL_STMT_WHILE;
						new->lineno   = plisql_location_to_lineno(@2);
						new->stmtid	  = ++plisql_curr_compile->nstatements;
						new->label	  = $1;
						new->cond	  = $3;
						new->body	  = $4.stmts;

						check_labels($1, $4.end_label, $4.end_label_location);
						plisql_ns_pop();

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_for		: opt_loop_label K_FOR for_control loop_body
					{
						/* This runs after we've scanned the loop body */
						if ($3->cmd_type == PLISQL_STMT_FORI)
						{
							PLiSQL_stmt_fori		*new;

							new = (PLiSQL_stmt_fori *) $3;
							new->lineno   = plisql_location_to_lineno(@2);
							new->label	  = $1;
							new->body	  = $4.stmts;
							$$ = (PLiSQL_stmt *) new;
						}
						else
						{
							PLiSQL_stmt_forq		*new;

							Assert($3->cmd_type == PLISQL_STMT_FORS ||
								   $3->cmd_type == PLISQL_STMT_FORC ||
								   $3->cmd_type == PLISQL_STMT_DYNFORS);
							/* forq is the common supertype of all three */
							new = (PLiSQL_stmt_forq *) $3;
							new->lineno   = plisql_location_to_lineno(@2);
							new->label	  = $1;
							new->body	  = $4.stmts;
							$$ = (PLiSQL_stmt *) new;
						}

						check_labels($1, $4.end_label, $4.end_label_location);
						/* close namespace started in opt_loop_label */
						plisql_ns_pop();
					}
				;

for_control		: for_variable K_IN
					{
						int			tok = yylex();
						int			tokloc = yylloc;

						if (tok == K_EXECUTE)
						{
							/* EXECUTE means it's a dynamic FOR loop */
							PLiSQL_stmt_dynfors	*new;
							PLiSQL_expr			*expr;
							int						term;

							expr = read_sql_expression2(K_LOOP, K_USING,
														"LOOP or USING",
														&term);

							new = palloc0(sizeof(PLiSQL_stmt_dynfors));
							new->cmd_type = PLISQL_STMT_DYNFORS;
							new->stmtid	  = ++plisql_curr_compile->nstatements;
							if ($1.row)
							{
								new->var = (PLiSQL_variable *) $1.row;
								check_assignable($1.row, @1);
							}
							else if ($1.scalar)
							{
								/* convert single scalar to list */
								new->var = (PLiSQL_variable *)
									make_scalar_list1($1.name, $1.scalar,
													  $1.lineno, @1);
								/* make_scalar_list1 did check_assignable */
							}
							else
							{
								ereport(ERROR,
										(errcode(ERRCODE_DATATYPE_MISMATCH),
										 errmsg("loop variable of loop over rows must be a record variable or list of scalar variables"),
										 parser_errposition(@1)));
							}
							new->query = expr;

							if (term == K_USING)
							{
								do
								{
									expr = read_sql_expression2(',', K_LOOP,
																", or LOOP",
																&term);
									new->params = lappend(new->params, expr);
								} while (term == ',');
							}

							$$ = (PLiSQL_stmt *) new;
						}
						else if (tok == T_DATUM &&
								 yylval.wdatum.datum->dtype == PLISQL_DTYPE_VAR &&
								 ((PLiSQL_var *) yylval.wdatum.datum)->datatype->typoid == REFCURSOROID)
						{
							/* It's FOR var IN cursor */
							PLiSQL_stmt_forc	*new;
							PLiSQL_var			*cursor = (PLiSQL_var *) yylval.wdatum.datum;

							new = (PLiSQL_stmt_forc *) palloc0(sizeof(PLiSQL_stmt_forc));
							new->cmd_type = PLISQL_STMT_FORC;
							new->stmtid = ++plisql_curr_compile->nstatements;
							new->curvar = cursor->dno;

							/* Should have had a single variable name */
							if ($1.scalar && $1.row)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("cursor FOR loop must have only one target variable"),
										 parser_errposition(@1)));

							/* can't use an unbound cursor this way */
							if (cursor->cursor_explicit_expr == NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("cursor FOR loop must use a bound cursor variable"),
										 parser_errposition(tokloc)));

							/* collect cursor's parameters if any */
							new->argquery = read_cursor_args(cursor,
															 K_LOOP);

							/* create loop's private RECORD variable */
							new->var = (PLiSQL_variable *)
								plisql_build_record($1.name,
													 $1.lineno,
													 NULL,
													 RECORDOID,
													 true);

							$$ = (PLiSQL_stmt *) new;
						}
						else
						{
							PLiSQL_expr	*expr1;
							int				expr1loc;
							bool			reverse = false;

							/*
							 * We have to distinguish between two
							 * alternatives: FOR var IN a .. b and FOR
							 * var IN query. Unfortunately this is
							 * tricky, since the query in the second
							 * form needn't start with a SELECT
							 * keyword.  We use the ugly hack of
							 * looking for two periods after the first
							 * token. We also check for the REVERSE
							 * keyword, which means it must be an
							 * integer loop.
							 */
							if (tok_is_keyword(tok, &yylval,
											   K_REVERSE, "reverse"))
								reverse = true;
							else
								plisql_push_back_token(tok);

							/*
							 * Read tokens until we see either a ".."
							 * or a LOOP.  The text we read may be either
							 * an expression or a whole SQL statement, so
							 * we need to invoke read_sql_construct directly,
							 * and tell it not to check syntax yet.
							 */
							expr1 = read_sql_construct(DOT_DOT,
													   K_LOOP,
													   0,
													   "LOOP",
													   RAW_PARSE_DEFAULT,
													   true,
													   false,
													   &expr1loc,
													   &tok);

							if (tok == DOT_DOT)
							{
								/* Saw "..", so it must be an integer loop */
								PLiSQL_expr		*expr2;
								PLiSQL_expr		*expr_by;
								PLiSQL_var			*fvar;
								PLiSQL_stmt_fori	*new;

								/*
								 * Relabel first expression as an expression;
								 * then we can check its syntax.
								 */
								expr1->parseMode = RAW_PARSE_PLPGSQL_EXPR;
								check_sql_expr(expr1->query, expr1->parseMode,
											   expr1loc);

								/* Read and check the second one */
								expr2 = read_sql_expression2(K_LOOP, K_BY,
															 "LOOP",
															 &tok);

								/* Get the BY clause if any */
								if (tok == K_BY)
									expr_by = read_sql_expression(K_LOOP,
																  "LOOP");
								else
									expr_by = NULL;

								/* Should have had a single variable name */
								if ($1.scalar && $1.row)
									ereport(ERROR,
											(errcode(ERRCODE_SYNTAX_ERROR),
											 errmsg("integer FOR loop must have only one target variable"),
											 parser_errposition(@1)));

								/* create loop's private variable */
								fvar = (PLiSQL_var *)
									plisql_build_variable($1.name,
														   $1.lineno,
														   plisql_build_datatype(INT4OID,
																				  -1,
																				  InvalidOid,
																				  NULL),
														   true);

								new = palloc0(sizeof(PLiSQL_stmt_fori));
								new->cmd_type = PLISQL_STMT_FORI;
								new->stmtid	  = ++plisql_curr_compile->nstatements;
								new->var	  = fvar;
								new->reverse  = reverse;
								new->lower	  = expr1;
								new->upper	  = expr2;
								new->step	  = expr_by;

								$$ = (PLiSQL_stmt *) new;
							}
							else
							{
								/*
								 * No "..", so it must be a query loop.
								 */
								PLiSQL_stmt_fors	*new;

								if (reverse)
									ereport(ERROR,
											(errcode(ERRCODE_SYNTAX_ERROR),
											 errmsg("cannot specify REVERSE in query FOR loop"),
											 parser_errposition(tokloc)));

								/* Check syntax as a regular query */
								check_sql_expr(expr1->query, expr1->parseMode,
											   expr1loc);

								new = palloc0(sizeof(PLiSQL_stmt_fors));
								new->cmd_type = PLISQL_STMT_FORS;
								new->stmtid = ++plisql_curr_compile->nstatements;
								if ($1.row)
								{
									new->var = (PLiSQL_variable *) $1.row;
									check_assignable($1.row, @1);
								}
								else if ($1.scalar)
								{
									/* convert single scalar to list */
									new->var = (PLiSQL_variable *)
										make_scalar_list1($1.name, $1.scalar,
														  $1.lineno, @1);
									/* make_scalar_list1 did check_assignable */
								}
								else
								{
									ereport(ERROR,
											(errcode(ERRCODE_SYNTAX_ERROR),
											 errmsg("loop variable of loop over rows must be a record variable or list of scalar variables"),
											 parser_errposition(@1)));
								}

								new->query = expr1;
								$$ = (PLiSQL_stmt *) new;
							}
						}
					}
				;

/*
 * Processing the for_variable is tricky because we don't yet know if the
 * FOR is an integer FOR loop or a loop over query results.  In the former
 * case, the variable is just a name that we must instantiate as a loop
 * local variable, regardless of any other definition it might have.
 * Therefore, we always save the actual identifier into $$.name where it
 * can be used for that case.  We also save the outer-variable definition,
 * if any, because that's what we need for the loop-over-query case.  Note
 * that we must NOT apply check_assignable() or any other semantic check
 * until we know what's what.
 *
 * However, if we see a comma-separated list of names, we know that it
 * can't be an integer FOR loop and so it's OK to check the variables
 * immediately.  In particular, for T_WORD followed by comma, we should
 * complain that the name is not known rather than say it's a syntax error.
 * Note that the non-error result of this case sets *both* $$.scalar and
 * $$.row; see the for_control production.
 */
for_variable	: T_DATUM
					{
						$$.name = NameOfDatum(&($1));
						$$.lineno = plisql_location_to_lineno(@1);
						if (is_row_record_datum($1.datum)) 
						{
							$$.scalar = NULL;
							$$.row = $1.datum;
						}
						else
						{
							int			tok;

							$$.scalar = $1.datum;
							$$.row = NULL;
							/* check for comma-separated list */
							tok = yylex();
							plisql_push_back_token(tok);
							if (tok == ',')
								$$.row = (PLiSQL_datum *)
									read_into_scalar_list($$.name,
														  $$.scalar,
														  @1);
						}
					}
				| T_WORD
					{
						int			tok;

						$$.name = $1.ident;
						$$.lineno = plisql_location_to_lineno(@1);
						$$.scalar = NULL;
						$$.row = NULL;
						/* check for comma-separated list */
						tok = yylex();
						plisql_push_back_token(tok);
						if (tok == ',')
							word_is_not_variable(&($1), @1);
					}
				| T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($1), @1);
					}
				;

stmt_foreach_a	: opt_loop_label K_FOREACH for_variable foreach_slice K_IN K_ARRAY expr_until_loop loop_body
					{
						PLiSQL_stmt_foreach_a *new;

						new = palloc0(sizeof(PLiSQL_stmt_foreach_a));
						new->cmd_type = PLISQL_STMT_FOREACH_A;
						new->lineno = plisql_location_to_lineno(@2);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->label = $1;
						new->slice = $4;
						new->expr = $7;
						new->body = $8.stmts;

						if ($3.row)
						{
							new->varno = $3.row->dno;
							check_assignable($3.row, @3);
						}
						else if ($3.scalar)
						{
							new->varno = $3.scalar->dno;
							check_assignable($3.scalar, @3);
						}
						else
						{
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("loop variable of FOREACH must be a known variable or list of variables"),
											 parser_errposition(@3)));
						}

						check_labels($1, $8.end_label, $8.end_label_location);
						plisql_ns_pop();

						$$ = (PLiSQL_stmt *) new;
					}
				;

foreach_slice	:
					{
						$$ = 0;
					}
				| K_SLICE ICONST
					{
						$$ = $2;
					}
				;

stmt_exit		: exit_type opt_label opt_exitcond
					{
						PLiSQL_stmt_exit *new;

						new = palloc0(sizeof(PLiSQL_stmt_exit));
						new->cmd_type = PLISQL_STMT_EXIT;
						new->stmtid	  = ++plisql_curr_compile->nstatements;
						new->is_exit  = $1;
						new->lineno	  = plisql_location_to_lineno(@1);
						new->label	  = $2;
						new->cond	  = $3;

						if ($2)
						{
							/* We have a label, so verify it exists */
							PLiSQL_nsitem *label;

							label = plisql_ns_lookup_label(plisql_ns_top(), $2);
							if (label == NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("there is no label \"%s\" "
												"attached to any block or loop enclosing this statement",
												$2),
										 parser_errposition(@2)));
							/* CONTINUE only allows loop labels */
							if (label->itemno != PLISQL_LABEL_LOOP && !new->is_exit)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("block label \"%s\" cannot be used in CONTINUE",
												$2),
										 parser_errposition(@2)));
						}
						else
						{
							/*
							 * No label, so make sure there is some loop (an
							 * unlabeled EXIT does not match a block, so this
							 * is the same test for both EXIT and CONTINUE)
							 */
							if (plisql_ns_find_nearest_loop(plisql_ns_top()) == NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 new->is_exit ?
										 errmsg("EXIT cannot be used outside a loop, unless it has a label") :
										 errmsg("CONTINUE cannot be used outside a loop"),
										 parser_errposition(@1)));
						}

						$$ = (PLiSQL_stmt *)new;
					}
				;

exit_type		: K_EXIT
					{
						$$ = true;
					}
				| K_CONTINUE
					{
						$$ = false;
					}
				;

stmt_return		: K_RETURN
					{
						int			tok;

						tok = yylex();
						if (tok == 0)
							yyerror("unexpected end of function definition");

						if (tok_is_keyword(tok, &yylval,
										   K_NEXT, "next"))
						{
							$$ = make_return_next_stmt(@1);
						}
						else if (tok_is_keyword(tok, &yylval,
												K_QUERY, "query"))
						{
							$$ = make_return_query_stmt(@1);
						}
						else
						{
							plisql_push_back_token(tok);
							$$ = make_return_stmt(@1);
						}
					}
				;

stmt_raise		: K_RAISE
					{
						PLiSQL_stmt_raise		*new;
						int	tok;

						new = palloc(sizeof(PLiSQL_stmt_raise));

						new->cmd_type	= PLISQL_STMT_RAISE;
						new->lineno		= plisql_location_to_lineno(@1);
						new->stmtid		= ++plisql_curr_compile->nstatements;
						new->elog_level = ERROR;	/* default */
						new->condname	= NULL;
						new->message	= NULL;
						new->params		= NIL;
						new->options	= NIL;

						tok = yylex();
						if (tok == 0)
							yyerror("unexpected end of function definition");

						/*
						 * We could have just RAISE, meaning to re-throw
						 * the current error.
						 */
						if (tok != ';')
						{
							/*
							 * First is an optional elog severity level.
							 */
							if (tok_is_keyword(tok, &yylval,
											   K_EXCEPTION, "exception"))
							{
								new->elog_level = ERROR;
								tok = yylex();
							}
							else if (tok_is_keyword(tok, &yylval,
													K_WARNING, "warning"))
							{
								new->elog_level = WARNING;
								tok = yylex();
							}
							else if (tok_is_keyword(tok, &yylval,
													K_NOTICE, "notice"))
							{
								new->elog_level = NOTICE;
								tok = yylex();
							}
							else if (tok_is_keyword(tok, &yylval,
													K_INFO, "info"))
							{
								new->elog_level = INFO;
								tok = yylex();
							}
							else if (tok_is_keyword(tok, &yylval,
													K_LOG, "log"))
							{
								new->elog_level = LOG;
								tok = yylex();
							}
							else if (tok_is_keyword(tok, &yylval,
													K_DEBUG, "debug"))
							{
								new->elog_level = DEBUG1;
								tok = yylex();
							}
							if (tok == 0)
								yyerror("unexpected end of function definition");

							/*
							 * Next we can have a condition name, or
							 * equivalently SQLSTATE 'xxxxx', or a string
							 * literal that is the old-style message format,
							 * or USING to start the option list immediately.
							 */
							if (tok == SCONST)
							{
								/* old style message and parameters */
								new->message = yylval.str;
								/*
								 * We expect either a semi-colon, which
								 * indicates no parameters, or a comma that
								 * begins the list of parameter expressions,
								 * or USING to begin the options list.
								 */
								tok = yylex();
								if (tok != ',' && tok != ';' && tok != K_USING)
									yyerror("syntax error");

								while (tok == ',')
								{
									PLiSQL_expr *expr;

									expr = read_sql_construct(',', ';', K_USING,
															  ", or ; or USING",
															  RAW_PARSE_PLPGSQL_EXPR,
															  true, true,
															  NULL, &tok);
									new->params = lappend(new->params, expr);
								}
							}
							else if (tok != K_USING)
							{
								/* must be condition name or SQLSTATE */
								if (tok_is_keyword(tok, &yylval,
												   K_SQLSTATE, "sqlstate"))
								{
									/* next token should be a string literal */
									char   *sqlstatestr;

									if (yylex() != SCONST)
										yyerror("syntax error");
									sqlstatestr = yylval.str;

									if (strlen(sqlstatestr) != 5)
										yyerror("invalid SQLSTATE code");
									if (strspn(sqlstatestr, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") != 5)
										yyerror("invalid SQLSTATE code");
									new->condname = sqlstatestr;
								}
								else
								{
									if (tok == T_WORD)
										new->condname = yylval.word.ident;
									else if (plisql_token_is_unreserved_keyword(tok))
										new->condname = pstrdup(yylval.keyword);
									else
										yyerror("syntax error");
									plisql_recognize_err_condition(new->condname,
																	false);
								}
								tok = yylex();
								if (tok != ';' && tok != K_USING)
									yyerror("syntax error");
							}

							if (tok == K_USING)
								new->options = read_raise_options();
						}

						check_raise_parameters(new);

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_assert		: K_ASSERT
					{
						PLiSQL_stmt_assert		*new;
						int	tok;

						new = palloc(sizeof(PLiSQL_stmt_assert));

						new->cmd_type	= PLISQL_STMT_ASSERT;
						new->lineno		= plisql_location_to_lineno(@1);
						new->stmtid		= ++plisql_curr_compile->nstatements;

						new->cond = read_sql_expression2(',', ';',
														 ", or ;",
														 &tok);

						if (tok == ',')
							new->message = read_sql_expression(';', ";");
						else
							new->message = NULL;

						$$ = (PLiSQL_stmt *) new;
					}
				;

loop_body		: proc_sect K_END K_LOOP opt_label ';'
					{
						$$.stmts = $1;
						$$.end_label = $4;
						$$.end_label_location = @4;
					}
				;

/*
 * T_WORD+T_CWORD match any initial identifier that is not a known plisql
 * variable.  (The composite case is probably a syntax error, but we'll let
 * the core parser decide that.)  Normally, we should assume that such a
 * word is a SQL statement keyword that isn't also a plisql keyword.
 * However, if the next token is assignment or '[' or '.', it can't be a valid
 * SQL statement, and what we're probably looking at is an intended variable
 * assignment.  Give an appropriate complaint for that, instead of letting
 * the core parser throw an unhelpful "syntax error".
 */
stmt_execsql	: K_IMPORT
					{
						$$ = make_execsql_stmt(K_IMPORT, @1);
					}
				| K_INSERT
					{
						$$ = make_execsql_stmt(K_INSERT, @1);
					}
				| K_MERGE
					{
						$$ = make_execsql_stmt(K_MERGE, @1);
					}
				| T_WORD
					{
						int			tok;

						tok = yylex();
						plisql_push_back_token(tok);
						if (tok == '=' || tok == COLON_EQUALS ||
							tok == '[' || tok == '.')
							word_is_not_variable(&($1), @1);
						if (tok == '(' || tok == ';')
						{
							PLiSQL_stmt_call *new;

							new = palloc0(sizeof(PLiSQL_stmt_call));
							new->cmd_type = PLISQL_STMT_CALL;
							new->lineno = plisql_location_to_lineno(@1);
							new->stmtid = ++plisql_curr_compile->nstatements;
							new->expr = build_call_expr(T_WORD, @1);
							new->is_call = true;

							$$ = (PLiSQL_stmt *)new;
						}
						else
						{
							$$ = make_execsql_stmt(T_WORD, @1);
						}
					}
				| T_CWORD
					{
						int			tok;

						tok = yylex();
						plisql_push_back_token(tok);
						if (tok == '=' || tok == COLON_EQUALS ||
							tok == '[' || tok == '.')
							cword_is_not_variable(&($1), @1);
						if (tok == '(' || tok == ';')
						{
							PLiSQL_stmt_call *new;

							new = palloc0(sizeof(PLiSQL_stmt_call));
							new->cmd_type = PLISQL_STMT_CALL;
							new->lineno = plisql_location_to_lineno(@1);
							new->stmtid = ++plisql_curr_compile->nstatements;
							new->expr = build_call_expr(T_CWORD, @1);
							new->is_call = true;

							$$ = (PLiSQL_stmt *)new;
						}
						else
						{
							$$ = make_execsql_stmt(T_CWORD, @1);
						}
					}
				;

stmt_dynexecute : K_EXECUTE
					{
						PLiSQL_stmt_dynexecute *new;
						PLiSQL_expr *expr;
						int endtoken;

						expr = read_sql_construct(K_INTO, K_USING, ';',
												  "INTO or USING or ;",
												  RAW_PARSE_PLPGSQL_EXPR,
												  true, true,
												  NULL, &endtoken);

						new = palloc(sizeof(PLiSQL_stmt_dynexecute));
						new->cmd_type = PLISQL_STMT_DYNEXECUTE;
						new->lineno = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->query = expr;
						new->into = false;
						new->strict = false;
						new->target = NULL;
						new->params = NIL;

						/*
						 * We loop to allow the INTO and USING clauses to
						 * appear in either order, since people easily get
						 * that wrong.  This coding also prevents "INTO foo"
						 * from getting absorbed into a USING expression,
						 * which is *really* confusing.
						 */
						for (;;)
						{
							if (endtoken == K_INTO)
							{
								if (new->into)			/* multiple INTO */
									yyerror("syntax error");
								new->into = true;
								read_into_target(&new->target, &new->strict);
								endtoken = yylex();
							}
							else if (endtoken == K_USING)
							{
								if (new->params)		/* multiple USING */
									yyerror("syntax error");
								do
								{
									expr = read_sql_construct(',', ';', K_INTO,
															  ", or ; or INTO",
															  RAW_PARSE_PLPGSQL_EXPR,
															  true, true,
															  NULL, &endtoken);
									new->params = lappend(new->params, expr);
								} while (endtoken == ',');
							}
							else if (endtoken == ';')
								break;
							else
								yyerror("syntax error");
						}

						$$ = (PLiSQL_stmt *)new;
					}
				;


stmt_open		: K_OPEN cursor_variable
					{
						PLiSQL_stmt_open *new;
						int				  tok;
						PLiSQL_var *cursorvar;

						new = palloc0(sizeof(PLiSQL_stmt_open));
						new->cmd_type = PLISQL_STMT_OPEN;
						new->lineno = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->curvar = $2->dno;
						new->cursor_options = CURSOR_OPT_FAST_PLAN;

						if ($2->dtype == PLISQL_DTYPE_PACKAGE_DATUM)
							cursorvar = (PLiSQL_var *) ((PLiSQL_pkg_datum *) $2)->pkgvar;
						else
							cursorvar = $2;

						if (cursorvar->cursor_explicit_expr == NULL) 
						{
							/* be nice if we could use opt_scrollable here */
							tok = yylex();
							if (tok_is_keyword(tok, &yylval,
											   K_NO, "no"))
							{
								tok = yylex();
								if (tok_is_keyword(tok, &yylval,
												   K_SCROLL, "scroll"))
								{
									new->cursor_options |= CURSOR_OPT_NO_SCROLL;
									tok = yylex();
								}
							}
							else if (tok_is_keyword(tok, &yylval,
													K_SCROLL, "scroll"))
							{
								new->cursor_options |= CURSOR_OPT_SCROLL;
								tok = yylex();
							}

							if (tok != K_FOR)
								yyerror("syntax error, expected \"FOR\"");

							tok = yylex();
							if (tok == K_EXECUTE)
							{
								int		endtoken;

								new->dynquery =
									read_sql_expression2(K_USING, ';',
														 "USING or ;",
														 &endtoken);

								/* If we found "USING", collect argument(s) */
								if (endtoken == K_USING)
								{
									PLiSQL_expr *expr;

									do
									{
										expr = read_sql_expression2(',', ';',
																	", or ;",
																	&endtoken);
										new->params = lappend(new->params,
															  expr);
									} while (endtoken == ',');
								}
							}
							else
							{
								plisql_push_back_token(tok);
								new->query = read_sql_stmt();
							}
						}
						else
						{
							/* predefined cursor query, so read args */
							new->argquery = read_cursor_args($2, ';');
						}

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_fetch		: K_FETCH opt_fetch_direction cursor_variable K_INTO
					{
						PLiSQL_stmt_fetch *fetch = $2;
						PLiSQL_variable *target;

						/* We have already parsed everything through the INTO keyword */
						read_into_target(&target, NULL);

						if (yylex() != ';')
							yyerror("syntax error");

						/*
						 * We don't allow multiple rows in PL/iSQL's FETCH
						 * statement, only in MOVE.
						 */
						if (fetch->returns_multiple_rows)
							ereport(ERROR,
									(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
									 errmsg("FETCH statement cannot return multiple rows"),
									 parser_errposition(@1)));

						fetch->lineno = plisql_location_to_lineno(@1);
						fetch->target	= target;
						fetch->curvar	= $3->dno;
						fetch->is_move	= false;

						$$ = (PLiSQL_stmt *)fetch;
					}
				;

stmt_move		: K_MOVE opt_fetch_direction cursor_variable ';'
					{
						PLiSQL_stmt_fetch *fetch = $2;

						fetch->lineno = plisql_location_to_lineno(@1);
						fetch->curvar	= $3->dno;
						fetch->is_move	= true;

						$$ = (PLiSQL_stmt *)fetch;
					}
				;

opt_fetch_direction	:
					{
						$$ = read_fetch_direction();
					}
				;

stmt_close		: K_CLOSE cursor_variable ';'
					{
						PLiSQL_stmt_close *new;

						new = palloc(sizeof(PLiSQL_stmt_close));
						new->cmd_type = PLISQL_STMT_CLOSE;
						new->lineno = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->curvar = $2->dno;

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_null		: K_NULL ';'
					{
						/* We do not bother building a node for NULL */
						$$ = NULL;
					}
				;

stmt_commit		: K_COMMIT opt_transaction_chain ';'
					{
						PLiSQL_stmt_commit *new;

						new = palloc(sizeof(PLiSQL_stmt_commit));
						new->cmd_type = PLISQL_STMT_COMMIT;
						new->lineno = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->chain = $2;

						$$ = (PLiSQL_stmt *)new;
					}
				;

stmt_rollback	: K_ROLLBACK opt_transaction_chain ';'
					{
						PLiSQL_stmt_rollback *new;

						new = palloc(sizeof(PLiSQL_stmt_rollback));
						new->cmd_type = PLISQL_STMT_ROLLBACK;
						new->lineno = plisql_location_to_lineno(@1);
						new->stmtid = ++plisql_curr_compile->nstatements;
						new->chain = $2;

						$$ = (PLiSQL_stmt *)new;
					}
				;

opt_transaction_chain:
			K_AND K_CHAIN			{ $$ = true; }
			| K_AND K_NO K_CHAIN	{ $$ = false; }
			| /* EMPTY */			{ $$ = false; }
				;


cursor_variable	: T_DATUM
					{
						/*
						 * In principle we should support a cursor_variable
						 * that is an array element, but for now we don't, so
						 * just throw an error if next token is '['.
						 *
						 * maybe a package variable
						 */
						if (($1.datum->dtype != PLISQL_DTYPE_VAR &&
							$1.datum->dtype != PLISQL_DTYPE_PACKAGE_DATUM) ||
							plisql_peek() == '[')
							ereport(ERROR,
									(errcode(ERRCODE_DATATYPE_MISMATCH),
									 errmsg("cursor variable must be a simple variable"),
									 parser_errposition(@1)));

						if ($1.datum->dtype == PLISQL_DTYPE_PACKAGE_DATUM)
						{
							PLiSQL_pkg_datum *pkg_datum = (PLiSQL_pkg_datum *) $1.datum;
							PLiSQL_var *pkg_var = (PLiSQL_var *) pkg_datum->pkgvar;

							if (pkg_var->dtype != PLISQL_DTYPE_VAR)
								ereport(ERROR,
									(errcode(ERRCODE_DATATYPE_MISMATCH),
									 errmsg("cursor variable must be a simple variable"),
									 parser_errposition(@1)));
							if (pkg_var->datatype->typoid != REFCURSOROID)
								ereport(ERROR,
									(errcode(ERRCODE_DATATYPE_MISMATCH),
									 errmsg("variable \"%s\" must be of type cursor or refcursor",
											pkg_var->refname),
									 parser_errposition(@1)));
						}
						else if (((PLiSQL_var *) $1.datum)->datatype->typoid != REFCURSOROID)
							ereport(ERROR,
									(errcode(ERRCODE_DATATYPE_MISMATCH),
									 errmsg("variable \"%s\" must be of type cursor or refcursor",
											((PLiSQL_var *) $1.datum)->refname),
									 parser_errposition(@1)));
						$$ = (PLiSQL_var *) $1.datum;
					}
				| T_WORD
					{
						/* just to give a better message than "syntax error" */
						word_is_not_variable(&($1), @1);
					}
				| T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($1), @1);
					}
				;

exception_sect	:
					{ $$ = NULL; }
				| K_EXCEPTION
					{
						/*
						 * We use a mid-rule action to add these
						 * special variables to the namespace before
						 * parsing the WHEN clauses themselves.  The
						 * scope of the names extends to the end of the
						 * current block.
						 */
						int			lineno = plisql_location_to_lineno(@1);
						PLiSQL_exception_block *new = palloc(sizeof(PLiSQL_exception_block));
						PLiSQL_variable *var;

						var = plisql_build_variable("sqlstate", lineno,
													 plisql_build_datatype(TEXTOID,
																			-1,
																			plisql_curr_compile->fn_input_collation,
																			NULL),
													 true);
						var->isconst = true;
						new->sqlstate_varno = var->dno;

						var = plisql_build_variable("sqlerrm", lineno,
													 plisql_build_datatype(TEXTOID,
																			-1,
																			plisql_curr_compile->fn_input_collation,
																			NULL),
													 true);
						var->isconst = true;
						new->sqlerrm_varno = var->dno;

						$<exception_block>$ = new;
					}
					proc_exceptions
					{
						PLiSQL_exception_block *new = $<exception_block>2;
						new->exc_list = $3;

						$$ = new;
					}
				;

proc_exceptions	: proc_exceptions proc_exception
						{
							$$ = lappend($1, $2);
						}
				| proc_exception
						{
							$$ = list_make1($1);
						}
				;

proc_exception	: K_WHEN proc_conditions K_THEN proc_sect
					{
						PLiSQL_exception *new;

						new = palloc0(sizeof(PLiSQL_exception));
						new->lineno = plisql_location_to_lineno(@1);
						new->conditions = $2;
						new->action = $4;

						$$ = new;
					}
				;

proc_conditions	: proc_conditions K_OR proc_condition
						{
							PLiSQL_condition	*old;

							for (old = $1; old->next != NULL; old = old->next)
								/* skip */ ;
							old->next = $3;
							$$ = $1;
						}
				| proc_condition
						{
							$$ = $1;
						}
				;

proc_condition	: any_identifier
						{
							if (strcmp($1, "sqlstate") != 0)
							{
								$$ = plisql_parse_err_condition($1);
							}
							else
							{
								PLiSQL_condition *new;
								char   *sqlstatestr;

								/* next token should be a string literal */
								if (yylex() != SCONST)
									yyerror("syntax error");
								sqlstatestr = yylval.str;

								if (strlen(sqlstatestr) != 5)
									yyerror("invalid SQLSTATE code");
								if (strspn(sqlstatestr, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") != 5)
									yyerror("invalid SQLSTATE code");

								new = palloc(sizeof(PLiSQL_condition));
								new->sqlerrstate =
									MAKE_SQLSTATE(sqlstatestr[0],
												  sqlstatestr[1],
												  sqlstatestr[2],
												  sqlstatestr[3],
												  sqlstatestr[4]);
								new->condname = sqlstatestr;
								new->next = NULL;

								$$ = new;
							}
						}
				;

expr_until_semi :
					{ $$ = read_sql_expression(';', ";"); }
				;

expr_until_then :
					{ $$ = read_sql_expression(K_THEN, "THEN"); }
				;

expr_until_loop :
					{ $$ = read_sql_expression(K_LOOP, "LOOP"); }
				;

opt_block_label	:
					{
						plisql_ns_push(NULL, PLISQL_LABEL_BLOCK);
						$$ = NULL;
					}
				| LESS_LESS any_identifier GREATER_GREATER
					{
						plisql_ns_push($2, PLISQL_LABEL_BLOCK);
						$$ = $2;
					}
				;

opt_loop_label	:
					{
						plisql_ns_push(NULL, PLISQL_LABEL_LOOP);
						$$ = NULL;
					}
				| LESS_LESS any_identifier GREATER_GREATER
					{
						plisql_ns_push($2, PLISQL_LABEL_LOOP);
						$$ = $2;
					}
				;

opt_label	:
					{
						$$ = NULL;
					}
				| any_identifier
					{
						/* label validity will be checked by outer production */
						$$ = $1;
					}
				;

opt_exitcond	: ';'
					{ $$ = NULL; }
				| K_WHEN expr_until_semi
					{ $$ = $2; }
				;

/*
 * need to allow DATUM because scanner will have tried to resolve as variable
 */
any_identifier	: T_WORD
					{
						$$ = $1.ident;
					}
				| unreserved_keyword
					{
						$$ = pstrdup($1);
					}
				| T_DATUM
					{
						if ($1.ident == NULL) /* composite name not OK */
							yyerror("syntax error");
						$$ = $1.ident;
					}
				;

unreserved_keyword	:
				K_ABSOLUTE
				| K_ACCESSIBLE
				| K_ALIAS
				| K_AND
				| K_ARRAY
				| K_AS
				| K_ASSERT
				| K_AUTHID
				| K_BACKWARD
				| K_CALL
				| K_CHAIN
				| K_CLOSE
				| K_COLLATE
				| K_COLLATION
				| K_COLUMN
				| K_COLUMN_NAME
				| K_COMMIT
				| K_CONSTANT
				| K_CONSTRAINT
				| K_CONSTRAINT_NAME
				| K_CONTINUE
				| K_CURRENT
				| K_CURRENT_USER
				| K_CURSOR
				| K_DATATYPE
				| K_DEBUG
				| K_DEFAULT
				| K_DEFINER
				| K_DETAIL
				| K_DETERMINISTIC
				| K_DIAGNOSTICS
				| K_DO
				| K_DUMP
				| K_ELSIF
				| K_ERRCODE
				| K_ERROR
				| K_EXCEPTION
				| K_EXIT
				| K_FETCH
				| K_FIRST
				| K_FORWARD
				| K_GET
				| K_HINT
				| K_IMPORT
				| K_INFO
				| K_INSERT
				| K_IS
				| K_LAST
				| K_LOG
				| K_MERGE
				| K_MESSAGE
				| K_MESSAGE_TEXT
				| K_MOVE
				| K_NEXT
				| K_NO
				| K_NOCOPY
				| K_NOTICE
				| K_OPEN
				| K_OPTION
				| K_OUT
				| K_PACKAGE
				| K_PARALLEL_ENABLE
				| K_PERFORM
				| K_PG_CONTEXT
				| K_PG_DATATYPE_NAME
				| K_PG_EXCEPTION_CONTEXT
				| K_PG_EXCEPTION_DETAIL
				| K_PG_EXCEPTION_HINT
				| K_PIPELINED
				| K_PG_ROUTINE_OID
				| K_PRINT_STRICT_PARAMS
				| K_PRIOR
				| K_QUERY
				| K_RAISE
				| K_RELATIVE
				| K_RELIES_ON
				| K_RESULT_CACHE
				| K_RETURN
				| K_RETURNED_SQLSTATE
				| K_REVERSE
				| K_ROLLBACK
				| K_ROW_COUNT
				| K_ROWTYPE
				| K_SCHEMA
				| K_SCHEMA_NAME
				| K_SCROLL
				| K_SLICE
				| K_SQLSTATE
				| K_STACKED
				| K_TABLE
				| K_TABLE_NAME
				| K_TRIGGER
				| K_TYPE
				| K_USE_COLUMN
				| K_USE_VARIABLE
				| K_USING_NLS_COMP
				| K_VARIABLE_CONFLICT
				| K_WARNING
				;

/*
 * This is to solve the shift/reduce conflict of the access by which
 * accept package/trigger/type package/trigger/type as unit_kind or unit_name
 * which removes the three keywords K_PACAGE, K_TYPE, K_TRIGGER on the basis
 * of the unreserved_keyword
 */
unit_name_keyword:
				K_ABSOLUTE
				| K_ACCESSIBLE
				| K_ALIAS
				| K_AND
				| K_ARRAY
				| K_AS
				| K_ASSERT
				| K_AUTHID
				| K_BACKWARD
				| K_CALL
				| K_CHAIN
				| K_CLOSE
				| K_COLLATE
				| K_COLLATION
				| K_COLUMN
				| K_COLUMN_NAME
				| K_COMMIT
				| K_CONSTANT
				| K_CONSTRAINT
				| K_CONSTRAINT_NAME
				| K_CONTINUE
				| K_CURRENT
				| K_CURRENT_USER
				| K_CURSOR
				| K_DATATYPE
				| K_DEBUG
				| K_DEFAULT
				| K_DEFINER
				| K_DETAIL
				| K_DETERMINISTIC
				| K_DIAGNOSTICS
				| K_DO
				| K_DUMP
				| K_ELSIF
				| K_ERRCODE
				| K_ERROR
				| K_EXCEPTION
				| K_EXIT
				| K_FETCH
				| K_FIRST
				| K_FORWARD
				| K_GET
				| K_HINT
				| K_IMPORT
				| K_INFO
				| K_INSERT
				| K_IS
				| K_LAST
				| K_LOG
				| K_MESSAGE
				| K_MESSAGE_TEXT
				| K_MOVE
				| K_NEXT
				| K_NO
				| K_NOCOPY
				| K_NOTICE
				| K_OPEN
				| K_OPTION
				| K_OUT
				| K_PARALLEL_ENABLE
				| K_PERFORM
				| K_PG_CONTEXT
				| K_PG_DATATYPE_NAME
				| K_PG_EXCEPTION_CONTEXT
				| K_PG_EXCEPTION_DETAIL
				| K_PG_EXCEPTION_HINT
				| K_PIPELINED
				| K_PRINT_STRICT_PARAMS
				| K_PRIOR
				| K_QUERY
				| K_RAISE
				| K_RELATIVE
				| K_RELIES_ON
				| K_RESULT_CACHE
				| K_RETURN
				| K_RETURNED_SQLSTATE
				| K_REVERSE
				| K_ROLLBACK
				| K_ROW_COUNT
				| K_ROWTYPE
				| K_SCHEMA
				| K_SCHEMA_NAME
				| K_SCROLL
				| K_SLICE
				| K_SQLSTATE
				| K_STACKED
				| K_TABLE
				| K_TABLE_NAME
				| K_USE_COLUMN
				| K_USE_VARIABLE
				| K_USING_NLS_COMP
				| K_VARIABLE_CONFLICT
				| K_WARNING
				;


%%

/*
 * Check whether a token represents an "unreserved keyword".
 * We have various places where we want to recognize a keyword in preference
 * to a variable name, but not reserve that keyword in other contexts.
 * Hence, this kluge.
 */
static bool
tok_is_keyword(int token, union YYSTYPE *lval,
			   int kw_token, const char *kw_str)
{
	if (token == kw_token)
	{
		/* Normal case, was recognized by scanner (no conflicting variable) */
		return true;
	}
	else if (token == T_DATUM)
	{
		/*
		 * It's a variable, so recheck the string name.  Note we will not
		 * match composite names (hence an unreserved word followed by "."
		 * will not be recognized).
		 */
		if (!lval->wdatum.quoted && lval->wdatum.ident != NULL &&
			strcmp(lval->wdatum.ident, kw_str) == 0)
			return true;
	}
	return false;				/* not the keyword */
}

/*
 * Convenience routine to complain when we expected T_DATUM and got T_WORD,
 * ie, unrecognized variable.
 */
static void
word_is_not_variable(PLword *word, int location)
{
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg("\"%s\" is not a known variable",
					word->ident),
			 parser_errposition(location)));
}

/* Same, for a CWORD */
static void
cword_is_not_variable(PLcword *cword, int location)
{
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg("\"%s\" is not a known variable",
					NameListToString(cword->idents)),
			 parser_errposition(location)));
}

/*
 * Convenience routine to complain when we expected T_DATUM and got
 * something else.  "tok" must be the current token, since we also
 * look at yylval and yylloc.
 */
static void
current_token_is_not_variable(int tok)
{
	if (tok == T_WORD)
		word_is_not_variable(&(yylval.word), yylloc);
	else if (tok == T_CWORD)
		cword_is_not_variable(&(yylval.cword), yylloc);
	else
		yyerror("syntax error");
}

/* Convenience routine to read an expression with one possible terminator */
static PLiSQL_expr *
read_sql_expression(int until, const char *expected)
{
	return read_sql_construct(until, 0, 0, expected,
							  RAW_PARSE_PLPGSQL_EXPR,
							  true, true, NULL, NULL);
}

/* Convenience routine to read an expression with two possible terminators */
static PLiSQL_expr *
read_sql_expression2(int until, int until2, const char *expected,
					 int *endtoken)
{
	return read_sql_construct(until, until2, 0, expected,
							  RAW_PARSE_PLPGSQL_EXPR,
							  true, true, NULL, endtoken);
}

/* Convenience routine to read a SQL statement that must end with ';' */
static PLiSQL_expr *
read_sql_stmt(void)
{
	return read_sql_construct(';', 0, 0, ";",
							  RAW_PARSE_DEFAULT,
							  false, true, NULL, NULL);
}

/*
 * Read a SQL construct and build a PLiSQL_expr for it.
 *
 * until:		token code for expected terminator
 * until2:		token code for alternate terminator (pass 0 if none)
 * until3:		token code for another alternate terminator (pass 0 if none)
 * expected:	text to use in complaining that terminator was not found
 * parsemode:	raw_parser() mode to use
 * isexpression: whether to say we're reading an "expression" or a "statement"
 * valid_sql:   whether to check the syntax of the expr
 * startloc:	if not NULL, location of first token is stored at *startloc
 * endtoken:	if not NULL, ending token is stored at *endtoken
 *				(this is only interesting if until2 or until3 isn't zero)
 */
static PLiSQL_expr *
read_sql_construct(int until,
				   int until2,
				   int until3,
				   const char *expected,
				   RawParseMode parsemode,
				   bool isexpression,
				   bool valid_sql,
				   int *startloc,
				   int *endtoken)
{
	int			tok;
	StringInfoData ds;
	IdentifierLookup save_IdentifierLookup;
	int			startlocation = -1;
	int			endlocation = -1;
	int			parenlevel = 0;
	PLiSQL_expr		*expr;

	initStringInfo(&ds);

	/* special lookup mode for identifiers within the SQL text */
	save_IdentifierLookup = plisql_IdentifierLookup;
	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;

	for (;;)
	{
		tok = yylex();
		if (startlocation < 0)			/* remember loc of first token */
			startlocation = yylloc;
		if (tok == until && parenlevel == 0)
			break;
		if (tok == until2 && parenlevel == 0)
			break;
		if (tok == until3 && parenlevel == 0)
			break;
		if (tok == '(' || tok == '[')
			parenlevel++;
		else if (tok == ')' || tok == ']')
		{
			parenlevel--;
			if (parenlevel < 0)
				yyerror("mismatched parentheses");
		}
		/*
		 * End of function definition is an error, and we don't expect to
		 * hit a semicolon either (unless it's the until symbol, in which
		 * case we should have fallen out above).
		 */
		if (tok == 0 || tok == ';')
		{
			if (parenlevel != 0)
				yyerror("mismatched parentheses");
			if (isexpression)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("missing \"%s\" at end of SQL expression",
								expected),
						 parser_errposition(yylloc)));
			else
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("missing \"%s\" at end of SQL statement",
								expected),
						 parser_errposition(yylloc)));
		}
		/* Remember end+1 location of last accepted token */
		endlocation = yylloc + plisql_token_length();
	}

	plisql_IdentifierLookup = save_IdentifierLookup;

	if (startloc)
		*startloc = startlocation;
	if (endtoken)
		*endtoken = tok;

	/* give helpful complaint about empty input */
	if (startlocation >= endlocation)
	{
		if (isexpression)
			yyerror("missing expression");
		else
			yyerror("missing SQL statement");
	}

	/*
	 * We save only the text from startlocation to endlocation-1.  This
	 * suppresses the "until" token as well as any whitespace or comments
	 * following the last accepted token.  (We used to strip such trailing
	 * whitespace by hand, but that causes problems if there's a "-- comment"
	 * in front of said whitespace.)
	 */
	plisql_append_source_text(&ds, startlocation, endlocation);

	expr = palloc0(sizeof(PLiSQL_expr));
	expr->query = pstrdup(ds.data);
	expr->parseMode = parsemode;
	expr->plan = NULL;
	expr->paramnos = NULL;
	expr->target_param = -1;
	expr->ns			= plisql_ns_top();
	pfree(ds.data);

	if (valid_sql)
		check_sql_expr(expr->query, expr->parseMode, startlocation);

	return expr;
}

/*
 * Read a datatype declaration, consuming the current lookahead token if any.
 * Returns a PLiSQL_type struct.
 */
static PLiSQL_type *
read_datatype(int tok)
{
	StringInfoData ds;
	char	   *type_name;
	int			startlocation;
	PLiSQL_type *result = NULL;
	int			parenlevel = 0;

	/* Should only be called while parsing DECLARE sections */
	Assert(plisql_IdentifierLookup == IDENTIFIER_LOOKUP_DECLARE);

	/* Often there will be a lookahead token, but if not, get one */
	if (tok == YYEMPTY)
		tok = yylex();

	/* The current token is the start of what we'll pass to parse_datatype */
	startlocation = yylloc;

	/*
	 * If we have a simple or composite identifier, check for %TYPE and
	 * %ROWTYPE constructs.
	 */
	if (tok == T_WORD)
	{
		char	   *dtname = yylval.word.ident;

		tok = yylex();
		if (tok == '%')
		{
			tok = yylex();
			if (tok_is_keyword(tok, &yylval,
							   K_TYPE, "type"))
				result = plisql_parse_wordtype(dtname);
			else if (tok_is_keyword(tok, &yylval,
									K_ROWTYPE, "rowtype"))
				result = plisql_parse_wordrowtype(dtname);
		}
	}
	else if (plisql_token_is_unreserved_keyword(tok))
	{
		char	   *dtname = pstrdup(yylval.keyword);

		tok = yylex();
		if (tok == '%')
		{
			tok = yylex();
			if (tok_is_keyword(tok, &yylval,
							   K_TYPE, "type"))
				result = plisql_parse_wordtype(dtname);
			else if (tok_is_keyword(tok, &yylval,
									K_ROWTYPE, "rowtype"))
				result = plisql_parse_wordrowtype(dtname);
		}
	}
	else if (tok == T_CWORD)
	{
		List	   *dtnames = yylval.cword.idents;

		tok = yylex();
		if (tok == '%')
		{
			tok = yylex();
			if (tok_is_keyword(tok, &yylval,
							   K_TYPE, "type"))
				result = plisql_parse_cwordtype(dtnames);
			else if (tok_is_keyword(tok, &yylval,
									K_ROWTYPE, "rowtype"))
				result = plisql_parse_cwordrowtype(dtnames);
		}
	}

	/*
	 * If we recognized a %TYPE or %ROWTYPE construct, see if it is followed
	 * by array decoration: [ ARRAY ] [ '[' [ iconst ] ']' [ ... ] ]
	 *
	 * Like the core parser, we ignore the specific numbers and sizes of
	 * dimensions; arrays of different dimensionality are still the same type
	 * in Postgres.
	 */
	if (result)
	{
		bool		is_array = false;

		tok = yylex();
		if (tok_is_keyword(tok, &yylval,
						   K_ARRAY, "array"))
		{
			is_array = true;
			tok = yylex();
		}
		while (tok == '[')
		{
			is_array = true;
			tok = yylex();
			if (tok == ICONST)
				tok = yylex();
			if (tok != ']')
				yyerror("syntax error, expected \"]\"");
			tok = yylex();
		}
		plisql_push_back_token(tok);

		if (is_array)
			result = plisql_build_datatype_arrayof(result);

		return result;
	}

	/*
	 * Not %TYPE or %ROWTYPE, so scan to the end of the datatype declaration,
	 * which could include typmod or array decoration.  We are not very picky
	 * here, instead relying on parse_datatype to complain about garbage.  But
	 * we must count parens to handle typmods within cursor_arg correctly.
	 */
	while (tok != ';')
	{
		if (tok == 0)
		{
			if (parenlevel != 0)
				yyerror("mismatched parentheses");
			else
				yyerror("incomplete data type declaration");
		}
		/* Possible followers for datatype in a declaration */
		if (tok == K_COLLATE || tok == K_NOT ||
			tok == '=' || tok == COLON_EQUALS || tok == K_DEFAULT)
			break;
		/* Possible followers for datatype in a cursor_arg list */
		if ((tok == ',' || tok == ')') && parenlevel == 0)
			break;
		if ((tok == K_AS || tok == K_IS || tok == K_RESULT_CACHE ||
			tok == K_PARALLEL_ENABLE || tok == K_DETERMINISTIC ||
			tok == K_PIPELINED) && parenlevel == 0)
			break;
		if (tok == '(')
			parenlevel++;
		else if (tok == ')')
			parenlevel--;

		tok = yylex();
	}

	/* set up ds to contain complete typename text */
	initStringInfo(&ds);
	plisql_append_source_text(&ds, startlocation, yylloc);
	type_name = ds.data;

	if (type_name[0] == '\0')
		yyerror("missing data type declaration");

	result = parse_datatype(type_name, startlocation);

	pfree(ds.data);

	plisql_push_back_token(tok);

	return result;
}

static PLiSQL_stmt *
make_execsql_stmt(int firsttoken, int location)
{
	StringInfoData		ds;
	IdentifierLookup	save_IdentifierLookup;
	PLiSQL_stmt_execsql *execsql;
	PLiSQL_expr		*expr;
	PLiSQL_variable	*target = NULL;
	int					tok;
	int					prev_tok;
	bool				have_into = false;
	bool				have_strict = false;
	int					into_start_loc = -1;
	int					into_end_loc = -1;

	initStringInfo(&ds);

	/* special lookup mode for identifiers within the SQL text */
	save_IdentifierLookup = plisql_IdentifierLookup;
	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;

	/*
	 * Scan to the end of the SQL command.  Identify any INTO-variables
	 * clause lurking within it, and parse that via read_into_target().
	 *
	 * Because INTO is sometimes used in the main SQL grammar, we have to be
	 * careful not to take any such usage of INTO as a PL/iSQL INTO clause.
	 * There are currently three such cases:
	 *
	 * 1. SELECT ... INTO.  We don't care, we just override that with the
	 * PL/iSQL definition.
	 *
	 * 2. INSERT INTO.  This is relatively easy to recognize since the words
	 * must appear adjacently; but we can't assume INSERT starts the command,
	 * because it can appear in CREATE RULE or WITH.  Unfortunately, INSERT is
	 * *not* fully reserved, so that means there is a chance of a false match;
	 * but it's not very likely.
	 *
	 * 3. IMPORT FOREIGN SCHEMA ... INTO.  This is not allowed in CREATE RULE
	 * or WITH, so we just check for IMPORT as the command's first token.
	 * (If IMPORT FOREIGN SCHEMA returned data someone might wish to capture
	 * with an INTO-variables clause, we'd have to work much harder here.)
	 *
	 * Fortunately, INTO is a fully reserved word in the main grammar, so
	 * at least we need not worry about it appearing as an identifier.
	 *
	 * Any future additional uses of INTO in the main grammar will doubtless
	 * break this logic again ... beware!
	 */
	tok = firsttoken;
	for (;;)
	{
		prev_tok = tok;
		tok = yylex();
		if (have_into && into_end_loc < 0)
			into_end_loc = yylloc;		/* token after the INTO part */
		if (tok == ';')
			break;
		if (tok == 0)
			yyerror("unexpected end of function definition");
		if (tok == K_INTO)
		{
			if (prev_tok == K_INSERT)
				continue;		/* INSERT INTO is not an INTO-target */
			if (prev_tok == K_MERGE)
				continue;		/* MERGE INTO is not an INTO-target */
			if (firsttoken == K_IMPORT)
				continue;		/* IMPORT ... INTO is not an INTO-target */
			if (have_into)
				yyerror("INTO specified more than once");
			have_into = true;
			into_start_loc = yylloc;
			plisql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
			read_into_target(&target, &have_strict);
			plisql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;
		}
	}

	plisql_IdentifierLookup = save_IdentifierLookup;

	if (have_into)
	{
		/*
		 * Insert an appropriate number of spaces corresponding to the
		 * INTO text, so that locations within the redacted SQL statement
		 * still line up with those in the original source text.
		 */
		plisql_append_source_text(&ds, location, into_start_loc);
		appendStringInfoSpaces(&ds, into_end_loc - into_start_loc);
		plisql_append_source_text(&ds, into_end_loc, yylloc);
	}
	else
		plisql_append_source_text(&ds, location, yylloc);

	/* trim any trailing whitespace, for neatness */
	while (ds.len > 0 && scanner_isspace(ds.data[ds.len - 1]))
		ds.data[--ds.len] = '\0';

	expr = palloc0(sizeof(PLiSQL_expr));
	expr->query			= pstrdup(ds.data);
	expr->parseMode		= RAW_PARSE_DEFAULT;
	expr->plan			= NULL;
	expr->paramnos		= NULL;
	expr->target_param	= -1;
	expr->ns			= plisql_ns_top();
	pfree(ds.data);

	check_sql_expr(expr->query, expr->parseMode, location);

	execsql = palloc0(sizeof(PLiSQL_stmt_execsql));
	execsql->cmd_type = PLISQL_STMT_EXECSQL;
	execsql->lineno  = plisql_location_to_lineno(location);
	execsql->stmtid  = ++plisql_curr_compile->nstatements;
	execsql->sqlstmt = expr;
	execsql->into	 = have_into;
	execsql->strict	 = have_strict;
	execsql->target	 = target;

	return (PLiSQL_stmt *) execsql;
}

static PLiSQL_expr *
build_call_expr(int firsttoken, int location)
{
	StringInfoData		ds;
	IdentifierLookup	save_IdentifierLookup;
	PLiSQL_expr			*expr;
	int					tok;

	initStringInfo(&ds);

	/* special lookup mode for identifiers within the SQL text */
	save_IdentifierLookup = plisql_IdentifierLookup;
	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;

	tok = firsttoken;
	for (;;)
	{
		tok = yylex();
		if (tok == ';')
			break;
		if (tok == 0)
			yyerror("unexpected end of function definition");
	}

	plisql_IdentifierLookup = save_IdentifierLookup;
	plisql_append_source_text(&ds, location, yylloc);

	/* trim any trailing whitespace, for neatness */
	while (ds.len > 0 && scanner_isspace(ds.data[ds.len - 1]))
		ds.data[--ds.len] = '\0';

	/* build call expr */
	if ((firsttoken == T_WORD || firsttoken ==T_CWORD) && tok == ';')
		ds.data = psprintf("CALL %s", ds.data);

	expr = palloc0(sizeof(PLiSQL_expr));
	expr->query			= pstrdup(ds.data);
	expr->parseMode		= RAW_PARSE_DEFAULT;
	expr->plan			= NULL;
	expr->paramnos		= NULL;
	expr->target_param	= -1;
	expr->ns			= plisql_ns_top();
	pfree(ds.data);

	check_sql_expr(expr->query, expr->parseMode, location);

	return expr;
}
/*
 * Read FETCH or MOVE direction clause (everything through FROM/IN).
 */
static PLiSQL_stmt_fetch *
read_fetch_direction(void)
{
	PLiSQL_stmt_fetch *fetch;
	int			tok;
	bool		check_FROM = true;

	/*
	 * We create the PLiSQL_stmt_fetch struct here, but only fill in
	 * the fields arising from the optional direction clause
	 */
	fetch = (PLiSQL_stmt_fetch *) palloc0(sizeof(PLiSQL_stmt_fetch));
	fetch->cmd_type = PLISQL_STMT_FETCH;
	fetch->stmtid	= ++plisql_curr_compile->nstatements;
	/* set direction defaults: */
	fetch->direction = FETCH_FORWARD;
	fetch->how_many = 1;
	fetch->expr = NULL;
	fetch->returns_multiple_rows = false;

	tok = yylex();
	if (tok == 0)
		yyerror("unexpected end of function definition");

	if (tok_is_keyword(tok, &yylval,
					   K_NEXT, "next"))
	{
		/* use defaults */
	}
	else if (tok_is_keyword(tok, &yylval,
							K_PRIOR, "prior"))
	{
		fetch->direction = FETCH_BACKWARD;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_FIRST, "first"))
	{
		fetch->direction = FETCH_ABSOLUTE;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_LAST, "last"))
	{
		fetch->direction = FETCH_ABSOLUTE;
		fetch->how_many  = -1;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_ABSOLUTE, "absolute"))
	{
		fetch->direction = FETCH_ABSOLUTE;
		fetch->expr = read_sql_expression2(K_FROM, K_IN,
										   "FROM or IN",
										   NULL);
		check_FROM = false;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_RELATIVE, "relative"))
	{
		fetch->direction = FETCH_RELATIVE;
		fetch->expr = read_sql_expression2(K_FROM, K_IN,
										   "FROM or IN",
										   NULL);
		check_FROM = false;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_ALL, "all"))
	{
		fetch->how_many = FETCH_ALL;
		fetch->returns_multiple_rows = true;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_FORWARD, "forward"))
	{
		complete_direction(fetch, &check_FROM);
	}
	else if (tok_is_keyword(tok, &yylval,
							K_BACKWARD, "backward"))
	{
		fetch->direction = FETCH_BACKWARD;
		complete_direction(fetch, &check_FROM);
	}
	else if (tok == K_FROM || tok == K_IN)
	{
		/* empty direction */
		check_FROM = false;
	}
	else if (tok == T_DATUM)
	{
		/* Assume there's no direction clause and tok is a cursor name */
		plisql_push_back_token(tok);
		check_FROM = false;
	}
	else
	{
		/*
		 * Assume it's a count expression with no preceding keyword.
		 * Note: we allow this syntax because core SQL does, but it's
		 * ambiguous with the case of an omitted direction clause; for
		 * instance, "MOVE n IN c" will fail if n is a variable, because the
		 * preceding else-arm will trigger.  Perhaps this can be improved
		 * someday, but it hardly seems worth a lot of work.
		 */
		plisql_push_back_token(tok);
		fetch->expr = read_sql_expression2(K_FROM, K_IN,
										   "FROM or IN",
										   NULL);
		fetch->returns_multiple_rows = true;
		check_FROM = false;
	}

	/* check FROM or IN keyword after direction's specification */
	if (check_FROM)
	{
		tok = yylex();
		if (tok != K_FROM && tok != K_IN)
			yyerror("expected FROM or IN");
	}

	return fetch;
}

/*
 * Process remainder of FETCH/MOVE direction after FORWARD or BACKWARD.
 * Allows these cases:
 *   FORWARD expr,  FORWARD ALL,  FORWARD
 *   BACKWARD expr, BACKWARD ALL, BACKWARD
 */
static void
complete_direction(PLiSQL_stmt_fetch *fetch,  bool *check_FROM)
{
	int			tok;

	tok = yylex();
	if (tok == 0)
		yyerror("unexpected end of function definition");

	if (tok == K_FROM || tok == K_IN)
	{
		*check_FROM = false;
		return;
	}

	if (tok == K_ALL)
	{
		fetch->how_many = FETCH_ALL;
		fetch->returns_multiple_rows = true;
		*check_FROM = true;
		return;
	}

	plisql_push_back_token(tok);
	fetch->expr = read_sql_expression2(K_FROM, K_IN,
									   "FROM or IN",
									   NULL);
	fetch->returns_multiple_rows = true;
	*check_FROM = false;
}


static PLiSQL_stmt *
make_return_stmt(int location)
{
	PLiSQL_stmt_return *new;

	new = palloc0(sizeof(PLiSQL_stmt_return));
	new->cmd_type = PLISQL_STMT_RETURN;
	new->lineno   = plisql_location_to_lineno(location);
	new->stmtid	  = ++plisql_curr_compile->nstatements;
	new->expr	  = NULL;
	new->retvarno = -1;

	if (plisql_curr_compile->fn_retset)
	{
		if (yylex() != ';')
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("RETURN cannot have a parameter in function returning set"),
					 errhint("Use RETURN NEXT or RETURN QUERY."),
					 parser_errposition(yylloc)));
	}
	else if (plisql_curr_compile->fn_rettype == VOIDOID)
	{
		if (yylex() != ';')
		{
			if (plisql_curr_compile->fn_prokind == PROKIND_PROCEDURE)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("RETURN cannot have a parameter in a procedure"),
						 parser_errposition(yylloc)));
			else
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg("RETURN cannot have a parameter in function returning void"),
						 parser_errposition(yylloc)));
		}
	}
	else if (plisql_curr_compile->out_param_varno >= 0)
	{
		if (yylex() != ';')
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("RETURN cannot have a parameter in function with OUT parameters"),
					 parser_errposition(yylloc)));
		new->retvarno = plisql_curr_compile->out_param_varno;
	}
	else
	{
		/*
		 * We want to special-case simple variable references for efficiency.
		 * So peek ahead to see if that's what we have.
		 */
		int			tok = yylex();

		if (tok == T_DATUM && plisql_peek() == ';' &&
			(yylval.wdatum.datum->dtype == PLISQL_DTYPE_VAR ||
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_PACKAGE_DATUM || 
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_PROMISE ||
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_ROW ||
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_REC))
		{
			new->retvarno = yylval.wdatum.datum->dno;
			/* eat the semicolon token that we only peeked at above */
			tok = yylex();
			Assert(tok == ';');
		}
		else
		{
			/*
			 * Not (just) a variable name, so treat as expression.
			 *
			 * Note that a well-formed expression is _required_ here;
			 * anything else is a compile-time error.
			 */
			plisql_push_back_token(tok);
			new->expr = read_sql_expression(';', ";");
		}
	}

	return (PLiSQL_stmt *) new;
}


static PLiSQL_stmt *
make_return_next_stmt(int location)
{
	PLiSQL_stmt_return_next *new;

	if (!plisql_curr_compile->fn_retset)
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("cannot use RETURN NEXT in a non-SETOF function"),
				 parser_errposition(location)));

	new = palloc0(sizeof(PLiSQL_stmt_return_next));
	new->cmd_type	= PLISQL_STMT_RETURN_NEXT;
	new->lineno		= plisql_location_to_lineno(location);
	new->stmtid		= ++plisql_curr_compile->nstatements;
	new->expr = NULL;
	new->retvarno = -1;

	if (plisql_curr_compile->out_param_varno >= 0)
	{
		if (yylex() != ';')
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("RETURN NEXT cannot have a parameter in function with OUT parameters"),
					 parser_errposition(yylloc)));
		new->retvarno = plisql_curr_compile->out_param_varno;
	}
	else
	{
		/*
		 * We want to special-case simple variable references for efficiency.
		 * So peek ahead to see if that's what we have.
		 */
		int			tok = yylex();

		if (tok == T_DATUM && plisql_peek() == ';' &&
			(yylval.wdatum.datum->dtype == PLISQL_DTYPE_VAR ||
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_PACKAGE_DATUM || 
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_PROMISE ||
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_ROW ||
			 yylval.wdatum.datum->dtype == PLISQL_DTYPE_REC))
		{
			new->retvarno = yylval.wdatum.datum->dno;
			/* eat the semicolon token that we only peeked at above */
			tok = yylex();
			Assert(tok == ';');
		}
		else
		{
			/*
			 * Not (just) a variable name, so treat as expression.
			 *
			 * Note that a well-formed expression is _required_ here;
			 * anything else is a compile-time error.
			 */
			plisql_push_back_token(tok);
			new->expr = read_sql_expression(';', ";");
		}
	}

	return (PLiSQL_stmt *) new;
}


static PLiSQL_stmt *
make_return_query_stmt(int location)
{
	PLiSQL_stmt_return_query *new;
	int			tok;

	if (!plisql_curr_compile->fn_retset)
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("cannot use RETURN QUERY in a non-SETOF function"),
				 parser_errposition(location)));

	new = palloc0(sizeof(PLiSQL_stmt_return_query));
	new->cmd_type = PLISQL_STMT_RETURN_QUERY;
	new->lineno = plisql_location_to_lineno(location);
	new->stmtid = ++plisql_curr_compile->nstatements;

	/* check for RETURN QUERY EXECUTE */
	if ((tok = yylex()) != K_EXECUTE)
	{
		/* ordinary static query */
		plisql_push_back_token(tok);
		new->query = read_sql_stmt();
	}
	else
	{
		/* dynamic SQL */
		int			term;

		new->dynquery = read_sql_expression2(';', K_USING, "; or USING",
											 &term);
		if (term == K_USING)
		{
			do
			{
				PLiSQL_expr *expr;

				expr = read_sql_expression2(',', ';', ", or ;", &term);
				new->params = lappend(new->params, expr);
			} while (term == ',');
		}
	}

	return (PLiSQL_stmt *) new;
}


/* convenience routine to fetch the name of a T_DATUM */
static char *
NameOfDatum(PLwdatum *wdatum)
{
	if (wdatum->ident)
		return wdatum->ident;
	Assert(wdatum->idents != NIL);
	return NameListToString(wdatum->idents);
}

static void
check_assignable(PLiSQL_datum *datum, int location)
{
	switch (datum->dtype)
	{
		case PLISQL_DTYPE_VAR:
		case PLISQL_DTYPE_PROMISE:
		case PLISQL_DTYPE_REC:
			if (((PLiSQL_variable *) datum)->isconst)
				ereport(ERROR,
						(errcode(ERRCODE_ERROR_IN_ASSIGNMENT),
						 errmsg("variable \"%s\" is declared CONSTANT",
								((PLiSQL_variable *) datum)->refname),
						 parser_errposition(location)));
			break;
		case PLISQL_DTYPE_ROW:
			/* always assignable; member vars were checked at compile time */
			break;
		case PLISQL_DTYPE_RECFIELD:
			/* assignable if parent record is */
			check_assignable(plisql_Datums[((PLiSQL_recfield *) datum)->recparentno],
							 location);
			break;
		case PLISQL_DTYPE_PACKAGE_DATUM:
			check_packagedatum_assignable((PLiSQL_pkg_datum *) datum, location);
			break;
		default:
			elog(ERROR, "unrecognized dtype: %d", datum->dtype);
			break;
	}
}

/*
 * check package datum can be assigned
 */
static void
check_packagedatum_assignable(PLiSQL_pkg_datum *pkg_datum, int location)
{
	PLiSQL_datum *datum = pkg_datum->pkgvar;
	PackageCacheItem *item = pkg_datum->item;
	PLiSQL_package *psource = (PLiSQL_package *) item->source;
	PLiSQL_function *func = (PLiSQL_function *) &psource->source;

	switch (datum->dtype)
	{
		case PLISQL_DTYPE_PACKAGE_DATUM:
			{
				PLiSQL_pkg_datum *pkg1_datum = (PLiSQL_pkg_datum *) datum;

				check_packagedatum_assignable(pkg1_datum, location);
			}
			break;
		case PLISQL_DTYPE_VAR:
		case PLISQL_DTYPE_PROMISE:
		case PLISQL_DTYPE_REC:
			if (((PLiSQL_variable *) datum)->isconst)
				ereport(ERROR,
						(errcode(ERRCODE_ERROR_IN_ASSIGNMENT),
						 errmsg("variable \"%s\" is declared CONSTANT",
								((PLiSQL_variable *) datum)->refname),
						 parser_errposition(location)));
			break;
		case PLISQL_DTYPE_ROW:
			/* always assignable; member vars were checked at compile time */
			break;
		case PLISQL_DTYPE_RECFIELD:
			/* assignable if parent record is */
			check_assignable(func->datums[((PLiSQL_recfield *) datum)->recparentno],
							 location);
			break;
		default:
			elog(ERROR, "unrecognized dtype: %d", datum->dtype);
			break;
	}
}

/*
 * Read the argument of an INTO clause.  On entry, we have just read the
 * INTO keyword.
 */
static void
read_into_target(PLiSQL_variable **target, bool *strict)
{
	int			tok;

	/* Set default results */
	*target = NULL;
	if (strict)
		*strict = false;

	tok = yylex();
	if (strict && tok == K_STRICT)
	{
		*strict = true;
		tok = yylex();
	}

	/*
	 * Currently, a row or record variable can be the single INTO target,
	 * but not a member of a multi-target list.  So we throw error if there
	 * is a comma after it, because that probably means the user tried to
	 * write a multi-target list.  If this ever gets generalized, we should
	 * probably refactor read_into_scalar_list so it handles all cases.
	 */
	switch (tok)
	{
		case T_DATUM:
			if (is_row_record_datum(yylval.wdatum.datum)) 
			{
				check_assignable(yylval.wdatum.datum, yylloc);
				*target = (PLiSQL_variable *) yylval.wdatum.datum;

				if ((tok = yylex()) == ',')
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("record variable cannot be part of multiple-item INTO list"),
							 parser_errposition(yylloc)));
				plisql_push_back_token(tok);
			}
			else
			{
				*target = (PLiSQL_variable *)
					read_into_scalar_list(NameOfDatum(&(yylval.wdatum)),
										  yylval.wdatum.datum, yylloc);
			}
			break;

		default:
			/* just to give a better message than "syntax error" */
			current_token_is_not_variable(tok);
	}
}

/*
 * Given the first datum and name in the INTO list, continue to read
 * comma-separated scalar variables until we run out. Then construct
 * and return a fake "row" variable that represents the list of
 * scalars.
 */
static PLiSQL_row *
read_into_scalar_list(char *initial_name,
					  PLiSQL_datum *initial_datum,
					  int initial_location)
{
	int			nfields;
	char	   *fieldnames[1024];
	int			varnos[1024];
	PLiSQL_row		*row;
	int			tok;

	check_assignable(initial_datum, initial_location);
	fieldnames[0] = initial_name;
	varnos[0] = initial_datum->dno;
	nfields = 1;

	while ((tok = yylex()) == ',')
	{
		/* Check for array overflow */
		if (nfields >= 1024)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("too many INTO variables specified"),
					 parser_errposition(yylloc)));

		tok = yylex();
		switch (tok)
		{
			case T_DATUM:
				check_assignable(yylval.wdatum.datum, yylloc);
				if (is_row_record_datum(yylval.wdatum.datum)) 
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("\"%s\" is not a scalar variable",
									NameOfDatum(&(yylval.wdatum))),
							 parser_errposition(yylloc)));
				fieldnames[nfields] = NameOfDatum(&(yylval.wdatum));
				varnos[nfields++]	= yylval.wdatum.datum->dno;
				break;

			default:
				/* just to give a better message than "syntax error" */
				current_token_is_not_variable(tok);
		}
	}

	/*
	 * We read an extra, non-comma token from yylex(), so push it
	 * back onto the input stream
	 */
	plisql_push_back_token(tok);

	row = palloc0(sizeof(PLiSQL_row));
	row->dtype = PLISQL_DTYPE_ROW;
	row->refname = "(unnamed row)";
	row->lineno = plisql_location_to_lineno(initial_location);
	row->rowtupdesc = NULL;
	row->nfields = nfields;
	row->fieldnames = palloc(sizeof(char *) * nfields);
	row->varnos = palloc(sizeof(int) * nfields);
	while (--nfields >= 0)
	{
		row->fieldnames[nfields] = fieldnames[nfields];
		row->varnos[nfields] = varnos[nfields];
	}

	plisql_adddatum((PLiSQL_datum *)row);

	return row;
}

/*
 * Convert a single scalar into a "row" list.  This is exactly
 * like read_into_scalar_list except we never consume any input.
 *
 * Note: lineno could be computed from location, but since callers
 * have it at hand already, we may as well pass it in.
 */
static PLiSQL_row *
make_scalar_list1(char *initial_name,
				  PLiSQL_datum *initial_datum,
				  int lineno, int location)
{
	PLiSQL_row		*row;

	check_assignable(initial_datum, location);

	row = palloc0(sizeof(PLiSQL_row));
	row->dtype = PLISQL_DTYPE_ROW;
	row->refname = "(unnamed row)";
	row->lineno = lineno;
	row->rowtupdesc = NULL;
	row->nfields = 1;
	row->fieldnames = palloc(sizeof(char *));
	row->varnos = palloc(sizeof(int));
	row->fieldnames[0] = initial_name;
	row->varnos[0] = initial_datum->dno;

	plisql_adddatum((PLiSQL_datum *)row);

	return row;
}

/*
 * When the PL/iSQL parser expects to see a SQL statement, it is very
 * liberal in what it accepts; for example, we often assume an
 * unrecognized keyword is the beginning of a SQL statement. This
 * avoids the need to duplicate parts of the SQL grammar in the
 * PL/iSQL grammar, but it means we can accept wildly malformed
 * input. To try and catch some of the more obviously invalid input,
 * we run the strings we expect to be SQL statements through the main
 * SQL parser.
 *
 * We only invoke the raw parser (not the analyzer); this doesn't do
 * any database access and does not check any semantic rules, it just
 * checks for basic syntactic correctness. We do this here, rather
 * than after parsing has finished, because a malformed SQL statement
 * may cause the PL/iSQL parser to become confused about statement
 * borders. So it is best to bail out as early as we can.
 *
 * It is assumed that "stmt" represents a copy of the function source text
 * beginning at offset "location".  We use this assumption to transpose
 * any error cursor position back to the function source text.
 * If no error cursor is provided, we'll just point at "location".
 */
static void
check_sql_expr(const char *stmt, RawParseMode parseMode, int location)
{
	sql_error_callback_arg cbarg;
	ErrorContextCallback  syntax_errcontext;
	MemoryContext oldCxt;

	if (!plisql_check_syntax)
		return;

	cbarg.location = location;

	syntax_errcontext.callback = plisql_sql_error_callback;
	syntax_errcontext.arg = &cbarg;
	syntax_errcontext.previous = error_context_stack;
	error_context_stack = &syntax_errcontext;

	oldCxt = MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	(void) raw_parser(stmt, parseMode);
	MemoryContextSwitchTo(oldCxt);

	/* Restore former ereport callback */
	error_context_stack = syntax_errcontext.previous;
}

static void
plisql_sql_error_callback(void *arg)
{
	sql_error_callback_arg *cbarg = (sql_error_callback_arg *) arg;
	int			errpos;

	/*
	 * First, set up internalerrposition to point to the start of the
	 * statement text within the function text.  Note this converts
	 * location (a byte offset) to a character number.
	 */
	parser_errposition(cbarg->location);

	/*
	 * If the core parser provided an error position, transpose it.
	 * Note we are dealing with 1-based character numbers at this point.
	 */
	errpos = geterrposition();
	if (errpos > 0)
	{
		int			myerrpos = getinternalerrposition();

		if (myerrpos > 0)		/* safety check */
			internalerrposition(myerrpos + errpos - 1);
	}

	/* In any case, flush errposition --- we want internalerrposition only */
	errposition(0);
}

/*
 * Parse a SQL datatype name and produce a PLiSQL_type structure.
 *
 * The heavy lifting is done elsewhere.  Here we are only concerned
 * with setting up an errcontext link that will let us give an error
 * cursor pointing into the plisql function source, if necessary.
 * This is handled the same as in check_sql_expr(), and we likewise
 * expect that the given string is a copy from the source text.
 */
static PLiSQL_type *
parse_datatype(const char *string, int location)
{
	TypeName   *typeName;
	Oid			type_id;
	int32		typmod;
	sql_error_callback_arg cbarg;
	ErrorContextCallback  syntax_errcontext;
	PLiSQL_type *result = NULL;

	cbarg.location = location;

	syntax_errcontext.callback = plisql_sql_error_callback;
	syntax_errcontext.arg = &cbarg;
	syntax_errcontext.previous = error_context_stack;
	error_context_stack = &syntax_errcontext;

	/* Let the main parser try to parse it under standard SQL rules */
	typeName = typeStringToTypeName(string, NULL);

	if (list_length(typeName->names) < 2 &&
		!is_compile_standard_package())
	{
		/* may be a standard.type */
		size_t len = 8 + strlen(string) + 2;
		char *refname = (char *) palloc0(len);
		TypeName *newtypName;

		snprintf(refname, len, "standard.%s", string);
		newtypName = typeStringToTypeName(refname, NULL);
		pfree(refname);
		result = plisql_parse_package_type(newtypName, parse_by_pkg_type, true);
		pfree(newtypName);
	}
	else
		result = plisql_parse_package_type(typeName, parse_by_pkg_type, false);
	if (result != NULL)
	{
		error_context_stack = syntax_errcontext.previous;
		return result;
	}

	typenameTypeIdAndMod(NULL, typeName, &type_id, &typmod);

	/* Restore former ereport callback */
	error_context_stack = syntax_errcontext.previous;

	/* Okay, build a PLiSQL_type data structure for it */
	return plisql_build_datatype(type_id, typmod,
								  plisql_curr_compile->fn_input_collation,
								  typeName);
}

/*
 * Check block starting and ending labels match.
 */
static void
check_labels(const char *start_label, const char *end_label, int end_location)
{
	if (end_label)
	{
		if (!start_label)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("end label \"%s\" specified for unlabeled block",
							end_label),
					 parser_errposition(end_location)));

		if (strcmp(start_label, end_label) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("end label \"%s\" differs from block's label \"%s\"",
							end_label, start_label),
					 parser_errposition(end_location)));
	}
}

/*
 * Read the arguments (if any) for a cursor, followed by the until token
 *
 * If cursor has no args, just swallow the until token and return NULL.
 * If it does have args, we expect to see "( arg [, arg ...] )" followed
 * by the until token, where arg may be a plain expression, or a named
 * parameter assignment of the form argname := expr. Consume all that and
 * return a SELECT query that evaluates the expression(s) (without the outer
 * parens).
 */
static PLiSQL_expr *
read_cursor_args(PLiSQL_var *cursor, int until)
{
	PLiSQL_expr *expr;
	PLiSQL_row *row;
	int			tok;
	int			argc;
	char	  **argv;
	StringInfoData ds;
	bool		any_named = false;
	PLiSQL_var	*real_cursor = NULL;
	bool		is_packagevar = false;

	tok = yylex();
	if (cursor->dtype == PLISQL_DTYPE_PACKAGE_DATUM)
	{
		real_cursor = (PLiSQL_var *) ((PLiSQL_pkg_datum *) cursor)->pkgvar;
		is_packagevar = true;
	}
	else
		real_cursor = cursor;
	if (real_cursor->cursor_explicit_argrow < 0)
	{
		/* No arguments expected */
		if (tok == '(')
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("cursor \"%s\" has no arguments",
							cursor->refname),
					 parser_errposition(yylloc)));

		if (tok != until)
			yyerror("syntax error");

		return NULL;
	}

	/* Else better provide arguments */
	if (tok != '(')
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("cursor \"%s\" has arguments",
						cursor->refname),
				 parser_errposition(yylloc)));

	/*
	 * Read the arguments, one by one.
	 */
	if (is_packagevar)
	{
		PLiSQL_pkg_datum *pkg_datum = (PLiSQL_pkg_datum *) cursor;
		PLiSQL_package *psource = (PLiSQL_package *) pkg_datum->item->source;

		row = (PLiSQL_row *) psource->source.datums[real_cursor->cursor_explicit_argrow];
	}
	else
		row = (PLiSQL_row *) plisql_Datums[cursor->cursor_explicit_argrow];

	argv = (char **) palloc0(row->nfields * sizeof(char *));

	for (argc = 0; argc < row->nfields; argc++)
	{
		PLiSQL_expr *item;
		int			endtoken;
		int			argpos;
		int			tok1,
					tok2;
		int			arglocation;

		/* Check if it's a named parameter: "param := value" */
		plisql_peek2(&tok1, &tok2, &arglocation, NULL);
		if (tok1 == IDENT && tok2 == COLON_EQUALS)
		{
			char   *argname;
			IdentifierLookup save_IdentifierLookup;

			/* Read the argument name, ignoring any matching variable */
			save_IdentifierLookup = plisql_IdentifierLookup;
			plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
			yylex();
			argname = yylval.str;
			plisql_IdentifierLookup = save_IdentifierLookup;

			/* Match argument name to cursor arguments */
			for (argpos = 0; argpos < row->nfields; argpos++)
			{
				if (strcmp(row->fieldnames[argpos], argname) == 0)
					break;
			}
			if (argpos == row->nfields)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("cursor \"%s\" has no argument named \"%s\"",
								cursor->refname, argname),
						 parser_errposition(yylloc)));

			/*
			 * Eat the ":=". We already peeked, so the error should never
			 * happen.
			 */
			tok2 = yylex();
			if (tok2 != COLON_EQUALS)
				yyerror("syntax error");

			any_named = true;
		}
		else
			argpos = argc;

		if (argv[argpos] != NULL)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("value for parameter \"%s\" of cursor \"%s\" specified more than once",
							row->fieldnames[argpos], cursor->refname),
					 parser_errposition(arglocation)));

		/*
		 * Read the value expression. To provide the user with meaningful
		 * parse error positions, we check the syntax immediately, instead of
		 * checking the final expression that may have the arguments
		 * reordered.
		 */
		item = read_sql_construct(',', ')', 0,
								  ",\" or \")",
								  RAW_PARSE_PLPGSQL_EXPR,
								  true, true,
								  NULL, &endtoken);

		argv[argpos] = item->query;

		if (endtoken == ')' && !(argc == row->nfields - 1))
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("not enough arguments for cursor \"%s\"",
							cursor->refname),
					 parser_errposition(yylloc)));

		if (endtoken == ',' && (argc == row->nfields - 1))
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("too many arguments for cursor \"%s\"",
							cursor->refname),
					 parser_errposition(yylloc)));
	}

	/* Make positional argument list */
	initStringInfo(&ds);
	for (argc = 0; argc < row->nfields; argc++)
	{
		Assert(argv[argc] != NULL);

		/*
		 * Because named notation allows permutated argument lists, include
		 * the parameter name for meaningful runtime errors.
		 */
		appendStringInfoString(&ds, argv[argc]);
		if (any_named)
			appendStringInfo(&ds, " AS %s",
							 quote_identifier(row->fieldnames[argc]));
		if (argc < row->nfields - 1)
			appendStringInfoString(&ds, ", ");
	}

	expr = palloc0(sizeof(PLiSQL_expr));
	expr->query = pstrdup(ds.data);
	expr->parseMode = RAW_PARSE_PLPGSQL_EXPR;
	expr->plan = NULL;
	expr->paramnos = NULL;
	expr->target_param = -1;
	expr->ns            = plisql_ns_top();
	pfree(ds.data);

	/* Next we'd better find the until token */
	tok = yylex();
	if (tok != until)
		yyerror("syntax error");

	return expr;
}

/*
 * Parse RAISE ... USING options
 */
static List *
read_raise_options(void)
{
	List	   *result = NIL;

	for (;;)
	{
		PLiSQL_raise_option *opt;
		int		tok;

		if ((tok = yylex()) == 0)
			yyerror("unexpected end of function definition");

		opt = (PLiSQL_raise_option *) palloc(sizeof(PLiSQL_raise_option));

		if (tok_is_keyword(tok, &yylval,
						   K_ERRCODE, "errcode"))
			opt->opt_type = PLISQL_RAISEOPTION_ERRCODE;
		else if (tok_is_keyword(tok, &yylval,
								K_MESSAGE, "message"))
			opt->opt_type = PLISQL_RAISEOPTION_MESSAGE;
		else if (tok_is_keyword(tok, &yylval,
								K_DETAIL, "detail"))
			opt->opt_type = PLISQL_RAISEOPTION_DETAIL;
		else if (tok_is_keyword(tok, &yylval,
								K_HINT, "hint"))
			opt->opt_type = PLISQL_RAISEOPTION_HINT;
		else if (tok_is_keyword(tok, &yylval,
								K_COLUMN, "column"))
			opt->opt_type = PLISQL_RAISEOPTION_COLUMN;
		else if (tok_is_keyword(tok, &yylval,
								K_CONSTRAINT, "constraint"))
			opt->opt_type = PLISQL_RAISEOPTION_CONSTRAINT;
		else if (tok_is_keyword(tok, &yylval,
								K_DATATYPE, "datatype"))
			opt->opt_type = PLISQL_RAISEOPTION_DATATYPE;
		else if (tok_is_keyword(tok, &yylval,
								K_TABLE, "table"))
			opt->opt_type = PLISQL_RAISEOPTION_TABLE;
		else if (tok_is_keyword(tok, &yylval,
								K_SCHEMA, "schema"))
			opt->opt_type = PLISQL_RAISEOPTION_SCHEMA;
		else
			yyerror("unrecognized RAISE statement option");

		tok = yylex();
		if (tok != '=' && tok != COLON_EQUALS)
			yyerror("syntax error, expected \"=\"");

		opt->expr = read_sql_expression2(',', ';', ", or ;", &tok);

		result = lappend(result, opt);

		if (tok == ';')
			break;
	}

	return result;
}

/*
 * Check that the number of parameter placeholders in the message matches the
 * number of parameters passed to it, if a message was given.
 */
static void
check_raise_parameters(PLiSQL_stmt_raise *stmt)
{
	char	   *cp;
	int			expected_nparams = 0;

	if (stmt->message == NULL)
		return;

	for (cp = stmt->message; *cp; cp++)
	{
		if (cp[0] == '%')
		{
			/* ignore literal % characters */
			if (cp[1] == '%')
				cp++;
			else
				expected_nparams++;
		}
	}

	if (expected_nparams < list_length(stmt->params))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				errmsg("too many parameters specified for RAISE")));
	if (expected_nparams > list_length(stmt->params))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				errmsg("too few parameters specified for RAISE")));
}

/*
 * Fix up CASE statement
 */
static PLiSQL_stmt *
make_case(int location, PLiSQL_expr *t_expr,
		  List *case_when_list, List *else_stmts)
{
	PLiSQL_stmt_case	*new;

	new = palloc(sizeof(PLiSQL_stmt_case));
	new->cmd_type = PLISQL_STMT_CASE;
	new->lineno = plisql_location_to_lineno(location);
	new->stmtid = ++plisql_curr_compile->nstatements;
	new->t_expr = t_expr;
	new->t_varno = 0;
	new->case_when_list = case_when_list;
	new->have_else = (else_stmts != NIL);
	/* Get rid of list-with-NULL hack */
	if (list_length(else_stmts) == 1 && linitial(else_stmts) == NULL)
		new->else_stmts = NIL;
	else
		new->else_stmts = else_stmts;

	/*
	 * When test expression is present, we create a var for it and then
	 * convert all the WHEN expressions to "VAR IN (original_expression)".
	 * This is a bit klugy, but okay since we haven't yet done more than
	 * read the expressions as text.  (Note that previous parsing won't
	 * have complained if the WHEN ... THEN expression contained multiple
	 * comma-separated values.)
	 */
	if (t_expr)
	{
		char		varname[32];
		PLiSQL_var *t_var;
		ListCell   *l;

		/* use a name unlikely to collide with any user names */
		snprintf(varname, sizeof(varname), "__Case__Variable_%d__",
				 plisql_nDatums);

		/*
		 * We don't yet know the result datatype of t_expr.  Build the
		 * variable as if it were INT4; we'll fix this at runtime if needed.
		 */
		t_var = (PLiSQL_var *)
			plisql_build_variable(varname, new->lineno,
								   plisql_build_datatype(INT4OID,
														  -1,
														  InvalidOid,
														  NULL),
								   true);
		new->t_varno = t_var->dno;

		foreach(l, case_when_list)
		{
			PLiSQL_case_when *cwt = (PLiSQL_case_when *) lfirst(l);
			PLiSQL_expr *expr = cwt->expr;
			StringInfoData	ds;

			/* We expect to have expressions not statements */
			Assert(expr->parseMode == RAW_PARSE_PLPGSQL_EXPR);

			/* Do the string hacking */
			initStringInfo(&ds);

			appendStringInfo(&ds, "\"%s\" IN (%s)",
							 varname, expr->query);

			pfree(expr->query);
			expr->query = pstrdup(ds.data);
			/* Adjust expr's namespace to include the case variable */
			expr->ns = plisql_ns_top();

			pfree(ds.data);
		}
	}

	return (PLiSQL_stmt *) new;
}
