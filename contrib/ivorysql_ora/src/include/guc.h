/*-------------------------------------------------------------------------
 *
 * guc.h
 *
 * This file contains extern declarations for GUC.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/include/guc.h
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#if 0
/* nls_length_semantics */
typedef enum
{
	NLS_LENGTH_SEMANTICS_CHAR,			/* CHAR */
	NLS_LENGTH_SEMANTICS_BYTE,			/* BYTE */
} NLSLENGTHSEMANTICS;

extern int	nls_length_semantics;
#endif

extern void IvorysqlOraDefineGucs(void);
