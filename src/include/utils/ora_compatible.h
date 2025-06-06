/*--------------------------------------------------------------------
 *
 * ora_compatible.h
 *
 * Definition enumeration structure is fro supporting different compatibility modes.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
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

#endif							/* ORA_COMPATIBLE_H */
