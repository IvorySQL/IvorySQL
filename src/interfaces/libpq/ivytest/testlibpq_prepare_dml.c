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

/* Keep each bind-info pointer alive until its statement handle is freed. */
static int
prepare_bound_stmt(IvyPreparedStatement **stmt, IvyError *errhp,
				   const char *query, IvyBindInfo **bindinfo,
				   int *value, int *indicator)
{
	return IvyHandleAlloc(NULL, (void **) stmt, IVY_HANDLE_STMT, 0, NULL) &&
		IvyStmtPrepare(*stmt, errhp, query, strlen(query), 0, 0) &&
		IvyBindByName(*stmt, bindinfo, errhp, ":v", 2, value, sizeof(*value),
					  23 | 0x20000000, indicator, NULL, NULL, 0, NULL, 0);
}

static int
check_stmt_result(Ivyconn *conn, IvyPreparedStatement *stmt, IvyError *errhp,
				  const char *expected, const char *label)
{
	Ivyresult  *res = IvyStmtExecute(conn, stmt, errhp);
	int			ok = res != NULL && IvyresultStatus(res) == PGRES_TUPLES_OK &&
		Ivyntuples(res) == 1 && Ivynfields(res) == 1 &&
		strcmp(Ivygetvalue(res, 0, 0), expected) == 0;

	if (ok)
		printf("%s: %s\n", label, Ivygetvalue(res, 0, 0));
	else
		fprintf(stderr, "%s failed: %s\n", label, errhp->error_msg);
	Ivyclear(res);
	return ok;
}

static int
exec_multiple_handles(Ivyconn *conn, const char *conninfo)
{
	Ivyconn    *other = NULL;
	IvyPreparedStatement *stmt[3] = {NULL, NULL, NULL};
	IvyBindInfo *bindinfo[3] = {NULL, NULL, NULL};
	IvyError   *errhp = NULL;
	int			values[3] = {11, 21, 31};
	int			indicators[3] = {0, 0, 0};
	int			ok = 0;
	int			i;

	if (!IvyHandleAlloc(NULL, (void **) &errhp, IVY_HANDLE_ERROR, 0, NULL))
		goto done;
	other = Ivyconnectdb(conninfo);
	if (other == NULL || Ivystatus(other) != CONNECTION_OK)
		goto done;
	if (!prepare_bound_stmt(&stmt[0], errhp, "SELECT :v", &bindinfo[0],
							&values[0], &indicators[0]) ||
		!prepare_bound_stmt(&stmt[1], errhp, "SELECT :v + 1", &bindinfo[1],
							&values[1], &indicators[1]))
		goto done;

	if (!check_stmt_result(conn, stmt[0], errhp, "11", "first handle") ||
		!check_stmt_result(conn, stmt[1], errhp, "22", "second handle"))
		goto done;
	values[0] = 12;
	if (!check_stmt_result(conn, stmt[0], errhp, "12", "first handle again") ||
		!check_stmt_result(other, stmt[0], errhp, "12", "first on other connection") ||
		!check_stmt_result(other, stmt[1], errhp, "22", "second on other connection"))
		goto done;

	/* Freeing one handle must not deallocate the other's server statement. */
	IvyFreeHandle(stmt[0], IVY_HANDLE_STMT);
	stmt[0] = NULL;
	if (!check_stmt_result(conn, stmt[1], errhp, "22", "second after first freed") ||
		!check_stmt_result(other, stmt[1], errhp, "22", "other after first freed"))
		goto done;

	/* A newly allocated handle can coexist with the surviving one. */
	if (!prepare_bound_stmt(&stmt[2], errhp, "SELECT :v + 2", &bindinfo[2],
							&values[2], &indicators[2]) ||
		!check_stmt_result(conn, stmt[2], errhp, "33", "new handle") ||
		!check_stmt_result(other, stmt[2], errhp, "33", "new on other connection") ||
		!check_stmt_result(conn, stmt[1], errhp, "22", "second after new handle"))
		goto done;
	IvyFreeHandle(stmt[1], IVY_HANDLE_STMT);
	IvyFreeHandle(stmt[2], IVY_HANDLE_STMT);
	stmt[1] = stmt[2] = NULL;

	/* Every connection associated with a released handle is cleaned up. */
	for (i = 0; i < 2; i++)
	{
		Ivyresult  *res = Ivyexec(i == 0 ? conn : other,
								  "SELECT count(*) FROM pg_prepared_statements");

		ok = res != NULL && IvyresultStatus(res) == PGRES_TUPLES_OK &&
			strcmp(Ivygetvalue(res, 0, 0), "0") == 0;
		Ivyclear(res);
		if (!ok)
			goto done;
	}
	printf("released handles leave no prepared statements\n");

done:
	for (i = 0; i < 3; i++)
		if (stmt[i] != NULL)
			IvyFreeHandle(stmt[i], IVY_HANDLE_STMT);
	if (errhp != NULL)
		IvyFreeHandle(errhp, IVY_HANDLE_ERROR);
	if (other != NULL)
		Ivyfinish(other);
	return ok;
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

	if (!exec_multiple_handles(conn, conninfo))
	{
		fprintf(stderr, "multiple statement handles failed\n");
		Ivyfinish(conn);
		return EXIT_FAILURE;
	}

	Ivyfinish(conn);
	return 0;
}

