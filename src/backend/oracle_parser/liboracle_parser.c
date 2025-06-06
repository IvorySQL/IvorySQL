/*-------------------------------------------------------------------------
 *
 * liboracle_parser.c
 *		Main entry point/driver for Oracle grammar
 *
 * Note that the grammar is not allowed to perform any table access
 * (since we need to be able to do basic parsing even while inside an
 * aborted transaction).  Therefore, the data structures returned by
 * the grammar are "raw" parsetrees that still need to be analyzed by
 * analyze.c and related files.
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/backend/oracle_parser/liboracle_parser.c
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"

#include "catalog/pg_type.h"
#include "oracle_parser/ora_keywords.h"
#include "mb/pg_wchar.h"
#include "funcapi.h"
#include "oracle_parser/ora_scanner.h"
#include "ora_gramparse.h"
#include "parser/parser.h"
#include "utils/builtins.h"
#include "oracle_parser/ora_parser_hook.h"
#include "parser/parser.h"
#include "parser/scansup.h"
#include "utils/ora_compatible.h"

PG_MODULE_MAGIC;

/*
 * Struct for tracking locations/lengths of constants during normalization
 */
typedef struct pgssLocationLen
{
	int			location;		/* start offset in query text */
	int			length;			/* length in bytes, or -1 to ignore */
} pgssLocationLen;

/*
 * Working state for computing a query jumble and producing a normalized
 * query string
 */
typedef struct JumbleState
{
	/* Jumble of current query tree */
	unsigned char *jumble;

	/* Number of bytes used in jumble[] */
	Size		jumble_len;

	/* Array of locations of constants that should be removed */
	pgssLocationLen *clocations;

	/* Allocated length of clocations array */
	int			clocations_buf_size;

	/* Current number of valid entries in clocations array */
	int			clocations_count;

	/* highest Param id we've seen, in order to start normalization correctly */
	int			highest_extern_param_id;
} JumbleState;

/* saved hook value */
static raw_parser_hook_type prev_raw_parser = NULL;
static get_keywords_hook_type prev_pg_get_keywords = NULL;
static fill_in_constant_lengths_hook_type prev_fill_in_contant_lengths = NULL;
quote_identifier_hook_type prev_quote_identifier = NULL;

void _PG_init(void);
void _PG_fini(void);

static int	oracle_comp_location(const void *a, const void *b);

static List * oracle_raw_parser(const char *str, RawParseMode mode);
static Datum oracle_pg_get_keywords(PG_FUNCTION_ARGS);
static void oracle_fill_in_constant_lengths(void *jjstate, const char *query, int query_loc);
static const char * oracle_quote_identifier(const char *ident);

/*
 * Module load callback
 */
void
_PG_init(void)
{
	prev_raw_parser 			  = ora_raw_parser;
	prev_pg_get_keywords 		  = get_keywords_hook;
	prev_fill_in_contant_lengths  = fill_in_constant_lengths_hook;
	prev_quote_identifier 		  = quote_identifier_hook;

	ora_raw_parser 			  	  = oracle_raw_parser;
	get_keywords_hook 			  = oracle_pg_get_keywords;
	fill_in_constant_lengths_hook = oracle_fill_in_constant_lengths;
	quote_identifier_hook		  = oracle_quote_identifier;
}

/*
 * Module unload callback
 */
void
_PG_fini(void)
{
	ora_raw_parser 			  = prev_raw_parser;
	get_keywords_hook 			  = prev_pg_get_keywords;
	fill_in_constant_lengths_hook = prev_fill_in_contant_lengths;
	quote_identifier_hook		  = prev_quote_identifier;
}

/*
 * comp_location: comparator for qsorting pgssLocationLen structs by location
 */
static int
oracle_comp_location(const void *a, const void *b)
{
	int			l = ((const pgssLocationLen *) a)->location;
	int			r = ((const pgssLocationLen *) b)->location;

	if (l < r)
		return -1;
	else if (l > r)
		return +1;
	else
		return 0;
}

static bool check_uescapechar(unsigned char escape);
static char *str_udeescape(const char *str, char escape,
						   int position, ora_core_yyscan_t yyscanner);


/*
 * oracle_raw_parser
 *		Given a query in string form, do lexical and grammatical analysis.
 *
 * Returns a list of raw (un-analyzed) parse trees.  The contents of the
 * list have the form required by the specified RawParseMode.
 */

