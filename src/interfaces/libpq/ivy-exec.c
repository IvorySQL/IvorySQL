/*-------------------------------------------------------------------------
 *
 * ivy-exec.c
 *
 * like fe-exec.c but contains ivy functions.         
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivy-exec.c
 *
 * functions related to sending a query down to the backend.
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"

#include <ctype.h>
#include <fcntl.h>
#include <limits.h>
#include "libpq-fe.h"
#include "libpq-int.h"
#include "mb/pg_wchar.h"

#ifdef WIN32
#include "win32.h"
#else
#include <unistd.h>
#endif
#include "pg_config.h"
#include "ivy_sema.h"
#include "libpq-ivy.h"

/*
 * The oid type has a total of 32 bits, and the highest 3 bits are used as:
 * first is arg of '{? = call}',
 * second means OUT mode,  
 * third means IN modes. 
 * left 29 bits for value of type.
 */
#define SetModeOut(typeoid) ((typeoid) |= 0x40000000)
#define SetModeIn(typeoid) ((typeoid) |= 0x20000000)
#define UnSetModeOut(typeoid) ((typeoid) &= 0x1FFFFFFF)

static void IvyassignOutParameters(const Ivyresult *res, IvyBindOutInfo *outbind);
static void IvyreplaceParamTypeByOutParameter(IvyBindOutInfo *bindinfo, int nParams, 
						Oid *paramTypes, const Ivyargmode *argmodes);
static void IvyaddRelationStmtHandleandConn(Ivyconn *tconn, IvyPreparedStatement *stmtHandle);
static Ivylist *IvyaddValueToList(Ivylist *list, void *value);
static Ivylist *IvyremoveValueFromList(Ivylist *list, void *value);
static void IvyremoveStmtHandleRelation(IvyPreparedStatement *stmtHandle);
static void IvyremoveConnRelation(Ivyconn *tconn);
static void Ivyfreelist(Ivylist *list);

typedef enum IVY_VALUE_TYPE
{
	IVY_VALUE_FLOAT,
	IVY_VALUE_INTEGER,
	IVY_VALUE_BIGINTEGER,
	IVY_VALUE_BYTE
} ivy_value_type;

static void IvyassignOutParameters2(const Ivyresult *res,
					IvyBindOutInfo *outbind);
static void IvyAssignPLISQLOutParameter(const Ivyresult *res,
					IvyPreparedStatement *stmtHandle);
static void assign_value_internel(PGresult *res, char *column,
					int *indp, void *bindvar,
					size_t bindvar_size, int dtype);
static ivy_value_type get_paramvalue_type(int type);
static int IvyhandleParamsValues(IvyPreparedStatement *stmtHandle,
					char  ***paramValuesp,
					int **paramLengthsp,
					int **paramFormatsp);
static int Ivyreplacenamebindtoposition(Ivyconn *tconn,
						IvyPreparedStatement *stmtHandle,
						char *errmsg,
						size_t size_error_buf);
static int Ivyreplacenamebindtoposition2(Ivyconn *tconn,
						IvyPreparedStatement *stmtHandle,
						IvyError *errhp);
static int Ivyreplacenamebindtoposition3(Ivyconn *tconn,
						IvyPreparedStatement *stmtHandle,
						IvyError *errhp,
						HostVariable *host);
static int IvybindOutParameterByPosInternel(IvyPreparedStatement *stmthandle,
						IvyBindOutInfo **bindinfo,
						int	position,
						void *var,
						size_t	val_size,
						int *indp,
						int	replace_ok,
						char *errormsg,
						size_t size_error_buf,
						bool nedd_lock);

static int IvyBindByPosInternel(IvyPreparedStatement *stmtHandle,
						IvyBindInfo **bindinfo,
						IvyError	*errhp,
						int	position,
						void *valuep,
						size_t	value_sz,
						int		dty,
						int *indp,
						char *alenp,
						char *recodep,
						int  maxarr_len,
						int  *curelep,
						int  mode,
						bool need_lock);

static int IvyExecCommand(PGconn *conn, const char *query);
static int get_field_number_from_coluname(PGresult *res, const char *column);
static int get_result_off(PGresult *res);
static int IvyGetParameterNum(IvyPreparedStatement *stmtHandle);
static int IvyAssignParameterTypes(IvyError *errhp, IvyPreparedStatement *stmtHandle);
static int IvyHandleDostmt(Ivyconn *tconn,
				IvyPreparedStatement *stmtHandle, bool noparams_info,
				char *errmsg, size_t err_buf_size);



/*
 * Ivyconnectdb like PQconnectdb, 
 */
Ivyconn *
Ivyconnectdb(const char *conninfo)
{
	Ivyconn	*ivyconn = NULL;
	PGconn	*conn = NULL;

	ivyconn = (Ivyconn *) malloc(sizeof(Ivyconn));
	if (ivyconn == NULL)
		return NULL;

	/* init self_lock */
	if (PGSemaphoreCreate(&ivyconn->self_lock) == 0)
	{
		free(ivyconn);
		return NULL;
	}

	/* init sock */
	if (PGSemaphoreCreate(&ivyconn->lock) == 0)
	{
		ReleaseSemaphores(&ivyconn->self_lock);
		free(ivyconn);
		return NULL;
	}

	conn = PQconnectdb(conninfo);
	if (conn == NULL)
	{
		ReleaseSemaphores(&ivyconn->self_lock);
		ReleaseSemaphores(&ivyconn->lock);
		free(ivyconn);
		return NULL;
	}

	ivyconn->conn = conn;
	ivyconn->IvystmtHandleList = NULL;
	return ivyconn;
}

/*
 * A variant of Ivyconnectdb.
 * this function constructs an Ivyconn using the PGconn structure.
 */
Ivyconn *
Ivyconnectdb2(PGconn *conn)
{
	Ivyconn	*ivyconn = NULL;

	ivyconn = (Ivyconn *) malloc(sizeof(Ivyconn));
	if (ivyconn == NULL)
		return NULL;

	/* init self_lock */
	if (PGSemaphoreCreate(&ivyconn->self_lock) == 0)
	{
		free(ivyconn);
		return NULL;
	}

	/* init sock */
	if (PGSemaphoreCreate(&ivyconn->lock) == 0)
	{
		ReleaseSemaphores(&ivyconn->self_lock);
		free(ivyconn);
		return NULL;
	}

	if (conn == NULL)
	{
		ReleaseSemaphores(&ivyconn->self_lock);
		ReleaseSemaphores(&ivyconn->lock);
		free(ivyconn);
		return NULL;
	}

	ivyconn->conn = conn;
	ivyconn->IvystmtHandleList = NULL;
	return ivyconn;
}

/*
 * like Ivyfinish, but we don't close the connection of tconn->conn.
 */
void
Ivyfinish2(Ivyconn *tconn)
{
	if (tconn == NULL || tconn->conn == NULL)
		return;

	/* add lock */
	PGSemaphoreLock(&tconn->self_lock);
	if (tconn->conn == NULL)
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		return;
	}

	tconn->conn = NULL;
	PGSemaphoreUnlock(&tconn->self_lock);
	ReleaseSemaphores(&tconn->self_lock);

	/* remove handle about its stmthandle */
	PGSemaphoreLock(&tconn->lock);
	IvyremoveConnRelation(tconn);

	/*free stmt list */
	Ivyfreelist(tconn->IvystmtHandleList);
	PGSemaphoreUnlock(&tconn->lock);
	ReleaseSemaphores(&tconn->lock);

	free(tconn);
	tconn = NULL;
	return;
}

/*
 *
 * like jdbc, create a statementhandle
 *
 * stmtName: the name of stmtment 
 * query: the sql query text
 * nParams: the number of parameters
 * paramTypes: the types of parameters
 */
IvyPreparedStatement *
IvyCreatePreparedStatement(const char *stmtName,
				const char *query,
				int nParams,
				const Oid *paramTypes)
{
	IvyPreparedStatement *result;

	if (stmtName == NULL || query == NULL || nParams == 0)
		return NULL;

	result = (IvyPreparedStatement *) malloc(sizeof(IvyPreparedStatement));
	if (result == NULL)
		return NULL;

	/* init s_lock */
	if (PGSemaphoreCreate(&result->lock) == 0)
	{
		free(result);
		return NULL;
	}

	result->query = strdup(query);
	result->stmtName = strdup(stmtName);
	result->nParams = nParams;
	result->paramTypes = (Oid *) malloc (sizeof(Oid) * nParams);
	result->query_len = strlen(query);

	if (result->paramTypes == NULL)
	{
		free(result->query);
		free(result->stmtName);
		ReleaseSemaphores(&result->lock);
		free(result);
		return NULL;
	}
	else
	{
		int i;

		for (i = 0; i < nParams; i++)
		{
			result->paramTypes[i] = paramTypes[i];
		}
	}

	result->IvyconnList = NULL;
	result->outbind = NULL;
	result->paramNames = NULL;
	result->namebind = NULL;
	result->noutvars = 0;
	result->name_replace = 0;
	result->stmttype = IVY_STMT_UNKNOW;
	result->do_using_query = NULL;

	return result;
}

/*
 *
 * like PQexecPreparedStatement
 * but combind PQprepare and PQexecPrepared
 *
 * if no prepare, send prepare using PQprepare,
 * then use PQexecPrepared to get result, 
 * and assign out parameters at last.
 */
Ivyresult *
IvyexecPreparedStatement(Ivyconn *tconn,
				IvyPreparedStatement *stmtHandle,
				int nParams,
				const char *const *paramValues,
				const int *paramLengths,
				const int *paramFormats,
				const Ivyargmode *argmodes,
				int resultFormat,
				char *errmsg,
				size_t size_error_buf)
{
	Ivyresult *tresult = NULL;
	PGconn *conn = NULL;
	PGresult *presult = NULL;
	bool	sendPrepare = true;

	if (tconn == NULL || tconn->conn == NULL ||
		stmtHandle == NULL || stmtHandle->query == NULL)
	{
		snprintf(errmsg, size_error_buf, "%s", "connection or stmt is null");
		return NULL;
	}

	tresult = (Ivyresult *) malloc(sizeof(Ivyresult));
	if (tresult == NULL)
	{
		snprintf(errmsg, size_error_buf, "%s", "malloc failed");
		return NULL;
	}

	/* send prepare stmt */
	/* first lock ivyconn and stmt */
	PGSemaphoreLock(&stmtHandle->lock);
	if (stmtHandle->query == NULL)
	{
		/* stmtHandle has already be freed */
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errmsg, size_error_buf, "%s", "stmt has already be freed");
		free(tresult);
		return NULL;
	}
	if (stmtHandle->nParams != nParams)
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errmsg, size_error_buf, "%s", "stmt params has already be changed");
		free(tresult);
		return NULL;
	}

	/* The placeholder varable is binded by name, change it to be by position */
	if (stmtHandle->namebind != NULL &&
		stmtHandle->name_replace == 0 &&
		!Ivyreplacenamebindtoposition(tconn, stmtHandle, errmsg, size_error_buf))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}
	else if (stmtHandle->stmttype == IVY_STMT_UNKNOW &&
			!Ivyreplacenamebindtoposition(tconn, stmtHandle, errmsg, size_error_buf))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}

	if (stmtHandle->stmttype == IVY_STMT_DO &&
		!IvyHandleDostmt(tconn, stmtHandle, false, errmsg, size_error_buf))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}

	PGSemaphoreLock(&tconn->self_lock);
	conn = tconn->conn;

	if (!PQexecStart(conn))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
		free(tresult);
		return NULL;
	}

	PGSemaphoreLock(&tconn->lock);
	if (tconn->IvystmtHandleList != NULL)
	{
		Ivylist *tmp;

		for (tmp = tconn->IvystmtHandleList; tmp != NULL; tmp = tmp->next)
		{
			if (tmp->value == stmtHandle)
			{
				sendPrepare = false;
				break;
			}
		}
	}

	/* if hasn't sent prepare */
	if (sendPrepare)
	{
		char *send_query;

		/* replace its parameter */
		if (stmtHandle->outbind != NULL)
			IvyreplaceParamTypeByOutParameter(stmtHandle->outbind,
								stmtHandle->nParams,
								stmtHandle->paramTypes,
								argmodes);

		if (stmtHandle->stmttype == IVY_STMT_DOHANDLED)
			send_query = stmtHandle->do_using_query;
		else
			send_query = stmtHandle->query;

		/* send Prepare */
		if (!PQsendPrepare(conn, stmtHandle->stmtName, send_query,
							nParams, stmtHandle->paramTypes))
		{
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			free(tresult);
			snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
			return NULL;
		}
		presult = PQexecFinish(conn);
		if (PQresultStatus(presult) != PGRES_COMMAND_OK)
		{
			/* failed */
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			PQclear(presult);
			free(tresult);
			snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
			return NULL;
		}
		PQclear(presult);

		IvyaddRelationStmtHandleandConn(tconn, stmtHandle);
	}
	PGSemaphoreUnlock(&tconn->lock);

	tresult->off = stmtHandle->noutvars;

	/* send query */
	if (!PQsendQueryPrepared(conn, stmtHandle->stmtName, nParams, paramValues,
							paramLengths, paramFormats, resultFormat))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
		return NULL;
	}

	/* get presult */
	presult = PQexecFinish(conn);
	if (PQresultStatus(presult) != PGRES_TUPLES_OK &&
		PQresultStatus(presult) != PGRES_COMMAND_OK &&
		PQresultStatus(presult) != PGRES_EMPTY_QUERY)
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		PQclear(presult);
		snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
		return NULL;
	}
	PGSemaphoreUnlock(&tconn->self_lock);
	tresult->result = presult;

	/* assign out parameters */
	if (stmtHandle->stmttype == IVY_STMT_DOHANDLED)
		IvyAssignPLISQLOutParameter(tresult, stmtHandle);
	else
		IvyassignOutParameters(tresult, stmtHandle->outbind);

	PGSemaphoreUnlock(&stmtHandle->lock);

	return tresult;
}


