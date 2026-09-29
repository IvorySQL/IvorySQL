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
#include "funcapi.h"
#include "utils/array.h"
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
	Datum		proallargtypes_datum;
	Datum		proargmodes_datum;
	bool		proallargtypes_null;
	bool		proargmodes_null;
	Oid		   *allargtypes;
	char	   *argmodes = NULL;	/* NULL means no OUT argument */
	int			numallargs;
	int			inidx = 0;
	int			i;

	initStringInfo(&sql);
	initStringInfo(&args);

	/* Get procedure/function name */
	proc_name = get_procedure_name(func->fn_oid);

	/* Get procedure info for argument types and return type */
	proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(func->fn_oid));
	if (!HeapTupleIsValid(proctup))
		elog(ERROR, "cache lookup failed for function %u", func->fn_oid);
	procstruct = (Form_pg_proc) GETSTRUCT(proctup);

	/*
	 * Determine if this is a function or procedure.  Check prokind rather
	 * than prorettype: a procedure with OUT/INOUT parameters has a non-void
	 * prorettype, but it still must be invoked with CALL, not SELECT.
	 */
	*is_function = (procstruct->prokind != PROKIND_PROCEDURE);

	/*
	 * For calls dispatched to an Oracle-mode session, every argument
	 * (including OUT arguments) must appear in the generated SQL, because
	 * the Oracle parser requires the full argument list.  OUT arguments are
	 * not passed through fcinfo (the executor hands them to the CALL
	 * statement separately), so emit NULL for them.  Functions never expose
	 * OUT arguments in the SELECT argument list, so only procedures need
	 * this treatment.
	 */
	numallargs = procstruct->pronargs;
	allargtypes = procstruct->proargtypes.values;
	if (!*is_function)
	{
		proallargtypes_datum = SysCacheGetAttr(PROCOID, proctup,
											   Anum_pg_proc_proallargtypes,
											   &proallargtypes_null);
		if (!proallargtypes_null)
		{
			ArrayType  *arr = DatumGetArrayTypeP(proallargtypes_datum);

			numallargs = ARR_DIMS(arr)[0];
			if (ARR_NDIM(arr) != 1 ||
				numallargs < procstruct->pronargs ||
				ARR_HASNULL(arr) ||
				ARR_ELEMTYPE(arr) != OIDOID)
				elog(ERROR, "proallargtypes is not a 1-D Oid array");
			allargtypes = (Oid *) ARR_DATA_PTR(arr);

			proargmodes_datum = SysCacheGetAttr(PROCOID, proctup,
											   Anum_pg_proc_proargmodes,
											   &proargmodes_null);
			if (!proargmodes_null)
			{
				arr = DatumGetArrayTypeP(proargmodes_datum);
				if (ARR_NDIM(arr) != 1 ||
					ARR_DIMS(arr)[0] != numallargs ||
					ARR_HASNULL(arr) ||
					ARR_ELEMTYPE(arr) != CHAROID)
					elog(ERROR, "proargmodes is not a 1-D char array of length %d",
						 numallargs);
				argmodes = (char *) ARR_DATA_PTR(arr);
			}
		}
	}

	/* Format arguments */
	for (i = 0; i < numallargs; i++)
	{
		bool		is_out = false;

		if (i > 0)
			appendStringInfoString(&args, ", ");

		/*
		 * Skip OUT-only arguments: their values are not carried by fcinfo,
		 * and the Oracle-mode session needs a placeholder in the call list.
		 */
		if (argmodes != NULL)
		{
			switch (argmodes[i])
			{
				case PROARGMODE_IN:
				case PROARGMODE_VARIADIC:
				case PROARGMODE_INOUT:
					break;
				case PROARGMODE_OUT:
				case PROARGMODE_TABLE:
					is_out = true;
					break;
				default:
					elog(ERROR, "invalid argmode %c for parameter %d",
						 argmodes[i], i + 1);
			}
		}

		if (is_out)
		{
			appendStringInfoString(&args, "NULL");
			continue;
		}

		/* Validate argument count */
		if (inidx >= fcinfo->nargs)
			elog(ERROR, "argument count mismatch: got %d, expected %d",
				 fcinfo->nargs, numallargs);

		if (fcinfo->args[inidx].isnull)
		{
			appendStringInfoString(&args, "NULL");
		}
		else
		{
			Oid			argtype = allargtypes[i];
			Oid			resolvedtype;
			Oid			typoutput;
			bool		typIsVarlena;
			char	   *valstr;

			/*
			 * Resolve polymorphic parameter types against the actual call
			 * argument.  pg_proc stores the declared type (e.g. anyelement)
			 * in proargtypes; the concrete type is only known from the call
			 * expression, if we have one.
			 */
			resolvedtype = get_fn_expr_argtype(fcinfo->flinfo, inidx);
			if (OidIsValid(resolvedtype))
				argtype = resolvedtype;

			getTypeOutputInfo(argtype, &typoutput, &typIsVarlena);
			valstr = OidOutputFunctionCall(typoutput, fcinfo->args[inidx].value);

			/*
			 * Serialize every value as a quoted literal with an explicit
			 * type cast.  This guarantees the text round-trips through the
			 * autonomous session's input function: unquoted numeric output is
			 * not a valid SQL literal for special values such as NaN or
			 * Infinity, and an explicit cast also forces the parser to pick
			 * the intended parameter type.
			 */
			appendStringInfoString(&args, quote_literal_cstr(valstr));
			appendStringInfo(&args, "::%s", format_type_be(argtype));
			pfree(valstr);
		}
		inidx++;
	}

	/* Build complete SQL - use SELECT for functions, CALL for procedures */
	if (*is_function)
	{
		/* Functions: use SELECT to capture return value */
		appendStringInfo(&sql,
			"SET ivorysql.compatible_mode = oracle; "
			"SET plisql.inside_autonomous_transaction = true; "
			"SELECT %s(%s);",
			proc_name,
			args.data);
	}
	else
	{
		/* Procedures: use CALL (no return value) */
		appendStringInfo(&sql,
			"SET ivorysql.compatible_mode = oracle; "
			"SET plisql.inside_autonomous_transaction = true; "
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
 * Retrieve the cached OID of the dblink() function, resolving it via the
 * extension schema on first use.
 *
 * @returns OID of dblink(text, text); errors if the dblink extension is missing.
 */
static Oid
get_dblink_oid(void)
{
	if (!OidIsValid(dblink_oid))
	{
		Oid			argtypes[2] = {TEXTOID, TEXTOID};
		Oid			oid;

		oid = LookupFuncName(list_make1(makeString("dblink")), 2, argtypes, true);
		if (!OidIsValid(oid))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_FUNCTION),
					 errmsg("dblink function not found"),
					 errhint("Install dblink extension: CREATE EXTENSION dblink")));
		dblink_oid = oid;
	}
	return dblink_oid;
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

	/* Make sure dblink is installed before building the query */
	(void) get_dblink_oid();

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
 * Execute an autonomous procedure that returns a record via dblink() and SPI.
 *
 * A CALL of a procedure with OUT/INOUT parameters returns a record, which
 * dblink_exec() refuses to run ("statement returning results not allowed").
 * Run the CALL through dblink() instead and pass the returned output values
 * back to the caller.
 *
 * @param connstr libpq connection string for the autonomous session
 * @param sql The SET-updated CALL statement to execute
 * @param funcoid OID of the procedure (used to derive the OUT column types)
 * @param fcinfo Call context whose expected result row type supplies the
 *               shape of the record to build
 * @return The record Datum containing the procedure's output values.  The
 *         result is never NULL for a successfully completed procedure.
 */
