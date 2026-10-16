/*-------------------------------------------------------------------------
 *
 * testlibpqstmt2.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpqstmt2.c
 *
 *-------------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include "libpq-fe.h"

#ifdef WIN32
#include<Winsock.h>
#include<Windows.h>
#pragma   comment   (lib,"Ws2_32.lib")
#else
#include <unistd.h>
#include <arpa/inet.h>
#endif

#include "libpq-ivy.h"
#include <string.h>

const char *plsql_function_out = "create or replace function plsql_function_out(id integer, name1 out varchar,name2 out varchar, id2 out integer) return varchar as "
"declare"
"   id1 integer;"
"begin"
"   id1 := id;"
"   name1 := 'plsql function name1';"
"   name2 := 'plsql function name2';"
"   id2 := 23;"
"   return 'thanks';"
"end;";

static void run_stmt(Ivyconn *tconn,IvyPreparedStatement *stmt, IvyBindOutInfo *bindinfos);

static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

static void
drop_data(Ivyconn *conn)
{
	Ivyresult *res;

	/* drop function */
	res = Ivyexec(conn, "drop function plsql_function_out(integer,varchar,varchar,integer);");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "Ivyexec failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);
	return;
}

static void
init_data(Ivyconn *conn)
{
	Ivyresult *res;

	/* create plsql function */
	res = Ivyexec(conn, plsql_function_out);
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "Ivyexec failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);
	return;
}

static IvyPreparedStatement *
init_statement()
{
	IvyPreparedStatement *prestmt1;
	const char *stmt1_name = "test1_stmt";
	const char *stmt1 = "select * from plsql_function_out($1,$2,$3,$4)";
	Oid param_types[4];

	param_types[0] = 0; ///let db to judge it.
	param_types[1] = 25;
	param_types[2] = 25;
	param_types[3] = 23;

	prestmt1 = IvyCreatePreparedStatement(stmt1_name, stmt1, 4, param_types);
	return prestmt1;
}

int
main()
{
	char first_parameter[256];
	char second_parameter[256];
	int  third_parameter;

	/* making connection */
	Ivyconn    *conn1;
	IvyPreparedStatement *stmt1;
	IvyBindOutInfo bindinfos[3];

	const char *conninfo="user=system dbname=postgres port=1521";

	/* make a connection to the database */
	conn1 = Ivyconnectdb(conninfo);

	/* check to see if the backend connection was successfully setup */
	if (Ivystatus(conn1) == CONNECTION_BAD)
	{
		fprintf(stderr, "Connection to database failed.\n");
		fprintf(stderr, "%s", IvyerrorMessage(conn1));
		exit_nicely(conn1);
	}

	init_data(conn1);
	stmt1 = init_statement();

	/* init bindinfos */
	/* First out parameter */
	bindinfos[0].next = &bindinfos[1];
	bindinfos[0].position = 2;
	bindinfos[0].resultcolumnno = 0;
	bindinfos[0].var = first_parameter;
	bindinfos[0].indp = NULL;
	bindinfos[0].val_size = 256;

	/* Second out parameter */
	bindinfos[1].next = &bindinfos[2];
	bindinfos[1].position = 3;
	bindinfos[1].resultcolumnno = 1;
	bindinfos[1].var = second_parameter;
	bindinfos[1].indp = NULL;
	bindinfos[1].val_size = 256;

	/* Third out parameter */
	bindinfos[2].next = NULL;
	bindinfos[2].position = 4;
	bindinfos[2].resultcolumnno = 2;
	bindinfos[2].var = &third_parameter;
	bindinfos[2].indp = NULL;
	bindinfos[2].val_size = sizeof(int);

	memset(first_parameter,0x00,256);
	memset(second_parameter,0x00,256);
	run_stmt(conn1,stmt1, bindinfos);

	/*printf out parameters */
	printf("out parameter:%s,%s,%d\n", first_parameter,second_parameter,ntohl(third_parameter));
	drop_data(conn1);

	/* close the connection to the database and cleanup */
	IvyFreePreparedStatement(stmt1);
	Ivyfinish(conn1);
	return 0;
}

static void
run_stmt(Ivyconn *tconn,IvyPreparedStatement *stmt, IvyBindOutInfo *bindinfos)
{
	Ivyresult *res;
	int   nFields;
	int   i,j;
	Ivyargmode argmodes[4];
	int param_lengths[4];
	int param_formats[4];
	char errmsg[256];

	const char* custid = "3";
	const char* salary = "2000";
	const char* name = "welcome to visit QD";
	const char* out_id2 = "2";
	const char* param_values[4];
	param_values[0] = custid;
	param_values[1] = salary;
	param_values[2] = name;
	param_values[3] = out_id2;
	param_lengths[0] = 1;
	param_lengths[1] = strlen(salary);
	param_lengths[2] = strlen(name);
	param_lengths[3] = 1;

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;
	param_formats[3] = 0;

	argmodes[0] = argmode_in;
	argmodes[1] = argmode_out;
	argmodes[2] = argmode_out;
	argmodes[3] = argmode_out;

	res = IvyexecPreparedStatement2(tconn, stmt, 4, param_values, param_lengths,
					param_formats, argmodes,
					bindinfos, 1, errmsg, 256);

	if (IvyresultStatus(res) != PGRES_TUPLES_OK)
	{
		fprintf(stderr, "errmsg:%s\n", errmsg);
		Ivyclear(res);
		return;
	}

	/* print the result attribute names */
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
	return;
}

