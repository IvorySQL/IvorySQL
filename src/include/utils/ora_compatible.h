/*--------------------------------------------------------------------
 *
 * ora_compatible.h
 *
 * Definition enumeration structure is fro supporting different compatibility modes.
 *
 * Portions Copyright (c) 2022, IvorySQL-2.0
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

/* BEGIN - case sensitive indentify */
typedef enum CaseSwitchMode
{
	NORMAL = 0,
	INTERCHANGE,
	LOWERCASE
}CaseSwitchMode;
/* END - case sensitive indentify */


typedef enum
{
	NLS_LENGTH_BYTE,
	NLS_LENGTH_CHAR
} NlsLengthSemantics;


#endif							/* ORA_COMPATIBLE_H */

