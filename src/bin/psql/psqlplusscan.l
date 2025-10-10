%{
/*-------------------------------------------------------------------------
 *
 * File: psqlplusscan.l
 *
 * Abstract: 
 * 		lexical scanner for oracle-compatible client commands.
 *
 * Authored by zhenmingyang@highgo.com, 20221221.
 *
 * Copyright (c) 2022-2025, IvorySQL Global Development Team
 *
 * Identification:
 *		src/bin/psql/psqlplusscan.l
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"
#include "common/string.h"
#include "fe_utils/psqlscan_int.h"
#include "libpq-fe.h"
#include "psqlplus.h"
#include "psqlplusparse.h"

/* LCOV_EXCL_START */

/*
 * Lists of keyword (name, token-value, category) entries.
 *
 * !!WARNING!!: These must be sorted by ASCII name, because binary
 *		 search is used to locate entries.
 */
static const PsqlScanKeyword psqlplus_keywords[] = {
	PSQL_KEYWORD("binary_double", K_BINARY_DOUBLE, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("binary_float", K_BINARY_FLOAT, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("byte", K_BYTE, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("char", K_CHAR, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("exec", K_EXEC, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("execute", K_EXECUTE, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("nchar", K_NCHAR, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("number", K_NUMBER, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("nvarchar2", K_NVARCHAR2, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("print", K_PRINT, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("var", K_VAR, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("varchar2", K_VARCHAR2, UNRESERVED_PSQL_KEYWORD)
	PSQL_KEYWORD("variable", K_VARIABLE, UNRESERVED_PSQL_KEYWORD)
};

const int	NumKeywords = lengthof(psqlplus_keywords);

/*
 * Set the type of YYSTYPE.
 */
#define YYSTYPE psql_YYSTYPE

static const PsqlScanKeyword *PsqlplusKeywordLookup(const char *text);
static int process_integer_literal(const char *token, YYSTYPE *lval);
static char *psqlplus_downcase_identifier(const char *str, int len);
static void startlit(yyscan_t yyscanner);
static void addlitchar(unsigned char ychar, yyscan_t yyscanner);
static void addlit(char *ytext, int yleng, yyscan_t yyscanner);
static char *litbufdup(char *prefix, yyscan_t yyscanner);

%}

%option reentrant
%option bison-bridge
%option 8bit
%option never-interactive
%option nodefault
%option noinput
%option nounput
%option noyywrap
%option warn
%option prefix="orapsql_yy"

/*
 * Exclusive states:
 *  <xc> Oracle C-style comments
 *	<xq> standard quoted strings
 *	<xd> double-quoted strings
 *	<xl> literal string
 */

%x xc
%x xq
%x xd
%x xl

/*
 * Ignore spaces and C-style comments before client commands.
 */
space			[ \t\n\r\f]

/* Extended quote
 * xqdouble implements embedded quote, ''''
 */
quote			'
xqstart			{quote}
xqdouble		{quote}{quote}
xqinside		[^']+

/* Double quote
 * xddouble implements embedded quote, """".
 */
dquote			\"
xdstart			{dquote}
xddouble		{dquote}{dquote}
xdinside		[^"]+

/*
 * Oracle C-style comments
 */
xcstart			\/\*{op_chars}*
xcstop			\*+\/
xcinside		[^*/]+

/*
 * Oracle variable name begins with a letter and can include letters,
 * digits, and these symbols:
 *	Dollar sign ($)
 *	Number sign (#)
 *	Underscore (_)
 */
digit			[0-9]
ident_start		[A-Za-z\200-\377]
ident_cont		[A-Za-z\200-\377_0-9\#\$]

identifier		{ident_start}{ident_cont}*

typecast		"::"

/*
 * This flex rule is not used in the syntax of bison,
 * we just use it to detect whether a bind variable is
 * referenced in a SQL text.
 */
bindvarref		:{identifier}

/*
 * "self" is the set of chars that should be returned
 * as single-character tokens.
 */
self			[,()\[\].;\:\+\-\*\/\%\^\<\>\=]
op_chars		[\~\!\@\#\^\&\|\`\?\+\-\*\/\%\<\>\=]

integer			{digit}+
decimal			(({digit}*\.{digit}+)|({digit}+\.{digit}*))
decimalfail		{digit}+\.\.
real			({integer}|{decimal})[Ee][-+]?{digit}+
realfail1		({integer}|{decimal})[Ee]
realfail2		({integer}|{decimal})[Ee][-+]

/* Lteral String
 * literal string is space-separated text string,
 * when none of the above rules match, we choose
 * to treat it as a literal string and return the
 * token LITERAL.
 */
other			.
xlstart			{other}
xlinside		[^ ]+

%%

%{
		/* Declare some local variables inside yylex(), for convenience */
		PsqlScanState cur_state = yyextra;

		/*
		 * Force flex into the state indicated by start_state.  This has a
		 * couple of purposes: it lets some of the functions below set a new
		 * starting state without ugly direct access to flex variables, and it
		 * allows us to transition from one flex lexer to another so that we
		 * can lex different parts of the source string using separate lexers.
		 */
		BEGIN(cur_state->start_state);
%}

	/* INITIAL state */

{space}			{
					/* ignore */
				}

{xcstart}		{
					BEGIN(xc);
					/* Put back any characters past slash-star */
					yyless(2);
				}

	/* xc state */

<xc>{
{xcstart}		{
					/* Put back any characters past slash-star */
					yyless(2);
				}

{xcstop}		{
					BEGIN(INITIAL);
				}

{xcinside}		{
					/* ignore */
				}

{op_chars}		{
					/* ignore */
				}

\*+				{
					/* ignore */
				}

<<EOF>>			{
					return 0;
				}
} /* <xc> */

{xqstart}		{
					BEGIN(xq);
					startlit(yyscanner);
				}

<xq>{xqdouble}	{
					addlitchar('\'', yyscanner);
				}
<xq>{xqinside}	{
					addlit(yytext, yyleng, yyscanner);
				}

<xq>{quote}		{
					BEGIN(INITIAL);
					yylval->str = litbufdup(NULL, yyscanner);
					cur_state->token_count++;
					return SQCONST;
				}

<xq><<EOF>>		{
					/*
					 * However, the expectation of this parser is that
					 * no errors are produced and the parser runs quietly.
					 */
					BEGIN(INITIAL);
					yylval->str = litbufdup("'", yyscanner);
					cur_state->token_count++;
					return SINGLE_QUOTE_NO_END;
				}

{xdstart}		{
					BEGIN(xd);
					startlit(yyscanner);
				}

<xd>{xddouble}	{
					addlitchar('"', yyscanner);
				}
<xd>{xdinside}	{
					addlit(yytext, yyleng, yyscanner);
				}

<xd>{dquote}	{
					BEGIN(INITIAL);
					yylval->str = litbufdup(NULL, yyscanner);
					cur_state->token_count++;
					return DQCONST;
				}

<xd><<EOF>>		{
					BEGIN(INITIAL);
					yylval->str = litbufdup("\"", yyscanner);
					cur_state->token_count++;
					return DOUBLE_QUOTE_NO_END;
				}

{typecast}		{
					cur_state->token_count++;
					return TYPECAST;
				}

{self}			{
					cur_state->token_count++;
					return yytext[0];
				}

{bindvarref}	{
					/*
					 * BINDVARREF is not a token number defined by bison,
					 * it is just a simple macro within psqlplus.h.
					 */
					yylval->str = pg_strdup(yytext);
					cur_state->token_count++;
					return BINDVARREF;
				}

{integer}		{
					cur_state->token_count++;
					return process_integer_literal(yytext, yylval);
				}
{decimal}		{
					cur_state->token_count++;
					yylval->str = pg_strdup(yytext);
					return FCONST;
				}
{decimalfail}	{
					/* throw back the .., and treat as integer */
					yyless(yyleng - 2);
					cur_state->token_count++;
					return process_integer_literal(yytext, yylval);
				}
{real}			{
					yylval->str = pg_strdup(yytext);
					cur_state->token_count++;
					return FCONST;
				}
{realfail1}		{
					/*
					 * throw back the [Ee], and figure out whether what
					 * remains is an {integer} or {decimal}.
					 */
					yyless(yyleng - 1);
					cur_state->token_count++;
					return process_integer_literal(yytext, yylval);
				}
{realfail2}		{
					/* throw back the [Ee][+-], and proceed as above */
					yyless(yyleng - 2);
					cur_state->token_count++;
					return process_integer_literal(yytext, yylval);
				}

{identifier}	{
					const PsqlScanKeyword *keyword;
					char	   *ident;

					keyword = PsqlplusKeywordLookup(yytext);

					if (keyword != NULL)
					{
						/*
						 * If it is a psqlplus command and no grammatical rule matches
						 * successfully in psqlplusparse.y, the parser will not try to
						 * continue processing according to the native PG psql parsing
						 * after returning, this command should not be sent to gram.y.
						 */
						if (cur_state->token_count == 0 &&
							(strcmp(keyword->name, "variable") == 0 ||
							 strcmp(keyword->name, "var") == 0 ||
							 strcmp(keyword->name, "print") == 0 ||
							 strcmp(keyword->name, "execute") == 0 ||
							 strcmp(keyword->name, "exec") == 0))
							cur_state->is_sqlplus_cmd = true;

						yylval->keyword = keyword->name;
						cur_state->token_count++;
						return keyword->value;
					}

					ident = psqlplus_downcase_identifier(yytext, yyleng);
					yylval->str = ident;
					cur_state->token_count++;
					return IDENT;
				}

	/* <xl> must be last of all regex rules except EOF */
{xlstart}		{
					BEGIN(xl);
					startlit(yyscanner);
				}

<xl>{xlinside}	{
					addlit(yytext, yyleng, yyscanner);
				}

<xl>{space}		{
					BEGIN(INITIAL);
					yylval->str = litbufdup(NULL, yyscanner);
					cur_state->token_count++;
					return LITERAL;
				}

<xl><<EOF>>		{
					BEGIN(INITIAL);
					yylval->str = litbufdup(NULL, yyscanner);
					cur_state->token_count++;
					return LITERAL;
				}

<<EOF>>			{
					return 0;			/* end of input reached */
				}

%%

/* LCOV_EXCL_STOP */

void orapsql_yyerror(yyscan_t yyscanner, const char *message)
{
	/* do nothing */
}

/*
 * Called before any actual parsing is done.
 */
yyscan_t
psqlplus_scanner_init(PsqlScanState state)
{
	/* Must be scanning already */
	Assert(state->scanbufhandle != NULL);

	/* Set current output target */
	state->output_buf = NULL;

	state->token_count = 0;
	state->is_sqlplus_cmd = false;

	/* initialize literal buffer */
	state->literalalloc = 0;
	state->literalbuf = NULL;
	state->literallen = 0;

	/* Set input source */
	if (state->buffer_stack != NULL)
		yy_switch_to_buffer(state->buffer_stack->buf, state->scanner);
	else
		yy_switch_to_buffer(state->scanbufhandle, state->scanner);

	/* Set start state */
	state->start_state = INITIAL;

	return state->scanner;
}

/*
 * Called after parsing is done to clean up after psqlplus_scanner_init().
 */
void
psqlplus_scanner_finish(yyscan_t yyscanner)
{
	PsqlScanState state = yyget_extra(yyscanner);

	if (state->literalbuf)
		pfree(state->literalbuf);

	/*
	 * Reselect appropriate initial state for SQL lexer.
	 */
	psql_scan_reselect_sql_lexer(state);
}

/*
 * Do downcasing and returns a palloc'd string.
 */
static char *
psqlplus_downcase_identifier(const char *str, int len)
{
	char	   *result;
	int			i;

	result = (char *) pg_malloc(len + 1);
	for (i = 0; i < len; i++)
	{
		result[i] = (char) pg_tolower((unsigned char) str[i]);
	}

	result[i] = '\0';

	return result;
}

/*
 * ScanKeywordLookup - see if a given word is a keyword.
 */
static const PsqlScanKeyword *
PsqlplusKeywordLookup(const char *text)
{
	int			len,
				i;
	char		word[NAMEDATALEN];
	const PsqlScanKeyword *low;
	const PsqlScanKeyword *high;

	len = strlen(text);

	/* We assume all keywords are shorter than NAMEDATALEN. */
	if (len >= NAMEDATALEN)
		return NULL;

	/*
	 * Apply an ASCII-only downcasing.  We must not use tolower() since it may
	 * produce the wrong translation in some locales (eg, Turkish).
	 */
	for (i = 0; i < len; i++)
	{
		char		ch = text[i];

		if (ch >= 'A' && ch <= 'Z')
			ch += 'a' - 'A';
		word[i] = ch;
	}
	word[len] = '\0';

	/*
	 * Now do a binary search using plain strcmp() comparison.
	 */
	low = psqlplus_keywords;
	high = psqlplus_keywords + (NumKeywords - 1);
	while (low <= high)
	{
		const PsqlScanKeyword *middle;
		int			difference;

		middle = low + (high - low) / 2;
		difference = strcmp(middle->name, word);
		if (difference == 0)
			return middle;
		else if (difference < 0)
			low = middle + 1;
		else
			high = middle - 1;
	}

	return NULL;
}

/*
 * Process {integer}.  Note this will also do the right thing with {decimal},
 * ie digits and a decimal point.
 */
static int
process_integer_literal(const char *token, YYSTYPE *lval)
{
	int			val;
	char	   *endptr;

	errno = 0;
	val = strtoint(token, &endptr, 10);
	if (*endptr != '\0' || errno == ERANGE)
	{
		/* integer too large (or contains decimal pt), treat it as a float */
		lval->str = pg_strdup(token);
		return FCONST;
	}
	lval->ival = val;
	return ICONST;
}

static void
startlit(yyscan_t yyscanner)
{
	PsqlScanState state = yyget_extra(yyscanner);
	
	if (state->literalbuf)
		state->literallen = 0;
	else
	{
		/* initialize literal buffer */
		state->literalalloc = 1024;
		state->literalbuf = (char *) palloc(state->literalalloc);
		state->literallen = 0;
	}
}

static void
addlitchar(unsigned char ychar, yyscan_t yyscanner)
{
	PsqlScanState state = yyget_extra(yyscanner);

	/* enlarge buffer if needed */
	if ((state->literallen + 1) >= state->literalalloc)
	{
		state->literalalloc *= 2;
		state->literalbuf = (char *) repalloc(state->literalbuf, state->literalalloc);
	}

	/* append new data */
	state->literalbuf[state->literallen] = ychar;
	state->literallen += 1;
}

static void
addlit(char *ytext, int yleng, yyscan_t yyscanner)
{
	PsqlScanState state = yyget_extra(yyscanner);

	/* enlarge buffer if needed */
	if ((state->literallen + yleng) >= state->literalalloc)
	{
		do
		{
			state->literalalloc *= 2;
		} while ((state->literallen + yleng) >= state->literalalloc);
		state->literalbuf = (char *) repalloc(state->literalbuf, state->literalalloc);
	}
	/* append new data */
	memcpy(state->literalbuf + state->literallen, ytext, yleng);
	state->literallen += yleng;
}

/*
 * Create a palloc'd copy of literalbuf, adding a trailing null.
 * If prefix is not NULL, append it to the front of literalbuf .
 */
static char *
litbufdup(char *prefix, yyscan_t yyscanner)
{
	PsqlScanState	state = yyget_extra(yyscanner);
	int				llen = state->literallen;
	int				plen = 0;
	char			*new;

	if (prefix)
		plen = strlen(prefix);

	new = palloc(llen + plen + 1);

	if (prefix)
		memcpy(new, prefix, plen);

	memcpy(new + plen, state->literalbuf, llen);
	new[llen + plen] = '\0';
	return new;
}