/*
 *
 * like IvyexecPreparedStatement
 * but use bindinfo as a parameter
 */
Ivyresult *
IvyexecPreparedStatement2(Ivyconn *tconn,
				IvyPreparedStatement *stmtHandle,
				int nParams,
				const char *const *paramValues,
				const int *paramLengths,
				const int *paramFormats,
				const Ivyargmode *argmodes,
				IvyBindOutInfo *bindinfos,
				int resultFormat,
				char *errmsg,
				size_t size_error_buf)
{
	Ivyresult *tresult = NULL;
	PGconn *conn = NULL;
	PGresult *presult = NULL;
	bool	sendPrepare = true;

	if (tconn == NULL || tconn->conn == NULL ||
		stmtHandle == NULL || stmtHandle->query == NULL)
	{
		snprintf(errmsg, size_error_buf, "%s", "connection or stmt is null");
		return NULL;
	}

	if (stmtHandle->outbind != NULL)
	{
		snprintf(errmsg, size_error_buf, "%s", "stmt has already binded out parameters");
		return NULL;
	}

	tresult = (Ivyresult *) malloc(sizeof(Ivyresult));
	if (tresult == NULL)
	{
		snprintf(errmsg, size_error_buf, "%s", "malloc failed");
		return NULL;
	}

	/* send prepare stmt */
	/* lock ivyconn and stmt */
	PGSemaphoreLock(&stmtHandle->lock);
	if (stmtHandle->query == NULL)
	{
		/* stmtHandle has already been freed */
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errmsg, size_error_buf, "%s", "stmt has already been freed");
		free(tresult);
		return NULL;
	}
	if (stmtHandle->nParams != nParams)
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errmsg, size_error_buf, "%s", "stmt params has already been changed");
		free(tresult);
		return NULL;
	}

	/* The placeholder varable is binded by name, change it to be by position */
	if (stmtHandle->namebind != NULL &&
		stmtHandle->name_replace == 0 &&
		Ivyreplacenamebindtoposition(tconn, stmtHandle, errmsg, size_error_buf) != 1)
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}
	else if (stmtHandle->stmttype == IVY_STMT_UNKNOW &&
			!Ivyreplacenamebindtoposition(tconn, stmtHandle, errmsg, size_error_buf))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}

	if (stmtHandle->stmttype == IVY_STMT_DO &&
		!IvyHandleDostmt(tconn, stmtHandle, false, errmsg, size_error_buf))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}


	PGSemaphoreLock(&tconn->self_lock);
	conn = tconn->conn;

	if (!PQexecStart(conn))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
		free(tresult);
		return NULL;
	}

	/* find out if this stmt has sent prepare in connection */
	PGSemaphoreLock(&tconn->lock);
	if (tconn->IvystmtHandleList != NULL)
	{
		Ivylist *tmp;

		for (tmp = tconn->IvystmtHandleList; tmp != NULL; tmp = tmp->next)
		{
			if (tmp->value == stmtHandle)
			{
				sendPrepare = false;
				break;
			}
		}
	}

	if (sendPrepare)
	{
		char *send_query = NULL;

		/* replace its parameter */
		if (bindinfos != NULL)
			IvyreplaceParamTypeByOutParameter(bindinfos,
								stmtHandle->nParams,
								stmtHandle->paramTypes,
								argmodes);

		if (stmtHandle->stmttype == IVY_STMT_DOHANDLED)
			send_query = stmtHandle->do_using_query;
		else
			send_query = stmtHandle->query;

		/* send Prepare */
		if (!PQsendPrepare(conn, stmtHandle->stmtName, send_query,
							nParams, stmtHandle->paramTypes))
		{
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			free(tresult);
			snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
			return NULL;
		}
		presult = PQexecFinish(conn);
		if (PQresultStatus(presult) != PGRES_COMMAND_OK)
		{
			/* failed */
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			PQclear(presult);
			free(tresult);
			snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
			return NULL;
		}
		PQclear(presult);

		IvyaddRelationStmtHandleandConn(tconn, stmtHandle);
	}
	PGSemaphoreUnlock(&tconn->lock);

	/* count out vars */
	if (bindinfos != NULL)
	{
		int noutvars = 0;
		IvyBindOutInfo *tmp = NULL;

		for (tmp = bindinfos; tmp != NULL; tmp = tmp->next)
			noutvars++;
		tresult->off = noutvars;
	}
	else
		tresult->off = 0;

	/* send query */
	if (!PQsendQueryPrepared(conn, stmtHandle->stmtName, nParams, paramValues,
							paramLengths, paramFormats, resultFormat))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
		return NULL;
	}

	/* get presult */
	presult = PQexecFinish(conn);
	if (PQresultStatus(presult) != PGRES_TUPLES_OK && PQresultStatus(presult) != PGRES_COMMAND_OK)
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		PQclear(presult);
		snprintf(errmsg, size_error_buf, "%s", PQerrorMessage(conn));
		return NULL;
	}
	PGSemaphoreUnlock(&tconn->self_lock);
	tresult->result = presult;

	/* assign out parameters */
	if (stmtHandle->stmttype == IVY_STMT_DO)
		IvyAssignPLISQLOutParameter(tresult, stmtHandle);
	else
		IvyassignOutParameters(tresult, bindinfos);

	PGSemaphoreUnlock(&stmtHandle->lock);

	return tresult;
}

/*
 * free a stmt
 */
void
IvyFreePreparedStatement(IvyPreparedStatement *stmtHandle)
{
	if (stmtHandle == NULL || stmtHandle->query == NULL)
		return;

	/* get the lock */
	PGSemaphoreLock(&stmtHandle->lock);

	/* already free */
	if (stmtHandle->query == NULL)
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		return;
	}

	/* free bind info of out parameter */
	if (stmtHandle->outbind != NULL)
	{
		IvyBindOutInfo *tmp = stmtHandle->outbind;
		IvyBindOutInfo *next = NULL;

		while (tmp != NULL)
		{
			next = tmp->next;
			free(tmp);
			tmp = next;
		}
		stmtHandle->outbind = NULL;
	}

	/* free name info of out parameter */
	if (stmtHandle->namebind != NULL)
	{
		IvyBindOutNameInfo *tmp = stmtHandle->namebind;
		IvyBindOutNameInfo *next = NULL;

		while (tmp != NULL)
		{
			next = tmp->next;
			free(tmp);
			tmp = next;
		}
		stmtHandle->namebind = NULL;
	}

	if (stmtHandle->paramNames != NULL)
	{
		int i;

		for (i = 0; i < stmtHandle->nParams; i++)
			if (stmtHandle->paramNames[i] != NULL)
				free(stmtHandle->paramNames[i]);
		free(stmtHandle->paramNames);
		stmtHandle->paramNames = NULL;
	}

	/* remove relationship */
	IvyremoveStmtHandleRelation(stmtHandle);

	/* remove connlist */
	Ivyfreelist(stmtHandle->IvyconnList);
	stmtHandle->IvyconnList = NULL;

	free(stmtHandle->query);
	free(stmtHandle->stmtName);
	free(stmtHandle->paramTypes);

	if (stmtHandle->do_using_query)
	{
		free(stmtHandle->do_using_query);
		stmtHandle->do_using_query = NULL;
	}

	stmtHandle->query = NULL;
	PGSemaphoreUnlock(&stmtHandle->lock);
	ReleaseSemaphores(&stmtHandle->lock);

	free(stmtHandle);
	stmtHandle = NULL;
	return;
}


/*
 * Ivyclear - like PGclear
 *	  free the memory associated with a PGresult
 */
void
Ivyclear(Ivyresult *tres)
{
	if (!tres)
		return;

	/* clean PGresult */
	PQclear(tres->result);
	free(tres);
	tres = NULL;

	return;
}


/*
 * like PQfinish, but do something more
 */
void
Ivyfinish(Ivyconn *tconn)
{
	if (tconn == NULL || tconn->conn == NULL)
		return;

	/* add lock */
	PGSemaphoreLock(&tconn->self_lock);
	if (tconn->conn == NULL)
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		return;
	}

	PQfinish(tconn->conn);
	tconn->conn = NULL;
	PGSemaphoreUnlock(&tconn->self_lock);
	ReleaseSemaphores(&tconn->self_lock);

	PGSemaphoreLock(&tconn->lock);
	IvyremoveConnRelation(tconn);

	/* free stmt list */
	Ivyfreelist(tconn->IvystmtHandleList);
	PGSemaphoreUnlock(&tconn->lock);
	ReleaseSemaphores(&tconn->lock);

	free(tconn);
	tconn = NULL;
	return;
}

/*
 * like PQstatus
 */
ConnStatusType
Ivystatus(const Ivyconn *tconn)
{
	if (!tconn || !tconn->conn)
		return CONNECTION_BAD;

	return tconn->conn->status;
}

/*
 * like PQexec
 */
Ivyresult *
Ivyexec(Ivyconn *tconn, const char *query)
{
	Ivyresult *tresult;

	if (!tconn || tconn->conn == NULL)
		return NULL;

	tresult = malloc(sizeof(Ivyresult));
	if (tresult == NULL)
		return NULL;

	PGSemaphoreLock(&tconn->self_lock);

	if (!tconn->conn || !PQexecStart(tconn->conn))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		free(tresult);
		return NULL;
	}
	if (!PQsendQuery(tconn->conn, query))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		free(tresult);
		return NULL;
	}
	tresult->result =  PQexecFinish(tconn->conn);
	tresult->off = 0;

	/* unlock its self lock */
	PGSemaphoreUnlock(&tconn->self_lock);

	return tresult;
}

/*
 * like PQresultStatus
 */
ExecStatusType
IvyresultStatus(const Ivyresult *res)
{
	if (!res || !res->result)
		return PGRES_FATAL_ERROR;

	return res->result->resultStatus;
}

/*
 * like PQnfields
 */
int
Ivynfields(const Ivyresult *res)
{
	if (!res || !res->result)
		return 0;

	return res->result->numAttributes - res->off;
}

/*
 * like PQfname
 */
char *
Ivyfname(const Ivyresult *res, int field_num)
{
	if (!res || !check_field_number(res->result, field_num + res->off))
		return NULL;

	if (res->result->attDescs)
		return res->result->attDescs[field_num + res->off].name;
	else
		return NULL;
}

/*
 * like PQntuples
 */
int
Ivyntuples(const Ivyresult *res)
{
	if (!res || !res->result)
		return 0;

	return res->result->ntups;
}

/*
 * like PQgetvalue
 */
char *
Ivygetvalue(const Ivyresult *res, int tup_num, int field_num)
{
	if (!res || !check_tuple_field_number(res->result, tup_num, field_num + res->off))
		return NULL;

	return res->result->tuples[tup_num][field_num + res->off].value;
}

/*
 * like PQerrorMessage
 */
char *
IvyerrorMessage(const Ivyconn *tconn)
{
	if (!tconn || !tconn->conn)
		return libpq_gettext("connection pointer is NULL\n");

	return tconn->conn->errorMessage.data;
}

/*
 * register out parameter by position
 *
 * stmthandle: stmt to save sql stmt informations
 * bindinfo: to save out parameter informations
 * position: the position of this out parameter
 * var: the address to save the out parameter value
 * val_size: the sizeof the var
 * indp: the index var like oci to save the out parameter
 *		0:  the result value is equal to or less than the val_size
 *		-1: the result value of this out parameter is null
 *		-2: the result value is more than the val_size plus INT_MAX
 *		positive integer: the result value is more than the
 *		val_size and the positive integer value = (result value - val_size) 
 *
 * replace_ok: this position can be binded repeatedly. 
 * if 1, it replaces original bind informations, 
 * if 0, then raise error.
 * errormsg: save some useful error messages
 * size_error_buf: the size of errormsg buf
 *
 * return 1 if bind succeeded, 0 if failed
 */
