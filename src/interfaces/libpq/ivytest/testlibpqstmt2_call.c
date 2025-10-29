/*
 * testlibpqstmt2_call.c
 * Test the C version of LIBPQ, the POSTGRES frontend library.
 *
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
"   return 'xiexie';"
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
	const char *stmt1 = "call plsql_function_out(:arg1, :arg2, :arg3, :arg4) into :hostvar";
	Oid param_types[5];

	param_types[0] = 23 | 0x20000000  /* in */;
	param_types[1] = 9503 | 0x40000000  /* out */;
	param_types[2] = 9503 | 0x40000000  /* out */;
	param_types[3] = 23 | 0x40000000  /* out */;
	param_types[4] = 9503 | 0x40000000  /* out */;
	prestmt1 = IvyCreatePreparedStatement(stmt1_name, stmt1, 5, param_types);
	return prestmt1;
}

int
main(int argc, char **argv)
{
	char first_parameter[256];
	char second_parameter[256];
	int  third_parameter;
	char four_parameter[256];

	/* Step1: making connection */
	Ivyconn    *conn1;
	IvyPreparedStatement *stmt1;
	IvyBindOutInfo bindinfos[4];

	char conninfo[100]="user=system dbname=postgres port=1521";
	//const char *oraport = argv[1];

	//strcat(conninfo, oraport);

	/* make a connection to the database */
	conn1 = Ivyconnectdb(conninfo);

	/* check to see that the backend connection was successfully made */
	if (Ivystatus(conn1) == CONNECTION_BAD)
	{
		fprintf(stderr, "Connection to database failed.\n");
		fprintf(stderr, "%s", IvyerrorMessage(conn1));
		exit_nicely(conn1);
	}

	init_data(conn1);
	stmt1 = init_statement();

	/* init bindinfos */
	/* first out parameter */
	bindinfos[0].next = &bindinfos[1];
	bindinfos[0].position = 2;
	bindinfos[0].resultcolumnno = 0;
	bindinfos[0].var = first_parameter;
	bindinfos[0].indp = NULL;
	bindinfos[0].val_size = 256;

	/* second out parameter */
	bindinfos[1].next = &bindinfos[2];
	bindinfos[1].position = 3;
	bindinfos[1].resultcolumnno = 1;
	bindinfos[1].var = second_parameter;
	bindinfos[1].indp = NULL;
	bindinfos[1].val_size = 256;

	/* third out parameter */
	bindinfos[2].next = &bindinfos[3];;
	bindinfos[2].position = 4;
	bindinfos[2].resultcolumnno = 2;
	bindinfos[2].var = &third_parameter;
	bindinfos[2].indp = NULL;
	bindinfos[2].val_size = sizeof(int);

	/* four out parameter */
	bindinfos[3].next = NULL;
	bindinfos[3].position = 5;
	bindinfos[3].resultcolumnno = 3;
	bindinfos[3].var = four_parameter;
	bindinfos[3].indp = NULL;
	bindinfos[3].val_size = 256;

	memset(first_parameter,0x00,256);
	memset(second_parameter,0x00,256);
	memset(four_parameter,0x00,256);
	run_stmt(conn1,stmt1, bindinfos);

	/*printf out parameters */
	printf("out parameter:%s,%s,%d\n", first_parameter,second_parameter,third_parameter);
	printf("return value:%s\n", four_parameter);
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
	Ivyargmode argmodes[5];
	int param_lengths[5];
	int param_formats[5];
	char errmsg[256];

	const char* custid = "3";
	const char* salary = "2000";
	const char* name = "welcome to beijing";
	const char* out_id2 = "2";
	const char* ret = "return";

	const char* param_values[5];
	param_values[0] = custid;
	param_values[1] = salary;
	param_values[2] = name;
	param_values[3] = out_id2;
	param_values[4] = ret;

	param_lengths[0] = 1;
	param_lengths[1] = strlen(salary);
	param_lengths[2] = strlen(name);
	param_lengths[3] = 1;
	param_lengths[4] = strlen(ret);

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;
	param_formats[3] = 0;
	param_formats[4] = 0;

	argmodes[0] = argmode_in;
	argmodes[1] = argmode_out;
	argmodes[2] = argmode_out;
	argmodes[3] = argmode_out;
	argmodes[4] = argmode_out;

	res = IvyexecPreparedStatement2(tconn, stmt, 5, param_values, param_lengths,
									param_formats, argmodes,
									bindinfos, 1, errmsg, 256);

	Ivyclear(res);
	return;
}

