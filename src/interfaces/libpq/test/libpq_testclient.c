/*
 * libpq_testclient.c
 *		A test program for the libpq public API
 *
 * Copyright (c) 2022-2026, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		src/interfaces/libpq/test/libpq_testclient.c
 */

#include "postgres_fe.h"

#include "libpq-fe.h"
#include "libpq-ivy.h"

/*
 * Exercise OUT bindings through the legacy or typed Ivy API.  The input
 * selects an empty result, a SQL NULL, an ordinary value, or a result with no
 * matching OUT column.  It also initializes the bound buffer, so the TAP test
 * can check that unavailable outputs leave the caller's data intact.
 *
 * Print the row count, indicator, and buffer for the TAP assertions.  Return
 * zero on successful query execution, or one after reporting an API error.
 */
static int
test_ivy_out(const char *conninfo, const char *api, const char *input)
{
	const char *query =
		"SELECT CASE WHEN $1 = 'null' THEN NULL::text "
		"ELSE 'returned'::text END AS \"_column_1\" WHERE $1 <> 'empty'";
	Ivyconn    *conn = Ivyconnectdb(conninfo);
	IvyPreparedStatement *stmt = NULL;
	IvyBindInfo *bind = NULL;
	IvyError   *error = NULL;
	Ivyresult  *result = NULL;
	char		buffer[32] = {0};
	char		errmsg[256] = {0};
	int			indicator = 0;
	Oid			type = 25;		/* text */
	Ivyargmode	mode = argmode_in;
	int			rc = 1;

	if (Ivystatus(conn) != CONNECTION_OK)
		goto done;
	strlcpy(buffer, input, sizeof(buffer));
	if (strcmp(input, "unbound") == 0)
		query = "SELECT $1::text AS ordinary WHERE false";

	if (strcmp(api, "typed") == 0)
	{
		HostVariableEntry entry = {"$1", 1};
		HostVariable host = {0};

		host.hostvars = &entry;
		host.length = 1;
		if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL) ||
			!IvyHandleAlloc(NULL, (void **) &error, IVY_HANDLE_ERROR, 0, NULL) ||
			!IvyStmtPrepare(stmt, error, query, strlen(query), 0, 0) ||
			!IvyBindByPos(stmt, &bind, error, 1, buffer, sizeof(buffer),
						  25 | 0x20000000, &indicator, NULL, NULL, 0, NULL, 0))
			goto done;
		result = IvyStmtExecute2(conn, stmt, error, &host);
	}
	else
	{
		stmt = IvyCreatePreparedStatement("ivy_out", query, 1, &type);
		if (stmt == NULL ||
			!IvybindOutParameterByPos(stmt, &bind, 1, buffer, sizeof(buffer),
									  &indicator, 0, errmsg, sizeof(errmsg)))
			goto done;
		result = IvyexecPreparedStatement(conn, stmt, 1, &input, NULL, NULL,
										  &mode, 0, errmsg, sizeof(errmsg));
	}

	if (IvyresultStatus(result) != PGRES_TUPLES_OK)
		goto done;
	printf("rows=%d indicator=%d value=%s\n",
		   Ivyntuples(result), indicator, buffer);
	rc = 0;

done:
	if (rc != 0)
		fprintf(stderr, "%s%s%s", IvyerrorMessage(conn), errmsg,
				error != NULL ? error->error_msg : "");
	Ivyclear(result);
	if (stmt != NULL)
		IvyFreePreparedStatement(stmt);
	if (error != NULL)
		IvyFreeHandle(error, IVY_HANDLE_ERROR);
	Ivyfinish(conn);
	return rc;
}

static void
print_ssl_library(void)
{
	const char *lib = PQsslAttribute(NULL, "library");

	if (!lib)
		fprintf(stderr, "SSL is not enabled\n");
	else
		printf("%s\n", lib);
}

/*
 * Dispatch the SSL-library probe or the Ivy OUT-binding scenario selected on
 * the command line.  Propagate the scenario's exit status to the TAP caller;
 * unsupported arguments print usage information and return failure.
 */
int
main(int argc, char *argv[])
{
	if (argc == 5 && strcmp(argv[1], "--ivy-out") == 0)
		return test_ivy_out(argv[2], argv[3], argv[4]);

	if ((argc > 1) && !strcmp(argv[1], "--ssl"))
	{
		print_ssl_library();
		return 0;
	}

	printf("supported options: --ssl, --ivy-out CONNINFO API INPUT\n");
	return 1;
}
