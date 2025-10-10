/*-------------------------------------------------------------------------
 *
 * testlibpq.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq.c
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

typedef struct
{
	IvyPreparedStatement *stmt1;
	IvyPreparedStatement *stmt3;

	Ivyconn *tconn1;
	Ivyconn *tconn2;
	Ivyconn *tconn3;
} main_thread_data;

/* global data */
main_thread_data thread_data;

/* out parameter data */
char name_out[256];
char name2_out[256];
int name3_out;
int indp[3];

char prestmt3_integer[256];
char prestmt3_name3[256];
char prestmt3_name32[256];
char prestmt3_name33[256];
int prestmt3_indp[4];


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

const char *anonymous_paramete_str =
"declare"
"       id integer;"
"       salary integer;"
"       id1 integer;"
"       id2 varchar(256);"
"begin"
"       insert into test_mds(id,id2,name) values(:1,:2,:3);"
"       id := :1;"
"       :1 := id * 2 + 1;"
"       :2 := :1 + 100;"
"       :3 := 'this is a test ok';"
"       :4 := 23;"
"       end;";

static void run_thread(int flag);
static void run_execPrepared(Ivyconn *tconn, int flag);
static void run_stmt(Ivyconn *tconn,IvyPreparedStatement *stmt, Ivyargmode *argmodes);


static void
exit_nicely()
{
	Ivyfinish(thread_data.tconn1);
	Ivyfinish(thread_data.tconn3);
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
		fprintf(stderr, "drop function plsql_function_out Ivyexec failed\n");
		Ivyclear(res);
		exit_nicely();
	}
	Ivyclear(res);

	/* drop table */
	res = Ivyexec(conn, "drop table test_mds;");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "dorp table Ivyexec failed\n");
		Ivyclear(res);
		exit_nicely();
	}
	Ivyclear(res);
	return;
}
static void
init_data(Ivyconn *conn)
{
	Ivyresult *res;

	/* create table */
	res = Ivyexec(conn,"create table test_mds(id integer,id2 integer,id3 integer,name varchar(23))");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "create table Ivyexec failed\n");
		Ivyclear(res);
		exit_nicely();
	}
	Ivyclear(res);

	/* create plsql function */
	res = Ivyexec(conn, plsql_function_out);
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "plsql_function_out Ivyexec failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	return;
}

static void
init_statement()
{
	IvyPreparedStatement *prestmt1;
	IvyPreparedStatement *prestmt3;

	const char *stmt1_name = "test1_stmt";
	const char *stmt1 = "select * from plsql_function_out($1,$2,$3,$4)";
	Oid param_types[4];

	const char *stmt3_name = "test3_stmt";
	const char *stmt3 = anonymous_paramete_str;
	Oid param_types3[4];


	param_types[0] = 0; //let db to judge it.
	param_types[1] = 25 | 0x40000000;  /* out */
	param_types[2] = 25 | 0x40000000;  /* out */
	param_types[3] = 23 | 0x40000000;  /* out */
	prestmt1 = IvyCreatePreparedStatement(stmt1_name, stmt1, 4, param_types);

	param_types3[0] = 23 | 0x60000000;  /* inout */
	param_types3[1] = 23 | 0x60000000;  /* inout */
	param_types3[2] = 25 | 0x60000000;  /* inout */
	param_types3[3] = 23 | 0x60000000;  /* inout */

	prestmt3 = IvyCreatePreparedStatement(stmt3_name, stmt3, 4, param_types3);

	thread_data.stmt1 = prestmt1;
	thread_data.stmt3 = prestmt3;

}

int
main()
{
	int i;

	/* Step1: make connection */
	Ivyconn    *conn1;
	Ivyconn    *conn3;

	const char *conninfo="user=system dbname=postgres port=1521";

	/* make a connection to the database */
	conn1 = Ivyconnectdb(conninfo);
	conn3 = Ivyconnectdb(conninfo);

	thread_data.tconn1 = conn1;
	thread_data.tconn3 = conn3;

	/* check to see if the backend connection was successfully setup */
	if (Ivystatus(conn1) == CONNECTION_BAD)
	{
		fprintf(stderr, "Connection to database failed.\n");
		fprintf(stderr, "%s", IvyerrorMessage(conn1));
		exit_nicely();
	}

	if (Ivystatus(conn3) == CONNECTION_BAD)
	{
		fprintf(stderr, "Connection to database failed.\n");
		fprintf(stderr, "%s", IvyerrorMessage(conn3));
		exit_nicely();
	}
	init_data(conn1);
	init_statement();

	for (i = 0; i < 1; i++)
	{
		int use_thread = i % 4;
		run_thread(use_thread);
	}

	/* drop table test_mds */
	drop_data(conn1);

	/* close the connection to the database and cleanup */
	IvyFreePreparedStatement(thread_data.stmt1);
	IvyFreePreparedStatement(thread_data.stmt3);

	Ivyfinish(conn1);
	Ivyfinish(conn3);
	return 0;
}

