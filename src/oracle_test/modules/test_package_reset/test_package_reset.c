/*--------------------------------------------------------------------------
 *
 * test_package_reset.c
 *		Test extension for PLiSQL package reset API
 *
 * IDENTIFICATION
 *		src/oracle_test/modules/test_package_reset/test_package_reset.c
 *
 *--------------------------------------------------------------------------
 */
#include "postgres.h"

#include "funcapi.h"
#include "fmgr.h"
#include "utils/packagecache.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(test_package_reset_reset_package_by_oid);

Datum
test_package_reset_reset_package_by_oid(PG_FUNCTION_ARGS)
{
	Oid pkg_oid = PG_GETARG_OID(0);

	PG_RETURN_BOOL(ResetPackageContext(pkg_oid));
}

PG_FUNCTION_INFO_V1(test_package_reset_reset_all_packages);

Datum
test_package_reset_reset_all_packages(PG_FUNCTION_ARGS)
{
	int count;

	count = ResetAllPackagesContext();

	PG_RETURN_INT32(count);
}
