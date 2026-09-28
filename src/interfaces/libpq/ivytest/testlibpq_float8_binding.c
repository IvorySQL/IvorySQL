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
	int			mode;

	if (!conn || Ivystatus(conn) != CONNECTION_OK ||
		!IvyHandleAlloc(NULL, (void **) &err, IVY_HANDLE_ERROR, 0, NULL))
		return EXIT_FAILURE;
	for (mode = 0; mode < 3; mode++)
	{
		IvyPreparedStatement *stmt = NULL;
		IvyBindInfo *bind = NULL;
		Ivyresult  *res;
		double		value = mode == 2 ? 0.0 : 1.23456789012345;
		int			indicator = 0;
		const char *query = mode == 2 ? "begin :x := 1.25; end;" : "select :x";

		if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL) ||
			!IvyStmtPrepare(stmt, err, query, strlen(query), 0, 0))
			return EXIT_FAILURE;
		if (mode == 0)
		{
			if (!IvyBindByPos(stmt, &bind, err, 1, &value, sizeof(value),
							  701, &indicator, NULL, NULL, 0, NULL, 0))
				return EXIT_FAILURE;
		}
		else if (!IvyBindByName(stmt, &bind, err, ":x", 2, &value, sizeof(value),
								701 | (mode == 2 ? 0x60000000 : 0),
								&indicator, NULL, NULL, 0, NULL, 0))
			return EXIT_FAILURE;
		res = IvyStmtExecute(conn, stmt, err);
		if (!res || (mode < 2 && (IvyresultStatus(res) != PGRES_TUPLES_OK ||
								  strtod(Ivygetvalue(res, 0, 0), NULL) != value)) ||
			(mode == 2 && (value != 1.25 || indicator != 0)))
		{
			fprintf(stderr, "double binding mode %d failed: %s\n", mode, err->error_msg);
			return EXIT_FAILURE;
		}
		Ivyclear(res);
		IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	}
	IvyFreeHandle(err, IVY_HANDLE_ERROR);
	Ivyfinish(conn);
	puts("double precision bindings passed");
	return EXIT_SUCCESS;
}
