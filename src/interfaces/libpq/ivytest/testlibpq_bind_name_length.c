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
	IvyBindInfo *bind = NULL;
	char	   *name = malloc(2);
	int			value = 7;
	int			rejected_value = 99;
	const char	invalid_name[] = {':', 'x', '\0', 'y'};
	int			indicator = 0;
	char		errmsg[256];
	int			legacy;

	if (!name || !IvyHandleAlloc(NULL, (void **) &err, IVY_HANDLE_ERROR, 0, NULL))
		return EXIT_FAILURE;
	for (legacy = 0; legacy < 2; legacy++)
	{
		if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL) ||
			!IvyStmtPrepare(stmt, err, "select :x", 9, 0, 0))
			return EXIT_FAILURE;
		memcpy(name, ":x", 2);
		if (legacy)
		{
			if (!IvybindOutParameterByName(stmt, &bind, name, 2, &value,
										   sizeof(value), &indicator, 1, errmsg, sizeof(errmsg)))
				return EXIT_FAILURE;
		}
		else if (!IvyBindByName(stmt, &bind, err, name, 2, &value,
								sizeof(value), 23, &indicator, NULL, NULL, 0, NULL, 0))
			return EXIT_FAILURE;
		name[1] = 'z';
		if (strcmp(stmt->namebind->name, ":x") != 0)
			return EXIT_FAILURE;
		if (legacy)
		{
			if (!IvybindOutParameterByName(stmt, &bind, ":xTAIL", 2, &value,
										   sizeof(value), &indicator, 1, errmsg, sizeof(errmsg)) ||
				IvybindOutParameterByName(stmt, &bind, ":xTAIL", 2, &value,
										  sizeof(value), &indicator, 0, errmsg, sizeof(errmsg)))
				return EXIT_FAILURE;
		}
		else if (!IvyBindByName(stmt, &bind, err, ":xTAIL", 2, &value,
								sizeof(value), 23, &indicator, NULL, NULL, 0, NULL, 0))
			return EXIT_FAILURE;
		if (stmt->namebind->next != NULL || strcmp(stmt->namebind->name, ":x") != 0)
			return EXIT_FAILURE;
		/* An explicit name span must not alias a shorter C string. */
		if (legacy)
		{
			if (IvybindOutParameterByName(stmt, &bind, invalid_name,
										  sizeof(invalid_name), &rejected_value,
										  sizeof(rejected_value), &indicator, 1,
										  errmsg, sizeof(errmsg)))
				return EXIT_FAILURE;
		}
		else if (IvyBindByName(stmt, &bind, err, invalid_name,
							   sizeof(invalid_name), &rejected_value,
							   sizeof(rejected_value), 23, &indicator,
							   NULL, NULL, 0, NULL, 0))
			return EXIT_FAILURE;
		if (stmt->namebind->next != NULL ||
			strcmp(stmt->namebind->name, ":x") != 0 ||
			stmt->namebind->var != &value)
			return EXIT_FAILURE;
		IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	}
	free(name);
	IvyFreeHandle(err, IVY_HANDLE_ERROR);
	puts("testlibpq_bind_name_length passed");
	return EXIT_SUCCESS;
}
