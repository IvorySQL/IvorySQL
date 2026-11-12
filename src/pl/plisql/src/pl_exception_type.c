/*-------------------------------------------------------------------------
 *
 * pl_exception_type.c
 *		Oracle-compatible EXCEPTION type implementation for PL/iSQL
 *
 * This module implements user-defined exception variables as found in
 * Oracle PL/SQL.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_exception_type.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "pl_exception_type.h"
#include "pl_package.h"
#include "plisql.h"

/*
 * Oracle error numbers that have a PostgreSQL counterpart.  A number listed
 * more than once is caught under all of its SQLSTATEs and raised with the
 * first one.  An SQLSTATE listed more than once reports the first number as
 * SQLCODE.
 */
typedef struct
{
	int			errnum;
	int			sqlerrstate;
} OraErrnumMap;

static const OraErrnumMap ora_errnum_map[] = {
	/* predefined exceptions of package STANDARD */
	{100, ERRCODE_NO_DATA_FOUND},	/* NO_DATA_FOUND */
	{-1, ERRCODE_UNIQUE_VIOLATION}, /* DUP_VAL_ON_INDEX */
	{-1001, ERRCODE_INVALID_CURSOR_STATE},	/* INVALID_CURSOR */
	{-1001, ERRCODE_UNDEFINED_CURSOR},
	{-1422, ERRCODE_TOO_MANY_ROWS}, /* TOO_MANY_ROWS */
	{-1476, ERRCODE_DIVISION_BY_ZERO},	/* ZERO_DIVIDE */
	{-6500, ERRCODE_OUT_OF_MEMORY}, /* STORAGE_ERROR */
	{-6501, ERRCODE_INTERNAL_ERROR},	/* PROGRAM_ERROR */
	{-6502, ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE},	/* VALUE_ERROR */
	{-6502, ERRCODE_STRING_DATA_RIGHT_TRUNCATION},
	{-6502, ERRCODE_INVALID_TEXT_REPRESENTATION},
	{-1722, ERRCODE_INVALID_TEXT_REPRESENTATION},	/* INVALID_NUMBER */
	{-6511, ERRCODE_DUPLICATE_CURSOR},	/* CURSOR_ALREADY_OPEN */
	{-6592, ERRCODE_CASE_NOT_FOUND},	/* CASE_NOT_FOUND */

	/* other errors */
	{-54, ERRCODE_LOCK_NOT_AVAILABLE},
	{-60, ERRCODE_T_R_DEADLOCK_DETECTED},
	{-904, ERRCODE_UNDEFINED_COLUMN},
	{-942, ERRCODE_UNDEFINED_TABLE},
	{-955, ERRCODE_DUPLICATE_TABLE},
	{-1013, ERRCODE_QUERY_CANCELED},
	{-1031, ERRCODE_INSUFFICIENT_PRIVILEGE},
	{-1400, ERRCODE_NOT_NULL_VIOLATION},
	{-1427, ERRCODE_CARDINALITY_VIOLATION},
	{-1438, ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE},
	{-2290, ERRCODE_CHECK_VIOLATION},
	{-2291, ERRCODE_FOREIGN_KEY_VIOLATION},
	{-2292, ERRCODE_FOREIGN_KEY_VIOLATION},
	{-8177, ERRCODE_T_R_SERIALIZATION_FAILURE},
	{-12899, ERRCODE_STRING_DATA_RIGHT_TRUNCATION},
	{0, 0}
};

/*
 * An Oracle error number without a PostgreSQL counterpart gets an SQLSTATE of
 * its own in class "O", which PostgreSQL does not use.  The absolute value of
 * the number is written in base 36 for the second character and base 35 for
 * the last three, which skip '0' so that the result is never mistaken for a
 * category code such as "O1000".  This covers every number down to -1000000.
 */
