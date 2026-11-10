/*-------------------------------------------------------------------------
 *
 * pl_autonomous.c
 *	  Autonomous transaction support for PL/iSQL
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "catalog/pg_extension.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "commands/extension.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "libpq/libpq-be.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "parser/parse_func.h"
#include "parser/parse_type.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/guc.h"
#include "utils/inval.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"

#include "plisql.h"
#include "pl_autonomous.h"

static Oid	dblink_exec_oid = InvalidOid;
static Oid	dblink_oid = InvalidOid;
static Oid	dblink_connect_oid = InvalidOid;
static Oid	dblink_disconnect_oid = InvalidOid;

/**
 * Reset the cached dblink_exec OID when the pg_proc catalog changes.
 *
 * This invalidation callback clears the module-level cache so the dblink_exec
 * function OID will be looked up again on next use.
 *
 * @param arg Unused callback argument passed by the syscache infrastructure.
 * @param cacheid Syscache identifier for the cache that signaled the invalidation.
 * @param hashvalue Hash value associated with the cache event (unused).
 */
static void
dblink_oid_invalidation_callback(Datum arg, int cacheid, uint32 hashvalue)
{
	/* Reset the cached OIDs so they will be looked up again next time */
	dblink_exec_oid = InvalidOid;
	dblink_oid = InvalidOid;
	dblink_connect_oid = InvalidOid;
	dblink_disconnect_oid = InvalidOid;
}

/**
 * Initialize support for autonomous transactions in PL/iSQL.
 *
 * Registers a syscache invalidation callback so the cached OID for
 * dblink_exec is reset when pg_proc changes.
 */
void
plisql_autonomous_init(void)
{
	/* Register callback to invalidate cached dblink_exec OID on pg_proc changes */
	CacheRegisterSyscacheCallback(PROCOID, dblink_oid_invalidation_callback, (Datum) 0);
}

/**
 * Retrieve a duplicated copy of the current database name from the backend connection port.
 *
 * Errors if not running in a client backend or if the connection's database name is unavailable.
 *
 * @return A newly allocated, null-terminated string containing the current database name.
 *         The string is allocated with pstrdup in the current memory context.
 *
 * @throws ERROR when MyProcPort is NULL (not a client backend) or when MyProcPort->database_name is NULL.
 */
static char *
get_current_database(void)
{
	/*
	 * Get database name from MyProcPort structure.
	 * This is safe - no catalog access needed, just reading from
	 * the connection's Port structure.
	 *
	 * MyProcPort is set during backend startup and should always be
	 * available in a normal client backend. If it's NULL, we're in
	 * an unexpected context (e.g., background worker, standalone mode).
	 */
	if (MyProcPort == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("autonomous transactions cannot run in background processes"),
				 errdetail("MyProcPort is NULL - not a client backend")));

	if (MyProcPort->database_name == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("database name not available in connection info"),
				 errdetail("MyProcPort->database_name is NULL")));

	return pstrdup(MyProcPort->database_name);
}

/**
 * Construct the schema-qualified, quoted name of the function identified by the given OID.
 *
 * @param funcoid OID of the target function.
 * @returns A palloc'd string containing the schema-qualified, quoted function name (e.g. "schema"."function").
 *          Caller is responsible for freeing the returned string with pfree.
 * @throws ERROR if the pg_proc cache lookup for the given OID fails.
 */
