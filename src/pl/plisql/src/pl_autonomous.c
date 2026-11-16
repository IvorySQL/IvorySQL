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
#include "catalog/pg_package.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "commands/extension.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "libpq/libpq-be.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "parser/parse_func.h"
#include "parser/parse_type.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/guc.h"
#include "utils/inval.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"

#include "plisql.h"
#include "pl_package.h"
#include "pl_subproc_function.h"
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
 * Resolve the PLiSQL_subproc_function descriptor of the callee of an
 * internal (non-pg_proc) dispatch FuncExpr.
 *
 * @param funcexpr The dispatch FuncExpr.
 * @returns The callee's descriptor; NULL when the dispatch is inconsistent.
 */
static PLiSQL_subproc_function *
get_dispatched_subproc(FuncExpr *funcexpr)
{
	PLiSQL_function *pfunc = (PLiSQL_function *) funcexpr->parent_func;

	if (pfunc == NULL)
		return NULL;

	if (funcexpr->funcid < 0 || funcexpr->funcid >= pfunc->nsubprocfuncs)
		return NULL;

	return pfunc->subprocfuncs[funcexpr->funcid];
}

/**
 * Find the position of a package member's descriptor in the owning
 * package's subprogram list.
 *
 * @param psource The owning package.
 * @param subprocfunc The member's descriptor.
 * @returns The member's index, or -1 when the descriptor does not belong
 *          to the package's own subprograms (for example a subprogram
 *          nested inside one of its members).
 */
static int
find_pkg_member_index(PLiSQL_package *psource,
					  PLiSQL_subproc_function *subprocfunc)
{
	PLiSQL_function *pfunc = &psource->source;
	int			i;

	for (i = 0; i < pfunc->nsubprocfuncs; i++)
	{
		if (pfunc->subprocfuncs[i] == subprocfunc)
			return i;
	}

	return -1;
}

/**
 * Recognize the invocation of a package member that carries
 * PRAGMA AUTONOMOUS_TRANSACTION.
 *
 * Package members have no pg_proc entry (the package itself owns a single
 * entry in pg_package), so their invocation is dispatched through one of
 * the internal dispatch kinds with a synthesized FmgrInfo whose fn_oid
 * carries the callee's index within its owner rather than a pg_proc OID.
 * The "real call" fn_oid equality test in plisql_exec_function() therefore
 * never fires for them; recognize the dispatch through its FuncExpr
 * instead.
 *
 * The callee is a package member when its subprogram descriptor is one of
 * the owning package's own entries.  Subprograms nested inside a member,
 * and the package's own initialization block, are not members: they have
 * no name another session could call.
 *
 * @param func The PL/iSQL function descriptor of the callee.
 * @param fcinfo The FunctionCallInfo of the invocation.
 * @returns true when this is a real call of a subprogram declared in a
 *          package and marked autonomous.
 */
bool
plisql_pkg_member_autonomous_call(PLiSQL_function *func, FunctionCallInfo fcinfo)
{
	FuncExpr   *funcexpr;
	PLiSQL_package *psource;
	PLiSQL_subproc_function *subprocfunc;

	if (fcinfo->flinfo->fn_expr == NULL ||
		!IsA(fcinfo->flinfo->fn_expr, FuncExpr))
		return false;

	funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;

	/* package members are invoked through the internal dispatch kinds */
	if (FUNC_EXPR_FROM_PG_PROC(funcexpr->function_from))
		return false;

	/* subprograms of standalone routines do not belong to a package */
	if (func->item == NULL)
		return false;

	psource = (PLiSQL_package *) func->item->source;

	/* the package's own initialization block is not a member */
	if (func == &psource->source)
		return false;

	subprocfunc = get_dispatched_subproc(funcexpr);
	if (subprocfunc == NULL)
		return false;

	return find_pkg_member_index(psource, subprocfunc) >= 0;
}

/**
 * Render an argument type for the cast in the autonomous session's SQL.
 *
 * The far session parses the whole dblink query text before the embedded
 * "SET ivorysql.compatible_mode = oracle" takes effect, so the cast must
 * use a spelling the PG parser resolves.  format_type_be() renders Oracle
 * display names in Oracle mode (e.g. "varchar2" for sys.oravarcharchar),
 * which the far parser cannot resolve; use the catalog spelling for the
 * Oracle string and date types.
 */