static const char sqlstate_digits[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

static int
errnum_to_oracle_class_sqlstate(int errnum)
{
	unsigned int value = (errnum < 0) ? -(unsigned int) errnum : errnum;
	char		chars[4];

	for (int i = 3; i > 0; i--)
	{
		chars[i] = sqlstate_digits[1 + value % 35];
		value /= 35;
	}
	Assert(value < 36);
	chars[0] = sqlstate_digits[value];

	return MAKE_SQLSTATE('O', chars[0], chars[1], chars[2], chars[3]);
}

static int
sqlstate_digit_value(char ch)
{
	if (ch >= '0' && ch <= '9')
		return ch - '0';
	if (ch >= 'A' && ch <= 'Z')
		return ch - 'A' + 10;
	return -1;
}

static bool
oracle_class_sqlstate_to_errnum(int sqlerrstate, int *errnum)
{
	int			value;
	int			digit;

	if (PGUNSIXBIT(sqlerrstate) != 'O')
		return false;

	value = sqlstate_digit_value(PGUNSIXBIT(sqlerrstate >> 6));
	if (value < 0)
		return false;

	for (int i = 2; i < 5; i++)
	{
		digit = sqlstate_digit_value(PGUNSIXBIT(sqlerrstate >> (6 * i)));
		if (digit < 1)
			return false;
		value = value * 35 + digit - 1;
	}

	*errnum = -value;
	return true;
}

/*
 * plisql_errnum_to_sqlstate
 *		Return the SQLSTATE that an Oracle error number is raised with
 */
int
plisql_errnum_to_sqlstate(int errnum)
{
	for (int i = 0; ora_errnum_map[i].errnum != 0; i++)
	{
		if (ora_errnum_map[i].errnum == errnum)
			return ora_errnum_map[i].sqlerrstate;
	}

	return errnum_to_oracle_class_sqlstate(errnum);
}

/*
 * plisql_sqlstate_to_errnum
 *		Return the Oracle error number (SQLCODE) for an SQLSTATE
 *
 * Errors raised by RAISE without an Oracle error number report 1, as Oracle
 * does for user-defined exceptions.  Other errors that have no Oracle error
 * number report the SQLSTATE in its packed integer form, which is positive:
 * Oracle uses positive numbers other than 1 and 100 for non-Oracle errors.
 */
int
plisql_sqlstate_to_errnum(int sqlerrstate)
{
	int			errnum;

	if (sqlerrstate == ERRCODE_RAISE_EXCEPTION)
		return 1;

	for (int i = 0; ora_errnum_map[i].errnum != 0; i++)
	{
		if (ora_errnum_map[i].sqlerrstate == sqlerrstate)
			return ora_errnum_map[i].errnum;
	}

	if (oracle_class_sqlstate_to_errnum(sqlerrstate, &errnum))
		return errnum;

	return sqlerrstate;
}

/*
 * plisql_exception_conditions
 *		Build the handler conditions that catch a user-defined exception
 *
 * An exception given an Oracle error number by PRAGMA EXCEPTION_INIT is
 * caught under every SQLSTATE that the number maps to.
 */
PLiSQL_condition *
plisql_exception_conditions(PLiSQL_exception_var *exc, char *condname)
{
	PLiSQL_condition *new;
	PLiSQL_condition *prev = NULL;

	for (int i = 0; ora_errnum_map[i].errnum != 0; i++)
	{
		if (ora_errnum_map[i].errnum != exc->sqlcode)
			continue;

		new = palloc_object(PLiSQL_condition);
		new->sqlerrstate = ora_errnum_map[i].sqlerrstate;
		new->condname = condname;
		new->next = prev;
		prev = new;
	}

	if (prev == NULL)
	{
		prev = palloc_object(PLiSQL_condition);
		prev->sqlerrstate = exc->sqlerrstate;
		prev->condname = condname;
		prev->next = NULL;
	}

	return prev;
}

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
	exc->sqlcode = 1;			/* Oracle's SQLCODE for user-defined exceptions */
	exc->sqlerrstate = ERRCODE_RAISE_EXCEPTION;
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
 *
 * A reference to a package exception from outside the package, such as
 * pkg.exc, is a package datum; return the package's exception variable.
 */
PLiSQL_exception_var *
plisql_datum_get_exception(PLiSQL_datum *datum)
{
	if (datum != NULL && datum->dtype == PLISQL_DTYPE_PACKAGE_DATUM)
		datum = ((PLiSQL_pkg_datum *) datum)->pkgvar;

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
	exc->sqlerrstate = plisql_errnum_to_sqlstate(sqlcode);
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

	printf("    EXCEPTION %s (dno %d, sqlcode %d, sqlstate %s, line %d)\n",
		   exc->refname, exc->dno, exc->sqlcode,
		   unpack_sql_state(exc->sqlerrstate), exc->lineno);
}