static char *
get_procedure_name(Oid funcoid)
{
	HeapTuple proctup;
	Form_pg_proc procstruct;
	char *procname;
	char *nspname;
	char *result;

	proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcoid));
	if (!HeapTupleIsValid(proctup))
		elog(ERROR, "cache lookup failed for function %u", funcoid);

	procstruct = (Form_pg_proc) GETSTRUCT(proctup);
	procname = NameStr(procstruct->proname);

	/* Get schema name for fully qualified name */
	nspname = get_namespace_name(procstruct->pronamespace);
	if (nspname == NULL)
	{
		Oid nspoid = procstruct->pronamespace;
		ReleaseSysCache(proctup);
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_SCHEMA),
				 errmsg("schema for function \"%s\" (OID %u) was dropped concurrently",
						procname, funcoid),
				 errdetail("Schema OID %u no longer exists.", nspoid)));
	}

	/* Build schema-qualified name */
	result = psprintf("%s.%s", quote_identifier(nspname), quote_identifier(procname));

	ReleaseSysCache(proctup);
	pfree(nspname);
	return result;
}

/**
 * Mark a PL/pgPLiSQL function or procedure as an autonomous transaction.
 *
 * Validates that the pragma appears inside a function/procedure and that the
 * function is not already marked autonomous; on validation failure a syntax
 * error is reported using the provided parse location and scanner context.
 *
 * @param func The PLiSQL function object to mark; must be non-NULL.
 * @param location Parse location used to produce an error cursor for diagnostics.
 * @param yyscanner Scanner state used to produce an error cursor for diagnostics.
 */
void
plisql_mark_autonomous_transaction(PLiSQL_function *func, int location, void *yyscanner)
{
	if (func == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("PRAGMA AUTONOMOUS_TRANSACTION must be inside a function or procedure"),
				 plisql_scanner_errposition(location, yyscanner)));

	if (func->fn_is_autonomous)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("duplicate PRAGMA AUTONOMOUS_TRANSACTION"),
				 plisql_scanner_errposition(location, yyscanner)));

	/*
	 * Don't check for dblink availability at procedure creation time.
	 * Check it at execution time instead. This avoids crashes during
	 * CREATE PROCEDURE when dblink might not be accessible yet.
	 */

	func->fn_is_autonomous = true;
}

/**
 * Check whether the dblink extension is installed in the current database.
 *
 * @returns `true` if the dblink extension is installed in the current database, `false` otherwise.
 */
bool
plisql_check_dblink_available(void)
{
	return OidIsValid(get_extension_oid("dblink", true));
}

/*
 * Name of the short-lived named dblink connection the autonomous-transaction
 * transport uses for statements that may end their own transaction.
 */
#define AUTONOMOUS_CONN_NAME "plisql_autonomous_txn"

/**
 * Build the connection string of the autonomous session: the current
 * database, on localhost and the port this backend listens on.
 *
 * @returns A palloc'd, libpq-safe connection string.  The caller frees it.
 */
static char *
build_autonomous_connstr(void)
{
	StringInfoData connstr_buf;
	const char *port_str;
	const char *host_str;
	char	   *dbname;

	/* Get current database name dynamically */
	dbname = get_current_database();

	/* Build connection string with libpq-safe quoting */
	port_str = GetConfigOption("port", false, false);
	initStringInfo(&connstr_buf);
	appendStringInfoString(&connstr_buf, "dbname='");
	for (const char *p = dbname; *p; p++)
	{
		if (*p == '\'' || *p == '\\')
			appendStringInfoChar(&connstr_buf, '\\');
		appendStringInfoChar(&connstr_buf, *p);
	}
	appendStringInfoChar(&connstr_buf, '\'');

	/* Add host if configured */
	host_str = GetConfigOption("listen_addresses", false, false);
	if (host_str && strcmp(host_str, "*") != 0 && strcmp(host_str, "") != 0)
	{
		/* Use localhost for local connections */
		appendStringInfoString(&connstr_buf, " host=localhost");
	}

	/* Add port if configured */
	if (port_str)
		appendStringInfo(&connstr_buf, " port=%s", port_str);

	pfree(dbname);
	return connstr_buf.data;
}

/*
 * Look up one of dblink's support functions; ereport with the standard
 * hint when the extension is not installed.
 */