int
IvybindOutParameterByPos(IvyPreparedStatement *stmthandle,
						IvyBindOutInfo **bindinfo,
						int	position,
						void *var,
						size_t	val_size,
						int *indp,
						int	replace_ok,
						char *errormsg,
						size_t size_error_buf)
{
	return IvybindOutParameterByPosInternel(stmthandle,
						bindinfo,
						position,
						var,
						val_size,
						indp,
						replace_ok,
						errormsg,
						size_error_buf,
						true);
}

/*
 * only support Stmt and Error handle
 */
int
IvyHandleAlloc(const void *parent,
			void **hndlpp,
			ivy_handle_type type,
			size_t	size,
			void	**usermapp)
{
	int result = 0;

	switch(type)
	{
		case IVY_HANDLE_STMT:
		{
			IvyPreparedStatement *prepared = NULL;

			*hndlpp = malloc(sizeof(IvyPreparedStatement));
			if (*hndlpp == NULL)
				return result;

			memset(*hndlpp, 0x00, sizeof(IvyPreparedStatement));

			prepared = (IvyPreparedStatement *) *hndlpp;
			/* init s_lock */
			if (PGSemaphoreCreate(&prepared->lock) == 0)
			{
				free(prepared);
				return result;
			}

			prepared->query = NULL;
			prepared->stmtName = strdup("_ivy_name_stmt");
			prepared->nParams = -1;
			prepared->paramTypes = NULL;
			prepared->query_len = -1;
			prepared->IvyconnList = NULL;
			prepared->outbind = NULL;
			prepared->noutvars = 0;
			prepared->paramNames = NULL;
			prepared->namebind = NULL;
			prepared->name_replace = 0;
			prepared->stmttype = IVY_STMT_UNKNOW;
			prepared->do_using_query = NULL;
		}
		break;
		case IVY_HANDLE_ERROR:
		{
			IvyError *errhp;

			*hndlpp = malloc(sizeof(IvyError));
			if (*hndlpp == NULL)
				return result;

			errhp = (IvyError *) *hndlpp;
			errhp->err_buf_size = 256;
			errhp->error_msg = malloc(errhp->err_buf_size);
			if (errhp->error_msg == NULL)
			{
				free(errhp);
				return result;
			}
			memset(errhp->error_msg, 0x00, errhp->err_buf_size);
		}
		break;
		default:
			return result;
			break;
	}

	return 1;
}

/*
 * free handle, only support Stmt and Error
 */
void
IvyFreeHandle(void *handle, ivy_handle_type type)
{
	switch (type)
	{
		case IVY_HANDLE_STMT:
			IvyFreePreparedStatement((IvyPreparedStatement *) handle);
			break;
		case IVY_HANDLE_ERROR:
			{
				IvyError *herrhp = (IvyError *) handle;
				free(herrhp->error_msg);
				free(herrhp);
			}
			break;
		default:
			break;
	}
	return;
}


int
IvyStmtPrepare(IvyPreparedStatement *stmthandle,
					IvyError	*errhp,
					const char 	*query,
					size_t		query_len,
					int		language,
					int		mode)
{
	if (NULL == stmthandle || NULL == query )
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"stmthandle or query is null");
		return 0;
	}

	PGSemaphoreLock(&stmthandle->lock);

	if (stmthandle->query != NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, 
				"stmt has prepared a query");
		PGSemaphoreUnlock(&stmthandle->lock);

		return 0;
	}

	stmthandle->query_len = query_len;
	stmthandle->query = strdup(query);
	stmthandle->mode = mode;
	stmthandle->language = language;

	PGSemaphoreUnlock(&stmthandle->lock);

	return 1;
}



/*
 * internal function for out parameter binding
 */
static int
IvybindOutParameterByPosInternel(IvyPreparedStatement *stmthandle,
					IvyBindOutInfo **bindinfo,
					int	position,
					void *var,
					size_t	val_size,
					int *indp,
					int	replace_ok,
					char *errormsg,
					size_t size_error_buf,
					bool need_lock)
{
	int resultcolumnno = 0;
	bool free_bind = false;

	if (NULL == stmthandle || NULL == stmthandle->query)
	{
		snprintf(errormsg, size_error_buf, "%s", "stmt has already been freed");
		return 0;
	}

	if (position <= 0)
	{
		snprintf(errormsg, size_error_buf, "%s", "position is wrong");
		return 0;
	}

	if (*bindinfo == NULL)
	{
		*bindinfo = (IvyBindOutInfo *) malloc(sizeof(IvyBindOutInfo));

		if (*bindinfo == NULL)
		{
			snprintf(errormsg, size_error_buf, "%s", "failed to allocate memory");
			return 0;
		}

		free_bind = true;
	}

	(*bindinfo)->next = NULL;
	(*bindinfo)->indp = indp;
	(*bindinfo)->val_size = val_size;
	(*bindinfo)->position = position;
	(*bindinfo)->var = var;

	/* lock the stmt, to avoid binding in two threads at the same time */
	if (need_lock)
		PGSemaphoreLock(&stmthandle->lock);

	/* check position again */
	if (position > stmthandle->nParams)
	{
		snprintf(errormsg, size_error_buf, "bind position is more than the stmt params");

		if (free_bind)
		{
			free(*bindinfo);
			*bindinfo = NULL;
		}

		if (need_lock)
			PGSemaphoreUnlock(&stmthandle->lock);

		return 0;
	}

	if (stmthandle->outbind == NULL)
	{
		stmthandle->outbind = *bindinfo;
	}
	else
	{
		IvyBindOutInfo *serbind = NULL;
		IvyBindOutInfo *prebind = NULL;

		/* find the bind which maps to resultcolumnno */
		for (serbind = stmthandle->outbind; 
			serbind != NULL; 
			prebind = serbind, serbind = serbind->next)
		{
			if (serbind->position < position)
				resultcolumnno++;
			else if (serbind->position > position)
				serbind->resultcolumnno++;
			else
			{
				if (replace_ok == 1)
				{
					/* replace its bind info */
					serbind->var = var;
					serbind->indp = indp;
					serbind->val_size = val_size;

					if (free_bind)
						free(*bindinfo);

					*bindinfo = serbind;

					if (need_lock)
						PGSemaphoreUnlock(&stmthandle->lock);

					return 1;
				}
				else
				{
					snprintf(errormsg, size_error_buf, "%s", "repeated bind variable");

					if (need_lock)
						PGSemaphoreUnlock(&stmthandle->lock);

					if (free_bind)
					{
						free(*bindinfo);
						*bindinfo = NULL;
					}

					return 0;
				}
			}
		}

		prebind->next = *bindinfo;
	}

	(*bindinfo)->resultcolumnno = resultcolumnno;
	stmthandle->noutvars++;

	if (stmthandle->do_using_query)
	{
		free(stmthandle->do_using_query);
		stmthandle->do_using_query = NULL;
	}

	if (need_lock)
		PGSemaphoreUnlock(&stmthandle->lock);

	return 1;
}

/*
 * BindPos internel function
 */
static int
IvyBindByPosInternel(IvyPreparedStatement *stmtHandle,
			IvyBindInfo **bindinfo,
			IvyError	*errhp,
			int	position,
			void *valuep,
			size_t	value_sz,
			int	dty,
			int *indp,
			char *alenp,
			char *recodep,
			int  maxarr_len,
			int  *curelep,
			int  mode,
			bool need_lock)
{
	bool free_bind = false;

	if (NULL == stmtHandle || NULL == stmtHandle->query)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "stmt has already been freed");
		return 0;
	}

	if (position <= 0)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "position is wrong");
		return 0;
	}

	if (*bindinfo == NULL)
	{
		*bindinfo = (IvyBindInfo *) malloc(sizeof(IvyBindOutInfo));

		if (*bindinfo == NULL)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "failed to allocate memory");
			return 0;
		}

		free_bind = true;
	}

	(*bindinfo)->next = NULL;
	(*bindinfo)->indp = indp;
	(*bindinfo)->val_size = value_sz;
	(*bindinfo)->position = position;
	(*bindinfo)->dtype = dty;
	(*bindinfo)->var = valuep;
	(*bindinfo)->recodep = recodep;
	(*bindinfo)->alenp = alenp;
	(*bindinfo)->maxarr_len = maxarr_len;
	(*bindinfo)->mode = mode;
	(*bindinfo)->curelep = curelep;

	/* lock the stmt, to avoid binding in two threads at the same time */
	if (need_lock)
		PGSemaphoreLock(&stmtHandle->lock);

	/* check position again */
	if (position > stmtHandle->nParams && stmtHandle->nParams != -1)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "bind position is more than the stmt params");

		if (free_bind)
		{
			free(*bindinfo);
			*bindinfo = NULL;
		}

		if (need_lock)
			PGSemaphoreUnlock(&stmtHandle->lock);

		return 0;
	}

	if (stmtHandle->outbind == NULL)
	{
		stmtHandle->outbind = *bindinfo;
	}
	else
	{
		IvyBindOutInfo *prebind = NULL;
		IvyBindOutInfo *serbind = NULL;

		/* find the bind which maps to resultcolumnno */
		for (serbind = stmtHandle->outbind; 
			serbind != NULL; 
			prebind = serbind, serbind = serbind->next)
		{
			if (serbind->position == position)
			{
				/* replace its bind info */
				serbind->val_size = value_sz;
				serbind->indp = indp;
				serbind->dtype = dty;
				serbind->var = valuep;
				serbind->alenp = alenp;
				serbind->recodep = recodep;
				serbind->maxarr_len = maxarr_len;
				serbind->mode = mode;
				serbind->curelep = curelep;

				if (free_bind)
					free(*bindinfo);

				*bindinfo = serbind;

				if (need_lock)
					PGSemaphoreUnlock(&stmtHandle->lock);

				return 1;
			}
		}

		prebind->next = *bindinfo;
	}

	(*bindinfo)->resultcolumnno = -1;

	if (stmtHandle->do_using_query)
	{
		free(stmtHandle->do_using_query);
		stmtHandle->do_using_query = NULL;
	}

	if (need_lock)
		PGSemaphoreUnlock(&stmtHandle->lock);

	return 1;
}

/*
 * Exec command 
 */
static int
IvyExecCommand(PGconn *conn, const char *query)
{
	PGresult *res = NULL;

	if (NULL == conn)
		return 0;

	res = PQexec(conn, query);

	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		PQclear(res);
		return 0;
	}

	PQclear(res);
	return 1;
}

/*
 * find column field number according to columnname
 */
static int
get_field_number_from_coluname(PGresult *res, const char *column)
{
	int i;
	int ret = -1;

	if (res == NULL)
		return -1;

	for (i = 0; i <  res->numAttributes; i++)
	{
		if (strcmp(res->attDescs[i].name, column) == 0)
		{
			ret = i;
			break;
		}
	}

	return ret;
}

/*
 * use column name to get realy result of column, 
 * this is because OUT paramters are put before the result.
 */
static int
get_result_off(PGresult *res)
{
	int i;
	int ret = 0;
	const char *extral_column = "_column_";
	size_t check_extral_column_len = strlen(extral_column);

	if (res == NULL)
		return -1;

	for (i = 0; i <  res->numAttributes; i++)
	{
		char *column = res->attDescs[i].name;

		if (strlen(column) > check_extral_column_len &&
			strncmp(column, extral_column, check_extral_column_len) == 0)
			ret++;
		else
			break;
	}

	return ret;
}

/*
 * get the number of parameters
 */
static int
IvyGetParameterNum(IvyPreparedStatement *stmtHandle)
{
	IvyBindInfo *tmp = NULL;
	int ret = 0;

	for (tmp = stmtHandle->outbind; 
		tmp != NULL; 
		tmp = tmp->next)
	{
		ret++;
	}

	return ret;
}

/*
 * assign parameter types from bind information
 */
static int
IvyAssignParameterTypes(IvyError *errhp, IvyPreparedStatement *stmtHandle)
{
	IvyBindOutNameInfo *tmp = NULL;

	/*
	 * reset param types
	 */
	if (stmtHandle->paramTypes != NULL)
	{
		free(stmtHandle->paramTypes);
		stmtHandle->paramTypes = NULL;
	}

	if (stmtHandle->nParams <= 0)
		return 0;

	stmtHandle->paramTypes = malloc(sizeof(Oid) * stmtHandle->nParams);

	if (stmtHandle->paramTypes == NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "malloc failed");
		return 0;
	}

	memset(stmtHandle->paramTypes, 0x00, sizeof(Oid) * stmtHandle->nParams);

	/*
	 * construct param types
	 */
	{
		int cur = 0;
		IvyBindInfo *tmp1 = NULL;

		for (tmp1 = stmtHandle->outbind; 
			tmp1 != NULL; 
			tmp1 = tmp1->next)
		{
			stmtHandle->paramTypes[tmp1->position - 1] = (Oid) tmp1->dtype;
			cur++;
		}

		if (cur < stmtHandle->nParams)
		{
			for (cur = 0; cur < stmtHandle->nParams; cur++)
			{
				bool found = false;

				if (stmtHandle->paramTypes[cur] != 0)
					continue;

				/* find the name in the namebind */
				for (tmp = stmtHandle->namebind; tmp != NULL; tmp = tmp->next)
				{
					if (strcmp(stmtHandle->paramNames[cur], tmp->name) == 0)
					{
						found = true;
						break;
					}
				}

				if (!found)
				{
					snprintf(errhp->error_msg, errhp->err_buf_size, "placehold variable %d has no bind", cur);
					free(stmtHandle->paramTypes);
					stmtHandle->paramTypes = NULL;

					return 0;
				}

				stmtHandle->paramTypes[cur] = tmp->dtype;
			}
		}
	}

	return 1;
}

