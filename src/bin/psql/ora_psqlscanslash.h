/*
 * psql - the PostgreSQL interactive terminal
 *
 * Authored by lanke@highgo.com, 20220705.
 *
 * Copyright:
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/bin/psql/ora_psqlscanslash.h
 */
/* Begin - ReqID:SRS-PSQL-PARSER */
#ifndef ORA_PSQLSCANSLASH_H
#define ORA_PSQLSCANSLASH_H

#include "oracle_fe_utils/ora_psqlscan.h"
#include "psqlscanslash.h"

typedef char *(*psql_scan_slash_option_hook_type) (PsqlScanState state,
					   enum slash_option_type type,
					   char *quote,
					   bool semicolon);
extern psql_scan_slash_option_hook_type psql_scan_slash_option_parser;

extern char *ora_psql_scan_slash_command(PsqlScanState state);

extern char *psql_scan_slash_option(PsqlScanState state,
					   enum slash_option_type type,
					   char *quote,
					   bool semicolon);

extern char *ora_psql_scan_slash_option(PsqlScanState state,
					   enum slash_option_type type,
					   char *quote,
					   bool semicolon);

extern void ora_psql_scan_slash_command_end(PsqlScanState state);

extern int	ora_psql_scan_get_paren_depth(PsqlScanState state);

extern void ora_psql_scan_set_paren_depth(PsqlScanState state, int depth);

extern void ora_dequote_downcase_identifier(char *str, bool downcase, int encoding);

#endif   /* PSQLSCANSLASH_H */
/* End - ReqID:SRS-PSQL-PARSER */
