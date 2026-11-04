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
	int			failures = 0;

	if (!conn || Ivystatus(conn) != CONNECTION_OK ||
		!IvyHandleAlloc(NULL, (void **) &err, IVY_HANDLE_ERROR, 0, NULL))
		return EXIT_FAILURE;
	for (mode = 0; mode < 3; mode++)
	{
		IvyPreparedStatement *stmt = NULL;
		Ivyresult  *res;
		HostVariable host;
		const char *query = "select 42";
		int			attempt;

		memset(&host, 0, sizeof(host));
		if (mode == 1)
			stmt = IvyCreatePreparedStatement("ivy_no_parameters", query, 0, NULL);
		else if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL) ||
				 !IvyStmtPrepare(stmt, err, query, strlen(query), 0, 0))
			return EXIT_FAILURE;
		if (!stmt)
		{
			failures++;
			continue;
		}
		for (attempt = 0; attempt < 2; attempt++)
		{
			if (mode == 0)
				res = IvyStmtExecute(conn, stmt, err);
			else if (mode == 2)
				res = IvyStmtExecute2(conn, stmt, err, &host);
			else
				res = IvyexecPreparedStatement(conn, stmt, 0, NULL, NULL, NULL,
											   NULL, 0, err->error_msg, err->err_buf_size);
			if (!res || IvyresultStatus(res) != PGRES_TUPLES_OK ||
				strcmp(Ivygetvalue(res, 0, 0), "42") != 0)
			{
				fprintf(stderr, "parameterless mode %d failed: %s\n", mode, err->error_msg);
				failures++;
			}
			Ivyclear(res);
		}
		IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	}
	IvyFreeHandle(err, IVY_HANDLE_ERROR);
	Ivyfinish(conn);
	if (failures)
		return EXIT_FAILURE;
	puts("parameterless prepared statements passed");
	return EXIT_SUCCESS;
}