static Oid
lookup_dblink_function(const char *funcname, int nargs, const Oid *argtypes)
{
	Oid			funcoid;

	funcoid = LookupFuncName(list_make1(makeString((char *) funcname)),
							 nargs, argtypes, true);
	if (!OidIsValid(funcoid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_FUNCTION),
				 errmsg("%s function not found", funcname),
				 errhint("Install dblink extension: CREATE EXTENSION dblink")));
	return funcoid;
}

/**
 * Disconnect the private named connection, ignoring any error (the
 * connection may not exist).  Kept in its own function so the PG_TRY does
 * not nest inside another one in the caller.
 */
static void
autonomous_conn_disconnect(Oid disconnect_oid)
{
	PG_TRY();
	{
		(void) OidFunctionCall1(disconnect_oid,
								CStringGetTextDatum(AUTONOMOUS_CONN_NAME));
	}
	PG_CATCH();
	{
		FlushErrorState();
	}
	PG_END_TRY();
}

/**
 * Run one statement in an autonomous session, with the session's GUCs set
 * up by separate statements.
 *
 * The statement is sent as the ONLY statement of its simple-query string.
 * That matters: a multi-statement string would put the far backend into an
 * implicit transaction block, which forces an atomic execution context,
 * and COMMIT/ROLLBACK inside an autonomous routine would then fail with
 * "invalid transaction termination".  As a single statement, the far
 * routine runs non-atomically and can end its own transaction, exactly
 * like an autonomous routine can in Oracle.
 *
 * A short-lived named connection carries the session GUCs between the
 * statements: connect, SET compatible_mode, SET the recursion guard, run
 * the statement, disconnect.  The name is private to this transport; a
 * leftover connection under that name (only possible after a hard error
 * between the steps) is disconnected best-effort first.
 *
 * @param sql The single SQL statement to run in the autonomous session.
 */
static void
autonomous_session_exec(const char *sql)
{
	char	   *connstr;
	Oid			connect_oid;
	Oid			exec_oid;
	Oid			disconnect_oid;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};

	/*
	 * Look up the dblink functions we need.  Each OID is cached and checked
	 * independently: a failed lookup must not leave the others set while
	 * some are still invalid (an enclosing PL/iSQL exception handler could
	 * recover from the error, and the next call would then skip the missing
	 * lookups and call into an invalid OID).
	 */
	if (!OidIsValid(dblink_exec_oid))
		dblink_exec_oid = lookup_dblink_function("dblink_exec", 2, argtypes);
	if (!OidIsValid(dblink_connect_oid))
		dblink_connect_oid = lookup_dblink_function("dblink_connect", 2, argtypes);
	if (!OidIsValid(dblink_disconnect_oid))
		dblink_disconnect_oid = lookup_dblink_function("dblink_disconnect", 1, argtypes);
	connect_oid = dblink_connect_oid;
	exec_oid = dblink_exec_oid;
	disconnect_oid = dblink_disconnect_oid;

	connstr = build_autonomous_connstr();

	/* Best effort: drop a leftover connection under our private name */
	autonomous_conn_disconnect(disconnect_oid);

	PG_TRY();
	{
		(void) OidFunctionCall2(connect_oid,
								CStringGetTextDatum(AUTONOMOUS_CONN_NAME),
								CStringGetTextDatum(connstr));

		(void) OidFunctionCall2(exec_oid,
								CStringGetTextDatum(AUTONOMOUS_CONN_NAME),
								CStringGetTextDatum("SET ivorysql.compatible_mode = oracle"));

		(void) OidFunctionCall2(exec_oid,
								CStringGetTextDatum(AUTONOMOUS_CONN_NAME),
								CStringGetTextDatum("SET plisql.inside_autonomous_transaction = true"));

		(void) OidFunctionCall2(exec_oid,
								CStringGetTextDatum(AUTONOMOUS_CONN_NAME),
								CStringGetTextDatum(sql));
	}
	PG_FINALLY();
	{
		/* Always release the named connection again */
		autonomous_conn_disconnect(disconnect_oid);
	}
	PG_END_TRY();

	pfree(connstr);
}

