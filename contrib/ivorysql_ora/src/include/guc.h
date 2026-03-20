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
 * guc.h
 *
 * This file contains extern declarations for GUC.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
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
