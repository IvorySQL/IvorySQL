/*-------------------------------------------------------------------------
 *
 * ora_keywords.h
 *	  IvorySQL's list of SQL keywords
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/include/oracle_parser/ora_keywords.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef ORA_KEYWORDS_H
#define ORA_KEYWORDS_H

#include "common/kwlookup.h"

/* Keyword categories --- should match lists in gram.y */
#define UNRESERVED_KEYWORD		0
#define COL_NAME_KEYWORD		1
#define TYPE_FUNC_NAME_KEYWORD	2
#define RESERVED_KEYWORD		3

extern const ScanKeywordList OraScanKeywords;
extern const uint8 OraScanKeywordCategories[];
extern const bool OraScanKeywordBareLabel[];


#endif							/* ORA_KEYWORDS_H */
