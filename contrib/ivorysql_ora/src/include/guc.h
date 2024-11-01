/*------------------------------------------------------------------
 * 
 * File: guc.h
 *
 * Abstract: 
 * 		This file contains extern declarations for GUC.
 *
 * Copyright:
 * Portions Copyright (c) 2024, Ivory SQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/include/guc.h
 *
 *------------------------------------------------------------------
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