static List *
oracle_raw_parser(const char *str, RawParseMode mode)
{
	ora_core_yyscan_t yyscanner;
	ora_base_yy_extra_type yyextra;
	int			yyresult;

	/* initialize the flex scanner */
	yyscanner = ora_scanner_init(str, &yyextra.core_yy_extra,
							 &OraScanKeywords, OraScanKeywordTokens);

	yyextra.max_pushbacks = MAX_PUSHBACKS;
	yyextra.pushback_token = palloc(sizeof(int)* MAX_PUSHBACKS);
	yyextra.pushback_auxdata = palloc(sizeof(TokenAuxData)* MAX_PUSHBACKS);
	yyextra.num_pushbacks = 0;
	yyextra.loc_pushback = 0;
	yyextra.lookahead_end = NULL;

	set_oracle_plsql_body(yyscanner, OraBody_UNKOWN);


	/* base_yylex() only needs us to initialize the lookahead token, if any */
	if (mode != RAW_PARSE_DEFAULT)
	{
		/* this array is indexed by RawParseMode enum */
		static const int mode_token[] = {
			[RAW_PARSE_DEFAULT] = 0,
			[RAW_PARSE_TYPE_NAME] = MODE_TYPE_NAME,
			[RAW_PARSE_PLPGSQL_EXPR] = MODE_PLPGSQL_EXPR,
			[RAW_PARSE_PLPGSQL_ASSIGN1] = MODE_PLPGSQL_ASSIGN1,
			[RAW_PARSE_PLPGSQL_ASSIGN2] = MODE_PLPGSQL_ASSIGN2,
			[RAW_PARSE_PLPGSQL_ASSIGN3] = MODE_PLPGSQL_ASSIGN3,
		};

		TokenAuxData auxdata;

		auxdata.lval.core_yystype.str = " ";	/* token value doesn't matter, no one uses it */
		auxdata.lloc = 0;
		auxdata.leng = 1;
		yyextra.pushback_token[yyextra.num_pushbacks] = mode_token[mode];
		yyextra.pushback_auxdata[yyextra.num_pushbacks] = auxdata;
		yyextra.num_pushbacks++;
	}

	/* initialize the bison parser */
	ora_parser_init(&yyextra);

	/* Parse! */
	yyresult = ora_base_yyparse(yyscanner);

	/* Clean up (release memory) */
	ora_scanner_finish(yyscanner);

	pfree(yyextra.pushback_token);
	pfree(yyextra.pushback_auxdata);

	if (yyresult)				/* error */
		return NIL;

	return yyextra.parsetree;
}

/*
 * Push a token into cache arrays using the token number and TokenAuxData.
 */
static void
push_back_token(ora_core_yyscan_t yyscanner,  int token, TokenAuxData *auxdata)
{
	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);

	/* ensure enough space */
	if (yyextra->num_pushbacks >= yyextra->max_pushbacks)
	{
		yyextra->max_pushbacks = yyextra->max_pushbacks * 2;
		yyextra->pushback_token = repalloc(yyextra->pushback_token, sizeof(int) * yyextra->max_pushbacks);
		yyextra->pushback_auxdata = repalloc(yyextra->pushback_auxdata, sizeof(TokenAuxData)* yyextra->max_pushbacks);

	}

	yyextra->pushback_token[yyextra->num_pushbacks] = token;
	yyextra->pushback_auxdata[yyextra->num_pushbacks] = *auxdata;
	yyextra->num_pushbacks++;
}

/*
 * Push a token into cache arrays using yylval, yylloc and token number.
 */
static void
ora_push_back_token(ora_core_yyscan_t yyscanner, int token, ora_core_YYSTYPE lval, YYLTYPE lloc, int length)
{
	TokenAuxData auxdata;

	auxdata.lval.core_yystype = lval;
	auxdata.lloc = lloc;
	auxdata.leng = length;
	push_back_token(yyscanner, token, &auxdata);
}

static void
forward_token(ora_core_yyscan_t yyscanner, int token, TokenAuxData *auxdata)
{
	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);

	if (yyextra->loc_pushback >= yyextra->num_pushbacks)
	{
		push_back_token(yyscanner, token, auxdata);
	}
	else
	{
		Assert(yyextra->loc_pushback > 0);

		yyextra->pushback_token[yyextra->loc_pushback-1] = token;
		yyextra->pushback_auxdata[yyextra->loc_pushback-1] = *auxdata;
		yyextra->loc_pushback--;
	}
}

/* Get next token using ora_core_yylex() */
static int
ora_internal_yylex(ora_core_yyscan_t yyscanner, YYLTYPE *llocp, TokenAuxData *auxdata)
{

	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);
	int			token;
	const char *yytext;

	token = ora_core_yylex(&auxdata->lval.core_yystype,
		llocp,
		yyscanner);
	auxdata->lloc = *llocp;

	/* remember the length of yytext before it gets changed */
	yytext = yyextra->core_yy_extra.scanbuf + auxdata->lloc;
	auxdata->leng = strlen(yytext);

	return token;
}

/*
 * Get next token directly from the cache when cache array
 * in yyextra is available, otherwise call ora_core_yylex()
 * to get the next token.
 */