/*
 * plisql using parameter
 * we should change it to "do + using xxx grammar"
 */
static int
IvyHandleDostmt(Ivyconn *tconn,
		IvyPreparedStatement *stmtHandle,
		bool noparams_info,
		char *errmsg,
		size_t err_buf_size)
{
	PQExpBuffer	query_buf;
	int nparams = 0;
	int i = 0;
	int	maxcharlen;

	Assert(stmtHandle->stmttype == IVY_STMT_DO);

	if (stmtHandle->namebind == NULL &&
		stmtHandle->outbind == NULL)
	{
		snprintf(errmsg, err_buf_size, "%s",
			"plisql should bind by name or position");

		return 0;
	}

	if (stmtHandle->namebind != NULL &&
		stmtHandle->outbind != NULL)
	{
		snprintf(errmsg, err_buf_size, "%s",
			"plisql should not bind by name and position at the same time");

		return 0;
	}

	query_buf = createPQExpBuffer();

	/* append do $$ */
	appendPQExpBuffer(query_buf, "do $$ %s $$ using ", stmtHandle->query);

	maxcharlen = pg_encoding_max_length(tconn->conn->client_encoding);

	if (noparams_info)
	{
		/* append parameter mode */
		if (stmtHandle->namebind != NULL)
		{
			IvyBindNameInfo *nameinfo = stmtHandle->namebind;

			/*
			 * we assume all parameters are inout mode
			 */
			for(; nameinfo != NULL; nameinfo = nameinfo->next)
			{
				appendPQExpBuffer(query_buf, "%s INOUT,", nameinfo->name);
				nparams++;
			}

			stmtHandle->nParams = nparams;
			stmtHandle->paramTypes = malloc(sizeof(Oid) * nparams);
			if (stmtHandle->paramTypes == NULL)
			{
				snprintf(errmsg, err_buf_size, "%s",
							"failed to allocate memory");

				destroyPQExpBuffer(query_buf);

				return 0;
			}

			stmtHandle->paramNames = malloc(sizeof(char *) * nparams);
			if (stmtHandle->paramNames == NULL)
			{
				snprintf(errmsg, err_buf_size, "%s",
							"failed to allocate memory");

				destroyPQExpBuffer(query_buf);

				return 0;
			}

			memset(stmtHandle->paramNames, 0x00, sizeof(char *) * nparams);

			query_buf->data[query_buf->len - 1] = ' ';
			appendPQExpBufferStr(query_buf, "paramslength ");

			for (nameinfo = stmtHandle->namebind; 
				nameinfo != NULL; 
				nameinfo = nameinfo->next)
			{
				size_t size_char;

				size_char = strlen(nameinfo->name) + 1;
				stmtHandle->paramNames[i] = malloc(size_char);
				if (stmtHandle->paramNames[i] == NULL)
				{
					snprintf(errmsg, err_buf_size, "%s",
							"failed to allocate memory");

					destroyPQExpBuffer(query_buf);

					return 0;
				}

				memset(stmtHandle->paramNames[i], 0x00, size_char);
				memcpy(stmtHandle->paramNames[i], nameinfo->name, size_char - 1);
				stmtHandle->paramTypes[i++] = (Oid) nameinfo->dtype;

				switch(UnSetModeOut(nameinfo->dtype))
				{
					case 9000:	/* ORACHARCHAROID */
					case 9002:	/* ORAVARCHARCHAROID */
						appendPQExpBuffer(query_buf, "%d,", ((int)nameinfo->val_size - 1) / maxcharlen);
						break;
					case 9001:	/* ORACHARBYTEOID */
					case 9003:	/* ORAVARCHARBYTEOID */
						appendPQExpBuffer(query_buf, "%d,", (int)nameinfo->val_size - 1);
						break;
					default:
						appendPQExpBuffer(query_buf, "%d,", -1);
						break;
				}
			}
		}
		else
		{
			IvyBindInfo *info = stmtHandle->outbind;

			/*
			 * assume all parameters are inout mode
			 */
			for(; info != NULL; info = info->next)
			{
				appendPQExpBuffer(query_buf, "%s,", "INOUT");
				nparams++;
			}

			stmtHandle->nParams = nparams;
			stmtHandle->paramTypes = malloc(sizeof(Oid) * nparams);
			if (stmtHandle->paramTypes == NULL)
			{
				snprintf(errmsg, err_buf_size, "%s",
							"failed to allocate memory");

				destroyPQExpBuffer(query_buf);

				return 0;
			}

			query_buf->data[query_buf->len - 1] = ' ';
			appendPQExpBufferStr(query_buf, "paramslength ");

			for (i = 0; i < stmtHandle->nParams; i++)
			{
				for (info = stmtHandle->outbind; info != NULL; info = info->next)
				{
					if (info->position == i + 1)
						break;
				}

				stmtHandle->paramTypes[i] = (Oid) info->dtype;

				switch(UnSetModeOut(info->dtype))
				{
					case 9000:	/* ORACHARCHAROID */
					case 9002:	/* ORAVARCHARCHAROID */
						appendPQExpBuffer(query_buf, "%d,", ((int)info->val_size - 1) / maxcharlen);
						break;
					case 9001:	/* ORACHARBYTEOID */
					case 9003:	/* ORAVARCHARBYTEOID */
						appendPQExpBuffer(query_buf, "%d,", (int)info->val_size - 1);
						break;
					default:
						appendPQExpBuffer(query_buf, "%d,", -1);
						break;
				}
			}
		}
	}
	else
	{
		PQExpBuffer	clause_buf;

		clause_buf = createPQExpBuffer();
		appendPQExpBufferStr(clause_buf, "paramslength ");

		/* append parameter mode */
		if (stmtHandle->namebind != NULL)
		{
			IvyBindNameInfo *nameinfo = stmtHandle->namebind;

			/*
			 * we assume all parameter are inout mode
			 */
			for(; nameinfo != NULL; nameinfo = nameinfo->next)
			{
				appendPQExpBuffer(query_buf, "%s INOUT,", nameinfo->name);

				switch(UnSetModeOut(nameinfo->dtype))
				{
					case 9000:	/* ORACHARCHAROID */
					case 9002:	/* ORAVARCHARCHAROID */
						appendPQExpBuffer(clause_buf, "%d,", ((int)nameinfo->val_size - 1) / maxcharlen);
						break;
					case 9001:	/* ORACHARBYTEOID */
					case 9003:	/* ORAVARCHARBYTEOID */
						appendPQExpBuffer(clause_buf, "%d,", (int)nameinfo->val_size - 1);
						break;
					default:
						appendPQExpBuffer(clause_buf, "%d,", -1);
						break;
				}

				nparams++;
			}

			/* others doesn't bind, we assume it is in mode */
			for (; nparams < stmtHandle->nParams; nparams++)
			{
				appendPQExpBuffer(query_buf, "%s,", "IN");
				appendPQExpBuffer(clause_buf, "%d,", -1);
			}
		}
		else
		{
			IvyBindInfo *info = NULL;

			for (i = 0; i < stmtHandle->nParams; i++)
			{
				for (info = stmtHandle->outbind; info != NULL; info = info->next)
				{
					if (info->position == i + 1)
						break;
				}

				if (info != NULL)
				{
					appendPQExpBuffer(query_buf, "%s,", "INOUT");

					switch(UnSetModeOut(info->dtype))
					{
						case 9000:	/* ORACHARCHAROID */
						case 9002:	/* ORAVARCHARCHAROID */
							appendPQExpBuffer(clause_buf, "%d,", ((int)info->val_size - 1) / maxcharlen);
							break;
						case 9001:	/* ORACHARBYTEOID */
						case 9003:	/* ORAVARCHARBYTEOID */
							appendPQExpBuffer(clause_buf, "%d,", (int)info->val_size - 1);
							break;
						default:
							appendPQExpBuffer(clause_buf, "%d,", -1);
							break;
					}
				}
				else
				{
					appendPQExpBuffer(query_buf, "%s,", "IN");
					appendPQExpBuffer(clause_buf, "%d,", -1);
				}
			}
		}

		query_buf->data[query_buf->len - 1] = ' ';
		appendPQExpBuffer(query_buf, "%s", clause_buf->data);
		destroyPQExpBuffer(clause_buf);
	}

	/* replace the last , to ; */
	query_buf->data[query_buf->len - 1] = ';';

	/* record in stmthandle */
	stmtHandle->do_using_query = query_buf->data;
	stmtHandle->stmttype = IVY_STMT_DOHANDLED;

	return 1;
}


/*
 * Bind placeholdvar by its position
 */
int
IvyBindByPos(IvyPreparedStatement *stmtHandle,
		IvyBindInfo **bindinfo,
		IvyError	*errhp,
		int	position,
		void *valuep,
		size_t	value_sz,
		int	dty,
		int *indp,
		char *alenp,
		char *recodep,
		int  maxarr_len,
		int  *curelep,
		int  mode)
{
	return IvyBindByPosInternel(stmtHandle,
					bindinfo,
					errhp,
					position,
					valuep,
					value_sz,
					dty,
					indp,
					alenp,
					recodep,
					maxarr_len,
					curelep,
					mode,
					true);
}


/*
 * Bind placeholdvar by its name
 */
int
IvyBindByName(IvyPreparedStatement *stmtHandle,
		IvyBindInfo **bindinfo,
		IvyError	*errhp,
		const char	*name,
		size_t name_len,
		void *var,
		size_t	val_size,
		int	dty,
		int *indp,
		char *alenp,
		char *recodep,
		int  maxarr_len,
		int  *curelep,
		int  mode)
{
	IvyBindNameInfo *bindname = NULL;

	if (NULL == stmtHandle || NULL == stmtHandle->query)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "stmt has already been freed");
		return 0;
	}

	if (name == NULL || name_len <= 0)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "bind name is NULL");
		return 0;
	}

	bindname = (IvyBindNameInfo *) malloc(sizeof(IvyBindOutNameInfo));
	if (bindname == NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "failed to allocate memory");
		return 0;
	}

	bindname->indp = indp;
	bindname->bindinfo = bindinfo;
	bindname->name_len = name_len;
	bindname->name = (char *) name;
	bindname->next = NULL;
	bindname->var = var;
	bindname->val_size = val_size;
	bindname->dtype = dty;
	bindname->replace = 0;
	bindname->mode = mode;
	bindname->alenp = alenp;
	bindname->recodep = recodep;
	bindname->maxarr_len = maxarr_len;
	bindname->curelep = curelep;

	/* lock the stmt, to avoid binding in two threads at the same time */
	PGSemaphoreLock(&stmtHandle->lock);

	if (stmtHandle->namebind== NULL)
	{
		stmtHandle->namebind = bindname;
	}
	else
	{
		IvyBindOutNameInfo *serbind = NULL;
		IvyBindOutNameInfo *prebind = NULL;

		/* find the bind which maps to resultcolumnno */
		for (serbind = stmtHandle->namebind;
			serbind != NULL; 
			prebind = serbind, serbind = serbind->next)
		{
			if (strcmp(serbind->name, name) == 0)
			{
				/* replace its bind info */
				serbind->var = var;
				serbind->indp = indp;
				serbind->val_size = val_size;
				serbind->name = (char *) name;
				serbind->name_len = name_len;
				serbind->bindinfo = bindinfo;
				serbind->replace = 0;
				serbind->dtype = dty;
				serbind->mode = mode;
				serbind->alenp = alenp;
				serbind->recodep = recodep;
				serbind->maxarr_len = maxarr_len;
				serbind->curelep = curelep;

				free(bindname);
				PGSemaphoreUnlock(&stmtHandle->lock);

				return 1;
			}
		}

		prebind->next = bindname;
	}

	stmtHandle->name_replace = 0;
	if (stmtHandle->do_using_query)
	{
		free(stmtHandle->do_using_query);
		stmtHandle->do_using_query = NULL;
	}

	PGSemaphoreUnlock(&stmtHandle->lock);

	return 1;
}


/*
 * execute a prepared stmt
 */
