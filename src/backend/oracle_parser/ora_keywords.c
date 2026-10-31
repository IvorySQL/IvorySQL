/*-------------------------------------------------------------------------
 *
 * ora_keywords.c
 *	  IvorySQL's list of SQL keywords (Oracle Compatible)
 *
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 *
 * IDENTIFICATION
 *	  src/backend/oracle_parser/ora_keywords.c
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */
#include "c.h"

#include "oracle_parser/ora_keywords.h"


/* ScanKeywordList lookup data for SQL keywords */


/*
 * The generated header declares the keyword list PGDLLIMPORT, for the
 * benefit of -Wmissing-variable-declarations, and then defines it. This
 * file is part of the Oracle parser module, not the backend proper, so
 * under MSVC that declaration would make the definition a redefinition
 * with a different storage class (C2370); the list is this module's own.
 */
#undef PGDLLIMPORT
#define PGDLLIMPORT
#include "ora_kwlist_d.h"

/* Keyword categories for SQL keywords */

#define PG_KEYWORD(kwname, value, category, collabel) category,

const uint8 OraScanKeywordCategories[ORASCANKEYWORDS_NUM_KEYWORDS] = {
#include "oracle_parser/ora_kwlist.h"
};

#undef PG_KEYWORD

/* Keyword can-be-bare-label flags for SQL keywords */

#define PG_KEYWORD(kwname, value, category, collabel) collabel,

#define BARE_LABEL true
#define AS_LABEL false

const bool	OraScanKeywordBareLabel[ORASCANKEYWORDS_NUM_KEYWORDS] = {
#include "oracle_parser/ora_kwlist.h"
};

#undef PG_KEYWORD
#undef BARE_LABEL
#undef AS_LABEL
