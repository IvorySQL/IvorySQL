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
	PGresult   *pgres = PQmakeEmptyPGresult(NULL, PGRES_TUPLES_OK);
	PGresAttDesc attrs[2];
	Ivyresult	res;

	memset(attrs, 0, sizeof(attrs));
	attrs[0].name = "hidden";
	attrs[1].name = "visible";
	if (!pgres || !PQsetResultAttrs(pgres, 2, attrs) ||
		!PQsetvalue(pgres, 0, 0, "secret", 6) ||
		!PQsetvalue(pgres, 0, 1, "value", 5))
		return EXIT_FAILURE;
	res.result = pgres;
	res.off = 1;
	if (Ivynfields(&res) != 1 ||
		strcmp(Ivyfname(&res, 0), "visible") != 0 ||
		strcmp(Ivygetvalue(&res, 0, 0), "value") != 0 ||
		Ivyfname(&res, -1) != NULL || Ivygetvalue(&res, 0, -1) != NULL ||
		Ivyfname(&res, 1) != NULL || Ivygetvalue(&res, 0, 1) != NULL ||
		Ivyfname(&res, INT_MAX) != NULL || Ivygetvalue(&res, 0, INT_MAX) != NULL)
		return EXIT_FAILURE;
	PQclear(pgres);
	res.result = NULL;
	if (Ivyfname(&res, 0) != NULL || Ivygetvalue(&res, 0, 0) != NULL)
		return EXIT_FAILURE;
	puts("testlibpq_result_bounds passed");
	return EXIT_SUCCESS;
}
