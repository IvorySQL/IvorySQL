/*
 * testlibpq_prepare_call.c
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

char *function_str1 = "create or replace function call_f_test(a varchar2, b out varchar2) return varchar2 is "
" begin"
"    b := a;"
"    return a||b;"
"end;";

char *procedure_str1 = "create or replace procedure call_p_test(a varchar2, b out varchar2) is "
" begin"
"    b := a || 'beijing';"
"end;";

const char *call_function_str = "call call_f_test(:x, :y) into :z";
const char *call_procedure_str = "call call_p_test(:x, :y)";

static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

static void
exec_prepare_func(Ivyconn *conn, int byname)
{
	Ivyresult   *res;
	IvyPreparedStatement *stmthandle = NULL;
	IvyError *errhp = NULL;
	char	x[256] = "beijing";
	char	y[256] = "welcome to beijing";
	char	z[256] = "welcome to HighGo Software";
	IvyBindInfo *bindinfo[3] = {NULL, NULL, NULL};
	int index[3] = {0,0,0};

	if (!IvyHandleAlloc(NULL, (void **) &stmthandle,IVY_HANDLE_STMT,4, NULL))
	{
		fprintf(stderr, "IvyHandleAlloc prepared stmt failed\n");
		exit_nicely(conn);
	}

	if (!IvyHandleAlloc(NULL, (void **) &errhp, IVY_HANDLE_ERROR, 4, NULL))
	{
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		fprintf(stderr, "IvyHandleAlloc Error handle failed\n");
		exit_nicely(conn);
	}

	if (!IvyStmtPrepare(stmthandle, errhp, call_function_str, strlen(call_function_str), 0, 0))
	{
		fprintf(stderr, "%s\n", errhp->error_msg);
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		IvyFreeHandle(errhp, IVY_HANDLE_ERROR);
		exit_nicely(conn);
	}
	if (byname)
	{
		IvyBindByName(stmthandle,
					&bindinfo[0],
					errhp,
					":x",
					strlen(":x"),
					x,
					256,
					9503 | 0x20000000  /* in */,
					&index[0],
					NULL,
					NULL,
					256,
					NULL,
					0);
		IvyBindByName(stmthandle,
					&bindinfo[1],
					errhp,
					":y",
					strlen(":y"),
					y,
					256,
					9503 | 0x40000000  /* out */,
					&index[1],
					NULL,
					NULL,
					256,
					NULL,
					0);
		IvyBindByName(stmthandle,
					&bindinfo[2],
					errhp,
					":z",
					strlen(":z"),
					z,
					256,
					9503 | 0x40000000  /* out */,
					&index[2],
					NULL,
					NULL,
					256,
					NULL,
					0);
	}
	else
	{
		IvyBindByPos(stmthandle,
					&bindinfo[0],
					errhp,
					1,
					x,
					256,
					9503  | 0x20000000  /* in */,
					&index[0],
					NULL,
					NULL,
					256,
					NULL,
					0);
		IvyBindByPos(stmthandle,
					&bindinfo[1],
					errhp,
					2,
					y,
					256,
					9503  | 0x40000000  /* out */,
					&index[1],
					NULL,
					NULL,
					256,
					NULL,
					0);
		IvyBindByPos(stmthandle,
					&bindinfo[2],
					errhp,
					3,
					z,
					256,
					9503  | 0x40000000  /* out */,
					&index[2],
					NULL,
					NULL,
					256,
					NULL,
					0);
	}

	res = IvyStmtExecute(conn, stmthandle, errhp);
	if (IvyresultStatus(res) != PGRES_TUPLES_OK && IvyresultStatus(res) != PGRES_COMMAND_OK &&
		IvyresultStatus(res) != PGRES_EMPTY_QUERY)
	{
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		IvyFreeHandle(errhp, IVY_HANDLE_ERROR);
		fprintf(stderr, "PQexecPrepared statement didn't return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);
	IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
	IvyFreeHandle(errhp, IVY_HANDLE_ERROR);

	printf("x:%s:%d\n", x, index[0]);
	printf("y:%s:%d\n", y, index[1]);
	printf("z:%s:%d\n", z, index[2]);

	return;
}

static void
exec_prepare_proc(Ivyconn *conn, int byname)
{
	Ivyresult   *res;
	IvyPreparedStatement *stmthandle = NULL;
	IvyError *errhp = NULL;
	char	x[256] = "welcome to ";
	char	y[256] = "welcome to HighGo Software";
	IvyBindInfo *bindinfo[2] = {NULL, NULL};
	int index[2] = {0,0};

	if (!IvyHandleAlloc(NULL, (void **) &stmthandle,IVY_HANDLE_STMT,4, NULL))
	{
		fprintf(stderr, "IvyHandleAlloc prepared stmt failed\n");
		exit_nicely(conn);
	}

	if (!IvyHandleAlloc(NULL, (void **) &errhp, IVY_HANDLE_ERROR, 4, NULL))
	{
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		fprintf(stderr, "IvyHandleAlloc Error handle failed\n");
		exit_nicely(conn);
	}

	if (!IvyStmtPrepare(stmthandle, errhp, call_procedure_str, strlen(call_procedure_str), 0, 0))
	{
		fprintf(stderr, "%s\n", errhp->error_msg);
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		IvyFreeHandle(errhp, IVY_HANDLE_ERROR);
		exit_nicely(conn);
	}
	if (byname)
	{
		IvyBindByName(stmthandle,
					&bindinfo[0],
					errhp,
					":x",
					strlen(":x"),
					x,
					256,
					9503 | 0x20000000  /* in */,
					&index[0],
					NULL,
					NULL,
					256,
					NULL,
					0);
		IvyBindByName(stmthandle,
					&bindinfo[1],
					errhp,
					":y",
					strlen(":y"),
					y,
					256,
					9503 | 0x40000000  /* out */,
					&index[1],
					NULL,
					NULL,
					256,
					NULL,
					0);
	}
	else
	{
		IvyBindByPos(stmthandle,
					&bindinfo[0],
					errhp,
					1,
					x,
					256,
					9503  | 0x20000000  /* in */,
					&index[0],
					NULL,
					NULL,
					256,
					NULL,
					0);
		IvyBindByPos(stmthandle,
					&bindinfo[1],
					errhp,
					2,
					y,
					256,
					9503  | 0x40000000  /* out */,
					&index[1],
					NULL,
					NULL,
					256,
					NULL,
					0);
	}

	res = IvyStmtExecute(conn, stmthandle, errhp);
	if (IvyresultStatus(res) != PGRES_TUPLES_OK && IvyresultStatus(res) != PGRES_COMMAND_OK &&
		IvyresultStatus(res) != PGRES_EMPTY_QUERY)
	{
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		IvyFreeHandle(errhp, IVY_HANDLE_ERROR);
		fprintf(stderr, "PQexecPrepared statement didn't return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);
	IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
	IvyFreeHandle(errhp, IVY_HANDLE_ERROR);

	printf("x:%s:%d\n", x, index[0]);
	printf("y:%s:%d\n", y, index[1]);

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

	res = Ivyexec(conn, function_str1);
	Ivyclear(res);
	res = Ivyexec(conn, procedure_str1);
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

	exec_prepare_func(conn, 1);
	exec_prepare_func(conn, 0);
	exec_prepare_proc(conn, 1);
	exec_prepare_proc(conn, 0);
	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	Ivyfinish(conn);
	return 0;
}

