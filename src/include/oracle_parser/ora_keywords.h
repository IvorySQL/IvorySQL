/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
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
