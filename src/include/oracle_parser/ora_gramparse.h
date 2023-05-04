/*-------------------------------------------------------------------------
 *
 * ora_gramparse.h
 *		Shared definitions for the "raw" parser (flex and bison phases only)
 *
 * NOTE: this file is only meant to be included in the core parsing files,
 * ie, parser.c, ora_gram.y, ora_scan.l, and src/backend/oracle_parser/ora_keywords.c.
 * Definitions that are needed outside the core parser should be in ora_gramparse.h.
 *
 *
 * Portions Copyright (c) 2023, IvorySQL
 *
 * src/include/oracle_parser/ora_gramparse.h
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#ifndef ORA_GRAMPARSE_H
#define ORA_GRAMPARSE_H

#include "nodes/parsenodes.h"
#include "oracle_parser/ora_scanner.h"

/*
 * NB: include ora_gram.h only AFTER including ora_scanner.h, because ora_scanner.h
 * is what #defines YYLTYPE.
 */
#include "ora_gram.h"

/*
 * The YY_EXTRA data that a flex scanner allows us to pass around.  Private
 * state needed for raw parsing/lexing goes here.
 */
typedef struct ora_base_yy_extra_type
{
	/*
	 * Fields used by the core scanner.
	 */
	ora_core_yy_extra_type core_yy_extra;

	/*
	 * State variables for ora_base_yylex().
	 */
	bool		have_lookahead; /* is lookahead info valid? */
	int			lookahead_token;	/* one-token lookahead */
	ora_core_YYSTYPE lookahead_yylval;	/* yylval for lookahead token */
	YYLTYPE		lookahead_yylloc;	/* yylloc for lookahead token */
	char	   *lookahead_end;	/* end of current token */
	char		lookahead_hold_char;	/* to be put back at *lookahead_end */

	/*
	 * State variables that belong to the grammar.
	 */
	List	   *parsetree;		/* final parse result is delivered here */
} ora_base_yy_extra_type;

/*
 * In principle we should use yyget_extra() to fetch the yyextra field
 * from a yyscanner struct.  However, flex always puts that field first,
 * and this is sufficiently performance-critical to make it seem worth
 * cheating a bit to use an inline macro.
 */
#define pg_yyget_extra(yyscanner) (*((ora_base_yy_extra_type **) (yyscanner)))


/* from libparser_oracle.c */
extern int	ora_base_yylex(YYSTYPE *lvalp, YYLTYPE *llocp,
							ora_core_yyscan_t yyscanner);

/* from ora_gram.y */
extern void ora_parser_init(ora_base_yy_extra_type *yyext);
extern int	ora_base_yyparse(ora_core_yyscan_t yyscanner);

#endif							/* ORA_GRAMPARSE_H */