Ivyresult *
IvyStmtExecute(Ivyconn *tconn,
		IvyPreparedStatement *stmtHandle,
		IvyError *errhp)
{
	Ivyresult *tresult = NULL;
	PGconn *conn = NULL;
	PGresult *presult = NULL;
	char 	**paramValues = NULL;
	int *paramLengths = NULL;
	int *paramFormats = NULL;
	bool	sendPrepare = true;
	int	i = 0;
	int resultFormat = 0;

	if (tconn == NULL || tconn->conn == NULL ||
		stmtHandle == NULL || stmtHandle->query == NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
			"connection or stmt is null");

		return NULL;
	}

	tresult = (Ivyresult *) malloc(sizeof(Ivyresult));
	if (tresult == NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
			"failed to allocate memory");

		return NULL;
	}

	/* send prepare stmt */

	/* first lock ivyconn and stmt */
	PGSemaphoreLock(&stmtHandle->lock);
	if (stmtHandle->query == NULL)
	{
		/* stmtHandle has already been freed */
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
			"stmt has already been freed");
		free(tresult);

		return NULL;
	}

	/* handle placeholder variables bind-by-name, change it to bind-by-position */
	if (stmtHandle->namebind != NULL &&
		stmtHandle->name_replace == 0 &&
		!Ivyreplacenamebindtoposition2(tconn, stmtHandle, errhp))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);

		return NULL;
	}
	else if (stmtHandle->stmttype == IVY_STMT_UNKNOW &&
			!Ivyreplacenamebindtoposition2(tconn, stmtHandle, errhp))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);

		return NULL;
	}

	/* process dostmt */
	if (stmtHandle->stmttype == IVY_STMT_DO &&
		!IvyHandleDostmt(tconn, stmtHandle, true, errhp->error_msg, errhp->err_buf_size))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);

		return NULL;
	}

	PGSemaphoreLock(&tconn->self_lock);
	conn = tconn->conn;

	if (!PQexecStart(conn))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);

		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
		free(tresult);

		return NULL;
	}

	/* find the stmt that has prepare in this connection */
	PGSemaphoreLock(&tconn->lock);
	if (tconn->IvystmtHandleList != NULL)
	{
		Ivylist *tmp;

		for (tmp = tconn->IvystmtHandleList; 
			tmp != NULL; 
			tmp = tmp->next)
		{
			if (tmp->value == stmtHandle)
			{
				sendPrepare = false;
				break;
			}
		}
	}

	/* if hasn't prepare yet */
	if (sendPrepare)
	{
		char *send_query;

		/* assign nparams */
		if (stmtHandle->nParams == -1)
			stmtHandle->nParams = IvyGetParameterNum(stmtHandle);

		/* assign parameter types */
		if (stmtHandle->stmttype != IVY_STMT_DOHANDLED &&
			!IvyAssignParameterTypes(errhp, stmtHandle))
		{
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);

			free(tresult);
			tresult = NULL;

			return NULL;
		}

		/* set ivorysql.out_parameter_column_position to true */
		if (!IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = true;"))
		{
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);

			free(tresult);
			tresult = NULL;
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"failed to set ivorysql.out_parameter_column_position");

			return NULL;
		}

		if (stmtHandle->stmttype == IVY_STMT_DOHANDLED)
			send_query = stmtHandle->do_using_query;
		else
			send_query = stmtHandle->query;

		/* send Prepare */
		if (!PQsendPrepare(conn, stmtHandle->stmtName, send_query,
					stmtHandle->nParams, stmtHandle->paramTypes))
		{
			/*
			 * Put the error handle assignment in front of the SET command,
			 * otherwise the execute of the SET command using the same connection
			 * conn will overwrite the error message text, resulting in failure to
			 * obtain the error message.
			 */
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));

			IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");

			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);

			free(tresult);

			return NULL;
		}

		presult = PQexecFinish(conn);
		if (PQresultStatus(presult) != PGRES_COMMAND_OK)
		{
			/* failed */
			/*
			 * Put the error handle assignment in front of the SET command,
			 * otherwise the execute of the SET command using the same connection
			 * conn will overwrite the error message text, resulting in failure to
			 * obtain the error message.
			 */
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));

			IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");

			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);

			PQclear(presult);
			free(tresult);
			return NULL;
		}
		PQclear(presult);

		IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");

		IvyaddRelationStmtHandleandConn(tconn, stmtHandle);
	}
	PGSemaphoreUnlock(&tconn->lock);

	if (!IvyhandleParamsValues(stmtHandle, &paramValues, &paramLengths, &paramFormats))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		tresult = NULL;
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "getParamsValues failed");
		return NULL;
	}

	/* send query */
	if (!PQsendQueryPrepared(conn, stmtHandle->stmtName, stmtHandle->nParams,
							(const char *const *) paramValues,
							paramLengths, paramFormats, resultFormat))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
		tresult = NULL;
		goto ERROR_HANDLE;
	}

	/* get presult */
	presult = PQexecFinish(conn);
	if (PQresultStatus(presult) != PGRES_TUPLES_OK &&
		PQresultStatus(presult) != PGRES_COMMAND_OK &&
		PQresultStatus(presult) != PGRES_EMPTY_QUERY)
	{
		PQclear(presult);
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
		tresult = NULL;
		goto ERROR_HANDLE;
	}
	PGSemaphoreUnlock(&tconn->self_lock);
	tresult->result = presult;
	tresult->off = get_result_off(presult);
	if (tresult->off == -1)
	{
		PQclear(presult);
		free(tresult);
		tresult = NULL;
		snprintf(errhp->error_msg, errhp->err_buf_size, "result is wrong");
		PGSemaphoreUnlock(&stmtHandle->lock);
		goto ERROR_HANDLE;
	}

	/* assign out parameters */
	if (stmtHandle->stmttype != IVY_STMT_DOHANDLED)
		IvyassignOutParameters2(tresult, stmtHandle->outbind);
	else
		IvyAssignPLISQLOutParameter(tresult, stmtHandle);

	PGSemaphoreUnlock(&stmtHandle->lock);

ERROR_HANDLE:
	for (i = 0; i < stmtHandle->nParams; i++)
	{
		if (paramValues[i] != NULL)
			free(paramValues[i]);
	}
	free(paramValues);
	free(paramLengths);
	free(paramFormats);
	paramValues = NULL;
	paramLengths = NULL;
	paramFormats = NULL;
	return tresult;
}

/* Begin - ReqID:SRS-CMD-PSQL */
/*
 * IvyStmtExecute2
 *
 * This is a variant of IvyStmtExecute. In IvyStmtExecute we
 * need to call get_parameter_description() to get the placeholder
 * information. But in IvyStmtExecute2,it provided by the caller.
 *
 * In PSQL, in order to be compatible with Oracle, we need to verify
 * whether the bind variable exists, so we must call get_parameter_description() 
 * in advance. We add this interface to reduce the additional performance
 * loss caused by meaningless calls to the get_parameter_description() function
 * within IvyStmtExecute.
 */
Ivyresult *
IvyStmtExecute2(Ivyconn *tconn,
					  IvyPreparedStatement *stmtHandle,
					  IvyError *errhp,
					  HostVariable *host)
{
	Ivyresult *tresult = NULL;
	PGconn *conn = NULL;
	PGresult *presult = NULL;
	bool	sendPrepare = true;
	char 	**paramValues = NULL;
	int *paramLengths = NULL;
	int *paramFormats = NULL;
	int	i;
	int resultFormat = 0;

	if (tconn == NULL || tconn->conn == NULL ||
		stmtHandle == NULL || stmtHandle->query == NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "connection or stmt is null");
		return NULL;
	}

	tresult = (Ivyresult *) malloc(sizeof(Ivyresult));
	if (tresult == NULL)
	{
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "malloc failed");
		return NULL;
	}

	/* send prepare stmt */
	/* first lock ivyconn and stmt */
	PGSemaphoreLock(&stmtHandle->lock);
	if (stmtHandle->query == NULL)
	{
		/* stmtHandle has already be freed */
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "stmt has already be freed");
		free(tresult);
		return NULL;
	}

	/* handle placevar bind byname, we replace it bind by position */
	if (stmtHandle->namebind != NULL &&
		stmtHandle->name_replace == 0 &&
		!Ivyreplacenamebindtoposition3(tconn, stmtHandle, errhp, host))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}
	else if (stmtHandle->stmttype == IVY_STMT_UNKNOW &&
			!Ivyreplacenamebindtoposition3(tconn, stmtHandle, errhp, host))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}

	/* handle dostmt */
	if (stmtHandle->stmttype == IVY_STMT_DO &&
		!IvyHandleDostmt(tconn, stmtHandle, true, errhp->error_msg, errhp->err_buf_size))
	{
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		return NULL;
	}

	PGSemaphoreLock(&tconn->self_lock);
	conn = tconn->conn;

	if (!PQexecStart(conn))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
		free(tresult);
		return NULL;
	}

	/* find this stmt has prepare in this connection */
	PGSemaphoreLock(&tconn->lock);
	if (tconn->IvystmtHandleList != NULL)
	{
		Ivylist *tmp;

		for (tmp = tconn->IvystmtHandleList; tmp != NULL; tmp = tmp->next)
		{
			if (tmp->value == stmtHandle)
			{
				sendPrepare = false;
				break;
			}
		}
	}

	/* if hasn't prepare */
	if (sendPrepare)
	{
		char *send_query;

		/* assing nparams */
		if (stmtHandle->nParams == -1)
			stmtHandle->nParams = IvyGetParameterNum(stmtHandle);

		/* assign parame types */
		if (stmtHandle->stmttype != IVY_STMT_DOHANDLED &&
			!IvyAssignParameterTypes(errhp, stmtHandle))
		{
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			free(tresult);
			tresult = NULL;
			return NULL;
		}

		/* set ivorysql.out_parameter_column_position to true */
		if (!IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = true;"))
		{
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			free(tresult);
			tresult = NULL;
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "ivorysql.out_parameter_column_position failed");
			return NULL;
		}

		if (stmtHandle->stmttype == IVY_STMT_DOHANDLED)
			send_query = stmtHandle->do_using_query;
		else
			send_query = stmtHandle->query;

		/* third send Prepare */
		if (!PQsendPrepare(conn, stmtHandle->stmtName, send_query,
							stmtHandle->nParams, stmtHandle->paramTypes))
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
			IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			free(tresult);
			return NULL;
		}
		presult = PQexecFinish(conn);
		if (PQresultStatus(presult) != PGRES_COMMAND_OK)
		{
			/* failed */
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
			IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");
			PGSemaphoreUnlock(&tconn->self_lock);
			PGSemaphoreUnlock(&stmtHandle->lock);
			PGSemaphoreUnlock(&tconn->lock);
			PQclear(presult);
			free(tresult);
			return NULL;
		}

		PQclear(presult);

		IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");

		IvyaddRelationStmtHandleandConn(tconn, stmtHandle);
	}

	PGSemaphoreUnlock(&tconn->lock);

	if (!IvyhandleParamsValues(stmtHandle, &paramValues, &paramLengths, &paramFormats))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);

		free(tresult);
		tresult = NULL;
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
			"IvyhandleParamsValues failed");

		return NULL;
	}

	/* set ivorysql.out_parameter_column_position to true */
	if (!IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = true;"))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);
		free(tresult);
		tresult = NULL;
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "ivorysql.out_parameter_column_position failed");
		return NULL;
	}

	/* send query */
	if (!PQsendQueryPrepared(conn, stmtHandle->stmtName, stmtHandle->nParams,
							(const char *const *) paramValues,
							paramLengths, paramFormats, resultFormat))
	{
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);

		free(tresult);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
		tresult = NULL;

		goto ERROR_HANDLE;
	}

	/* get presult */
	presult = PQexecFinish(conn);
	if (PQresultStatus(presult) != PGRES_TUPLES_OK &&
		PQresultStatus(presult) != PGRES_COMMAND_OK &&
		PQresultStatus(presult) != PGRES_EMPTY_QUERY)
	{
		PQclear(presult);
		PGSemaphoreUnlock(&tconn->self_lock);
		PGSemaphoreUnlock(&stmtHandle->lock);

		free(tresult);
		snprintf(errhp->error_msg, errhp->err_buf_size, "%s", PQerrorMessage(conn));
		tresult = NULL;

		goto ERROR_HANDLE;
	}

	PGSemaphoreUnlock(&tconn->self_lock);
	tresult->result = presult;
	tresult->off = get_result_off(presult);

	if (tresult->off == -1)
	{
		PQclear(presult);
		free(tresult);
		tresult = NULL;
		snprintf(errhp->error_msg, errhp->err_buf_size, "result is wrong");
		PGSemaphoreUnlock(&stmtHandle->lock);

		goto ERROR_HANDLE;
	}

	/* assign OUT parameters */
	if (stmtHandle->stmttype != IVY_STMT_DOHANDLED)
		IvyassignOutParameters2(tresult, stmtHandle->outbind);
	else
		IvyAssignPLISQLOutParameter(tresult, stmtHandle);

	PGSemaphoreUnlock(&stmtHandle->lock);