/**
 * Run an anonymous code block (DO) that carries PRAGMA AUTONOMOUS_TRANSACTION
 * in its own session.
 *
 * A DO block has no catalog entry that another session could re-invoke by
 * name, so the whole source text is shipped to the autonomous session and
 * re-run there.  The far session is told it is already inside an autonomous
 * transaction (the recursion guard the named-routine path uses as well), so
 * the far copy of the block executes inline in the far session's own
 * transaction: its COMMIT/ROLLBACK end only that transaction, and the
 * caller's transaction is untouched.
 *
 * @param source_text The source text of the anonymous block, exactly as the
 *        DO statement received it (including the PRAGMA in the declaration
 *        section).
 */
void
plisql_exec_autonomous_do(const char *source_text)
{
	StringInfoData sql;

	initStringInfo(&sql);
	appendStringInfoString(&sql, "DO LANGUAGE plisql ");
	appendStringInfoString(&sql, quote_literal_cstr(source_text));

	autonomous_session_exec(sql.data);

	pfree(sql.data);
}

/**
 * Construct the SQL statement that invokes the specified function/procedure inside an autonomous session.
 *
 * Formats and quotes each argument according to its SQL type and wraps the call with session-local
 * settings required for autonomous execution. For functions (non-VOID return type), builds a SELECT
 * statement; for procedures (VOID return), builds a CALL statement.
 *
 * @param func The PL/pgSQL function descriptor representing the target function/procedure.
 * @param fcinfo The FunctionCallInfo containing the actual call arguments to be formatted.
 * @param is_function Output parameter set to true if this is a function, false if procedure.
 * @return A palloc'd null-terminated C string containing the complete SQL statement to execute
 *         (including mode/flag settings and the SELECT/CALL invocation). The caller is
 *         responsible for freeing the returned string with pfree.
 */
static char *
build_autonomous_call(PLiSQL_function *func, FunctionCallInfo fcinfo, bool *is_function)
{
	StringInfoData sql;
	StringInfoData args;
	char *proc_name;
	HeapTuple proctup;
	Form_pg_proc procstruct;
	int i;

	initStringInfo(&sql);
	initStringInfo(&args);

	/* Get procedure/function name */
	proc_name = get_procedure_name(func->fn_oid);

	/* Get procedure info for argument types and return type */
	proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(func->fn_oid));
	if (!HeapTupleIsValid(proctup))
		elog(ERROR, "cache lookup failed for function %u", func->fn_oid);
	procstruct = (Form_pg_proc) GETSTRUCT(proctup);

	/* Determine if this is a function (returns value) or procedure (void) */
	*is_function = (procstruct->prorettype != VOIDOID);

	/* Validate argument count */
	if (fcinfo->nargs > procstruct->pronargs)
		elog(ERROR, "argument count mismatch: got %d, expected %d",
			 fcinfo->nargs, procstruct->pronargs);

	/* Format arguments */
	for (i = 0; i < fcinfo->nargs; i++)
	{
		if (i > 0)
			appendStringInfoString(&args, ", ");

		if (fcinfo->args[i].isnull)
		{
			appendStringInfoString(&args, "NULL");
		}
		else
		{
			Oid argtype = procstruct->proargtypes.values[i];
			Oid typoutput;
			bool typIsVarlena;
			char *valstr;

			getTypeOutputInfo(argtype, &typoutput, &typIsVarlena);
			valstr = OidOutputFunctionCall(typoutput, fcinfo->args[i].value);

			/* Format based on type */
			switch (argtype)
			{
				case INT2OID:
				case INT4OID:
				case INT8OID:
				case FLOAT4OID:
				case FLOAT8OID:
				case NUMERICOID:
				case OIDOID:
					/* Numeric types don't need quoting */
					appendStringInfoString(&args, valstr);
					break;
				case BOOLOID:
					/* Convert 't'/'f' to 'true'/'false' for SQL */
					if (DatumGetBool(fcinfo->args[i].value))
						appendStringInfoString(&args, "true");
					else
						appendStringInfoString(&args, "false");
					break;
				default:
					/* Quote string literals and other types */
					appendStringInfoString(&args, quote_literal_cstr(valstr));
					break;
			}
			pfree(valstr);
		}
	}

	/* Build complete SQL - use SELECT for functions, CALL for procedures.
	 * Only the invocation itself: the session settings are applied by the
	 * transport (a separate statement prefix for functions, dedicated
	 * statements on a named connection for procedures and DO blocks, which
	 * must not share a query string with anything else, see
	 * autonomous_session_exec).
	 */
	if (*is_function)
	{
		/* Functions: use SELECT to capture return value */
		appendStringInfo(&sql,
			"SELECT %s(%s);",
			proc_name,
			args.data);
	}
	else
	{
		/* Procedures: use CALL (no return value) */
		appendStringInfo(&sql,
			"CALL %s(%s);",
			proc_name,
			args.data);
	}

	ReleaseSysCache(proctup);
	pfree(proc_name);
	pfree(args.data);  /* Free args buffer after building SQL */

	return sql.data;
}

