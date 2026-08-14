/*-------------------------------------------------------------------------
 *
 * testlibpq_unprepared_handle.c
 *
 * Test releasing an Ivy statement handle before preparing a query.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivytest/testlibpq_unprepared_handle.c
 *
 *-------------------------------------------------------------------------
 */

#include <stdio.h>

#include "libpq-fe.h"
#include "libpq-ivy.h"

int
main(void)
{
	IvyPreparedStatement *stmt = NULL;

	if (!IvyHandleAlloc(NULL, (void **) &stmt, IVY_HANDLE_STMT, 0, NULL))
	{
		fprintf(stderr, "IvyHandleAlloc failed\n");
		return 1;
	}

	IvyFreeHandle(stmt, IVY_HANDLE_STMT);
	printf("unprepared statement handle released\n");

	return 0;
}
