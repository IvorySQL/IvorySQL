/*
 * testlibpq_call.c
 * Test the C version of LIBPQ, the POSTGRES frontend library.
 *
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

char *function_str = "create or replace function call_f_test(a varchar2, b out varchar2) return varchar2 is "
" begin"
"    b := 'beijing';"
"    return a||b;"
"end;";

char *procedure_str = "create or replace procedure call_p_test(a varchar2, b out varchar2) is "
" begin"
"    b := a||'beijing';"
"end;";

static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

static void
exec_prepare_func(Ivyconn *conn)
{
	int   result_format = 0;
	Ivyresult   *res;
	const char *stmt_name = "test_callstmt1";
	const char *stmt = "call call_f_test(:x, :y) into :z";
	Oid param_types[3];
	IvyPreparedStatement *stmthandle;
	const char* x = "welcome to ";
	const char* y = "out1";
	const char* z = "out2";
	const char* param_values[3];
	int param_lengths[3];
	int param_formats[3];
	char errmsg[256];
	IvyBindOutInfo *bindinfo[2] = {NULL, NULL};
	char bindvar1[256];
	char bindvar2[256];
	int index[2];
	Ivyargmode modes[3];

	memset(bindvar1, 0x00, 256);
	memset(bindvar2, 0x00, 256);

	param_types[0] = 9503 | 0x20000000  /* in */;
	param_types[1] = 9503 | 0x40000000  /* out */;
	param_types[2] = 9503 | 0x40000000  /* out */;
	stmthandle = IvyCreatePreparedStatement(stmt_name, stmt, 3, param_types);
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
	param_values[0] = x;
	param_values[1] = y;
	param_values[2] = z;

	param_lengths[0] = strlen(x);
	param_lengths[1] = strlen(y);
	param_lengths[2] = strlen(z);

	param_formats[0] = 0;
	param_formats[1] = 0;
	param_formats[2] = 0;

	modes[0] = argmode_in;
	modes[1] = modes[2] = argmode_out;

	res = IvyexecPreparedStatement(conn, stmthandle, 3, param_values, param_lengths,
									param_formats, modes, result_format, errmsg, 256);
	if (IvyresultStatus(res) != PGRES_TUPLES_OK && IvyresultStatus(res) != PGRES_COMMAND_OK &&
		IvyresultStatus(res) != PGRES_EMPTY_QUERY)
	{
		fprintf(stderr, "PQexecPrepared statement didn't return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	printf("%s,%s\n",bindvar1,bindvar2);
	printf("%d,%d\n",index[0],index[1]);
	Ivyclear(res);
	IvyFreePreparedStatement(stmthandle);
	return;
}

static void
exec_prepare_proc(Ivyconn *conn)
{
	int   result_format = 0;
	Ivyresult   *res;
	const char *stmt_name = "test_callstmt2";
	const char *stmt = "call call_p_test(:x, :y)";
	Oid param_types[2];
	IvyPreparedStatement *stmthandle;
	const char* x = "welcome to ";
	const char* y = "out";
	const char* param_values[2];
	int param_lengths[2];
	int param_formats[2];
	char errmsg[256];
	IvyBindOutInfo *bindinfo[1] = {NULL};
	char bindvar[256];
	int index[1];
	Ivyargmode modes[2];

	memset(bindvar, 0x00, 256);
	param_types[0] = 9503 | 0x20000000  /* in */;
	param_types[1] = 9503 | 0x40000000  /* out */;
	stmthandle = IvyCreatePreparedStatement(stmt_name, stmt, 2, param_types);
	IvybindOutParameterByPos(stmthandle,
							&bindinfo[0],
							2,
							bindvar,
							256,
							&index[0],
							1,
							errmsg,
							256);
	param_values[0] = x;
	param_values[1] = y;

	param_lengths[0] = strlen(x);
	param_lengths[1] = strlen(y);

	param_formats[0] = 0;
	param_formats[1] = 0;

	modes[0] = argmode_in;
	modes[1] = argmode_out;

	res = IvyexecPreparedStatement(conn, stmthandle, 2, param_values, param_lengths,
									param_formats, modes, result_format, errmsg, 256);
	if (IvyresultStatus(res) != PGRES_TUPLES_OK && IvyresultStatus(res) != PGRES_COMMAND_OK &&
		IvyresultStatus(res) != PGRES_EMPTY_QUERY)
	{
		fprintf(stderr, "PQexecPrepared statement didn't return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	printf("%s\n",bindvar);
	printf("%d\n",index[0]);
	Ivyclear(res);
	IvyFreePreparedStatement(stmthandle);
	return;
}

int
main(int argc, char **argv)
{
	Ivyconn    *conn;
	Ivyresult   *res;
	char conninfo[100]="user=system dbname=postgres port=1521";
	//const char *oraport = argv[1];

	//strcat(conninfo, oraport);

	/* make a connection to the database */
	conn = Ivyconnectdb(conninfo);

	/* check to see that the backend connection was successfully made */
	if (Ivystatus(conn) == CONNECTION_BAD)
	{
		fprintf(stderr, "Connection to database failed.\n");
		fprintf(stderr, "%s", IvyerrorMessage(conn));
		exit_nicely(conn);
	}
	res = Ivyexec(conn,function_str);
	Ivyclear(res);
	res = Ivyexec(conn,procedure_str);
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

	exec_prepare_func(conn);
	exec_prepare_proc(conn);
	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	res = Ivyexec(conn, "drop function call_f_test(a varchar2, b out varchar2);");
	Ivyclear(res);
	res = Ivyexec(conn, "drop procedure call_p_test(a varchar2, b out varchar2);");
	Ivyclear(res);

	Ivyfinish(conn);
	return 0;
}

