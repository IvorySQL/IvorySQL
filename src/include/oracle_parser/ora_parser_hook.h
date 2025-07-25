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
 * ora_parser_hook.h
 *		Variable Declarations shown as below are used to
 *	 	for the Hook function's definitions.
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/include/oracle_parser/ora_parser_hook.h
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#ifndef ORA_PARSER_HOOK_H
#define ORA_PARSER_HOOK_H

/* Hook for plugins to get control in get_keywords() */
typedef Datum (*get_keywords_hook_type)(PG_FUNCTION_ARGS);
extern PGDLLIMPORT get_keywords_hook_type get_keywords_hook;

/* Hook for plugins to get control in fill_in_constant_lengths() */
typedef void (*fill_in_constant_lengths_hook_type)(void *jstate, const char *query, int query_loc);
extern PGDLLIMPORT fill_in_constant_lengths_hook_type fill_in_constant_lengths_hook;

//fill_in_constant_lengths_hook_type fill_in_constant_lengths_hook = NULL;

/* Hook for plugins to get control in quote_identifier() */
typedef const char *(*quote_identifier_hook_type)(const char *ident);
extern PGDLLIMPORT quote_identifier_hook_type quote_identifier_hook;

#endif							/* ORA_PARSER_HOOK_H */
