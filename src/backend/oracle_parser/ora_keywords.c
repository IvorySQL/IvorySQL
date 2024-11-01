/*-------------------------------------------------------------------------
 *
 * ora_keywords.c
 *	  IvorySQL-2.0's list of SQL keywords (Oracle Compatible)
 *
 *
 * Portions Copyright (c) 2022, IvorySQL-2.0
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
