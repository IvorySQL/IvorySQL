/*-------------------------------------------------------------------------
 *
 * testlibpq_allout.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq_allout.c
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

char *function_str = "create or replace function short_proc(OUT IMAX int2, OUT IMIN int2, OUT INUL int2) return int as "
" begin "
 "         select max_val into imax from short_tab;"
 "         select min_val into imin from short_tab;"
 "         select null_val into inul from short_tab;"
 "         return 1;" 
 "         end;";

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
	const char *stmt = "select * from short_proc($1,$2,$3);";
	Oid param_types[3];
	IvyPreparedStatement *stmthandle;
	const char* custid = "200";
	const char* salary = "2000";
	const char* name = "2000";
	const char* param_values[3];
	int param_lengths[3];
	int param_formats[3];
	char errmsg[256];
	IvyBindOutInfo *bindinfo[3] = {NULL, NULL, NULL};
	signed short int bindvar[3];
	int index[3];
	Ivyargmode modes[3];
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

	res = Ivyexec(conn, "create temp table short_tab ( max_val int2, min_val int2, null_val int2 );");
	Ivyclear(res);
	res = Ivyexec(conn, "insert into short_tab values (32767,-32768,null);");
	Ivyclear(res);
	res = Ivyexec(conn,function_str);
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

	/* activate prepared statement */
	param_types[0] = 21 | 0x40000000;  /* out */;
	param_types[1] = 21 | 0x40000000;  /* out */;
	param_types[2] = 21 | 0x40000000;  /* out */;

	stmthandle = IvyCreatePreparedStatement(stmt_name, stmt, 3, param_types);
	IvybindOutParameterByPos(stmthandle,
				&bindinfo[0],
				1,
				&bindvar[0],
				sizeof (signed short int),
				&index[0],
				1,
				errmsg,
				256);
	IvybindOutParameterByPos(stmthandle,
				&bindinfo[1],
				2,
				&bindvar[1],
				sizeof(signed short int),
				&index[1],
				1,
				errmsg,
				256);
	IvybindOutParameterByPos(stmthandle,
				&bindinfo[2],
				3,
				&bindvar[2],
				sizeof(signed short int),
				&index[2],
				1,
				errmsg,
				256);

	param_values[0] = custid;
	param_values[1] = salary;
	param_values[2] = name;

	param_lengths[0] = strlen(custid);
	param_lengths[1] = strlen(salary);
	param_lengths[2] = strlen(name);

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;

	modes[0] = modes[1] = modes[2] = argmode_out;
	res = IvyexecPreparedStatement(conn, stmthandle, 3, param_values, param_lengths,
				param_formats, modes, result_format, errmsg, 256);

	if (IvyresultStatus(res) != PGRES_TUPLES_OK && IvyresultStatus(res) != PGRES_COMMAND_OK &&
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
	printf("%hd,%hd,%hd,%hd\n",ntohs(bindvar[0]),ntohs(bindvar[1]),ntohs(bindvar[2]), bindvar[2]);
	printf("%d,%d,%d\n",index[0],index[1],index[2]);

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

	res = Ivyexec(conn, "drop function short_proc(OUT IMAX int2, OUT IMIN int2, OUT INUL int2);");
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
			printf("\n");
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

