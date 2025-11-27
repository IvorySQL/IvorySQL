/*-------------------------------------------------------------------------
 *
 * pl_exception_type.h
 *		Oracle-compatible EXCEPTION type support for PL/iSQL
 *
 * This module implements user-defined exception variables as found in
 * Oracle PL/SQL. Exception variables are declared with the EXCEPTION
 * keyword and can be raised and caught by name.
 *
 * Example:
 *   DECLARE
 *     my_exception EXCEPTION;
 *   BEGIN
 *     RAISE my_exception;
 *   EXCEPTION
 *     WHEN my_exception THEN
 *       DBMS_OUTPUT.PUT_LINE('Caught!');
 *   END;
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_exception_type.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PL_EXCEPTION_TYPE_H
#define PL_EXCEPTION_TYPE_H

#include "plisql.h"

/*
 * User-defined exception variable
 *
 * This represents an EXCEPTION declaration in Oracle PL/SQL.
 * Exception variables can be raised with RAISE statement and
 * caught in EXCEPTION handlers. They can optionally be associated
 * with specific error codes via PRAGMA EXCEPTION_INIT.
 */
typedef struct PLiSQL_exception_var
{
	PLiSQL_datum_type dtype;	/* always PLISQL_DTYPE_EXCEPTION */
	int			dno;
	Oid			pkgoid;
	char	   *refname;		/* exception name */
	int			lineno;			/* line number of declaration */

	/*
	 * sqlcode is the error code associated with this exception.
	 * Default is 1 for user-defined exceptions.
	 * Can be set to a specific Oracle error code via PRAGMA EXCEPTION_INIT.
	 */
	int			sqlcode;		/* associated error code (default 1) */
} PLiSQL_exception_var;

/*
 * Public API functions
 */

/* Build a new exception variable */
extern PLiSQL_exception_var *plisql_build_exception(const char *refname,
													 int lineno,
													 bool add2namespace);

/* Check if a datum is an exception variable */
extern bool plisql_datum_is_exception(PLiSQL_datum *datum);

/* Get exception variable from datum */
extern PLiSQL_exception_var *plisql_datum_get_exception(PLiSQL_datum *datum);

/* Lookup exception by name in namespace */
extern PLiSQL_exception_var *plisql_lookup_exception(const char *name);

/* Set SQLCODE for exception (used by PRAGMA EXCEPTION_INIT) */
extern void plisql_exception_set_sqlcode(PLiSQL_exception_var *exc, int sqlcode);

/* Process PRAGMA EXCEPTION_INIT directive (compile-time) */
extern void plisql_process_pragma_exception_init(const char *exc_name,
												  int sqlcode,
												  int location,
												  void *yyscanner);

/* Dump exception info (for debugging) */
extern void plisql_dump_exception(PLiSQL_exception_var *exc);

#endif	/* PL_EXCEPTION_TYPE_H */
