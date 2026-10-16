/*-------------------------------------------------------------------------
 *
 * testlibpq_interval.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq_interval.c
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
#include <netinet/in.h>
#include <sys/types.h>

char *function_str1 = "create or replace function test_interval(id integer, time1 out interval year to month, time2 out interval year to month[], time3 interval year to month) return interval year to month as "
"  mds interval year to month[3];"
" begin"
"    mds[0] := interval '1-1' year to month;"
"    mds[1] := interval '1-2' year to month;"
"    mds[2] := interval '1-3' year to month;"
"    time1 := interval '1-2' year to month;"
"    time2 := mds;"
"    return time3;"
"end;";

char *function_str2 = "create or replace function test_interval(id integer, time1 out interval day to second, time2 out interval day to second[], time3 interval day to second) return interval day to second as "
"  mds interval day to second[3];"
" begin"
"    mds[0] := interval '4 13:12:12' day to second;"
"    mds[1] := interval '5 13:12:12' day to second;"
"    mds[2] := interval '6 13:12:12' day to second;"
"    time1 := interval '4 12:12:12' day to second;"
"    time2 := mds;"
"    return time3;"
"end;";


static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

static void
exec_prepare(Ivyconn *conn, int flag)
{
	int   nFields;
	int   i,j;
	int   result_format = 0;
	Ivyresult   *res;
	const char *stmt_name = "test_stmt";
	const char *stmt = "select * from test_interval($1,$2,$3,$4);";
	Oid param_types[4];
	IvyPreparedStatement *stmthandle;
	const char* custid = "200";
	const char* time1 = "'1-1'";
	const char* time2 = "'1-2'";
	const char* time3 = "'1-3'";
	const char* param_values[4];
	int param_lengths[4];
	int param_formats[4];
	char errmsg[256];
	IvyBindOutInfo *bindinfo[2] = {NULL, NULL};
	char bindvar1[256];
	char bindvar2[256];
	int index[2];
	Ivyargmode modes[4];

	memset(bindvar1, 0x00, 256);
	memset(bindvar2, 0x00, 256);

	if (flag == 1)
	{
		param_types[0] = 23 | 0x20000000  /* in */;
		param_types[1] = 9516 | 0x40000000  /* out */;
		param_types[2] = 9517 | 0x40000000  /* out */;
		param_types[3] = 9516 | 0x20000000  /* in */;
	}
	else
	{
		param_types[0] = 23 | 0x20000000  /* in */;
		param_types[1] = 9518 | 0x40000000  /* out */;
		param_types[2] = 9519 | 0x40000000  /* out */;
		param_types[3] = 9518 | 0x20000000  /* in */;
		time1 = "'4 12:12:12'";
		time2 = "'4 13:12:12'";
		time3 = "'4 14:12:12'";
	}
	stmthandle = IvyCreatePreparedStatement(stmt_name, stmt, 4, param_types);
	IvybindOutParameterByPos(stmthandle,
					&bindinfo[0],
					2,
					bindvar1,
					256,
					&index[0],
					1,
					errmsg,
					256);
	IvybindOutParameterByPos(stmthandle,
					&bindinfo[1],
					3,
					bindvar2,
					256,
					&index[1],
					1,
					errmsg,
					256);
	param_values[0] = custid;
	param_values[1] = time1;
	param_values[2] = time2;
	param_values[3] = time3;

	param_lengths[0] = strlen(custid);
	param_lengths[1] = strlen(time1);
	param_lengths[2] = strlen(time2);
	param_lengths[3] = strlen(time3);

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;
	param_formats[3] = 0;

	modes[0] = argmode_in;
	modes[1] = modes[2] = argmode_out;
	modes[3] = argmode_in;

	res = IvyexecPreparedStatement(conn, stmthandle, 4, param_values, param_lengths,
					param_formats, modes, result_format, errmsg, 256);

	if (IvyresultStatus(res) != PGRES_TUPLES_OK && IvyresultStatus(res) != PGRES_COMMAND_OK &&
		IvyresultStatus(res) != PGRES_EMPTY_QUERY)
	{
		fprintf(stderr, "PQexecPrepared statement not return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

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

	printf("%s,%s\n",bindvar1,bindvar2);
	printf("%d,%d\n",index[0],index[1]);
	Ivyclear(res);
	IvyFreePreparedStatement(stmthandle);
	return;
}

int
main()
{
	Ivyconn    *conn;
	Ivyresult   *res;
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

	res = Ivyexec(conn, function_str1);
	Ivyclear(res);
	res = Ivyexec(conn,function_str2);
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

	exec_prepare(conn, 1);
	exec_prepare(conn, 2);

	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	res = Ivyexec(conn, "drop function test_interval(integer, interval year to month, interval year to month[], interval year to month);");
	Ivyclear(res);
	res = Ivyexec(conn, "drop function test_interval(integer, interval day to second, interval day to second[], interval day to second);");
	Ivyclear(res);

	Ivyfinish(conn);
	return 0;
}