static char *
format_autonomous_argtype(Oid argtype)
{
	switch (argtype)
	{
		case ORAVARCHARCHAROID:
			return pstrdup("sys.oravarcharchar");
		case ORAVARCHARBYTEOID:
			return pstrdup("sys.oravarcharbyte");
		case ORACHARCHAROID:
			return pstrdup("sys.oracharchar");
		case ORACHARBYTEOID:
			return pstrdup("sys.oracharbyte");
		case ORADATEOID:
			return pstrdup("sys.oradate");
		default:
			return format_type_be(argtype);
	}
}

/**
 * Construct the SQL statement that re-invokes a package member inside an
 * autonomous session.
 *
 * Package members are addressed as "schema"."package"."member": the owning
 * package is resolved from the dispatch FuncExpr's pkgoid, and the member
 * name from the compiled descriptor.  Argument values are taken from the
 * FunctionCallInfo, formatted according to the member's declared argument
 * types.
 *
 * @param func The compiled member function descriptor.
 * @param fcinfo The FunctionCallInfo carrying the actual argument values.
 * @param funcexpr The package dispatch FuncExpr of this invocation.
 * @param is_function Output parameter set to true for functions, false for
 *        procedures.
 * @return A palloc'd SQL statement that runs the member in the autonomous
 *         session (including the session-local settings).
 */
