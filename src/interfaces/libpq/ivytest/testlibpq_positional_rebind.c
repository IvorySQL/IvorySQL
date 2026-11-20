/*-------------------------------------------------------------------------
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"
#include <assert.h>
#include <limits.h>
#include "libpq-fe.h"
#include "libpq-ivy.h"

int
main(void)
{
	IvyPreparedStatement *stmt = NULL;
	IvyError   *err = NULL;
	IvyBindInfo *bind[3] = {NULL, NULL, NULL};
	int			values[3] = {1, 2, 3};
	int			indicators[3] = {0, 0, 0};
	Oid			types[3] = {23, 23, 23};
	char		errmsg[256];
	int			i;

	if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL) ||
		!IvyHandleAlloc(NULL, (void **) &err, IVY_HANDLE_ERROR, 0, NULL) ||
		!IvyStmtPrepare(stmt, err, "select $1, $2, $3", 17, 0, 0))
		return EXIT_FAILURE;
	for (i = 0; i < 3; i++)
		if (!IvyBindByPos(stmt, &bind[i], err, i + 1, &values[i], sizeof(int),
						  23, &indicators[i], NULL, NULL, 0, NULL, 0))
			return EXIT_FAILURE;
	values[0] = 42;
	if (!IvyBindByPos(stmt, &bind[0], err, 1, &values[0], sizeof(int),
					  23, &indicators[0], NULL, NULL, 0, NULL, 0) ||
		stmt->outbind != bind[0] || bind[0]->next != bind[1] ||
		bind[1]->next != bind[2] || bind[2]->next != NULL)
		return EXIT_FAILURE;
	if (!IvyBindByPos(stmt, &bind[1], err, 2, &values[1], sizeof(int),
					  23, &indicators[1], NULL, NULL, 0, NULL, 0) ||
		bind[0]->next != bind[1] || bind[1]->next != bind[2])
		return EXIT_FAILURE;
	IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	stmt = IvyCreatePreparedStatement("legacy_rebind", "select $1, $2, $3", 3, types);
	if (!stmt)
		return EXIT_FAILURE;
	for (i = 0; i < 3; i++)
	{
		bind[i] = NULL;
		if (!IvybindOutParameterByPos(stmt, &bind[i], i + 1, &values[i],
									  sizeof(int), &indicators[i], 1, errmsg, sizeof(errmsg)))
			return EXIT_FAILURE;
	}
	if (!IvybindOutParameterByPos(stmt, &bind[0], 1, &values[0], sizeof(int),
								  &indicators[0], 1, errmsg, sizeof(errmsg)) ||
		stmt->outbind != bind[0] || bind[0]->next != bind[1] ||
		bind[1]->next != bind[2] || bind[2]->next != NULL)
		return EXIT_FAILURE;
	if (!IvybindOutParameterByPos(stmt, &bind[1], 2, &values[1], sizeof(int),
								  &indicators[1], 1, errmsg, sizeof(errmsg)) ||
		stmt->outbind != bind[0] || bind[0]->next != bind[1] ||
		bind[1]->next != bind[2] || bind[2]->next != NULL)
		return EXIT_FAILURE;
	IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	IvyFreeHandle(err, IVY_HANDLE_ERROR);
	puts("testlibpq_positional_rebind passed");
	return EXIT_SUCCESS;
}