ERROR_HANDLE:
	IvyExecCommand(conn, "set ivorysql.out_parameter_column_position = false;");

	for (i = 0; i < stmtHandle->nParams; i++)
	{
		if (paramValues[i] != NULL)
			free(paramValues[i]);
	}

	free(paramValues);
	free(paramLengths);
	free(paramFormats);

	paramValues = NULL;
	paramLengths = NULL;
	paramFormats = NULL;

	return tresult;
}

/*
 *
 * register OUT parameter by name
 *
 * stmthandle: a stmt to save sql stmt informations
 * bindinfo: to save OUT parameter informations
 * position: the position of this OUT parameter
 * var: the address to save the OUT parameter value
 * val_size: the sizeof the var
 * indp: the index var like oci to save the OUT parameter
 *		0:  the result value is equal to or less then the val_size
 *		-1: the result value of this OUT parameter is null
 *		-2: the result value is more than the val_size plus INT_MAX
 *		positive integer: the result value is more than the
 *		val_size and the positive integer value = (result value - val_size)
 *
 * replace_ok: this position can be binded repeatedly, 
 * if 1, it replaces origin bind informations, 
 * if 0, then error raise.
 * errormsg: save some userful error messages
 * size_error_buf: the size of errormsg buf
 *
 * return 1 if bind succeeded, 0 if failed
 */
int
IvybindOutParameterByName(IvyPreparedStatement *stmthandle,
				IvyBindOutInfo **bindinfo,
				const char *name,
				size_t name_len,
				void *var,
				size_t	val_size,
				int *indp,
				int	replace_ok,
				char *errormsg,
				size_t size_error_buf)
{
	IvyBindOutNameInfo *bindname = NULL;

	if (NULL == stmthandle || NULL == stmthandle->query)
	{
		snprintf(errormsg, size_error_buf, "%s", 
			"stmt has already been freed");
		return 0;
	}

	if (NULL == name || name_len <= 0)
	{
		snprintf(errormsg, size_error_buf, "%s", 
			"bind name is wrong");
		return 0;
	}

	bindname = (IvyBindOutNameInfo *) malloc(sizeof(IvyBindOutNameInfo));
	if (bindname == NULL)
	{
		snprintf(errormsg, size_error_buf, "%s", 
			"failed to allocate memory");
		return 0;
	}

	bindname->indp = indp;
	bindname->bindinfo = bindinfo;
	bindname->name = (char *) name;
	bindname->name_len = name_len;
	bindname->replace = 0;
	bindname->var = var;
	bindname->next = NULL;
	bindname->val_size = val_size;

	/* lock the stmt, to avoid bind in two threads at the same time */
	PGSemaphoreLock(&stmthandle->lock);

	if (stmthandle->namebind== NULL)
	{
		stmthandle->namebind = bindname;
	}
	else
	{
		IvyBindOutNameInfo *serbind = NULL;
		IvyBindOutNameInfo *prebind = NULL;

		/* find the bind which maps to resultcolumnno */
		for (serbind = stmthandle->namebind; 
			serbind != NULL; 
			prebind = serbind, serbind = serbind->next)
		{
			if (strcmp(serbind->name, name) == 0)
			{
				if (replace_ok == 1)
				{
					/* replace the bound info */
					serbind->var = var;
					serbind->indp = indp;
					serbind->val_size = val_size;
					serbind->name = (char *) name;
					serbind->replace = 0;
					serbind->name_len = name_len;
					serbind->bindinfo = bindinfo;

					free(bindname);
					PGSemaphoreUnlock(&stmthandle->lock);

					return 1;
				}
				else
				{
					snprintf(errormsg, size_error_buf, "%s", "repeat bind variable");
					PGSemaphoreUnlock(&stmthandle->lock);

					free(bindname);
					*bindinfo = NULL;

					return 0;
				}
			}
		}

		prebind->next = bindname;
	}

	stmthandle->name_replace = 0;
	if (stmthandle->do_using_query)
	{
		free(stmthandle->do_using_query);
		stmthandle->do_using_query = NULL;
	}

	PGSemaphoreUnlock(&stmthandle->lock);

	return 1;
}

/*
 *
 * copy OUT parameters from result
 */
static void
IvyassignOutParameters(const Ivyresult *tres, IvyBindOutInfo *outbind)
{
	if (outbind == NULL)
		return;

	/* no result, we set indp to -1 */
	if (NULL == tres || NULL == tres->result)
	{
		IvyBindOutInfo *serbind;

		for (serbind = outbind; 
			serbind != NULL; 
			serbind = serbind->next)
		{
			if (serbind->indp != NULL)
				*(serbind->indp) = -1;
		}

		return;
	}
	else
	{
		IvyBindOutInfo *serbind;
		PGresult	*res = tres->result;

		for (serbind = outbind; serbind != NULL; serbind = serbind->next)
		{
			/* position is incorrect */
			if (!check_field_number(res, serbind->resultcolumnno))
			{
				if (serbind->indp != NULL)
					*(serbind->indp) = -1;
			}
			else
			{
				struct pgresAttValue *attrvalue;

				attrvalue = &res->tuples[0][serbind->resultcolumnno];
				if (attrvalue->len > 0 && attrvalue->len > serbind->val_size)
				{
					unsigned int diff = attrvalue->len - serbind->val_size;

					if (diff > INT_MAX)
					{
						if (serbind->indp != NULL)
							*(serbind->indp) = -2;
					}
					else if (serbind->indp != NULL)
					{
						*(serbind->indp) = diff;
					}

					memcpy(serbind->var, attrvalue->value, serbind->val_size);
				}
				else
				{
					if (attrvalue->len <= 0)
					{	
						if (serbind->indp != NULL)
							*(serbind->indp) = -1;
					}
					else
					{
						if (serbind->indp != NULL)
							*(serbind->indp) = 0;

						memcpy(serbind->var, attrvalue->value, attrvalue->len);
					}
				}
			}
		}
	}
}

static void
IvyreplaceParamTypeByOutParameter(IvyBindOutInfo *bindinfo, int nParams, Oid *paramTypes, const Ivyargmode *argmodes)
{
	IvyBindOutInfo *serbind;

	Assert(bindinfo != NULL);

	if (nParams <= 0)
		return;

	for (serbind = bindinfo; serbind != NULL; serbind = serbind->next)
	{
		if (serbind->position <= nParams)
		{
			/* just OUT mode parameter, we replace its oid with a virtual oid */
			if (argmodes != NULL && argmodes[serbind->position - 1] == argmode_out)
				SetModeOut(paramTypes[serbind->position - 1]);
			else if (argmodes != NULL && argmodes[serbind->position - 1] == argmode_out)
				SetModeIn(paramTypes[serbind->position - 1]);
		}
		else
		{
			fprintf(stderr, "position :%d is more than nparams %d", serbind->position, nParams);
			return;
		}
	}

	return;
}

/*
 * add value to list
 * if there is value in the list already, 
 * don't append.
 */
static Ivylist*
IvyaddValueToList(Ivylist *list, void *value)
{
	if (list == NULL)
	{
		Ivylist *new = (Ivylist *) malloc(sizeof(Ivylist));

		if (new == NULL)
		{
			fprintf(stderr, "failed to allocate memory");

			return NULL;
		}

		new->next = NULL;
		new->value = value;

		return new;
	}

	Ivylist *pre = NULL;
	Ivylist *tmp = NULL;
	int find = 0;

	for (tmp = list, pre = list; tmp != NULL; pre = tmp, tmp = tmp->next)
	{
		if (tmp->value == value)
		{
			find = 1;
			break;
		}
	}

	/* if no found then add */
	if (find == 0)
	{
		Ivylist *new = (Ivylist *) malloc(sizeof(Ivylist));

		if (new == NULL)
			return NULL;

		new->next = NULL;
		new->value = value;
		pre->next = new;
	}

	return list;
}


/*
 * remove value from list
 */
static Ivylist*
IvyremoveValueFromList(Ivylist *list, void *value)
{
	Ivylist *pre = NULL;
	Ivylist *tmp = NULL;

	if (list == NULL)
		return NULL;


	/* if no found then return */
	for (pre = list, tmp = list; tmp->next != NULL; pre = tmp, tmp = tmp->next)
	{
		if (tmp->value == value)
			break;
	}

	if (tmp->value == value)
	{
		if (pre == tmp)
		{
			Ivylist *result;

			if (pre->next != NULL)
				result = pre->next;
			else
				result = NULL;

			free(tmp);
			return result;
		}
		else
		{
			pre->next = tmp->next;
			free(tmp);
			return list;
		}
	}

	/* no found */
	return list;
}

/*
 * this function records the relationship
 * of the connection and the stmtment, so that
 * if the stmt is dropped, we can dealloc the stmt
 * in the connection, and don't send preapre 
 * in same connection.
 */

static void
IvyaddRelationStmtHandleandConn(Ivyconn *tconn, IvyPreparedStatement *stmtHandle)
{
	Ivylist *tconnlist = stmtHandle->IvyconnList;
	Ivylist *stmtHlist = tconn->IvystmtHandleList;

	tconn->IvystmtHandleList = IvyaddValueToList(stmtHlist, (void *) stmtHandle);

	/* add tconn to connList */
	stmtHandle->IvyconnList = IvyaddValueToList(tconnlist, (void *) tconn);

	return;
}

/*
 * remove relationship of stmthandle in connection
 */
static void
IvyremoveStmtHandleRelation(IvyPreparedStatement *stmtHandle)
{
	Ivylist *tmp = NULL;

	if (stmtHandle->IvyconnList == NULL)
		return;

	for (tmp = stmtHandle->IvyconnList; tmp != NULL; tmp = tmp->next)
	{
		Ivyconn *tconn = (Ivyconn *) tmp->value;
		Ivyresult *tresult = NULL;
		char	buf[256];
		int	len;

		memset(buf, 0x00, 256);
		len = snprintf(buf, 256, "DEALLOCATE %s", stmtHandle->stmtName);

		if (len >= 255)
			fprintf(stderr, "length of stmt name is  more than 245 bytes\n");

		/* deallocate stmt */
		tresult = Ivyexec(tconn, (const char *) buf);
		if (IvyresultStatus(tresult) != PGRES_COMMAND_OK)
		{
			if (tconn->conn == NULL)
				fprintf(stderr, "deallocate stmt %s failed because connection is gone\n", buf);
			else
				fprintf(stderr, "deallocate stmt %s failed\n", buf);
		}

		Ivyclear(tresult);

		/* conn may be null due to other threads call Ivyclean() */
		if (tconn->conn != NULL)
		{
			PGSemaphoreLock(&tconn->lock);
			tconn->IvystmtHandleList = IvyremoveValueFromList(tconn->IvystmtHandleList, (void *) stmtHandle);
			PGSemaphoreUnlock(&tconn->lock);
		}
	}

	return;
}

/*
 * remove relationship of connection in stmt
 */
static void
IvyremoveConnRelation(Ivyconn *tconn)
{
	Ivylist *tmp = NULL;

	if (tconn->IvystmtHandleList == NULL)
		return;

	for (tmp = tconn->IvystmtHandleList; tmp != NULL; tmp = tmp->next)
	{
		IvyPreparedStatement *tprepare = (IvyPreparedStatement *) tmp->value;

		if (tprepare->query != NULL)
		{
			PGSemaphoreLock(&tprepare->lock);
			tprepare->IvyconnList = IvyremoveValueFromList(tprepare->IvyconnList, (void *) tconn);
			PGSemaphoreUnlock(&tprepare->lock);
		}
	}

	return;
}

/*
 *
 * free Ivylist 
 */
static void
Ivyfreelist(Ivylist *list)
{
	Ivylist *next;

	while (list != NULL)
	{
		next = list->next;
		free(list);
		list = next;
	}

	return;
}

/*
 * like IvyassignOutParameters, assign by _column_%d
 */
static void
IvyassignOutParameters2(const Ivyresult *tres, IvyBindOutInfo *outbind)
{
	IvyBindOutInfo *serbind;
	PGresult	*res = tres->result;
	PQExpBuffer	column_buf;

	if (outbind == NULL)
		return;

	/* no result, we return */
	if (tres == NULL || tres->result == NULL )
		return;

	column_buf = createPQExpBuffer();

	for (serbind = outbind; serbind != NULL; serbind = serbind->next)
	{
		appendPQExpBuffer(column_buf, "_column_%d", serbind->position);
		assign_value_internel(res,
					column_buf->data,
					serbind->indp,
					serbind->var,
					serbind->val_size,
					serbind->dtype);

		resetPQExpBuffer(column_buf);
	}

	destroyPQExpBuffer(column_buf);

	return;
}

/*
 * assign values for OUT parameters in plisql anonymous block
 */
