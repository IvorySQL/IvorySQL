/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Implementation of Oracle's DBMS_LOCK package.
 * This module is part of ivorysql_ora extension.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_lock/dbms_lock.c
 *
 *-------------------------------------------------------------------------
 */
#include "pg_config.h" 
#include "c.h" 
#include "miscadmin.h" 
#include "pgtime.h" 
#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include "storage/lwlock.h"
#include "miscadmin.h"
#include "catalog/pg_type.h"
#include "utils/elog.h"
#include "utils/timeout.h"
#include "utils/uuid.h"
#include "access/hash.h"
#include "storage/lock.h"
#include "storage/lmgr.h"
#include "storage/lockdefs.h"

/* Oracle compatible lock modes */
/* we support only:
 * LOCK_S_MODE
 * LOCK_X_MODE
 */
#define DBMS_LOCK_S_MODE      1
#define DBMS_LOCK_X_MODE      2

/* Oracle compatible return codes */
#define DBMS_LOCK_SUCCESS         0
#define DBMS_LOCK_TIMEOUT         1
#define DBMS_LOCK_DEADLOCK        2
#define DBMS_LOCK_PARAM_ERROR     3
#define DBMS_LOCK_ALREADY_OWNED   4 
#define DBMS_LOCK_INVALID_HANDLE  5 

#define DBMS_LOCK_HANDLE_LENGTH	32
/*
 * 0x9e3779b9 = 2654435769 
 * derived from 2**32/PHI(golden ratio)
 * should ensure good distribution for lock names
 */
#define DBMS_LOCK_SEED 0x9e3779b9 


/*
 * from lockfuncs.c
 */
#define SET_LOCKTAG_INT64(tag, key64) \
    SET_LOCKTAG_ADVISORY(tag, \
                         MyDatabaseId, \
                         (uint32) ((key64) >> 32), \
                         (uint32) (key64), \
                         1)
/* Hash lock name into int64 advisory key */
static int64
lockname_to_key(text *lockname)
{
    char *name = text_to_cstring(lockname);
    uint32 hash1 = DatumGetUInt32(hash_any((unsigned char *) name, strlen(name)));
    uint32 hash2 = DatumGetUInt32(hash_any_extended((unsigned char *) name,
                                                    strlen(name), DBMS_LOCK_SEED));
    int64 key = ((int64) hash1 << 32) | hash2;
    pfree(name);
    return key;
}

static bool
is_exclusive_mode(int mode)
{
    switch (mode)
    {
        case DBMS_LOCK_X_MODE:
            return true;

        case DBMS_LOCK_S_MODE:
            return false;

        default:
            ereport(ERROR,
                    (errmsg("invalid DBMS_LOCK mode")));
    }
}

/*
 * DBMS_LOCK.ALLOCATE_UNIQUE
 *
 */
PG_FUNCTION_INFO_V1(ivorysql_dbms_lock_allocate_unique);
Datum
ivorysql_dbms_lock_allocate_unique(PG_FUNCTION_ARGS)
{
    char *lockname_text = text_to_cstring(PG_GETARG_TEXT_PP(0));
    char handle[DBMS_LOCK_HANDLE_LENGTH];
    int expiration_secs = PG_GETARG_INT32(2);

    /* Use PostgreSQL 64-bit stable hash */
    uint64 hash =
        DatumGetUInt64(
            hash_any_extended(
                (unsigned char *) lockname_text,
                strlen(lockname_text),
                0));

    snprintf(handle, sizeof(handle),
             "%llu",
             (unsigned long long) hash);

    PG_RETURN_TEXT_P(cstring_to_text(handle));

}


/*
 * DBMS_LOCK.REQUEST
 */
PG_FUNCTION_INFO_V1(ivorysql_dbms_lock_request);
Datum
ivorysql_dbms_lock_request(PG_FUNCTION_ARGS)
{
    text *lockname = PG_GETARG_TEXT_PP(0);
    int mode = PG_GETARG_INT32(1);     /* Oracle lock mode 1–6 */
    int timeout = PG_GETARG_INT32(2);  /* seconds */
    int64 key = lockname_to_key(lockname);
    bool exclusive = is_exclusive_mode(mode);
    TimestampTz start = GetCurrentTimestamp();
    LOCKTAG     locktag;

    if (mode != DBMS_LOCK_S_MODE && mode != DBMS_LOCK_X_MODE)
        PG_RETURN_INT32(DBMS_LOCK_PARAM_ERROR);

    SET_LOCKTAG_INT64(locktag, key);
    
     
     if (exclusive && LockHeldByMe(&locktag, ExclusiveLock, false)) 
     {
    	/* Logic for when the lock is already held by us */
	PG_RETURN_INT32(DBMS_LOCK_ALREADY_OWNED);
     }
     if (!exclusive && LockHeldByMe(&locktag, ShareLock, false)) 
     {
    	/* Logic for when the lock is already held by us */
	PG_RETURN_INT32(DBMS_LOCK_ALREADY_OWNED);
     }

    while (true)
    {
        bool acquired;

        if (exclusive)
            acquired = DirectFunctionCall1(pg_try_advisory_lock_int8,
                                           Int64GetDatum(key)) != 0;
        else
            acquired = DirectFunctionCall1(pg_try_advisory_lock_shared_int8,
                                           Int64GetDatum(key)) != 0;

        if (acquired)
            PG_RETURN_INT32(DBMS_LOCK_SUCCESS);

        if (timeout == 0)
            PG_RETURN_INT32(DBMS_LOCK_TIMEOUT);

        if (timeout > 0)
        {
            TimestampTz now = GetCurrentTimestamp();
            long elapsed = (long) ((now - start) / 1000000);

            if (elapsed >= timeout)
                PG_RETURN_INT32(DBMS_LOCK_TIMEOUT);
        }

        pg_usleep(100000); /* 100ms retry */
        CHECK_FOR_INTERRUPTS();
    }
}

/*
 * DBMS_LOCK.RELEASE
 */
PG_FUNCTION_INFO_V1(ivorysql_dbms_lock_release);

Datum
ivorysql_dbms_lock_release(PG_FUNCTION_ARGS)
{
    text *lockname = PG_GETARG_TEXT_PP(0);
    int64 key = lockname_to_key(lockname);

    bool released = DatumGetBool(
        DirectFunctionCall1(pg_advisory_unlock_int8,
                            Int64GetDatum(key)));

    if (released)
        PG_RETURN_INT32(DBMS_LOCK_SUCCESS);
    else
        PG_RETURN_INT32(DBMS_LOCK_PARAM_ERROR);
}

/*
 * DBMS_LOCK.SLEEP
 */
PG_FUNCTION_INFO_V1(ivorysql_dbms_lock_sleep);

Datum
ivorysql_dbms_lock_sleep(PG_FUNCTION_ARGS)
{
    float8 seconds = PG_GETARG_FLOAT8(0);

    if (seconds < 0)
        PG_RETURN_INT32(DBMS_LOCK_PARAM_ERROR);

    pg_usleep(seconds * 1000000);

    PG_RETURN_VOID();
}

