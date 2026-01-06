/*-------------------------------------------------------------------------
 *
 * testlibpq_nullstmt.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq_nullstmt.c
 *
 *-------------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include "libpq-fe.h"
#include "libpq-ivy.h"
#include <string.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>

static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

int
main()
{
	int   nFields;
	int   i,j;
	int   result_format = 1;
	Ivyconn    *conn;
	Ivyresult   *res;
	const char *stmt_name = "test_stmt";
	const char *stmt = "";	//null stmt
	Oid param_types[4];
	IvyPreparedStatement *stmthandle;
	const char* custid = "200";
	const char* salary = "2000";
	const char* name = "2000";
	const char* ix = "welcome to visit QD";
	const char* param_values[4];
	int param_lengths[4];
	int param_formats[4];
	char errmsg[256];

	const char *conninfo="user=system dbname=postgres port=1521";

	/* make a connection to the database */
	conn = Ivyconnectdb(conninfo);

	/* check to see if the backend connection was successfully setup */
	if (Ivystatus(conn) == CONNECTION_BAD)
	{
		fprintf(stderr, "Connection to database failed.\n");
		fprintf(stderr, "%s", IvyerrorMessage(conn));
		exit_nicely(conn);
	}

	/* start a transaction block */
	res = Ivyexec(conn, "BEGIN");

	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "BEGIN command failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);

	/* activate prepared statement */
	param_types[0] = 23; ///let db to judge it.
	param_types[1] = 23;
	param_types[2] = 23;
	param_types[3] = 1043;

	stmthandle = IvyCreatePreparedStatement(stmt_name, stmt, 4, param_types);

	param_values[0] = custid;
	param_values[1] = salary;
	param_values[2] = name;
	param_values[3] = ix;

	param_lengths[0] = strlen(custid);
	param_lengths[1] = strlen(salary);
	param_lengths[2] = strlen(name);
	param_lengths[3] = strlen(ix);

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;
	param_formats[3] = 0;

	res = IvyexecPreparedStatement(conn, stmthandle, 4, param_values, param_lengths,
					param_formats, NULL, result_format, errmsg, 256);

	if (IvyresultStatus(res) != PGRES_TUPLES_OK &&
		IvyresultStatus(res) != PGRES_COMMAND_OK &&
		IvyresultStatus(res) != PGRES_EMPTY_QUERY)
	{
		fprintf(stderr, "PQexecPrepared statement not return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	/* print out the attribute names */
	nFields = Ivynfields(res);
	for (i = 0; i < nFields; i++)
		printf("%-15s", Ivyfname(res, i));

	printf("\n");

	/* print out the instances */
	for (i = 0; i < Ivyntuples(res); i++)
	{
		for (j = 0; j < nFields; j++)
		{
			printf("%-15s", Ivygetvalue(res, i, j));
			printf("\t");
		}
		printf("\n");
	}

	Ivyclear(res);

	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	/* start a transaction block */
	res = Ivyexec(conn, "BEGIN");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "BEGIN command failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);

	/* define cursor */
	res = Ivyexec(conn, "DECLARE myportal CURSOR FOR select * from pg_prepared_statements");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "DECLARE CURSOR command failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	/* fetch cursor */
	res = Ivyexec(conn, "FETCH ALL in myportal");
	if (IvyresultStatus(res) != PGRES_TUPLES_OK)
	{
		fprintf(stderr, "FETCH ALL command didn't return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	/* first, print out the attribute names */
	nFields = Ivynfields(res);
	for (i = 0; i < nFields; i++)
		printf("%-15s", Ivyfname(res, i));
	printf("\n");

	/* next, print out the instances */
	for (i = 0; i < Ivyntuples(res); i++)
	{
		for (j = 0; j < nFields; j++)
		{
			if (j == 2)
				printf("prepare time is always change");
			else
				printf("%-15s", Ivygetvalue(res, i, j));
			printf("\t");
		}
		printf("\n");
	}

	Ivyclear(res);

	/* close the portal */
	res = Ivyexec(conn, "CLOSE myportal");
	Ivyclear(res);

	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	/* looking for cached status of prepared statements */
	IvyFreePreparedStatement(stmthandle);
	Ivyfinish(conn);
	return 0;
}