static void
run_thread(int flag)
{
	char errmsg[256];
	IvyBindOutInfo *pbind[3] = {NULL, NULL, NULL};
	IvyBindOutInfo *prestmt3_bindinfo[4] = {NULL, NULL, NULL, NULL};

	memset(name2_out, 0x00,256);
	if (IvybindOutParameterByPos(thread_data.stmt1,&pbind[0],2, (void *) name2_out, 256,
					&indp[0], 1, errmsg, 255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	memset(name_out,0x00,256);
	if (IvybindOutParameterByPos(thread_data.stmt1,
					&pbind[1],
					3,
					(void *) name_out,
					256,
					&indp[1], 1, errmsg, 255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	if (IvybindOutParameterByPos(thread_data.stmt1,
					&pbind[2],
					4,
					(void *) &name3_out,
					sizeof(int),
					&indp[2], 1, errmsg, 255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	/* bind prestmt3 */
	memset(prestmt3_integer,0x00,256);
	if (IvybindOutParameterByPos(thread_data.stmt3,
					&prestmt3_bindinfo[0],
					1,
					(void *) prestmt3_integer,
					256,
					&prestmt3_indp[0],
					1,
					errmsg,
					255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	memset(prestmt3_name3,0x00,256);
	if (IvybindOutParameterByPos(thread_data.stmt3,
					&prestmt3_bindinfo[1],
					2,
					(void *) prestmt3_name3,
					256,
					&prestmt3_indp[1],
					1,
					errmsg,
					255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	memset(prestmt3_name32,0x00,256);
	if (IvybindOutParameterByPos(thread_data.stmt3,
					&prestmt3_bindinfo[2],
					3,
					(void *) prestmt3_name32,
					256,
					&prestmt3_indp[2],
					1,
					errmsg,
					255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	memset(prestmt3_name33, 0x00,256);
	if (IvybindOutParameterByPos(thread_data.stmt3,
					&prestmt3_bindinfo[3],
					4,
					(void *) prestmt3_name33,
					256,
					&prestmt3_indp[3],
					1,
					errmsg,
					255) == 0)
	{
		printf("%s\n",errmsg);
		return;
	}

	switch (flag)
	{
		case 0:
			run_execPrepared(thread_data.tconn1, 1);
			run_execPrepared(thread_data.tconn3, 1);
			break;
		case 1:
			run_execPrepared(thread_data.tconn3, 2);
			run_execPrepared(thread_data.tconn1, 2);
			break;
		default:
			run_execPrepared(thread_data.tconn1, 1);
			run_execPrepared(thread_data.tconn2, 2);
			run_execPrepared(thread_data.tconn3, 3);
			run_execPrepared(thread_data.tconn2, 4);
			break;
	}

	printf("plsql_function_out: %s,%s,%d\n", name2_out, name_out,ntohl(name3_out));
	printf("anonymous: %s,%s,%s,%s\n", prestmt3_integer, prestmt3_name3, prestmt3_name32,prestmt3_name33);

	return;
}

static void
run_execPrepared(Ivyconn *tconn, int flag)
{
	Ivyargmode argmodes1[4];
	Ivyargmode argmodes3[4];

	argmodes1[0] = argmode_in;
	argmodes1[1] = argmode_out;
	argmodes1[2] = argmode_out;
	argmodes1[3] = argmode_out;

	argmodes3[0] = argmodes3[1] = argmodes3[2] = argmode_inout;

	run_stmt(tconn, thread_data.stmt1, argmodes1);
	run_stmt(tconn, thread_data.stmt3, argmodes3);

	return;
}

static void
run_stmt(Ivyconn *tconn,IvyPreparedStatement *stmt, Ivyargmode *argmodes)
{
	Ivyresult *res;
	int   nFields;
	int   i,j;
	int param_lengths[4];
	int param_formats[4];
	char errmsg[256];
	int result_format = 0;

	const char* custid = "3";
	const char* salary = "2000";
	const char* name = "welcome to beijing";
	const char* out_invalid = "2";
	const char* param_values[4];
	param_values[0] = custid;
	param_values[1] = salary;
	param_values[2] = name;
	param_values[3] = out_invalid;
	param_lengths[0] = 1;
	param_lengths[1] = strlen(salary);
	param_lengths[2] = strlen(name);
	param_lengths[3] = strlen(out_invalid);

	if (stmt == thread_data.stmt1)
		result_format = 1;

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;
	param_formats[3] = 0;

	res = IvyexecPreparedStatement(tconn, stmt, 4, param_values, param_lengths,
					param_formats, argmodes, result_format, errmsg, 256);


	if (IvyresultStatus(res) != PGRES_TUPLES_OK)
	{
		fprintf(stderr, "errmsg:%s\n", errmsg);
		Ivyclear(res);
		return;
	}

	/* print the result attribute names */
	if (stmt == thread_data.stmt1)
	{
		printf("plsql_function_out result start:\n");
	}
	else if (stmt == thread_data.stmt3)
	{
		printf("anonymous result start:\n");
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

	/* print the result attribute names */
	if (stmt == thread_data.stmt1)
	{
		printf("plsql_function_out result end:\n");
	}
	else if (stmt == thread_data.stmt3)
	{
		printf("anonymous result end:\n");
	}

	Ivyclear(res);
	return;
}