static int
internal_yylex(ora_core_yyscan_t yyscanner, YYLTYPE *llocp, TokenAuxData *auxdata)
{
	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);
	int token;

	/* get token from cache arrays */
	if (yyextra->loc_pushback < yyextra->num_pushbacks)
	{
		token = yyextra->pushback_token[yyextra->loc_pushback];
		*auxdata = yyextra->pushback_auxdata[yyextra->loc_pushback];
		yyextra->loc_pushback++;
		*llocp = auxdata->lloc;

		/* If this is the last token in the cache array, reset it */
		if (yyextra->loc_pushback >= yyextra->num_pushbacks)
		{
			yyextra->loc_pushback = 0;
			yyextra->num_pushbacks = 0;
		}
	}
	else
	{
		token = ora_internal_yylex(yyscanner, llocp, auxdata);
	}

	return token;
}

static bool
token_is_col_id(int token)
{
	int	i = 0;

	if (token == IDENT)
		return true;

	/* Get the subscript of token in the keyword array */
	for (i = 0; i < OraScanKeywords.num_keywords; i++)
	{
		if (OraScanKeywordTokens[i] == token)
			break;
	}

	if (OraScanKeywordCategories[i]== UNRESERVED_KEYWORD ||
		OraScanKeywordCategories[i]== COL_NAME_KEYWORD)
		return true;
	return false;
}


/*
 * Intermediate filter between parser and core lexer (core_yylex in scan.l).
 *
 * This filter is needed because in some cases the standard SQL grammar
 * requires more than one token lookahead.  We reduce these cases to one-token
 * lookahead by replacing tokens here, in order to keep the grammar LALR(1).
 *
 * Using a filter is simpler than trying to recognize multiword tokens
 * directly in scan.l, because we'd have to allow for comments between the
 * words.  Furthermore it's not clear how to do that without re-introducing
 * scanner backtrack, which would cost more performance than this filter
 * layer does.
 *
 * We also use this filter to convert UIDENT and USCONST sequences into
 * plain IDENT and SCONST tokens.  While that could be handled by additional
 * productions in the main grammar, it's more efficient to do it like this.
 *
 * The filter also provides a convenient place to translate between
 * the core_YYSTYPE and YYSTYPE representations (which are really the
 * same thing anyway, but notationally they're different).
 */