static void
IvyAssignPLISQLOutParameter(const Ivyresult *tres,
				IvyPreparedStatement *stmtHandle)
{
	PGresult	*res = tres->result;
	PQExpBuffer 	column_buf;

	if (stmtHandle->namebind == NULL && stmtHandle->outbind == NULL)
		return;

	/* no result, return */
	if (tres == NULL || tres->result == NULL )
		return;

	column_buf = createPQExpBuffer();

	if (stmtHandle->namebind != NULL)
	{
		IvyBindNameInfo *nameinfo;

		for (nameinfo = stmtHandle->namebind; nameinfo != NULL; nameinfo = nameinfo->next)
		{
			appendPQExpBuffer(column_buf, "%s", nameinfo->name);
			assign_value_internel(res,
						column_buf->data,
						nameinfo->indp,
						nameinfo->var,
						nameinfo->val_size,
						nameinfo->dtype);

			resetPQExpBuffer(column_buf);
		}
	}
	else if (stmtHandle->outbind != NULL)
	{
		IvyBindOutInfo *serbind;

		for (serbind = stmtHandle->outbind; serbind != NULL; serbind = serbind->next)
		{
			/* plisql return out by $number */
			appendPQExpBuffer(column_buf, "$%d", serbind->position);
			assign_value_internel(res,
						column_buf->data,
						serbind->indp,
						serbind->var,
						serbind->val_size,
						serbind->dtype);

			resetPQExpBuffer(column_buf);
		}
	}

	destroyPQExpBuffer(column_buf);
}

/*
 * get bind variable value type
 */
static ivy_value_type
get_paramvalue_type(int type)
{
	ivy_value_type ret = IVY_VALUE_BYTE;

	switch (UnSetModeOut(type))
	{
		case 21:	//INT2
			ret = IVY_VALUE_INTEGER;
			break;
		case 1005:	//INT2_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 23:	//INT4
			ret = IVY_VALUE_INTEGER;
			break;
		case 1007:	//INT4_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 20:	//INT8
			ret = IVY_VALUE_BIGINTEGER;
			break;
		case 1016:	//INT8_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 25:	//TEXT
			ret = IVY_VALUE_BYTE;
			break;
		case 1009:	//TEXT_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 1700:	//NUMERIC
			ret = IVY_VALUE_FLOAT;
			break;
		case 1231:	//NUMERIC_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 700:	//FLOAT4
			ret = IVY_VALUE_FLOAT;
			break;
		case 1021:	//FLOAT4_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 701:	//FLOAT8
			ret = IVY_VALUE_FLOAT;
			break;
		case 1022:	//FLOAT8_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 16:		//BOOL
			ret = IVY_VALUE_INTEGER;
			break;
		case 1000:	//BOOL_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 1082:	//DATE
			ret = IVY_VALUE_BYTE;
			break;
		case 1182:	//DATE_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 1083:	//TIME
			ret = IVY_VALUE_BYTE;
			break;
		case 1183:	//TIME_ARRAY
		case 1266:	//TIMETZ
		case 1270:	//TIMETZ_ARRAY
		case 1114:	//TIMESTAMP
		case 1115:	//TIMESTAMP_ARRAY
		case 1184:	//TIMESTAMPTZ
		case 1185:	//TIMESTAMPTZ_ARRAY
		case 17:	//BYTEA
		case 1001:	//BYTEA_ARRAY
		case 1043:	//VARCHAR
		case 1015:	//VARCHAR_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		case 26:	//OID
			ret = IVY_VALUE_INTEGER;
			break;
		case 1028:	//OID_ARRAY
		case 1042:	//BPCHAR
		case 1014:	//BPCHAR_ARRAY
		case 790:	//MONEY
		case 791:	//MONEY_ARRAY
		case 19:	//NAME
		case 1003:	//NAME_ARRAY
		case 1560:	//BIT
		case 1561:	//BIT_ARRAY
		case 2278:	//VOID
		case 1186:	//INTERVAL
		case 1187:	//INTERVAL_ARRAY
		case 18:	//CHAR
		case 1002:	//CHAR_ARRAY
		case 1562:	//VARBIT
		case 1563:	//VARBIT_ARRAY
		case 2950:	//UUID
		case 2951:	//UUID_ARRAY
		case 142:	//XML
		case 143:	//XML_ARRAY
		case 600:	//POINT
		case 1017:	//POINT_ARRAY
		case 603:	//BOX
		case 3807:	//JSONB_ARRAY
		case 114:	//JSON
		case 199:	//JSON_ARRAY
		case 1790:	//REF_CURSOR
		case 2201:	//REF_CURSOR_ARRAY
		 /* oracle support type */
		case 9000:	//ORACHARCHAR
		case 9004:	//ORACHARCHAR_ARRAY
		case 9001:	//ORACHARBYTE
		case 9005:	//ORACHARBYTE_ARRAY
		case 9002:	//ORAVARCHARCHAR
		case 9006:	//ORAVARCHARCHAR_ARRAY
		case 9003:	//ORAVARCHARBYTE
		case 9007:	//ORAVARCHARBYTE_ARRAY
		case 9008:	//ORADATE
		case 9009:	//ORADATE_ARRAY
		case 9010:	//ORATIMESTAMP
		case 9011:	//ORATIMESTAMP_ARRAY
		case 9012:	//ORATIMESTAMPTZ
		case 9013:	//ORATIMESTAMPTZ_ARRAY
		case 9014:	//ORATIMESTAMPLTZ
		case 9015:	//ORATIMESTAMPLTZ_ARRAY
		case 9016: // YMINTERVAL
		case 9017: // YMINTERVAL_ARRAY
		case 9018: // DSINTERVAL
		case 9019: // DSINTERVAL_ARRAY
		case 9020: // NUMBER
		case 9021: // NUMBER_ARRAY
		case 9022: // BINARY_FLOAT
		case 9023: // BINARY_FLOAT_ARRAY
		case 9024: // BINARY_DOUBLE
		case 9025: // BINARY_DOUBLE_ARRAY
		case 9030: // ORAREFCURSOR
		case 9031:  // ORAREFCURSOR_ARRAY
			ret = IVY_VALUE_BYTE;
			break;
		default:
			ret = IVY_VALUE_BYTE;
			break;
	}
	return ret;
}

/*
 * assign OUT parameter according to column value
 */
static void
assign_value_internel(PGresult *res, char *column,
			int *indp, void *bindvar,
			size_t bindvar_size, int dtype)
{
	int resultcolumno = -1;
	ivy_value_type	value_type;

	resultcolumno = get_field_number_from_coluname(res, column);
	value_type = get_paramvalue_type(dtype);

	if (resultcolumno >= 0)
	{
		struct pgresAttValue *attrvalue;

		attrvalue = &res->tuples[0][resultcolumno];

		/* null value */
		if (attrvalue->len <= 0)
		{
			if (indp != NULL)
				*indp = -1;

			return;
		}

		memset(bindvar, 0x00, bindvar_size);
		switch (value_type)
		{
			case IVY_VALUE_BYTE:
			{
				if (attrvalue->len > bindvar_size)
				{
					unsigned int diff = attrvalue->len - bindvar_size;

					if (diff > INT_MAX)
					{
						if (indp != NULL)
							*indp = -2;
					}
					else if (indp != NULL)
						*indp = diff;
					memcpy(bindvar, attrvalue->value, bindvar_size);
				}
				else
				{
					if (indp != NULL)
						*indp = 0;
					memcpy(bindvar, attrvalue->value, attrvalue->len);
				}
			}
			break;
			case IVY_VALUE_INTEGER:
			{
				int int_value;
				unsigned int diff = sizeof(int) - bindvar_size;

				int_value = atoi(attrvalue->value);
				if (indp != NULL)
					*indp = diff;
				*((int *) bindvar) = int_value;
			}
			break;
			case IVY_VALUE_BIGINTEGER:
			{
				long long_value;
				unsigned int diff = sizeof(long) - bindvar_size;

				long_value = atol(attrvalue->value);
				if (indp != NULL)
					*indp = diff;
				*((long *) bindvar) = long_value;
			}
			break;
			case IVY_VALUE_FLOAT:
			{
				float float_value;
				unsigned int diff = sizeof(float) - bindvar_size;

				float_value = atof(attrvalue->value);
				if (indp != NULL)
					*indp = diff;
				*((float *) bindvar) = float_value;
			}
			break;
			default:
			if (indp != NULL)
				*indp = -2;
			break;
		}
	}
	return;
}

/*
 * construct param informations from handle
 */
static int
IvyhandleParamsValues(IvyPreparedStatement *stmtHandle,
			char  ***paramValuesp,
			int **paramLengthsp,
			int **paramFormatsp)
{
	int i;

	if (stmtHandle->nParams == 0)
		return 0;

	*paramValuesp = malloc(sizeof(char *) * stmtHandle->nParams);
	if (*paramValuesp == NULL)
		return 0;

	*paramLengthsp = malloc(sizeof(int) * stmtHandle->nParams);
	if (*paramLengthsp == NULL)
	{
		free(*paramValuesp);
		return 0;
	}

	*paramFormatsp = malloc(sizeof(int) * stmtHandle->nParams);
	if (*paramFormatsp == NULL)
	{
		free(*paramValuesp);
		free(*paramLengthsp);
		return 0;
	}

	memset(*paramValuesp, 0x00, sizeof(char *) * stmtHandle->nParams);
	memset(*paramLengthsp, 0x00, sizeof(int) * stmtHandle->nParams);
	memset(*paramFormatsp, 0x00, sizeof(int) * stmtHandle->nParams);

	for (i = 0; i < stmtHandle->nParams; i++)
	{
		IvyBindInfo *tmp;

		for (tmp = stmtHandle->outbind; tmp != NULL; tmp = tmp->next)
		{
			if (tmp->position == i + 1)
				break;
		}

		if (tmp != NULL)
		{
			int len;
			char buf[256];

			if (*tmp->indp == -1)
				continue;

			memset(buf, 0x00, 256);

			switch (get_paramvalue_type(tmp->dtype))
			{
				case IVY_VALUE_BIGINTEGER:
					len = snprintf(buf, 256, "%ld", *((long *)tmp->var));
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], buf, len);
					break;

				case IVY_VALUE_INTEGER:
					len = snprintf(buf, 256, "%d", *((int *) tmp->var));
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], buf, len);
					break;

				case IVY_VALUE_FLOAT:
					len = snprintf(buf, 256, "%f", *((float *)tmp->var));
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], buf, len);
					break;

				case IVY_VALUE_BYTE:
					len = tmp->val_size;
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], tmp->var, len);
					break;

				default:
					goto ERROR_HANDLE;
					break;
			}

			(*paramLengthsp)[i] = len;
			(*paramFormatsp)[i]  = 0;
		}
		else
		{
			IvyBindNameInfo *tmp1 = NULL;
			int len;
			char buf[256];

			memset(buf, 0x00, 256);

			for (tmp1 = stmtHandle->namebind; tmp1 != NULL; tmp1 = tmp1->next)
			{
				if (strcmp(tmp1->name, stmtHandle->paramNames[i]) == 0)
					break;
			}

			if (tmp1 == NULL)
				goto ERROR_HANDLE;

			if (*tmp1->indp == -1)
				continue;

			switch (get_paramvalue_type(tmp1->dtype))
			{
				case IVY_VALUE_BIGINTEGER:
					len = snprintf(buf, 256, "%ld", *((long *)tmp1->var));
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], buf, len);
					break;

				case IVY_VALUE_INTEGER:
					len = snprintf(buf, 256, "%d", *((int *)tmp1->var));
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], buf, len);
					break;

				case IVY_VALUE_FLOAT:
					len = snprintf(buf, 256, "%f", *((float *)tmp1->var));
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], buf, len);
					break;

				case IVY_VALUE_BYTE:
					len = tmp1->val_size;
					(*paramValuesp)[i] = (char *) malloc(len + 1);

					if ((*paramValuesp)[i] == NULL)
						goto ERROR_HANDLE;

					memset((*paramValuesp)[i], 0x00, len + 1);
					memcpy((*paramValuesp)[i], tmp1->var, len);
					break;

				default:
					goto ERROR_HANDLE;
					break;
			}

			(*paramLengthsp)[i] = len;
			(*paramFormatsp)[i]  = 0;
		}
	}

	return 1;

ERROR_HANDLE:
	for (i = 0; i < stmtHandle->nParams; i++)
	{
		if ((*paramValuesp)[i] != NULL)
			free((*paramValuesp)[i]);
	}

	free(*paramValuesp);
	free(*paramLengthsp);
	free(*paramFormatsp);

	*paramValuesp = NULL;
	*paramLengthsp = NULL;
	*paramFormatsp = NULL;

	return 0;
}

/*
 * replace bindbyname to position
 */
