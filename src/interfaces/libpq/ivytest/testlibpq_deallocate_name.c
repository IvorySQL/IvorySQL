/*-------------------------------------------------------------------------
 *
 * testlibpq_deallocate_name.c
 *		Exercise Ivy prepared-statement names that require SQL quoting.
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 *-------------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>

#include "libpq-fe.h"
#include "libpq-ivy.h"

static void
fail(Ivyconn *conn, const char *message)
{
	fprintf(stderr, "%s: %s", message, IvyerrorMessage(conn));
	Ivyfinish(conn);
	exit(EXIT_FAILURE);
}

int
main(void)
{
	const char *stmt_name =
		"statement with \"quotes\"; and spaces: "
		"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
		"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
		"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
		"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
		"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
	IvyPreparedStatement *statement;
	Ivyconn    *conn;
	Ivyresult  *result;
	Oid		param_types[1] = {23};
	const char *param_values[1] = {"1"};
	int		param_lengths[1] = {1};
	int		param_formats[1] = {0};
	char		errmsg[256];

	conn = Ivyconnectdb("user=system dbname=postgres port=1521");
	if (Ivystatus(conn) == CONNECTION_BAD)
		fail(conn, "connection failed");

	statement = IvyCreatePreparedStatement(stmt_name, "SELECT $1::int", 1,
											 param_types);
	if (statement == NULL)
		fail(conn, "statement allocation failed");

	result = IvyexecPreparedStatement(conn, statement, 1, param_values,
									param_lengths, param_formats, NULL, 0,
									errmsg, sizeof(errmsg));
	if (IvyresultStatus(result) != PGRES_TUPLES_OK)
	{
		Ivyclear(result);
		fail(conn, "prepare or execute failed");
	}
	Ivyclear(result);

	IvyFreePreparedStatement(statement);

	result = Ivyexec(conn,
				 "SELECT count(*) FROM pg_prepared_statements "
				 "WHERE name = 'statement with \"quotes\"; and spaces: ' || "
				 "repeat('x', 320)");
	if (IvyresultStatus(result) != PGRES_TUPLES_OK ||
		Ivyntuples(result) != 1 ||
		Ivygetvalue(result, 0, 0)[0] != '0')
	{
		Ivyclear(result);
		fail(conn, "long quoted statement was not deallocated");
	}

	printf("long quoted prepared statement deallocated\n");
	Ivyclear(result);
	Ivyfinish(conn);
	return 0;
}