int
ora_base_yylex(YYSTYPE *lvalp, YYLTYPE *llocp, ora_core_yyscan_t yyscanner)
{
	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);
	int			cur_token;
	int			next_token;
	int			cur_token_length;
	YYLTYPE		cur_yylloc;

	TokenAuxData aux1;

	/* Get next token --- we might already have it */
	cur_token = internal_yylex(yyscanner, llocp, &aux1);

	lvalp->core_yystype = aux1.lval.core_yystype;

	if (yyextra->lookahead_end)
	{
		*(yyextra->lookahead_end) = yyextra->lookahead_hold_char;
		yyextra->lookahead_end = NULL;
	}

	if (yyextra->body_style == OraBody_MAYBE_ANONYMOUS_BLOCK_BEGIN)
	{
		/* If it is the beginning of BEGIN, maybe it is a Transaction or routine_body of function */
		if (cur_token != WORK &&
			cur_token != TRANSACTION &&
			cur_token != ATOMIC &&
			cur_token != ';' &&
			cur_token != ISOLATION &&
			cur_token != READ &&
			cur_token != DEFERRABLE &&
			cur_token != NOT &&
			cur_token != 0)
		{
			yyextra->body_style = OraBody_ANONYMOUS_BLOCK;
		}
	}

	else if (yyextra->body_style == OraBody_MAYBE_ANONYMOUS_BLOCK_DECLARE)
	{
		/* If it is the beginning of DECLARE, maybe the transaction defines a cursor */
		int	token = cur_token;
		bool is_def_cursor_stmt = false;

		if (token_is_col_id(cur_token))
		{
			bool has_cursor = false;

			token = ora_internal_yylex(yyscanner, llocp, &aux1);
			push_back_token(yyscanner, token, &aux1);

			is_def_cursor_stmt = false;
			while (token != 0 && token != ';')
			{
				/*
				 * support anonymous block
				 * In the PLSQL, the cursor declare must be 'CURSOR ...',
				 * not '... CURSOR ...'.
				 *
				 * PLSQL support type xxx is ref cursor grammer
				 * so we check the last token is ref
				 * declare cursor don't support ref for the cursor name
				 *
				 * Inline function support cursor
				 * we judge it is the cursor of SQL, if it next token
				 * is WITH or FOR or WITHOUT. see details for ora_gram.y about
				 * declare cursor stmt
				 */
				if (token == CURSOR)
					has_cursor = true;

				token = ora_internal_yylex(yyscanner, llocp, &aux1);
				push_back_token(yyscanner, token, &aux1);

				if (has_cursor &&
					(token == WITH ||
					token == FOR ||
					token == WITHOUT))
				{
					is_def_cursor_stmt = true;
					break;
				}
				else if (has_cursor)
					break;
			}
		}

		if (!is_def_cursor_stmt)
		{
			yyextra->body_style = OraBody_ANONYMOUS_BLOCK;
		}
	}

	if ((yyextra->body_style == OraBody_FUNC && cur_token != SCONST) ||
		(yyextra->body_style == OraBody_ANONYMOUS_BLOCK))
	{
		int beginpos = yyextra->body_start;
		int blocklevel = yyextra->body_level;
		bool found_begin = false;
		bool found_foreign_begin = false;
		int subproc_define_level = 0;

		if (blocklevel > 0)
		{
			found_begin = true;
			found_foreign_begin = true;
		}

		while (cur_token != 0)
		{
			if (beginpos < 0)
				beginpos = *llocp;

			if (cur_token == FUNCTION || cur_token == PROCEDURE)
			{
				while (true)
				{
					cur_token = internal_yylex(yyscanner, llocp, &aux1);

					if (cur_token == IS || cur_token == AS)
					{
						subproc_define_level++;
						break;
					}
					if (cur_token == ';' || cur_token == 0)
						break;
				}
			}
			while (cur_token == BEGIN_P)
			{
				cur_token = internal_yylex(yyscanner, llocp, &aux1);
				if (cur_token != ';' && cur_token != '(')
				{
					blocklevel++;
					found_begin = true;
					if (subproc_define_level == 0)
						found_foreign_begin = true;
				}
			}

			if (found_begin)
			{
				if (cur_token == CASE)
				{
					blocklevel++;
				}
				else if (cur_token == END_P)
				{
					if (blocklevel > 0)
					{
						cur_token = internal_yylex(yyscanner, llocp, &aux1);
						if (cur_token == ';')
						{
							blocklevel--;
						}
						else if (cur_token == 0)
						{
							blocklevel--;
							break;
						}
						else if (cur_token != LOOP_P && cur_token != IF_P)
						{
							blocklevel--;
						}
				}

				if (blocklevel == 0)
				{
						if (found_foreign_begin && subproc_define_level == 0)
							break;
						else if (subproc_define_level > 0)
							subproc_define_level--;
					}
				}
			}

			cur_token = internal_yylex(yyscanner, llocp, &aux1);
		}

		if ((cur_token == ';' && blocklevel == 0 &&
			subproc_define_level == 0) ||
			(cur_token == 0 && blocklevel > 0))
		{
			aux1.lval.str = ";";
			ora_push_back_token(yyscanner, ';', aux1.lval.core_yystype, aux1.lloc, 1);

			/* Now revert the un-truncation of the current token */
			yyextra->lookahead_end = yyextra->core_yy_extra.scanbuf +
				aux1.lloc;
			yyextra->lookahead_hold_char = *(yyextra->lookahead_end);
			*(yyextra->lookahead_end) = '\0';
		}

		lvalp->core_yystype.str = pstrdup(yyextra->core_yy_extra.scanbuf + beginpos);
		*llocp = beginpos;
		cur_token = SCONST;
	}

	else if ((yyextra->body_style == OraBody_PACKAGE ||
		yyextra->body_style == OraBody_PACKAGEBODY) &&
			cur_token != SCONST)
	{
		int beginpos = yyextra->body_start;
		int blocklevel = yyextra->body_level;
		bool found_end = false;
		int sub_proc_level = 0;

		while (cur_token != 0)
		{
			if (beginpos < 0)
				beginpos = *llocp;

			if (yyextra->body_style == OraBody_PACKAGEBODY &&
				(cur_token == FUNCTION || cur_token == PROCEDURE))
			{
				while(true)
				{
					cur_token = internal_yylex(yyscanner, llocp, &aux1);

					if (cur_token == IS || cur_token == AS)
					{
						sub_proc_level++;
						break;
					}
					if (cur_token == ';' || cur_token == 0)
						break;
				}
			}

			while (cur_token == BEGIN_P)
			{
				cur_token = internal_yylex(yyscanner, llocp, &aux1);
				if (cur_token != ';' && cur_token != '(')
				{
					blocklevel++;
				}
			}

			if (cur_token == CASE)
			{
				blocklevel++;
			}
			else if (cur_token == END_P)
			{
				if (blocklevel > 0)
				{
					cur_token = internal_yylex(yyscanner, llocp, &aux1);
					if (cur_token == ';')
					{
						blocklevel--;
					}
					else if (cur_token == 0)
					{
						blocklevel--;
						break;
					}
					else if (cur_token != LOOP_P && cur_token != IF_P)
					{
						blocklevel--;
					}

					/*
					 * there, maybe package body has init block
					 */
					if (yyextra->body_style == OraBody_PACKAGEBODY &&
						blocklevel == 0)
					{
						if (sub_proc_level > 0)
							sub_proc_level--;
						else
							found_end = true;
					}
				}
				else
					found_end = true;
			}
			if (blocklevel == 0 && found_end && cur_token == ';')
			{
				break;
			}

			cur_token = internal_yylex(yyscanner, llocp, &aux1);
		}

		if ((cur_token == ';'  && blocklevel == 0) ||
			(cur_token == 0    && blocklevel > 0))
		{
			aux1.lval.str = ";";
			ora_push_back_token(yyscanner, ';', aux1.lval.core_yystype,
				aux1.lloc, 1);


			/* Now revert the un-truncation of the current token */
			yyextra->lookahead_end = yyextra->core_yy_extra.scanbuf +
				aux1.lloc;
			yyextra->lookahead_hold_char = *(yyextra->lookahead_end);
			*(yyextra->lookahead_end) = '\0';
		}

		lvalp->core_yystype.str = pstrdup(yyextra->core_yy_extra.scanbuf + beginpos);
		*llocp = beginpos;
		cur_token = SCONST;
	}

	set_oracle_plsql_body(yyscanner, OraBody_UNKOWN);

	/*
	 * If this token isn't one that requires lookahead, just return it.  If it
	 * does, determine the token length.  (We could get that via strlen(), but
	 * since we have such a small set of possibilities, hardwiring seems
	 * feasible and more efficient --- at least for the fixed-length cases.)
	 */
	switch (cur_token)
	{
		case FORMAT:
			cur_token_length = 6;
			break;
		case NOT:
			cur_token_length = 3;
			break;
		case NULLS_P:
			cur_token_length = 5;
			break;
		case WITH:
			cur_token_length = 4;
			break;
		case UIDENT:
		case USCONST:
			cur_token_length = strlen(yyextra->core_yy_extra.scanbuf + *llocp);
			break;
		case WITHOUT:
			cur_token_length = 7;
			break;
		case LONG_P:
			cur_token_length = 4;
			break;
		case PACKAGE:
			cur_token_length = 7;
			break;
		default:
			return cur_token;
	}

	/*
	 * Identify end+1 of current token.  core_yylex() has temporarily stored a
	 * '\0' here, and will undo that when we call it again.  We need to redo
	 * it to fully revert the lookahead call for error reporting purposes.
	 */
	yyextra->lookahead_end = yyextra->core_yy_extra.scanbuf +
		*llocp + cur_token_length;
	Assert(*(yyextra->lookahead_end) == '\0');

	/*
	 * Save and restore *llocp around the call.  It might look like we could
	 * avoid this by just passing &lookahead_yylloc to core_yylex(), but that
	 * does not work because flex actually holds onto the last-passed pointer
	 * internally, and will use that for error reporting.  We need any error
	 * reports to point to the current token, not the next one.
	 */
	cur_yylloc = aux1.lloc;

	/* Get next token, saving outputs into lookahead variables */
	next_token = internal_yylex(yyscanner, llocp, &aux1);
	forward_token(yyscanner, next_token, &aux1);

	*llocp = cur_yylloc;

	/* Now revert the un-truncation of the current token */
	yyextra->lookahead_hold_char = *(yyextra->lookahead_end);
	*(yyextra->lookahead_end) = '\0';

	yyextra->have_lookahead = true;

	/* Replace cur_token if needed, based on lookahead */
	switch (cur_token)
	{
		case FORMAT:
			/* Replace FORMAT by FORMAT_LA if it's followed by JSON */
			switch (next_token)
			{
				case JSON:
					cur_token = FORMAT_LA;
					break;
			}
			break;

		case NOT:
			/* Replace NOT by NOT_LA if it's followed by BETWEEN, IN, etc */
			switch (next_token)
			{
				case BETWEEN:
				case IN_P:
				case LIKE:
				case ILIKE:
				case SIMILAR:
					cur_token = NOT_LA;
					break;
			}
			break;

		case NULLS_P:
			/* Replace NULLS_P by NULLS_LA if it's followed by FIRST or LAST */
			switch (next_token)
			{
				case FIRST_P:
				case LAST_P:
					cur_token = NULLS_LA;
					break;
			}
			break;

		case PACKAGE:
			/* Replace PACKAGE by PACKAGE_BODY if it's followed by BODY */
			if (next_token == BODY)
				cur_token = PACKAGE_BODY;
			break;

		case WITH:
			/* Replace WITH by WITH_LA if it's followed by TIME or ORDINALITY */
			switch (next_token)
			{
				case TIME:
				case ORDINALITY:
					cur_token = WITH_LA;
					break;
				case LOCAL:	
					{
						/*
						 * Get third token, if it is TIME return WITH_LA
						 * otherwise return WITH.
						 */
						next_token = ora_internal_yylex(yyscanner, llocp, &aux1);
						push_back_token(yyscanner, next_token, &aux1);

						if (next_token == TIME)
							cur_token = WITH_LA;
					}
					break;
			}
			break;

		case WITHOUT:
			/* Replace WITHOUT by WITHOUT_LA if it's followed by TIME */
			switch (next_token)
			{
				case TIME:
					cur_token = WITHOUT_LA;
					break;
			}
			break;

		case LONG_P:
			switch (next_token)
				{
				case RAW_P:
					yyextra->loc_pushback++;	/* eat RAW_P token */
					cur_token = LONG_RAW;
					break;
				}
			break;

		case UIDENT:
		case USCONST:
			/* Look ahead for UESCAPE */
			if (next_token == UESCAPE)
			{
				/* Yup, so get third token, which had better be SCONST */
				const char *escstr;

				/* Un-truncate current token so errors point to third token */
				*(yyextra->lookahead_end) = yyextra->lookahead_hold_char;

				/* Get third token using ora_core_yylex() and don't push it into cache arrays */
				next_token = ora_internal_yylex(yyscanner, llocp, &aux1);

				/* If we throw error here, it will point to third token */
				if (next_token != SCONST)
					ora_scanner_yyerror("UESCAPE must be followed by a simple string literal",
									yyscanner);

				escstr = aux1.lval.str;
				if (strlen(escstr) != 1 || !check_uescapechar(escstr[0]))
					ora_scanner_yyerror("invalid Unicode escape character",
									yyscanner);

				/* Apply Unicode conversion */
				lvalp->core_yystype.str =
					str_udeescape(lvalp->core_yystype.str,
								  escstr[0],
								  *llocp,
								  yyscanner);

				/*
				 * We don't need to revert the un-truncation of UESCAPE.  What
				 * we do want to do is  eat one-token within cache array, thereby
				 * consuming all three tokens.
				 */
				yyextra->loc_pushback++;
			}
			else
			{
				/* No UESCAPE, so convert using default escape character */
				lvalp->core_yystype.str =
					str_udeescape(lvalp->core_yystype.str,
								  '\\',
								  *llocp,
								  yyscanner);
			}

			if (cur_token == UIDENT)
			{
				/* It's an identifier, so truncate as appropriate */
				truncate_identifier(lvalp->core_yystype.str,
									strlen(lvalp->core_yystype.str),
									true);
				cur_token = IDENT;
			}
			else if (cur_token == USCONST)
			{
				cur_token = SCONST;
			}
			break;
	}

	return cur_token;
}

