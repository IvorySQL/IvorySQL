/*-------------------------------------------------------------------------
 *
 * testlibpq_prepare_plsql.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq_prepare_plsql.c
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

const char *anonymous_paramete_str =
"declare"
"       id integer;"
"       salary integer;"
"       id1 integer;"
"       id2 varchar(256);"
"begin"
"       id := :x;"
"		id1 := :m;"
"       :x := id * 2 + 1;"
"       :y := :x + 100;"
"       :z := 'this is a test ok';"
"       :f := 23;"
" end;";


static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

static void
exec_prepare(Ivyconn *conn, int byname)
{
	Ivyresult   *res;
	IvyPreparedStatement *stmthandle = NULL;
	IvyError *errhp = NULL;
	int		x = 12;
	int		y = 0;
	char	z[256] = "welcome to visit QD";
	int		f = 24;
	int		m = 345;
	IvyBindInfo *bindinfo[5] = {NULL, NULL, NULL, NULL, NULL};
	int index[5] = {0,0,0,0,0};

	if (!IvyHandleAlloc(NULL, (void **) &stmthandle,IVY_HANDLE_STMT,4, NULL))
	{
		fprintf(stderr, "IvyHandleAlloc failed\n");
		exit_nicely(conn);
	}

	if (!IvyHandleAlloc(NULL, (void **) &errhp, IVY_HANDLE_ERROR, 4, NULL))
	{
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		fprintf(stderr, "IvyHandleAlloc failed\n");
		exit_nicely(conn);
	}

	if (!IvyStmtPrepare(stmthandle, errhp, anonymous_paramete_str, strlen(anonymous_paramete_str), 0, 0))
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
				":m",
				strlen(":m"),
				&m,
				sizeof(m),
				23 | 0x60000000  /* inout */,
				&index[0],
				NULL,
				NULL,
				256,
				NULL,
				0);
		IvyBindByName(stmthandle,
				&bindinfo[1],
				errhp,
				":x",
				strlen(":x"),
				&x,
				sizeof(x),
				23 | 0x60000000  /* inout */,
				&index[1],
				NULL,
				NULL,
				256,
				NULL,
				0);
		IvyBindByName(stmthandle,
				&bindinfo[2],
				errhp,
				":y",
				strlen(":y"),
				&y,
				sizeof(int),
				23 | 0x60000000  /* inout */,
				&index[2],
				NULL,
				NULL,
				256,
				NULL,
				0);
		IvyBindByName(stmthandle,
				&bindinfo[3],
				errhp,
				":z",
				strlen(":z"),
				z,
				strlen(z),
				1043 | 0x60000000  /* inout */,
				&index[3],
				NULL,
				NULL,
				256,
				NULL,
				0);
		IvyBindByName(stmthandle,
				&bindinfo[4],
				errhp,
				":f",
				strlen(":f"),
				&f,
				sizeof(int),
				23 | 0x60000000  /* inout */,
				&index[4],
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
				&x,
				sizeof(int),
				23  | 0x60000000  /* inout */,
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
				&m,
				sizeof(int),
				23  | 0x60000000  /* inout */,
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
				&y,
				sizeof(int),
				23  | 0x60000000  /* inout */,
				&index[2],
				NULL,
				NULL,
				256,
				NULL,
				0);
		IvyBindByPos(stmthandle,
				&bindinfo[3],
				errhp,
				4,
				z,
				strlen(z),
				1043  | 0x60000000  /* inout */,
				&index[3],
				NULL,
				NULL,
				256,
				NULL,
				0);
		IvyBindByPos(stmthandle,
				&bindinfo[4],
				errhp,
				5,
				&f,
				sizeof(int),
				23  | 0x60000000  /* inout */,
				&index[4],
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
		fprintf(stderr, "PQexecPrepared statement not return tuples properly\n");
		Ivyclear(res);
		exit_nicely(conn);
	}

	Ivyclear(res);
	IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
	IvyFreeHandle(errhp, IVY_HANDLE_ERROR);

	printf("x:%d:%d\n", x, index[0]);
	printf("y:%d:%d\n", y, index[1]);
	printf("z:%s:%d\n", z, index[2]);
	printf("f:%d:%d\n", f, index[3]);
	printf("m:%d:%d\n", m, index[4]);

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
	exec_prepare(conn, 0);

	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	Ivyfinish(conn);
	return 0;
}

