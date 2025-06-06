/*-------------------------------------------------------------------------
 *
 * String-processing utility routines for frontend code (Oracle compatibility)
 *
 * Utility functions that interpret backend output or quote strings for
 * assorted contexts.
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/include/oracle_fe_utils/ora_string_utils.h
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */
#ifndef ORA_STRING_UTILS_H
#define ORA_STRING_UTILS_H

#include "libpq-fe.h"
#include "pqexpbuffer.h"
#include "oracle_parser/ora_keywords.h"
#include "utils/ora_compatible.h"

/* Global variables controlling behavior of ora_fmtId() */
extern DBMode db_mode;
extern void getDbCompatibleMode(PGconn *conn);

/* Functions */
extern const char *ora_fmtId(const char *identifier, int encoding);

#endif							/* ORA_STRING_UTILS_H */