/**
 * Execute an autonomous function (that returns a value) using dblink() and SPI.
 *
 * @param connstr libpq connection string for dblink
 * @param sql SQL SELECT statement to execute
 * @param rettype OID of the return type
 * @param fcinfo Function call info (used to set isnull)
 * @return The return value from the autonomous function
 */
static Datum
execute_autonomous_function(char *connstr, char *sql, Oid rettype, FunctionCallInfo fcinfo)
{
	char *query;
	int ret;
	Datum result;
	bool isnull;
	int16 typlen;
	bool typbyval;
	MemoryContext oldcontext;
	bool spi_connected = false;

	/* Look up dblink() function if not cached */
	if (!OidIsValid(dblink_oid))
	{
		Oid argtypes[2] = {TEXTOID, TEXTOID};
		dblink_oid = LookupFuncName(list_make1(makeString("dblink")), 2, argtypes, true);
		if (!OidIsValid(dblink_oid))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_FUNCTION),
					 errmsg("dblink function not found"),
					 errhint("Install dblink extension: CREATE EXTENSION dblink")));
	}

	/* Build query: SELECT * FROM dblink('connstr', 'sql') AS t(result rettype) */
	query = psprintf("SELECT * FROM dblink(%s, %s) AS t(result %s)",
					 quote_literal_cstr(connstr),
					 quote_literal_cstr(sql),
					 format_type_be(rettype));

	/* Execute via SPI with proper error handling */
	PG_TRY();
	{
		/* Connect to SPI */
		ret = SPI_connect();
		if (ret < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("could not connect to SPI for autonomous function execution"),
					 errdetail("SPI_connect returned %d", ret)));
		spi_connected = true;

		/* Execute the query */
		ret = SPI_execute(query, true, 1);
		if (ret != SPI_OK_SELECT)
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("autonomous function execution failed"),
					 errdetail("SPI_execute returned %d", ret)));

		if (SPI_processed != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("autonomous function returned unexpected number of rows: %lu",
							(unsigned long) SPI_processed)));

		/* Extract return value from result */
		result = SPI_getbinval(SPI_tuptable->vals[0],
							  SPI_tuptable->tupdesc,
							  1,
							  &isnull);

		/* Get type information for datumCopy */
		get_typlenbyval(rettype, &typlen, &typbyval);

		/*
		 * Copy result to function's memory context before SPI_finish frees SPI memory.
		 * For pass-by-reference types, switch to the caller's context to ensure the
		 * copied data survives after SPI_finish().
		 */
		if (!isnull && !typbyval)
		{
			oldcontext = MemoryContextSwitchTo(fcinfo->flinfo->fn_mcxt);
			result = datumCopy(result, typbyval, typlen);
			MemoryContextSwitchTo(oldcontext);
		}

		SPI_finish();
	}
	PG_CATCH();
	{
		/* Clean up on error */
		if (spi_connected)
			SPI_finish();
		pfree(query);
		PG_RE_THROW();
	}
	PG_END_TRY();

	pfree(query);

	fcinfo->isnull = isnull;
	return result;
}

