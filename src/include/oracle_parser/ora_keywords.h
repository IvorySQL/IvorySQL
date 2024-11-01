/*-------------------------------------------------------------------------
 *
 * ora_keywords.h
 *	  IvorySQL-2.0's list of SQL keywords
 *
 *
 * Portions Copyright (c) 2022, IvorySQL-2.0 Global Development Group
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

#ifndef FRONTEND
extern const ScanKeywordList OraScanKeywords;
extern const uint8 OraScanKeywordCategories[];
extern const bool OraScanKeywordBareLabel[];
#else
extern const ScanKeywordList OraScanKeywords;
extern const uint8 OraScanKeywordCategories[];
extern const bool OraScanKeywordBareLabel[];
#endif

#endif							/* ORA_KEYWORDS_H */
