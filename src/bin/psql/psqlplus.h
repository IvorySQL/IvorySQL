/*------------------------------------------------------------------
 * 
 * File: psqlplus.h
 *
 * Abstract: 
 *    Lexical scanner for Oracle-compatible client commands.
 *
 * Authored by zhenmingyang@highgo.com, 20221221.
 *
 * Copyright (c) 2022-2025, IvorySQL Global Development Team
 *
 * Identification:
 *		src/bin/psql/psqlplus.h
 *
 *------------------------------------------------------------------
 */
#ifndef PSQLPLUS_H
#define PSQLPLUS_H

#include "fe_utils/psqlscan_int.h"

/*
 * Keyword categories - should match lists in psqlplusparse.y
 * 
 * These categories may not be actively used currently, but they allow
 * object names created by Oracle client commands to have the same name
 * as keywords by providing a way to distinguish between them.
 */
#define UNRESERVED_PSQL_KEYWORD		0
#define RESERVED_PSQL_KEYWORD		1

/*
 * Structure representing a SQL keyword for the scanner
 */
typedef struct PsqlScanKeyword
{
	const char *name;			/* keyword name in lower case */
	int16		value;			/* grammar's token code */
	int16		category;		/* keyword category (UNRESERVED/RESERVED) */
} PsqlScanKeyword;

/* Macro for defining keywords */
#define PSQL_KEYWORD(name,value,category) {name,value,category},

/* Macro to get extra data from yyscanner */
#define psql_yyget_extra(yyscanner) (*((PsqlScanStateData **) (yyscanner)))

/*
 * Oracle-compatible type OIDs
 * 
 * These are declared here to avoid dependency on backend pg_type_d.h
 * when compiling the psql client separately. If modifying these OID
 * values, ensure synchronization with pg_type_d.h.
 */
#define ORACHARCHAROID		9500
#define ORACHARBYTEOID		9501
#define ORAVARCHARCHAROID	9502
#define ORAVARCHARBYTEOID	9503
#define NUMBEROID		9520
#define BINARY_FLOATOID		9522
#define BINARY_DOUBLEOID	9524

/* Maximum sizes for Oracle character types */
#define MaxOraCharLen 2000	/* Maximum length for CHAR */
#define MaxOraVarcharLen 32767	/* Maximum length for VARCHAR2 */

#define BINDVARREF 3000

/*
 * The scanner returns extra data about scanned tokens in this union type.
 * Note that this is a subset of the fields used in YYSTYPE of the bison
 * parsers built atop the scanner.
 */
typedef union psql_YYSTYPE
{
	int			ival;
	char	   *str;
	const char *keyword;
} psql_YYSTYPE;

union YYSTYPE;
/* Scanner lifecycle management */
extern yyscan_t psqlplus_scanner_init(PsqlScanState state);
extern void psqlplus_scanner_finish(yyscan_t yyscanner);
/* Parser interface functions */
extern int psqlplus_yyparse(yyscan_t yyscanner);
extern int psqlplus_yylex(union YYSTYPE *lvalp, yyscan_t yyscanner);
extern int orapsql_yylex(psql_YYSTYPE *lvalp, yyscan_t yyscanner);
extern void psqlplus_yyerror(yyscan_t yyscanner, const char *message);
extern void orapsql_yyerror(yyscan_t yyscanner, const char *message);

/* Callback functions for the flex lexer */
static const Ora_psqlScanCallbacks psqlplus_callbacks = {
	NULL,	 /* placeholder for future callback functions */
};

#endif   /* PSQLPLUS_H */
