#include "postgres.h"
#include "miscadmin.h"
#include "storage/lwlock.h"
#include "storage/shmem.h"
#include "utils/guc.h"
#include "commands/variable.h"

#include "orafce.h"
#include "builtins.h"
#include "pipe.h"

/*  default value */
char  *nls_date_format = NULL;
char  *orafce_timezone = NULL;

/* Saved hook values in case of unload */
static shmem_request_hook_type prev_shmem_request_hook = NULL;

/* Function declarations */
static void process_shmem_request(void);

void
_PG_init(void)
{

#if PG_VERSION_NUM < 90600

	RequestAddinLWLocks(1);

#endif

	prev_shmem_request_hook = shmem_request_hook;
	shmem_request_hook = process_shmem_request;

	/* Define custom GUC variables. */
	DefineCustomStringVariable("orafce.nls_date_format",
									"Emulate oracle's date output behaviour.",
									NULL,
									&nls_date_format,
									NULL,
									PGC_USERSET,
									0,
									NULL,
									NULL, NULL);

	DefineCustomStringVariable("orafce.timezone",
									"Specify timezone used for sysdate function.",
									NULL,
									&orafce_timezone,
									"GMT",
									PGC_USERSET,
									0,
									check_timezone, NULL, NULL);

	DefineCustomBoolVariable("orafce.varchar2_null_safe_concat",
									"Specify timezone used for sysdate function.",
									NULL,
									&orafce_varchar2_null_safe_concat,
									false,
									PGC_USERSET,
									0,
									NULL, NULL, NULL);

	EmitWarningsOnPlaceholders("orafce");
}

/*
 * shmem_request hook: request additional shared resources.  We'll allocate or
 * attach to the shared resources in pgss_shmem_startup().
 */
static void
process_shmem_request(void)
{
	if (prev_shmem_request_hook)
		prev_shmem_request_hook();

	RequestAddinShmemSpace(SHMEMMSGSZ);
}