static Datum
execute_autonomous_procedure(char *connstr, char *sql, Oid funcoid,
							 FunctionCallInfo fcinfo)
{
	HeapTuple	proctup;
	Datum		proallargtypes_datum;
	Datum		proargmodes_datum;
	bool		allargtypes_null;
	bool		argmodes_null;
	ArrayType  *arr;
	int			numargs;
	Oid		   *allargtypes;
	char	   *argmodes;
	StringInfoData outcols;
	char	   *query;
	Oid			resultTypeId;
	TupleDesc	tupdesc;
	Datum	   *values;
	bool	   *nulls;
	HeapTuple	tuple;
	HeapTupleHeader tuphdr;
	Datum		result;
	MemoryContext oldcontext;
	int			ret;
	bool		spi_connected = false;
	bool		first = true;
	int			nout = 0;
	int			i;

	/* Make sure dblink is installed before building the query */
	(void) get_dblink_oid();

	initStringInfo(&outcols);

	proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcoid));
	if (!HeapTupleIsValid(proctup))
		elog(ERROR, "cache lookup failed for function %u", funcoid);

	/* A record-returning procedure must have proallargtypes/proargmodes */
	proallargtypes_datum = SysCacheGetAttr(PROCOID, proctup,
										   Anum_pg_proc_proallargtypes,
										   &allargtypes_null);
	if (allargtypes_null)
		elog(ERROR, "procedure %u has no proallargtypes", funcoid);
	proargmodes_datum = SysCacheGetAttr(PROCOID, proctup,
									   Anum_pg_proc_proargmodes,
									   &argmodes_null);
	if (argmodes_null)
		elog(ERROR, "procedure %u has no proargmodes", funcoid);

	arr = DatumGetArrayTypeP(proallargtypes_datum);
	numargs = ARR_DIMS(arr)[0];
	if (ARR_NDIM(arr) != 1 ||
		ARR_HASNULL(arr) ||
		ARR_ELEMTYPE(arr) != OIDOID)
		elog(ERROR, "proallargtypes is not a 1-D Oid array");
	allargtypes = (Oid *) ARR_DATA_PTR(arr);

	arr = DatumGetArrayTypeP(proargmodes_datum);
	if (ARR_NDIM(arr) != 1 ||
		ARR_DIMS(arr)[0] != numargs ||
		ARR_HASNULL(arr) ||
		ARR_ELEMTYPE(arr) != CHAROID)
		elog(ERROR, "proargmodes is not a 1-D char array of length %d",
			 numargs);
	argmodes = (char *) ARR_DATA_PTR(arr);

	ReleaseSysCache(proctup);

	/*
	 * Declare one column per OUT/INOUT argument, in declaration order, so
	 * that dblink can materialize the record returned by CALL.
	 */
	for (i = 0; i < numargs; i++)
	{
		if (argmodes[i] != PROARGMODE_OUT &&
			argmodes[i] != PROARGMODE_INOUT)
			continue;
		if (!first)
			appendStringInfoString(&outcols, ", ");
		appendStringInfo(&outcols, "c%d %s", i + 1,
						 format_type_be(allargtypes[i]));
		first = false;
		nout++;
	}
	if (first)
		elog(ERROR, "procedure %u has no output parameters", funcoid);

	query = psprintf("SELECT * FROM dblink(%s, %s) AS t(%s)",
					 quote_literal_cstr(connstr),
					 quote_literal_cstr(sql),
					 outcols.data);
	pfree(outcols.data);

	/* Execute via SPI with proper error handling */
	PG_TRY();
	{
		/* Connect to SPI */
		ret = SPI_connect();
		if (ret < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("could not connect to SPI for autonomous procedure execution"),
					 errdetail("SPI_connect returned %d", ret)));
		spi_connected = true;

		/* Execute the query and read the returned output-parameter row */
		ret = SPI_execute(query, true, 1);
		if (ret != SPI_OK_SELECT)
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("autonomous procedure execution failed"),
					 errdetail("SPI_execute returned %d", ret)));
		if (SPI_processed != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("autonomous procedure returned unexpected number of rows: %lu",
							(unsigned long) SPI_processed)));

		/*
		 * Build the return record in the shape the CALL statement expects,
		 * mapping the remote output columns positionally.
		 */
		if (get_call_result_type(fcinfo, &resultTypeId, &tupdesc) !=
			TYPEFUNC_COMPOSITE)
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("could not determine the result row type of autonomous procedure %u",
							funcoid)));
		if (tupdesc->natts != nout ||
			tupdesc->natts != SPI_tuptable->tupdesc->natts)
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("autonomous procedure output column count mismatch")));

		values = palloc(sizeof(Datum) * tupdesc->natts);
		nulls = palloc(sizeof(bool) * tupdesc->natts);
		for (i = 0; i < tupdesc->natts; i++)
			values[i] = SPI_getbinval(SPI_tuptable->vals[0],
									  SPI_tuptable->tupdesc,
									  i + 1,
									  &nulls[i]);

		/*
		 * Copy the tuple into the caller's memory context before SPI_finish
		 * frees the SPI tuplestore.
		 */
		oldcontext = MemoryContextSwitchTo(fcinfo->flinfo->fn_mcxt);
		tuple = heap_form_tuple(tupdesc, values, nulls);
		MemoryContextSwitchTo(oldcontext);

		tuphdr = (HeapTupleHeader) tuple->t_data;
		HeapTupleHeaderSetTypeId(tuphdr, tupdesc->tdtypeid);
		HeapTupleHeaderSetTypMod(tuphdr, tupdesc->tdtypmod);
		result = HeapTupleGetDatum(tuple);

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

	return result;
}