static char *
build_package_autonomous_call(PLiSQL_function *func, FunctionCallInfo fcinfo,
							  FuncExpr *funcexpr, bool *is_function)
{
	StringInfoData sql;
	StringInfoData args;
	PLiSQL_subproc_function *subprocfunc;
	PLiSQL_package *psource;
	HeapTuple	pkgTup;
	Form_pg_package pkgStruct;
	char	   *pkg_name;
	char	   *member_name;
	Oid		   *argtypes;
	char	  **argnames;
	char	   *argmodes;
	int			declared_nargs;
	int			member_index;
	int			i;

	subprocfunc = get_dispatched_subproc(funcexpr);
	if (subprocfunc == NULL)
		elog(ERROR, "package member dispatch has not been set up");

	psource = (PLiSQL_package *) func->item->source;
	member_index = find_pkg_member_index(psource, subprocfunc);
	if (member_index < 0)
		elog(ERROR, "package member dispatch has not been set up");

	/*
	 * A member that is only defined in the package body has no name that
	 * another session could call: the package specification is the only
	 * externally visible interface.  Fail clearly instead of letting the
	 * autonomous session report a confusing lookup failure.
	 */
	if (member_index >= psource->last_specialfno)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("package member \"%s\" cannot run in an autonomous transaction",
						subprocfunc->func_name),
				 errdetail("Only members declared in the package specification can be re-invoked in an autonomous session.")));

	/* The schema-qualified name of the owning package */
	pkgTup = SearchSysCache1(PKGOID, ObjectIdGetDatum(func->item->pkey));
	if (!HeapTupleIsValid(pkgTup))
		elog(ERROR, "cache lookup failed for package %u", func->item->pkey);
	pkgStruct = (Form_pg_package) GETSTRUCT(pkgTup);
	pkg_name = quote_qualified_identifier(
		get_namespace_name_or_temp(pkgStruct->pkgnamespace),
		NameStr(pkgStruct->pkgname));
	ReleaseSysCache(pkgTup);

	/* The member name, already quote_identifier()'d at compile time */
	member_name = func->fn_signature;

	*is_function = !subprocfunc->is_proc;

	/* The member's declared argument types, in call order */
	declared_nargs = get_subprocfunc_arg_info(funcexpr, &argtypes,
											  &argnames, &argmodes);

	/*
	 * A polymorphic member keeps pseudotypes (anyelement, anyarray, ...)
	 * in its declared argument list.  The far session cannot parse a cast
	 * to a pseudotype, and the local output-function lookup below fails on
	 * one, so substitute the concrete type of the actual argument
	 * expression for each polymorphic entry, exactly like the call-time
	 * resolution the local dispatch already performed.
	 */
	if (funcexpr->args != NIL)
	{
		ListCell   *lc;
		int			j = 0;

		foreach(lc, funcexpr->args)
		{
			if (j >= declared_nargs)
				break;

			if (IsPolymorphicType(argtypes[j]))
			{
				Oid			actualtype = exprType((Node *) lfirst(lc));

				if (!OidIsValid(actualtype) ||
					IsPolymorphicType(actualtype))
					ereport(ERROR,
							(errcode(ERRCODE_DATATYPE_MISMATCH),
							 errmsg("could not resolve polymorphic argument %d of package member \"%s\"",
									j + 1, member_name),
							 errdetail("The argument expression does not have a concrete type.")));

				argtypes[j] = actualtype;
			}
			j++;
		}
	}

	/* Format argument values */
	initStringInfo(&args);
	for (i = 0; i < fcinfo->nargs; i++)
	{
		Oid			argtype;
		Oid			typoutput;
		bool		typIsVarlena;
		char	   *valstr;

		if (i > 0)
			appendStringInfoString(&args, ", ");

		/*
		 * Resolve the declared type first: every argument, including a
		 * NULL, is rendered with an explicit cast so that the far session
		 * resolves the member and its coercions exactly like the local
		 * call did (bare NULLs would be ambiguous across overloads).
		 */
		argtype = (i < declared_nargs) ? argtypes[i] : InvalidOid;
		if (!OidIsValid(argtype))
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("cannot pass argument %d of package member \"%s\" to an autonomous transaction",
							i + 1, member_name),
					 errdetail("The argument type cannot be rendered as a literal.")));

		if (fcinfo->args[i].isnull)
		{
			appendStringInfo(&args, "NULL::%s", format_autonomous_argtype(argtype));
			continue;
		}

		getTypeOutputInfo(argtype, &typoutput, &typIsVarlena);
		valstr = OidOutputFunctionCall(typoutput, fcinfo->args[i].value);

		/*
		 * Quote every value: it is always followed by an explicit cast, and
		 * an unquoted rendering breaks two numeric shapes.  A float output
		 * like "NaN" or "Infinity" would be read as a column reference, and
		 * "-32768" would bind the cast before the unary minus
		 * (-(32768::int2) overflows int2).  Quoted, the cast's input
		 * function parses the exact value the local output function
		 * produced.
		 */
		appendStringInfoString(&args, quote_literal_cstr(valstr));
		appendStringInfo(&args, "::%s", format_autonomous_argtype(argtype));
		pfree(valstr);
	}

	/* Build complete SQL - use SELECT for functions, CALL for procedures */
	initStringInfo(&sql);
	if (*is_function)
	{
		appendStringInfo(&sql,
			"SET ivorysql.compatible_mode = oracle; "
			"SET plisql.inside_autonomous_transaction = true; "
			"SELECT %s.%s(%s);",
			pkg_name,
			member_name,
			args.data);
	}
	else
	{
		appendStringInfo(&sql,
			"SET ivorysql.compatible_mode = oracle; "
			"SET plisql.inside_autonomous_transaction = true; "
			"CALL %s.%s(%s);",
			pkg_name,
			member_name,
			args.data);
	}

	pfree(pkg_name);
	pfree(args.data);
	if (declared_nargs > 0)
	{
		pfree(argtypes);
		pfree(argnames);
		pfree(argmodes);
	}

	return sql.data;
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

	/*
	 * A package member is invoked through the package dispatch, whose
	 * FmgrInfo does not describe a pg_proc entry: build its call from the
	 * dispatch FuncExpr and the compiled member instead of the catalogs.
	 */
	if (plisql_pkg_member_autonomous_call(func, fcinfo))
	{
		FuncExpr   *funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;

		sql = build_package_autonomous_call(func, fcinfo, funcexpr,
											&is_function);
		rettype = funcexpr->funcresulttype;
	}
	else
	{
		/* Get return type to determine if this is a function or procedure */
		proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(func->fn_oid));
		if (!HeapTupleIsValid(proctup))
			elog(ERROR, "cache lookup failed for function %u", func->fn_oid);
		procstruct = (Form_pg_proc) GETSTRUCT(proctup);
		rettype = procstruct->prorettype;
		ReleaseSysCache(proctup);

		/* Build SQL - will be SELECT for functions, CALL for procedures */
		sql = build_autonomous_call(func, fcinfo, &is_function);
	}

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
