/*-------------------------------------------------------------------------
 *
 * ora_keywords.c
 *	  IvorySQL's list of SQL keywords (Oracle Compatible)
 *
 *
 * Portions Copyright (c) 1996-2023, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
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
