/*-------------------------------------------------------------------------
 *
 * ora_psqlscan.h
 *	  lexical scanner for Oracle compatible SQL commands
 *
 * This lexer used to be part of psql, and that heritage is reflected in
 * the file name as well as function and typedef names, though it can now
 * be used by other frontend programs as well.  It's also possible to extend
 * this lexer with a compatible add-on lexer to handle program-specific
 * backslash commands.
 *
 * Authored by lanke@highgo.com
 *
 * Copyright:
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/include/oracle_fe_utils/ora_psqlscan.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef ORA_PSQLSCAN_H
#define ORA_PSQLSCAN_H

#include "pqexpbuffer.h"


/* Abstract type for lexer's internal state */
typedef struct PsqlScanStateData *PsqlScanState;

/* Termination states for psql_scan() */
typedef enum
{
	ORAPSCAN_SEMICOLON,			/* found command-ending semicolon */
	ORAPSCAN_BACKSLASH,			/* found backslash command */
	ORAPSCAN_INCOMPLETE,			/* end of line, SQL statement incomplete */
	ORAPSCAN_EOL					/* end of line, SQL possibly complete */
} Ora_PsqlScanResult;

/* Prompt type returned by psql_scan() */
typedef enum Ora_promptStatus
{
	ORAPROMPT_READY,
	ORAPROMPT_CONTINUE,
	ORAPROMPT_COMMENT,
	ORAPROMPT_SINGLEQUOTE,
	ORAPROMPT_DOUBLEQUOTE,
	ORAPROMPT_DOLLARQUOTE,
	ORAPROMPT_QQUOTE,
	ORAPROMPT_PAREN,
	ORAPROMPT_COPY
} Ora_promptStatus_t;

/* Quoting request types for get_variable() callback */
typedef enum
{
	ORAPQUOTE_PLAIN,				/* just return the actual value */
	ORAPQUOTE_SQL_LITERAL,			/* add quotes to make a valid SQL literal */
	ORAPQUOTE_SQL_IDENT,			/* quote if needed to make a SQL identifier */
	ORAPQUOTE_SHELL_ARG			/* quote if needed to be safe in a shell cmd */
} Ora_psqlScanQuoteType;

/* Callback functions to be used by the lexer */
typedef struct Ora_psqlScanCallbacks
{
	/* Fetch value of a variable, as a free'able string; NULL if unknown */
	/* This pointer can be NULL if no variable substitution is wanted */
	char	   *(*get_variable) (const char *varname, Ora_psqlScanQuoteType quote,
								 void *passthrough);
} Ora_psqlScanCallbacks;

extern PsqlScanState ora_psql_scan_create(const Ora_psqlScanCallbacks *callbacks);
extern void ora_psql_scan_destroy(PsqlScanState state);

extern void ora_psql_scan_set_passthrough(PsqlScanState state, void *passthrough);

extern void ora_psql_scan_setup(PsqlScanState state,
							const char *line, int line_len,
							int encoding, bool std_strings);
extern void ora_psql_scan_finish(PsqlScanState state);

extern Ora_PsqlScanResult ora_psql_scan(PsqlScanState state,
								PQExpBuffer query_buf,
								Ora_promptStatus_t *prompt);

extern void ora_psql_scan_reset(PsqlScanState state);

extern void ora_psql_scan_reselect_sql_lexer(PsqlScanState state);

extern bool ora_psql_scan_in_quote(PsqlScanState state);
extern bool is_oracle_slash(PsqlScanState state, const char *line);


#endif							/* PSQLSCAN_H */