/**
 * Execute a PL/iSQL function or procedure in an autonomous transaction.
 *
 * For procedures (VOID return), runs the CALL statement as the only
 * statement of a short-lived autonomous session, so the procedure can end
 * its own transaction (COMMIT/ROLLBACK).
 * For functions (non-VOID return), dispatches a SELECT statement via dblink() and SPI
 * to capture the return value.
 *
 * @param func PLiSQL function object to invoke in the autonomous transaction.
 * @param fcinfo Call context carrying the function's argument values and result slot.
 * @param simple_eval_estate Evaluation estate used for simple-eval execution (passed through).
 * @param simple_eval_resowner Resource owner used for simple-eval execution (passed through).
 * @returns For functions: the return value. For procedures: NULL Datum with fcinfo->isnull = true.
 */
Datum
plisql_exec_autonomous_function(PLiSQL_function *func, FunctionCallInfo fcinfo,
								EState *simple_eval_estate, ResourceOwner simple_eval_resowner)
{
	char *sql;
	char *connstr;
	Datum result;
	bool is_function;
	HeapTuple proctup;
	Form_pg_proc procstruct;
	Oid rettype;

	/* Get return type to determine if this is a function or procedure */
	proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(func->fn_oid));
	if (!HeapTupleIsValid(proctup))
		elog(ERROR, "cache lookup failed for function %u", func->fn_oid);
	procstruct = (Form_pg_proc) GETSTRUCT(proctup);
	rettype = procstruct->prorettype;
	ReleaseSysCache(proctup);

	/* Build SQL - will be SELECT for functions, CALL for procedures */
	sql = build_autonomous_call(func, fcinfo, &is_function);

	/* Build connection string with libpq-safe quoting */
	connstr = build_autonomous_connstr();

	/* Execute based on whether this is a function or procedure */
	if (is_function)
	{
		/*
		 * Function: use dblink() with SPI to capture the return value.  A
		 * function cannot end its caller's transaction anyway, so the
		 * session settings can share the query string with the SELECT.
		 */
		StringInfoData fullsql;

		initStringInfo(&fullsql);
		appendStringInfoString(&fullsql,
							   "SET ivorysql.compatible_mode = oracle; "
							   "SET plisql.inside_autonomous_transaction = true; ");
		appendStringInfoString(&fullsql, sql);

		PG_TRY();
		{
			result = execute_autonomous_function(connstr, fullsql.data, rettype, fcinfo);
		}
		PG_CATCH();
		{
			/* Clean up and re-throw */
			pfree(fullsql.data);
			pfree(connstr);
			pfree(sql);
			PG_RE_THROW();
		}
		PG_END_TRY();

		/* Clean up */
		pfree(fullsql.data);
		pfree(connstr);
		pfree(sql);

		return result;
	}
	else
	{
		/*
		 * Procedure: run the CALL as the only statement of an autonomous
		 * session, so that an explicit COMMIT/ROLLBACK inside the procedure
		 * ends only that session's transaction instead of failing with
		 * "invalid transaction termination".
		 */
		PG_TRY();
		{
			autonomous_session_exec(sql);
		}
		PG_CATCH();
		{
			/* Clean up and re-throw */
			pfree(connstr);
			pfree(sql);
			PG_RE_THROW();
		}
		PG_END_TRY();

		/* Clean up */
		pfree(connstr);
		pfree(sql);

		/* Procedures return NULL */
		fcinfo->isnull = true;
		return (Datum) 0;
	}
}
