/*-------------------------------------------------------------------------
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"
#include <assert.h>
#include <limits.h>
#include "libpq-fe.h"
#include "libpq-ivy.h"

int
main(void)
{
	Ivyconn    *conn = Ivyconnectdb(getenv("IVY_TEST_CONNINFO") ? getenv("IVY_TEST_CONNINFO") :
									"user=system dbname=postgres port=1521");
	IvyError   *err = NULL;
	int			named;

	if (!conn || Ivystatus(conn) != CONNECTION_OK ||
		!IvyHandleAlloc(NULL, (void **) &err, IVY_HANDLE_ERROR, 0, NULL))
		return EXIT_FAILURE;
	for (named = 0; named < 3; named++)
	{
		IvyPreparedStatement *stmt = NULL;
		IvyBindInfo *bind = NULL;
		Ivyresult  *res;
		int			value = 42;
		const char *query = named == 2 ? "begin :x := :x + 1; end;" : "select :x";

		if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL) ||
			!IvyStmtPrepare(stmt, err, query, strlen(query), 0, 0))
			return EXIT_FAILURE;
		if (named)
		{
			if (!IvyBindByName(stmt, &bind, err, ":x", 2, &value, sizeof(value),
							   23 | (named == 2 ? 0x60000000 : 0),
							   NULL, NULL, NULL, 0, NULL, 0))
				return EXIT_FAILURE;
		}
		else if (!IvyBindByPos(stmt, &bind, err, 1, &value, sizeof(value),
							   23, NULL, NULL, NULL, 0, NULL, 0))
			return EXIT_FAILURE;
		res = IvyStmtExecute(conn, stmt, err);
		if (!res || IvyresultStatus(res) != PGRES_TUPLES_OK ||
			(named < 2 && strcmp(Ivygetvalue(res, 0, 0), "42") != 0) ||
			(named == 2 && value != 43))
		{
			fprintf(stderr, "%s\n", err->error_msg);
			return EXIT_FAILURE;
		}
		Ivyclear(res);
		IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	}
	IvyFreeHandle(err, IVY_HANDLE_ERROR);
	Ivyfinish(conn);
	puts("optional input indicators passed");
	return EXIT_SUCCESS;
}