/*
 * Sets the current syntax type.
 */
void set_oracle_plsql_body(ora_core_yyscan_t yyscanner, OraBodyStyle body_style)
{

	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);
	yyextra->body_style = body_style;

	set_oracle_plsql_bodystart(yyscanner, -1, 0);
}

/*
 * Sets the current syntax position.
 */
void set_oracle_plsql_bodystart(ora_core_yyscan_t yyscanner, int body_start, int body_level)
{

	ora_base_yy_extra_type *yyextra = pg_yyget_extra(yyscanner);
	yyextra->body_start = body_start;
	yyextra->body_level = body_level;
}

/* convert hex digit (caller should have verified that) to value */
static unsigned int
hexval(unsigned char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 0xA;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 0xA;
	elog(ERROR, "invalid hexadecimal digit");
	return 0;					/* not reached */
}

/* is Unicode code point acceptable? */
static void
check_unicode_value(pg_wchar c)
{
	if (!is_valid_unicode_codepoint(c))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("invalid Unicode escape value")));
}

/* is 'escape' acceptable as Unicode escape character (UESCAPE syntax) ? */
static bool
check_uescapechar(unsigned char escape)
{
	if (isxdigit(escape)
		|| escape == '+'
		|| escape == '\''
		|| escape == '"'
		|| scanner_isspace(escape))
		return false;
	else
		return true;
}

