/*------------------------------------------------------------------
 * 
 * File: psqlplus.h
 *
 * Abstract: 
 * 		lexical scanner for client commands.
 *
 * Authored by zhenmingyang@highgo.com, 20221221.
 *
 * Copyright:
 * Copyright (c) 2022, HighGo Software Co.,Ltd. All rights reserved. 
 *
 * Identification:
 *		src/bin/psql/psqlplus.h
 *
 *------------------------------------------------------------------
 */
#ifndef PSQLPLUS_H
#define PSQLPLUS_H

#include "fe_utils/psqlscan_int.h"

#define PSQL_KEYWORD(a,b,c) {a,b,c},

/*
 * Keyword categories --- should match lists in psqlplusparse.y,
 * the keyword categories may not be useful at the moment,  but
 * the name of the "object" created by the some Oracle client
 * command is allowed to have the same name as the keyword ,
 * which can use this to distinguish.
 */
#define UNRESERVED_PSQL_KEYWORD		0
#define RESERVED_PSQL_KEYWORD		1

typedef struct PsqlScanKeyword
{
	const char *name;			/* in lower case */
	int16		value;			/* grammar's token code */
	int16		category;		/* see codes above */
} PsqlScanKeyword;

#define psql_yyget_extra(yyscanner) (*((PsqlScanStateData **) (yyscanner)))

/*
 * You can compile the psql client separately from the source code.
 * In order not to depend on the backend pg_type_d.h file, declare
 * the type OID macro here.  If you modify the OID values of these
 * types, pay attention to keeping in sync with pg_type_d.h.
 */
#define ORACHARCHAROID		9500
#define ORACHARBYTEOID		9501
#define ORAVARCHARCHAROID	9502
#define ORAVARCHARBYTEOID	9503
#define NUMBEROID		9520
#define BINARY_FLOATOID		9522
#define BINARY_DOUBLEOID	9524

/* Maxsize of char and varchar2 within Oracle */
#define MaxOraCharLen 2000
#define MaxOraVarcharLen 32767

/*
 * The type of yyscanner is opaque outside psqlplus.l.
 */
//#define yyscan_t  void *
union YYSTYPE;

/* callback functions for our flex lexer */
static const Ora_psqlScanCallbacks psqlplus_callbacks = {
	NULL,
};

extern int	psqlplus_yyparse(yyscan_t yyscanner);
extern int	psqlplus_yylex(union YYSTYPE *lvalp, yyscan_t yyscanner);
extern void psqlplus_yyerror(yyscan_t yyscanner, const char *message);
extern yyscan_t psqlplus_scanner_init(PsqlScanState state);
extern void psqlplus_scanner_finish(yyscan_t yyscanner);
#endif   /* PSQLPLUS_H */