/**
 * Execute a PL/iSQL function or procedure in an autonomous transaction.
 *
 * For procedures (VOID return), dispatches a CALL statement via dblink_exec().
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
	StringInfoData connstr_buf;
	const char *port_str;
	const char *host_str;
	char *dbname;
	Datum connstr_datum;
	Datum sql_datum;
	Datum result_datum;
	Datum result;
	char *result_str;
	Oid dblink_exec_oid_local;
	bool is_function;
	HeapTuple proctup;
	Form_pg_proc procstruct;
	Oid rettype;

	/* Lookup dblink_exec function if not cached */
	if (!OidIsValid(dblink_exec_oid))
	{
		Oid argtypes[2] = {TEXTOID, TEXTOID};
		dblink_exec_oid_local = LookupFuncName(list_make1(makeString("dblink_exec")), 2, argtypes, true);
		if (!OidIsValid(dblink_exec_oid_local))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_FUNCTION),
					 errmsg("dblink_exec function not found"),
					 errhint("Install dblink extension: CREATE EXTENSION dblink")));
		dblink_exec_oid = dblink_exec_oid_local;
	}

	/* Get current database name dynamically */
	dbname = get_current_database();

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
	port_str = GetConfigOption("port", false, false);
	initStringInfo(&connstr_buf);

	/* Append dbname with single-quote escaping for libpq */
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

	connstr = connstr_buf.data;

	/* Execute based on whether this is a function or procedure */
	if (is_function)
	{
		/* Function: use dblink() with SPI to capture return value */
		PG_TRY();
		{
			result = execute_autonomous_function(connstr, sql, rettype, fcinfo);
		}
		PG_CATCH();
		{
			/* Clean up and re-throw */
			pfree(connstr_buf.data);
			pfree(sql);
			pfree(dbname);
			PG_RE_THROW();
		}
		PG_END_TRY();

		/* Clean up */
		pfree(connstr_buf.data);
		pfree(sql);
		pfree(dbname);

		return result;
	}
	else
	{
		/*
		 * Procedure with OUT/INOUT parameters: CALL returns a record, which
		 * dblink_exec() cannot handle.  Run it through dblink() and discard
		 * the output-parameter row.
		 */
		if (rettype != VOIDOID)
		{
			PG_TRY();
			{
				result = execute_autonomous_procedure(connstr, sql, func->fn_oid, fcinfo);
			}
			PG_CATCH();
			{
				/* Clean up and re-throw */
				pfree(connstr_buf.data);
				pfree(sql);
				pfree(dbname);
				PG_RE_THROW();
			}
			PG_END_TRY();

			/* Clean up */
			pfree(connstr_buf.data);
			pfree(sql);
			pfree(dbname);

			/*
			 * The record carrying the output values was built in the caller's
			 * memory context, so it survives; hand it back to the CALL
			 * statement.
			 */
			fcinfo->isnull = false;
			return result;
		}

		/* Procedure: use dblink_exec() - no return value */
		connstr_datum = CStringGetTextDatum(connstr);
		sql_datum = CStringGetTextDatum(sql);

		PG_TRY();
		{
			result_datum = OidFunctionCall2(dblink_exec_oid, connstr_datum, sql_datum);
			result_str = TextDatumGetCString(result_datum);
			pfree(result_str);  /* Result is typically "OK" or similar */
		}
		PG_CATCH();
		{
			/* Clean up and re-throw */
			pfree(connstr_buf.data);
			pfree(sql);
			pfree(dbname);
			PG_RE_THROW();
		}
		PG_END_TRY();

		/* Clean up */
		pfree(connstr_buf.data);
		pfree(sql);
		pfree(dbname);

		/* Procedures return NULL */
		fcinfo->isnull = true;
		return (Datum) 0;
	}
}