/*
 * Process Unicode escapes in "str", producing a palloc'd plain string
 *
 * escape: the escape character to use
 * position: start position of U&'' or U&"" string token
 * yyscanner: context information needed for error reports
 */
static char *
str_udeescape(const char *str, char escape,
			  int position, ora_core_yyscan_t yyscanner)
{
	const char *in;
	char	   *new,
			   *out;
	size_t		new_len;
	pg_wchar	pair_first = 0;
	OraScannerCallbackState scbstate;

	/*
	 * Guesstimate that result will be no longer than input, but allow enough
	 * padding for Unicode conversion.
	 */
	new_len = strlen(str) + MAX_UNICODE_EQUIVALENT_STRING + 1;
	new = palloc(new_len);

	in = str;
	out = new;
	while (*in)
	{
		/* Enlarge string if needed */
		size_t		out_dist = out - new;

		if (out_dist > new_len - (MAX_UNICODE_EQUIVALENT_STRING + 1))
		{
			new_len *= 2;
			new = repalloc(new, new_len);
			out = new + out_dist;
		}

		if (in[0] == escape)
		{
			/*
			 * Any errors reported while processing this escape sequence will
			 * have an error cursor pointing at the escape.
			 */
			ora_setup_scanner_errposition_callback(&scbstate, yyscanner,
											   in - str + position + 3);	/* 3 for U&" */
			if (in[1] == escape)
			{
				if (pair_first)
					goto invalid_pair;
				*out++ = escape;
				in += 2;
			}
			else if (isxdigit((unsigned char) in[1]) &&
					 isxdigit((unsigned char) in[2]) &&
					 isxdigit((unsigned char) in[3]) &&
					 isxdigit((unsigned char) in[4]))
			{
				pg_wchar	unicode;

				unicode = (hexval(in[1]) << 12) +
					(hexval(in[2]) << 8) +
					(hexval(in[3]) << 4) +
					hexval(in[4]);
				check_unicode_value(unicode);
				if (pair_first)
				{
					if (is_utf16_surrogate_second(unicode))
					{
						unicode = surrogate_pair_to_codepoint(pair_first, unicode);
						pair_first = 0;
					}
					else
						goto invalid_pair;
				}
				else if (is_utf16_surrogate_second(unicode))
					goto invalid_pair;

				if (is_utf16_surrogate_first(unicode))
					pair_first = unicode;
				else
				{
					pg_unicode_to_server(unicode, (unsigned char *) out);
					out += strlen(out);
				}
				in += 5;
			}
			else if (in[1] == '+' &&
					 isxdigit((unsigned char) in[2]) &&
					 isxdigit((unsigned char) in[3]) &&
					 isxdigit((unsigned char) in[4]) &&
					 isxdigit((unsigned char) in[5]) &&
					 isxdigit((unsigned char) in[6]) &&
					 isxdigit((unsigned char) in[7]))
			{
				pg_wchar	unicode;

				unicode = (hexval(in[2]) << 20) +
					(hexval(in[3]) << 16) +
					(hexval(in[4]) << 12) +
					(hexval(in[5]) << 8) +
					(hexval(in[6]) << 4) +
					hexval(in[7]);
				check_unicode_value(unicode);
				if (pair_first)
				{
					if (is_utf16_surrogate_second(unicode))
					{
						unicode = surrogate_pair_to_codepoint(pair_first, unicode);
						pair_first = 0;
					}
					else
						goto invalid_pair;
				}
				else if (is_utf16_surrogate_second(unicode))
					goto invalid_pair;

				if (is_utf16_surrogate_first(unicode))
					pair_first = unicode;
				else
				{
					pg_unicode_to_server(unicode, (unsigned char *) out);
					out += strlen(out);
				}
				in += 8;
			}
			else
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("invalid Unicode escape"),
						 errhint("Unicode escapes must be \\XXXX or \\+XXXXXX.")));

			ora_cancel_scanner_errposition_callback(&scbstate);
		}
		else
		{
			if (pair_first)
				goto invalid_pair;

			*out++ = *in++;
		}
	}

	/* unfinished surrogate pair? */
	if (pair_first)
		goto invalid_pair;

	*out = '\0';
	return new;

	/*
	 * We might get here with the error callback active, or not.  Call
	 * scanner_errposition to make sure an error cursor appears; if the
	 * callback is active, this is duplicative but harmless.
	 */
