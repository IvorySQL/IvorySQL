/*--------------------------------------------------------------------
 *
 * ora_compatible.h
 *
 * Definition enumeration structure is fro supporting different compatibility modes.
 *
 * Portions Copyright (c) 2023, IvorySQL
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
#define DB_MODE_PARMATER "database_mode"

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

#endif							/* ORA_COMPATIBLE_H */
