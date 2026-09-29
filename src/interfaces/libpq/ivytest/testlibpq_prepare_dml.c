/*-------------------------------------------------------------------------
 *
 * testlibpq_prepare_dml.c
 *
 * Test the C version of LIBPQ, the POSTGRES frontend library.  
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq_prepare_dml.c
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


const char *update_parameter_str = "update t_update set id = :x where name = :y";
const char *insert_parameter_str = "insert into t_insert values(:x,:y);";


static void
exit_nicely(Ivyconn *conn)
{
	Ivyfinish(conn);
	exit(EXIT_SUCCESS);
}

static void
print_tuple(Ivyresult *res)
{
	int nFields;
	int i;
	int j;

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

	return;
}

static void
exec_prepare(Ivyconn *conn, int byname, int update)
{
	Ivyresult   *res;
	IvyPreparedStatement *stmthandle = NULL;
	IvyError *errhp = NULL;
	int		x = 23;
	char	y[256] = "update";
	IvyBindInfo *bindinfo[2] = {NULL, NULL};
	int index[2] = {0,0};
	char	*query = NULL;
	int i;

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

	if (update)
		query = (char *) update_parameter_str;
	else
		query = (char *) insert_parameter_str;

	if (!IvyStmtPrepare(stmthandle, errhp, query, strlen(query), 0, 0))
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
				&x,
				sizeof(x),
				23 | 0x20000000  /* in */,
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
				25 | 0x20000000  /* in */,
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
				&x,
				sizeof(int),
				23 | 0x20000000  /* in */,
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
				25 | 0x20000000  /* in */,
				&index[1],
				NULL,
				NULL,
				256,
				NULL,
				0);
	}

	for (i = 0; i < 10; i++)
	{
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
		x++;
		Ivyclear(res);
	}

	IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
	IvyFreeHandle(errhp, IVY_HANDLE_ERROR);

	return;
}

/*
 * Prepare a statement from a non-NUL-terminated buffer.
 *
 * OCI semantics: the caller passes the exact statement length in query_len
 * and the statement text is not required to be NUL-terminated.  This used to
 * break IvyStmtPrepare(), which depended on strdup()/strlen() and over-read
 * past the caller's buffer.  The buffer below is poisoned with bytes after
 * the text (and contains no NUL within its bounds), so the old code either
 * crashed or prepared a garbage statement while the fixed code must prepare
 * and execute the statement correctly.
 */
static void
exec_prepare_nonul(Ivyconn *conn)
{
	Ivyresult   *res;
	IvyPreparedStatement *stmthandle = NULL;
	IvyError *errhp = NULL;
	char	*buf = NULL;
	size_t	buf_size = 4096;
	size_t	query_len;
	int		x = 40;
	char	y[256] = "nonul";
	IvyBindInfo *bindinfo[2] = {NULL, NULL};
	int index[2] = {0,0};

	/* build query text in a heap buffer WITHOUT a NUL terminator */
	buf = (char *) malloc(buf_size);
	if (buf == NULL)
	{
		fprintf(stderr, "malloc failed\n");
		exit_nicely(conn);
	}
	memset(buf, 'X', buf_size);	/* no NUL anywhere in the buffer */
	query_len = strlen("insert into t_insert values(:x,:y)");
	memcpy(buf, "insert into t_insert values(:x,:y)", query_len);

	if (!IvyHandleAlloc(NULL, (void **) &stmthandle, IVY_HANDLE_STMT, 4, NULL))
	{
		free(buf);
		fprintf(stderr, "IvyHandleAlloc prepared stmt failed\n");
		exit_nicely(conn);
	}

	if (!IvyHandleAlloc(NULL, (void **) &errhp, IVY_HANDLE_ERROR, 4, NULL))
	{
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		free(buf);
		fprintf(stderr, "IvyHandleAlloc Error handle failed\n");
		exit_nicely(conn);
	}

	if (!IvyStmtPrepare(stmthandle, errhp, buf, query_len, 0, 0))
	{
		fprintf(stderr, "%s\n", errhp->error_msg);
		IvyFreeHandle(stmthandle, IVY_HANDLE_STMT);
		IvyFreeHandle(errhp, IVY_HANDLE_ERROR);
		free(buf);
		exit_nicely(conn);
	}
	free(buf);

	IvyBindByPos(stmthandle,
			&bindinfo[0],
			errhp,
			1,
			&x,
			sizeof(int),
			23 | 0x20000000  /* in */,
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
			25 | 0x20000000  /* in */,
			&index[1],
			NULL,
			NULL,
			256,
			NULL,
			0);

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

	/* create insert table */
	res = Ivyexec(conn, "create table t_insert(id integer, name text)");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "create table t_insert failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	/* create insert table */
	res = Ivyexec(conn, "create table t_update(id integer, name text)");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "create table t_update failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	/* insert a row to t_update */
	res = Ivyexec(conn, "insert into t_update values(1,'ok')");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "insert t_update failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	/* insert a row to t_update */
	res = Ivyexec(conn, "insert into t_update values(1,'update')");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "insert t_update failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	exec_prepare(conn, 1, 0);
	exec_prepare(conn, 0, 1);
	exec_prepare_nonul(conn);

	res = Ivyexec(conn, "select * from t_insert order by id");
	if (IvyresultStatus(res) != PGRES_TUPLES_OK)
	{
		fprintf(stderr, "select t_insert failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	print_tuple(res);
	Ivyclear(res);

	res = Ivyexec(conn, "select * from t_update order by id");
	if (IvyresultStatus(res) != PGRES_TUPLES_OK)
	{
		fprintf(stderr, "select t_update failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	print_tuple(res);
	Ivyclear(res);

	/* drop table */
	res = Ivyexec(conn, "drop table t_insert");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "drop t_insert failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	res = Ivyexec(conn, "drop table t_update");
	if (IvyresultStatus(res) != PGRES_COMMAND_OK)
	{
		fprintf(stderr, "drop t_update failed\n");
		Ivyclear(res);
		exit_nicely(conn);
	}
	Ivyclear(res);

	/* end the transaction */
	res = Ivyexec(conn, "END");
	Ivyclear(res);

	Ivyfinish(conn);
	return 0;
}

