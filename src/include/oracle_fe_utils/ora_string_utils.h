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
 * String-processing utility routines for frontend code (Oracle compatibility)
 *
 * Utility functions that interpret backend output or quote strings for
 * assorted contexts.
 *
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
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
extern const char *ora_fmtId(const char *identifier);

#endif							/* ORA_STRING_UTILS_H */