invalid_pair:
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg("invalid Unicode surrogate pair"),
			 ora_scanner_errposition(in - str + position + 3,	/* 3 for U&" */
								 yyscanner)));
	return NULL;				/* keep compiler quiet */
}

static Datum
oracle_pg_get_keywords(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		TupleDesc	tupdesc;

		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		tupdesc = CreateTemplateTupleDesc(3);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "word",
						   TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "catcode",
						   CHAROID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 3, "catdesc",
						   TEXTOID, -1, 0);

		funcctx->attinmeta = TupleDescGetAttInMetadata(tupdesc);

		MemoryContextSwitchTo(oldcontext);
	}

	funcctx = SRF_PERCALL_SETUP();

	if (funcctx->call_cntr < OraScanKeywords.num_keywords)
	{
		char	   *values[3];
		HeapTuple	tuple;

		/* cast-away-const is ugly but alternatives aren't much better */
		values[0] = unconstify(char *,
							   GetScanKeyword(funcctx->call_cntr,
											  &OraScanKeywords));

		switch (OraScanKeywordCategories[funcctx->call_cntr])
		{
			case UNRESERVED_KEYWORD:
				values[1] = "U";
				values[2] = _("unreserved");
				break;
			case COL_NAME_KEYWORD:
				values[1] = "C";
				values[2] = _("unreserved (cannot be function or type name)");
				break;
			case TYPE_FUNC_NAME_KEYWORD:
				values[1] = "T";
				values[2] = _("reserved (can be function or type name)");
				break;
			case RESERVED_KEYWORD:
				values[1] = "R";
				values[2] = _("reserved");
				break;
			default:			/* shouldn't be possible */
				values[1] = NULL;
				values[2] = NULL;
				break;
		}

		tuple = BuildTupleFromCStrings(funcctx->attinmeta, values);

		SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuple));
	}

	SRF_RETURN_DONE(funcctx);
}

