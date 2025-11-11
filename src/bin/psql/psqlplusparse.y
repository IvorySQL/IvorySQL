%{
/*-------------------------------------------------------------------------
 *
 * File: psqlplusparse.y
 *
 * Abstract:
 *		bison grammar for a oracle-compatible client commands.
 *
 * Authored by zhenmingyang@highgo.com, 20221221.
 *
 * Copyright (c) 2022-2025, IvorySQL Global Development Team
 *
 * Identification:
 *		src/bin/psql/psqlplusparse.y
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"
#include "common/logging.h"
#include "fe_utils/psqlscan_int.h"
#include "oracle_fe_utils/ora_psqlscan.h"
#include "psqlplus.h"
#include "settings.h"

static psqlplus_cmd_var *make_variable_node(void);
static psqlplus_cmd_print *make_print_node(void);
static psqlplus_cmd_execute *make_exec_node(void);
static BindVarType *make_bindvartype(int32 oid, int32 typmod, const char *typname);
static char *get_guc_settings(const char *gucname);
static print_item *make_print_item(char *name, bool valid);
static print_list *make_print_list1(print_item *item);
static print_list *merge_print_list(print_list *list1, print_list *list2);

%}

%pure-parser
%expect 0
%name-prefix="psqlplus_yy"

%parse-param {yyscan_t yyscanner}
%lex-param   {yyscan_t yyscanner}

%union
{
	psql_YYSTYPE		psql_yysype;
	int					ival;
	char				*str;
	const char			*keyword;
	psqlplus_cmd		*psqlplus_cmd;
	BindVarType			*bindvartype;
	print_list			*print_item_list;
}

%type <psqlplus_cmd> variable_stmt variable_spec print_stmt exec_stmt
%type <bindvartype> bind_vartype
%type <print_item_list> print_items_list print_items
%type <keyword> unreserved_keyword
%type <keyword> variable_keyword exec_keyword
%type <str> opt_varname bind_varname bind_varvalue
%type <str> Sconst

%token <keyword>	K_VAR K_VARIABLE K_CHAR K_BYTE K_NCHAR K_VARCHAR2 K_NVARCHAR2
	K_NUMBER K_BINARY_FLOAT K_BINARY_DOUBLE K_PRINT K_EXECUTE K_EXEC
%token <str>	IDENT FCONST LITERAL DQCONST SQCONST
%token <ival>	ICONST
%token <str>	SINGLE_QUOTE_NO_END DOUBLE_QUOTE_NO_END
%token			TYPECAST

%%

psqlplus_toplevel_stmt:
		variable_stmt opt_semi
			{
				psql_yyget_extra(yyscanner)->psqlpluscmd = $1;
			}
		| print_stmt opt_semi
			{
				psql_yyget_extra(yyscanner)->psqlpluscmd = $1;
			}
		| exec_stmt opt_semi
			{
				psql_yyget_extra(yyscanner)->psqlpluscmd = $1;
			}
	;

/*
 * Oracle SQL*PLUS VARIABLE statement.
 */
variable_stmt:
	variable_keyword variable_spec
		{
			$$ = $2;
		}
	| variable_keyword opt_varname truncate_char
		{
			/*
			 * Oracle's unusual behavior, when encountering these characters 
			 * represented by $3, ignore these characters and the following text.
			 */
			PsqlScanState		state = psql_yyget_extra(yyscanner);
			psqlplus_cmd_var	*var = make_variable_node();

			if ($2)
				var->var_name = $2;

			var->list_bind_var = true;
			state->psqlpluscmd = (psqlplus_cmd *) var;
			return 0;
		}
	;

variable_keyword:
			K_VARIABLE
			| K_VAR
		;

variable_spec:
		bind_varname
			{
				/* list the specified bind variables */
				psqlplus_cmd_var *var = make_variable_node();
				var->var_name = $1;
				var->list_bind_var = true;
				$$ = (psqlplus_cmd *) var;
			}
		| bind_varname '=' bind_varvalue
			{
				/* bind variable assignment */
				psqlplus_cmd_var *var = make_variable_node();
				var->assign_bind_var = true;
				var->var_name = $1;
				var->init_value = $3;
				$$ = (psqlplus_cmd *) var;
			}
		| bind_varname '='
			{
				/* An error scenario, bind variable assignment without a value */
				psqlplus_cmd_var *var = make_variable_node();
				var->assign_bind_var = true;
				var->var_name = $1;
				$$ = (psqlplus_cmd *) var;
			}
		| bind_varname '=' SINGLE_QUOTE_NO_END
			{
				/*
				 * An error scenario
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = $1;
				var->init_value = $3;
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
		| bind_varname '=' DOUBLE_QUOTE_NO_END
			{
				/*
				 * An error scenario
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = $1;
				var->init_value = $3;
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
		| bind_varname bind_vartype
			{
				/* declare a bind variable */
				psqlplus_cmd_var *var = make_variable_node();
				var->var_name = $1;
				var->vartype = $2;
				var->list_bind_var = false;
				$$ = (psqlplus_cmd *) var;
			}
		| bind_varname bind_vartype '=' bind_varvalue
			{
				/* declare a bind variable with an initial value */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = $1;
				var->vartype = $2;
				var->init_value = $4;
				var->list_bind_var = false;
				var->initial_nonnull_value = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
		| bind_varname bind_vartype '='
			{
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = $1;
				var->vartype = $2;
				var->init_value = NULL;
				var->list_bind_var = false;
				var->initial_nonnull_value = true;
				$$ = (psqlplus_cmd *) var;
			}
		| bind_varname bind_vartype '=' SINGLE_QUOTE_NO_END
			{
				/*
				 * An error scenario, implemented separately in 
				 * order to reduce interaction with the server.
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var *var = make_variable_node();
				var->var_name = $1;
				var->vartype = $2;
				var->init_value = $4;
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				var->initial_nonnull_value = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
		| bind_varname bind_vartype '=' DOUBLE_QUOTE_NO_END
			{
				/*
				 * An error scenario, implemented separately in 
				 * order to reduce interaction with the server.
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = $1;
				var->vartype = $2;
				var->init_value = $4;
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				var->initial_nonnull_value = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
		| /* empty */
			{
				/* list all bind variables */
				psqlplus_cmd_var *var = make_variable_node();
				var->list_bind_var = true;
				$$ = (psqlplus_cmd *) var;
			}
	;

opt_varname:
		bind_varname
			{  $$ = $1; }
		| /* empty */
			{  $$ = NULL; }
	;

bind_varname: IDENT			{ $$ = $1; }
		| unreserved_keyword	{ $$ = pg_strdup($1); }
	;

bind_varvalue:
		Sconst					{ $$ = $1; }
		| LITERAL				{ $$ = $1; }
		| IDENT					{ $$ = $1; }
		| '+' FCONST			{ $$ = $2; }
		| '-' FCONST			{ $$ = psprintf("-%s", $2); } /* itoa() is not portable */
		| FCONST				{ $$ = $1; }
		| '+' ICONST			{ $$ = psprintf("+%d", $2); }
		| '-' ICONST			{ $$ = psprintf("-%d", $2); }
		| ICONST				{ $$ = psprintf("%d", $1); }
		| unreserved_keyword	{ $$ = pg_strdup($1); }
	;

/*
 * Interact with the server in plsq, call the typmodout function of the datatype
 * to verify the validity of the typmod input and obtain the correct typmod value,
 * but the VARIABLE client command only has the typmod value for the character type,
 * and we already know the header of character datatype is 4 byte, so we don't need
 * to sacrifice this performance consumption.
 */
bind_vartype:
		K_CHAR
			{
				$$ = make_bindvartype(ORACHARCHAROID, 1, $1);
			}
		| K_CHAR '(' ICONST ')'
			{
				if (pg_strcasecmp(get_guc_settings("nls_length_semantics"), "byte") == 0)
					$$ = make_bindvartype(ORACHARBYTEOID, $3, $1);
				else
					$$ = make_bindvartype(ORACHARCHAROID, $3, $1);
			}
		| K_CHAR '(' ICONST K_CHAR ')'
			{
				$$ = make_bindvartype(ORACHARCHAROID, $3, $1);
			}
		| K_CHAR '(' ICONST K_BYTE ')'
			{
				$$ = make_bindvartype(ORACHARBYTEOID, $3, $1);
			}
		| K_NCHAR
			{
				$$ = make_bindvartype(ORACHARCHAROID, 1, $1);
			}
		| K_NCHAR '(' ICONST ')'
			{
				$$ = make_bindvartype(ORACHARCHAROID, $3, $1);
			}
		| K_VARCHAR2
			{
				$$ = make_bindvartype(ORAVARCHARCHAROID, 1, $1);
			}
		| K_VARCHAR2 '(' ICONST ')'
			{
				if (pg_strcasecmp(get_guc_settings("nls_length_semantics"), "byte") == 0)
					$$ = make_bindvartype(ORAVARCHARBYTEOID, $3, $1);
				else
					$$ = make_bindvartype(ORAVARCHARCHAROID, $3, $1);
			}
		| K_VARCHAR2 '(' ICONST K_CHAR ')'
			{
				$$ = make_bindvartype(ORAVARCHARCHAROID, $3, $1);
			}
		| K_VARCHAR2 '(' ICONST K_BYTE ')'
			{
				$$ = make_bindvartype(ORAVARCHARBYTEOID, $3, $1);
			}
		| K_NVARCHAR2
			{
				$$ = make_bindvartype(ORAVARCHARCHAROID, 1, $1);
			}
		| K_NVARCHAR2 '(' ICONST ')'
			{
				$$ = make_bindvartype(ORAVARCHARCHAROID, $3, $1);
			}
		| K_NUMBER
			{
				$$ = make_bindvartype(NUMBEROID, -1, $1);
			}
		| K_BINARY_FLOAT
			{
				$$ = make_bindvartype(BINARY_FLOATOID, -1, $1);
			}
		| K_BINARY_DOUBLE
			{
				$$ = make_bindvartype(BINARY_DOUBLEOID, -1, $1);
			}
	;

truncate_char:
		'('
		| ')'
		| ','
	;

/*
 * Oracle SQL*PLUS PRINT statement.
 */
print_stmt:
		K_PRINT
			{
				$$ = (psqlplus_cmd *) make_print_node();
			}
		| K_PRINT print_items_list
			{
				psqlplus_cmd_print *n = make_print_node();
				n->print_items = $2;
				$$ = (psqlplus_cmd *) n;
			}
	;

print_items_list:
	print_items
		{
			$$ = $1;
		}
	| print_items_list print_items
		{
			$$ = merge_print_list($1, $2);
		}
	;

print_items:
	IDENT
		{
			$$ = make_print_list1(make_print_item($1, true));
		}
	| unreserved_keyword
		{
			$$ = make_print_list1(make_print_item(pg_strdup($1), true));
		}
	| DQCONST
		{
			/*
			 * When PRINT specifies a bind variable name,
			 * it can be surrounded by double quotes but
			 * not single quotes.
			 */
			$$ = make_print_list1(make_print_item($1, true));
		}
	| SQCONST
		{
			$$ = make_print_list1(make_print_item($1, false));
		}
	;

/*
 * Oracle SQL*PLUS EXEC[UTE] statement.
 */
exec_stmt: exec_keyword
		{
			PsqlScanState state = psql_yyget_extra(yyscanner);

			if (state->is_sqlplus_cmd)
			{
				psqlplus_cmd_execute *exec = make_exec_node();
				int	offset = strlen(state->scanbuf);
				exec->plisqlstmts = pg_strdup(state->scanline + offset);
				state->psqlpluscmd = (psqlplus_cmd *) exec;
				return 0;
			}
			else
			{
				return 1;
			}
		}
	;

exec_keyword:
		K_EXECUTE
		| K_EXEC
	;

/*
 * Single quotes and double quotes have different semantics 
 * in the PRINT command of SQL*PLUS ,  so the tokens of the 
 * quotes are separated separately.
 */
Sconst:
		SQCONST		{ $$ = $1; };
		| DQCONST	{ $$ = $1; };
	;

opt_semi:
		';'
		| /* empty */
	;

unreserved_keyword:
		K_BINARY_DOUBLE
		| K_BINARY_FLOAT
		| K_BYTE
		| K_CHAR
		| K_EXEC
		| K_EXECUTE
		| K_NCHAR
		| K_NUMBER
		| K_NVARCHAR2
		| K_PRINT
		| K_VAR
		| K_VARCHAR2
		| K_VARIABLE
	;

%%

static psqlplus_cmd_var *
make_variable_node(void)
{
	psqlplus_cmd_var *var = pg_malloc0(sizeof(psqlplus_cmd_var));
	var->cmd_type = PSQLPLUS_CMD_VARIABLE;
	var->var_name = NULL;
	var->vartype = NULL;
	var->init_value = NULL;
	var->miss_termination_quote = false;
	var->list_bind_var = false;
	var->assign_bind_var = false;
	var->initial_nonnull_value = false;
	return var;
}

static psqlplus_cmd_print *
make_print_node(void)
{
	psqlplus_cmd_print *print = pg_malloc0(sizeof(psqlplus_cmd_print));
	print->cmd_type = PSQLPLUS_CMD_PRINT;
	print->print_items = NULL;
	return print;
}

static psqlplus_cmd_execute *
make_exec_node(void)
{
	psqlplus_cmd_execute *exec = pg_malloc0(sizeof(psqlplus_cmd_execute));
	exec->cmd_type = PSQLPLUS_CMD_EXECUTE;
	exec->plisqlstmts = NULL;
	return exec;
}

static BindVarType *
make_bindvartype(int32 oid, int32 typmod, const char *typname)
{
	BindVarType *vartype;

	/*
	 * We emulate what anychar_typmodin does here, avoiding the
	 * need to send queries to the server, typmod value need to
	 * add a 4-byte header length for character datatype.
	 */
	if (oid == ORACHARCHAROID ||
		oid == ORACHARBYTEOID ||
		oid == ORAVARCHARCHAROID ||
		oid == ORAVARCHARBYTEOID)
		typmod = typmod + 4;

	vartype = pg_malloc0(sizeof(BindVarType));
	vartype->name = pg_strdup(typname);
	vartype->oid = oid;
	vartype->typmod = typmod;

	return vartype;
}


/*
 * Get the value of the specified GUC.
 */
static char *
get_guc_settings(const char *gucname)
{
	PQExpBuffer query = createPQExpBuffer();
	PGresult	*res;
	char		*val = NULL;

	appendPQExpBuffer(query, "SELECT setting from pg_settings where name = '%s';", gucname);
	res = PQexec(pset.db, query->data);

	if (PQresultStatus(res) == PGRES_TUPLES_OK &&
		PQntuples(res) == 1 &&
		!PQgetisnull(res, 0, 0))
	{		
		val = pg_strdup(PQgetvalue(res, 0, 0));
	}

	PQclear(res);
	destroyPQExpBuffer(query);

	return val;
}

static print_item *
make_print_item(char *name, bool valid)
{
	print_item *item = pg_malloc0(sizeof(print_item));

	item->bv_name = name;
	item->valid = valid;

	return item;
}

static print_list *
make_print_list1(print_item *item)
{
	print_list	*pl = pg_malloc0(sizeof(print_list));
	pl->items = (print_item **) pg_malloc0(sizeof(print_item *) * 1);
	pl->items[0] = item;
	pl->length = 1;

	return pl;
}

static print_list *
merge_print_list(print_list *list1, print_list *list2)
{
	int	newlen;
	int i;

	if (list1 == NULL)
		return list2;
	if (list2 == NULL)
		return list1;

	newlen = list1->length + list2->length;
	list1->items = (print_item **) pg_realloc(list1->items, sizeof(print_item *) * newlen);

	for (i = 0; i < list2->length; i++)
	{
		list1->items[list1->length] = list2->items[i];
		list1->length++;
	}

	return list1;
}

int
psqlplus_yylex(YYSTYPE *lvalp, yyscan_t yyscanner)
{
	return orapsql_yylex(&(lvalp->psql_yysype), yyscanner);
}

void
psqlplus_yyerror(yyscan_t yyscanner, const char *message)
{
	/* do nothing */
}

/* yylex and the yylval macro, which flex will have its own definition */
#undef yylval
#undef yylex

