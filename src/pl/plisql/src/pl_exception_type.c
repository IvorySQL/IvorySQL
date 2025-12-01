/*-------------------------------------------------------------------------
 *
 * pl_exception_type.c
 *		Oracle-compatible EXCEPTION type implementation for PL/iSQL
 *
 * This module implements user-defined exception variables as found in
 * Oracle PL/SQL.
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_exception_type.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "pl_exception_type.h"
#include "plisql.h"

/*
 * plisql_build_exception
 *		Build a user-defined exception variable
 *
 * This creates a new exception variable and optionally adds it to
 * the current namespace.
 */
PLiSQL_exception_var *
plisql_build_exception(const char *refname, int lineno, bool add2namespace)
{
	PLiSQL_exception_var *exc;

	exc = palloc0(sizeof(PLiSQL_exception_var));
	exc->dtype = PLISQL_DTYPE_EXCEPTION;
	exc->refname = pstrdup(refname);
	exc->lineno = lineno;
	exc->sqlcode = ERRCODE_RAISE_EXCEPTION;  /* Default P0001 for user-defined exceptions */
	exc->pkgoid = InvalidOid;

	/* Assign datum number and add to datum array */
	exc->dno = plisql_nDatums;
	plisql_adddatum((PLiSQL_datum *) exc);

	/* Add to namespace if requested */
	if (add2namespace)
		plisql_ns_additem(PLISQL_NSTYPE_VAR, exc->dno, refname);

	return exc;
}

/*
 * plisql_datum_is_exception
 *		Check if a datum is an exception variable
 */
bool
plisql_datum_is_exception(PLiSQL_datum *datum)
{
	if (datum == NULL)
		return false;

	return (datum->dtype == PLISQL_DTYPE_EXCEPTION);
}

/*
 * plisql_datum_get_exception
 *		Get exception variable from datum (with type checking)
 */
PLiSQL_exception_var *
plisql_datum_get_exception(PLiSQL_datum *datum)
{
	if (!plisql_datum_is_exception(datum))
		return NULL;

	return (PLiSQL_exception_var *) datum;
}

/*
 * plisql_lookup_exception
 *		Lookup an exception by name in the current namespace
 */
PLiSQL_exception_var *
plisql_lookup_exception(const char *name)
{
	PLiSQL_nsitem *nse;

	nse = plisql_ns_lookup(plisql_ns_top(), false, name, NULL, NULL, NULL);

	if (nse == NULL)
		return NULL;

	if (plisql_Datums[nse->itemno]->dtype != PLISQL_DTYPE_EXCEPTION)
		return NULL;

	return (PLiSQL_exception_var *) plisql_Datums[nse->itemno];
}

/*
 * plisql_exception_set_sqlcode
 *		Set the SQLCODE for an exception variable
 *
 * This is used by PRAGMA EXCEPTION_INIT to associate a specific
 * Oracle error code with an exception.
 */
void
plisql_exception_set_sqlcode(PLiSQL_exception_var *exc, int sqlcode)
{
	if (exc == NULL)
		return;

	exc->sqlcode = sqlcode;
}

/*
 * plisql_validate_exception_error_code
 *		Validate error code for PRAGMA EXCEPTION_INIT (Oracle compatibility)
 *
 * Oracle documentation states valid error codes are:
 *   - Error code 100 (ANSI NO_DATA_FOUND)
 *   - Any negative integer >= -1000000, except -1403
 *
 * Oracle rejects at compile time with PLS-00701:
 *   - Error code 0 (zero is not a valid error code)
 *   - Error code -1403 (Oracle-specific NO_DATA_FOUND; must use 100 instead)
 *   - All positive error codes EXCEPT 100
 *   - Error codes less than -1000000
 *
 * Returns true if valid, false if invalid.
 */
static bool
plisql_validate_exception_error_code(int sqlcode)
{
	/* Reject zero */
	if (sqlcode == 0)
		return false;

	/* Reject -1403 (Oracle-specific NO_DATA_FOUND) */
	if (sqlcode == -1403)
		return false;

	/* For positive codes, only 100 (ANSI NO_DATA_FOUND) is allowed */
	if (sqlcode > 0 && sqlcode != 100)
		return false;

	/* For negative codes, must be >= -1000000 */
	if (sqlcode < -1000000)
		return false;

	/* All other codes are valid */
	return true;
}

/*
 * plisql_process_pragma_exception_init
 *		Process PRAGMA EXCEPTION_INIT directive at compile time
 *
 * This associates a user-defined exception with a specific error code.
 * Called during compilation when PRAGMA EXCEPTION_INIT is encountered.
 *
 * Syntax: PRAGMA EXCEPTION_INIT(exception_name, error_code);
 */
void
plisql_process_pragma_exception_init(const char *exc_name, int sqlcode,
									  int location, void *yyscanner)
{
	PLiSQL_nsitem *nse;
	PLiSQL_exception_var *exc;

	/* Lookup exception in current namespace */
	nse = plisql_ns_lookup(plisql_ns_top(), false, exc_name, NULL, NULL, NULL);

	if (nse == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("exception \"%s\" does not exist", exc_name),
				 plisql_scanner_errposition(location, yyscanner)));

	/* Verify it's an exception variable */
	if (plisql_Datums[nse->itemno]->dtype != PLISQL_DTYPE_EXCEPTION)
		ereport(ERROR,
				(errcode(ERRCODE_WRONG_OBJECT_TYPE),
				 errmsg("\"%s\" is not an exception", exc_name),
				 plisql_scanner_errposition(location, yyscanner)));

	/* Validate error code (Oracle compatibility) */
	if (!plisql_validate_exception_error_code(sqlcode))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("illegal ORACLE error number %d for PRAGMA EXCEPTION_INIT", sqlcode),
				 plisql_scanner_errposition(location, yyscanner)));

	/* Set the exception's sqlcode */
	exc = (PLiSQL_exception_var *) plisql_Datums[nse->itemno];
	plisql_exception_set_sqlcode(exc, sqlcode);
}

/*
 * plisql_dump_exception
 *		Dump exception info for debugging
 */
void
plisql_dump_exception(PLiSQL_exception_var *exc)
{
	if (exc == NULL)
		return;

	printf("    EXCEPTION %s (dno %d, sqlcode %d, line %d)\n",
		   exc->refname, exc->dno, exc->sqlcode, exc->lineno);
}
