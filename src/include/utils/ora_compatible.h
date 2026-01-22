/*--------------------------------------------------------------------
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
 * ora_compatible.h
 *
 * Definition enumeration structure is fro supporting different compatibility modes.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * src/include/utils/ora_compatible.h
 *
 * add the file for requirement "SQL PARSER"
 *
 *----------------------------------------------------------------------
 */

#ifndef ORA_COMPATIBLE_H
#define ORA_COMPATIBLE_H

#define ORA_SEARCH_PATH "sys,\"$user\", public"
#define DB_MODE_PARMATER "ivorysql.database_mode"

#define CHAR_TYPE_LENGTH_MAX    2000

typedef enum DBMode
{
	DB_PG = 0,
	DB_ORACLE
}DBMode;

typedef enum DBParser
{
	PG_PARSER = 0,
	ORA_PARSER
}DBParser;

typedef enum CaseSwitchMode
{
	NORMAL = 0,
	INTERCHANGE,
	LOWERCASE
}CaseSwitchMode;

typedef enum
{
	NLS_LENGTH_BYTE,
	NLS_LENGTH_CHAR
} NlsLengthSemantics;
extern int       bootstrap_database_mode;
#endif							/* ORA_COMPATIBLE_H */