static void
oracle_fill_in_constant_lengths(void *jjstate, const char *query,
						 int query_loc)
{
	JumbleState	*jstate;
	pgssLocationLen *locs;
	ora_core_yyscan_t yyscanner;
	ora_core_yy_extra_type yyextra;
	ora_core_YYSTYPE yylval;
	YYLTYPE		yylloc;
	int			last_loc = -1;
	int			i;

	/*
	 * Sort the records by location so that we can process them in order while
	 * scanning the query text.
	 */
	jstate = (JumbleState *)jjstate;
	if (jstate->clocations_count > 1)
		qsort(jstate->clocations, jstate->clocations_count,
			  sizeof(pgssLocationLen), oracle_comp_location);
	locs = jstate->clocations;

	/* initialize the flex scanner --- should match oracle_raw_parser() */
	yyscanner = ora_scanner_init(query,
							 &yyextra,
							 &OraScanKeywords,
							 OraScanKeywordTokens);

	/* we don't want to re-emit any escape string warnings */
	yyextra.escape_string_warning = false;

	/* Search for each constant, in sequence */
	for (i = 0; i < jstate->clocations_count; i++)
	{
		int			loc = locs[i].location;
		int			tok;

		/* Adjust recorded location if we're dealing with partial string */
		loc -= query_loc;

		Assert(loc >= 0);

		if (loc <= last_loc)
			continue;			/* Duplicate constant, ignore */

		/* Lex tokens until we find the desired constant */
		for (;;)
		{
			tok = ora_core_yylex(&yylval, &yylloc, yyscanner);

			/* We should not hit end-of-string, but if we do, behave sanely */
			if (tok == 0)
				break;			/* out of inner for-loop */

			/*
			 * We should find the token position exactly, but if we somehow
			 * run past it, work with that.
			 */
			if (yylloc >= loc)
			{
				if (query[loc] == '-')
				{
					/*
					 * It's a negative value - this is the one and only case
					 * where we replace more than a single token.
					 *
					 * Do not compensate for the core system's special-case
					 * adjustment of location to that of the leading '-'
					 * operator in the event of a negative constant.  It is
					 * also useful for our purposes to start from the minus
					 * symbol.  In this way, queries like "select * from foo
					 * where bar = 1" and "select * from foo where bar = -2"
					 * will have identical normalized query strings.
					 */
					tok = ora_core_yylex(&yylval, &yylloc, yyscanner);
					if (tok == 0)
						break;	/* out of inner for-loop */
				}

				/*
				 * We now rely on the assumption that flex has placed a zero
				 * byte after the text of the current token in scanbuf.
				 */
				locs[i].length = strlen(yyextra.scanbuf + loc);
				break;			/* out of inner for-loop */
			}
		}

		/* If we hit end-of-string, give up, leaving remaining lengths -1 */
		if (tok == 0)
			break;

		last_loc = loc;
	}

	ora_scanner_finish(yyscanner);
}

static const char *
oracle_quote_identifier(const char *ident)
{
	/*
	 * Can avoid quoting if ident starts with a lowercase letter or underscore
	 * and contains only lowercase letters, digits, and underscores, *and* is
	 * not any SQL keyword.  Otherwise, supply quotes.
	 */
	int			nquotes = 0;
	bool		safe;
	const char *ptr;
	char	   *result;
	char	   *optr;

	/*
	 * would like to use <ctype.h> macros here, but they might yield unwanted
	 * locale-specific results...
	 */
	safe = ((ident[0] >= 'a' && ident[0] <= 'z') || ident[0] == '_');

	for (ptr = ident; *ptr; ptr++)
	{
		char		ch = *ptr;

		if ((ch >= 'a' && ch <= 'z') ||
			(ch >= '0' && ch <= '9') ||
			(ch == '_'))
		{
			/* okay */
		}
		else
		{
			safe = false;
			if (ch == '"')
				nquotes++;
		}
	}

	if (quote_all_identifiers)
		safe = false;

	if (safe)
	{
		/*
		 * Check for keyword.  We quote keywords except for unreserved ones.
		 * (In some cases we could avoid quoting a col_name or type_func_name
		 * keyword, but it seems much harder than it's worth to tell that.)
		 *
		 * Note: ScanKeywordLookup() does case-insensitive comparison, but
		 * that's fine, since we already know we have all-lower-case.
		 */
		int			kwnum = ScanKeywordLookup(ident, &OraScanKeywords);

		if (kwnum >= 0 && OraScanKeywordCategories[kwnum] != UNRESERVED_KEYWORD)
			safe = false;
	}

	if (safe)
		return ident;			/* no change needed */

	result = (char *) palloc(strlen(ident) + nquotes + 2 + 1);

	optr = result;
	*optr++ = '"';
	for (ptr = ident; *ptr; ptr++)
	{
		char		ch = *ptr;

		if (ch == '"')
			*optr++ = '"';
		*optr++ = ch;
	}
	*optr++ = '"';
	*optr = '\0';

	return result;
}
