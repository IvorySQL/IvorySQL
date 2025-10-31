/*
 * psql - the PostgreSQL interactive terminal
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 * Copyright (c) 2000-2025, PostgreSQL Global Development Group
 *
 * src/bin/psql/common.h
 */
#ifndef COMMON_H
#define COMMON_H

#include <setjmp.h>
#include <signal.h>

#include "fe_utils/print.h"
#include "fe_utils/psqlscan.h"
#include "oracle_fe_utils/ora_psqlscan.h" 
#include "libpq-fe.h"
#include "libpq-ivy.h"

extern bool openQueryOutputFile(const char *fname, FILE **fout, bool *is_pipe);
extern bool setQFout(const char *fname);

extern char *psql_get_variable(const char *varname, PsqlScanQuoteType quote,
							   void *passthrough);

extern char *ora_psql_get_variable(const char *varname, Ora_psqlScanQuoteType quote,
						void *passthrough);

extern void NoticeProcessor(void *arg, const char *message);

extern volatile sig_atomic_t sigint_interrupt_enabled;

extern sigjmp_buf sigint_interrupt_jmp;

extern void psql_setup_cancel_handler(void);

extern void SetShellResultVariables(int wait_result);

extern PGresult *PSQLexec(const char *query);
extern int	PSQLexecWatch(const char *query, const printQueryOpt *opt, FILE *printQueryFout, int min_rows);

extern bool SendQuery(const char *query);

extern bool is_superuser(void);
extern bool standard_strings(void);
extern const char *session_username(void);

extern void expand_tilde(char **filename);
extern void clean_extended_state(void);

extern bool recognized_connection_string(const char *connstr);
extern char *psqlplus_skip_space(char *query);
extern HostVariable *get_hostvariables(const char *sql, bool *error);
extern bool SendQuery_PBE(const char *query, HostVariable *hv);

#endif							/* COMMON_H */