static int
Ivyreplacenamebindtoposition(Ivyconn *tconn,
				IvyPreparedStatement *stmtHandle,
				char *errmsg,
				size_t size_error_buf)
{
	int i;
	Ivyresult *res;
	IvyBindOutNameInfo *tmp;

	/* null stmt */
	if (strcmp(stmtHandle->query, "") == 0)
	{
		stmtHandle->stmttype = IVY_STMT_OTHERS;
		return 1;
	}

	if (stmtHandle->paramNames == NULL)
	{
		char	*query;
		int	query_len;
		int	n_tuples;
		int	n_fields;
		char	*first_name;
		int	first_pos;
		int	dostmt = 0;
		char	*newsql = NULL;
		char	*ptr = NULL;
		int		i = 0;

		query_len = (stmtHandle->query_len * 2) + strlen("select * from get_parameter_description(") + 5;
		query = (char *) malloc(query_len);

		if (query == NULL)
		{
			snprintf(errmsg, size_error_buf, "%s", "failed to allocate memory");
			return 0;
		}

		newsql = malloc(stmtHandle->query_len * 2);	/* enough */
		ptr = newsql;
		while (stmtHandle->query[i] != '\0')
		{
			if (stmtHandle->query[i] == '\'')
				*ptr++ = stmtHandle->query[i];
			*ptr++ = stmtHandle->query[i];
			i++;
		}
		*ptr = '\0';

		memset(query, 0x00, query_len);
		snprintf(query, query_len, "select * from get_parameter_description('%s');", newsql);
		free(newsql);

		res = Ivyexec(tconn, query);
		if (IvyresultStatus(res) != PGRES_TUPLES_OK)
		{
			snprintf(errmsg, size_error_buf, "%s", IvyerrorMessage(tconn));
			free(query);
			return 0;
		}

		free(query);
		n_fields = Ivynfields(res);
		n_tuples = Ivyntuples(res);

		/* check if failed */
		if (n_fields != 2 || n_tuples < 1)
		{
			snprintf(errmsg, size_error_buf, "%s", 
				"get_parameter_description return wrong fields or tuples");
			Ivyclear(res);
			return 0;
		}

		/* first column should be stmt type */
		first_pos = atoi(Ivygetvalue(res, 0, 1));
		first_name = Ivygetvalue(res, 0, 0);

		if (first_pos != 0)
		{
			snprintf(errmsg, size_error_buf, "%s", 
				"get_parameter_description first_pos wrong");
			Ivyclear(res);
			return 0;
		}

		if (strcmp(first_name, "true") == 0)
			dostmt = 1;
		else if (strcmp(first_name, "false") != 0)
		{
			snprintf(errmsg, size_error_buf, "%s", 
				"get_parameter_description returns wrong first_name");
			Ivyclear(res);
			return 0;
		}

		/* process dostmt */
		if (dostmt == 1)
		{
			stmtHandle->stmttype = IVY_STMT_DO;
			Ivyclear(res);
			return 1;
		}

		stmtHandle->stmttype = IVY_STMT_OTHERS;

		/*
		 * if no namebind, just return.
		 */
		if (stmtHandle->namebind == NULL)
			return 1;

		/* number of params doesn't match */
		if (n_tuples - 1 != stmtHandle->nParams)
		{
			snprintf(errmsg, size_error_buf, "%s", 
				"params number doesn't match tuple");
			Ivyclear(res);
			return 0;
		}

		if (n_tuples == 1)
		{
			snprintf(errmsg, size_error_buf, "%s", 
				"get_parameter_description return failed");
			Ivyclear(res);
			return 0;
		}

		stmtHandle->paramNames = (char **) malloc(sizeof(char *) * (n_tuples - 1));
		memset(stmtHandle->paramNames, 0x00, sizeof(char *) * (n_tuples - 1));
		for (i = 1; i < n_tuples; i++)
		{
			int position;
			char *name;
			size_t name_len;

			position = atoi(Ivygetvalue(res, i, 1)) - 1;
			name = Ivygetvalue(res, i, 0);

			if (stmtHandle->paramNames[position] != NULL)
				goto error_handle;

			name_len = strlen(name) + 1;
			stmtHandle->paramNames[position] = (char *) malloc(name_len);

			if (stmtHandle->paramNames[position] == NULL)
				goto error_handle;

			snprintf(stmtHandle->paramNames[position], name_len, "%s", name);
		}
		Ivyclear(res);
	}

	/* replace position according to paramnames */
	for (tmp = stmtHandle->namebind; tmp != NULL; tmp = tmp->next)
	{
		int position;
		int	ret;

		if (tmp->replace != 0)
			continue;

		for (position = 0; position < stmtHandle->nParams; position++)
		{
			if (strcmp(stmtHandle->paramNames[position], tmp->name) == 0)
				break;
		}

		if (position == stmtHandle->nParams)
		{
			snprintf(errmsg, size_error_buf, "placehondvar \"%s\" not found",
						tmp->name);
			return 0;
		}

		ret = IvybindOutParameterByPosInternel(stmtHandle,
							tmp->bindinfo,
							position + 1,
							tmp->var,
							tmp->val_size,
							tmp->indp,
							0,
							errmsg,
							size_error_buf,
							false);
		if (ret != 1)
			return 0;

		tmp->replace = 1;
	}

	stmtHandle->name_replace = 1;
	return 1;

error_handle:
	snprintf(errmsg, size_error_buf, "%s", 
		"get_parameter_description return failed");

	Ivyclear(res);
	for (i = 0; i < stmtHandle->nParams; i++)
	{
		if (stmtHandle->paramNames[i] != NULL)
			free(stmtHandle->paramNames[i]);
	}

	free(stmtHandle->paramNames);
	stmtHandle->paramNames = NULL;

	return 0;
}

/*
 * like Ivyreplacenamebindtoposition
 * but used by IvyStmtExecute
 */
static int
Ivyreplacenamebindtoposition2(Ivyconn *tconn,
				IvyPreparedStatement *stmtHandle,
				IvyError *errhp)
{
	int i;
	Ivyresult *res;
	IvyBindNameInfo *tmp;

	if (stmtHandle->paramNames == NULL)
	{
		char	*query;
		int 	query_len;
		int 	n_tuples;
		int 	n_fields;
		int	first_pos;
		char	*first_name;
		int	dostmt = 0;
		char	*newsql = NULL;
		char	*ptr = NULL;
		int		i = 0;

		query_len = (strlen(stmtHandle->query) * 2) + strlen("select * from get_parameter_description(") + 5;
		query = (char *) malloc(query_len);

		if (query == NULL)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"failed to allocate memory");
			return 0;
		}

		newsql = malloc(strlen(stmtHandle->query) * 2);	/* enough */
		ptr = newsql;
		while (stmtHandle->query[i] != '\0')
		{
			if (stmtHandle->query[i] == '\'')
				*ptr++ = stmtHandle->query[i];
			*ptr++ = stmtHandle->query[i];
			i++;
		}
		*ptr = '\0';

		memset(query, 0x00, query_len);
		snprintf(query, query_len, "select * from get_parameter_description('%s');", newsql);
		free(newsql);

		res = Ivyexec(tconn, query);
		if (IvyresultStatus(res) != PGRES_TUPLES_OK)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", IvyerrorMessage(tconn));
			free(query);
			return 0;
		}

		free(query);
		n_fields = Ivynfields(res);
		n_tuples = Ivyntuples(res);

		/* number of params doesn't match */
		if (n_fields != 2 || n_tuples < 1)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"get_parameter_description return wrong fields or tuples");
			Ivyclear(res);
			return 0;
		}

		/* first column must be stmt type */
		first_pos = atoi(Ivygetvalue(res, 0, 1));
		first_name = Ivygetvalue(res, 0, 0);

		if (first_pos != 0)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"get_parameter_description return wrong first_pos");
			Ivyclear(res);
			return 0;
		}

		if (strcmp(first_name, "true") == 0)
		{
			dostmt = 1;
		}
		else if (strcmp(first_name, "false") != 0)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"get_parameter_description return wrong first_name");
			Ivyclear(res);
			return 0;
		}

		/* process dostmt */
		if (dostmt == 1)
		{
			stmtHandle->stmttype = IVY_STMT_DO;
			Ivyclear(res);
			return 1;
		}

		stmtHandle->stmttype = IVY_STMT_OTHERS;
		if (n_tuples == 1)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
				"get_parameter_description return failed");
			Ivyclear(res);
			return 0;
		}

		stmtHandle->paramNames = (char **) malloc(sizeof(char *) * (n_tuples - 1));
		stmtHandle->nParams = n_tuples - 1;
		memset(stmtHandle->paramNames, 0x00, sizeof(char *) * (n_tuples - 1));
		for (i = 1; i < n_tuples; i++)
		{
			int position;
			char *name;
			size_t name_len;

			position = atoi(Ivygetvalue(res, i, 1)) - 1;
			name = Ivygetvalue(res, i, 0);

			if (stmtHandle->paramNames[position] != NULL)
				goto error_handle;

			name_len = strlen(name) + 1;
			stmtHandle->paramNames[position] = (char *) malloc(name_len);
			if (stmtHandle->paramNames[position] == NULL)
				goto error_handle;

			snprintf(stmtHandle->paramNames[position], name_len, "%s", name);
		}

		Ivyclear(res);
	}

	/* replace position according to paramnames */
	for (tmp = stmtHandle->namebind; tmp != NULL; tmp = tmp->next)
	{
		int position;
		int ret;

		if (tmp->replace != 0)
			continue;

		for (position = 0; position < stmtHandle->nParams; position++)
		{
			if (strcmp(stmtHandle->paramNames[position], tmp->name) == 0)
				break;
		}

		if (position == stmtHandle->nParams)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "placehondvar \"%s\" not found",
						tmp->name);
			return 0;
		}

		ret = IvyBindByPosInternel(stmtHandle,
						tmp->bindinfo,
						errhp,
						position + 1,
						tmp->var,
						tmp->val_size,
						tmp->dtype,
						tmp->indp,
						tmp->alenp,
						tmp->recodep,
						tmp->maxarr_len,
						tmp->curelep,
						tmp->mode,
						false);
		if (ret != 1)
			return 0;

		tmp->replace = 1;
	}

	stmtHandle->name_replace = 1;
	return 1;

error_handle:
	snprintf(errhp->error_msg, errhp->err_buf_size, "%s", 
		"get_parameter_description return failed");

	Ivyclear(res);
	for (i = 0; i < stmtHandle->nParams; i++)
	{
		if (stmtHandle->paramNames[i] != NULL)
			free(stmtHandle->paramNames[i]);
	}

	free(stmtHandle->paramNames);
	stmtHandle->paramNames = NULL;

	return 0;
}
/*
 * like Ivyreplacenamebindtoposition2
 * but used by IvyStmtExecute2
 */
static int
Ivyreplacenamebindtoposition3(Ivyconn *tconn,
										IvyPreparedStatement *stmtHandle,
										IvyError *errhp,
										HostVariable *host)
{
	int i;
	IvyBindNameInfo *tmp;

	if (stmtHandle->paramNames == NULL)
	{
		if (!host || host->length == 0)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "No placehondvars specified");
			return 0;
		}
			
		/* dostmt should handle special */
		if (host->isdostmt)
		{
			stmtHandle->stmttype = IVY_STMT_DO;
			return 1;
		}

		stmtHandle->stmttype = IVY_STMT_OTHERS;
		stmtHandle->paramNames = (char **) malloc(sizeof(char *) * host->length);
		stmtHandle->nParams = host->length;
		memset(stmtHandle->paramNames, 0x00, sizeof(char *) * host->length);
		for (i = 0; i < host->length; i++)
		{
			int position;
			char *name;
			size_t name_len;

			position = host->hostvars[i].position - 1;
			name = host->hostvars[i].name;

			if (stmtHandle->paramNames[position] != NULL)
				goto error_handle;
			name_len = strlen(name) + 1;
			stmtHandle->paramNames[position] = (char *) malloc(name_len);
			if (stmtHandle->paramNames[position] == NULL)
				goto error_handle;
			snprintf(stmtHandle->paramNames[position], name_len, "%s", name);
		}
	}

	/* according to paramnames to replace position */
	for (tmp = stmtHandle->namebind; tmp != NULL; tmp = tmp->next)
	{
		int position;
		int ret;

		if (tmp->replace != 0)
			continue;

		for (position = 0; position < stmtHandle->nParams; position++)
			if (strcmp(stmtHandle->paramNames[position], tmp->name) == 0)
				break;
		if (position == stmtHandle->nParams)
		{
			snprintf(errhp->error_msg, errhp->err_buf_size, "placehondvar \"%s\" not found",
						tmp->name);
			return 0;
		}
		ret = IvyBindByPosInternel(stmtHandle,
								tmp->bindinfo,
								errhp,
								position + 1,
								tmp->var,
								tmp->val_size,
								tmp->dtype,
								tmp->indp,
								tmp->alenp,
								tmp->recodep,
								tmp->maxarr_len,
								tmp->curelep,
								tmp->mode,
								false);
		if (ret != 1)
			return 0;
		tmp->replace = 1;
	}
	stmtHandle->name_replace = 1;
	return 1;

error_handle:
	snprintf(errhp->error_msg, errhp->err_buf_size, "%s", "Ivyreplacenamebindtoposition3 failed");
	for (i = 0; i < stmtHandle->nParams; i++)
		if (stmtHandle->paramNames[i] != NULL)
			free(stmtHandle->paramNames[i]);
	free(stmtHandle->paramNames);
	stmtHandle->paramNames = NULL;
	return 0;
}

