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
#include "postgres.h"
#include "fmgr.h"
#include "miscadmin.h" 
#include "pgtime.h" 
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include "storage/lwlock.h"
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
#define DBMS_LOCK_S_MODE      4
#define DBMS_LOCK_X_MODE      6

/* Oracle compatible return codes */
#define DBMS_LOCK_SUCCESS         0
#define DBMS_LOCK_TIMEOUT         1
#define DBMS_LOCK_DEADLOCK        2
#define DBMS_LOCK_PARAM_ERROR     3
#define DBMS_LOCK_ALREADY_OWNED   4 
#define DBMS_LOCK_INVALID_HANDLE  5 

#define DBMS_LOCK_HANDLE_LENGTH 64	
/*
 * 0x9e3779b9 = 2654435769 
 * derived from 2**32/PHI(golden ratio)
 * should ensure good distribution for lock names
 */
#define DBMS_LOCK_SEED 0x9e3779b9 


/*
 * private hash table for backend locks
 */

#define DBMS_LOCK_MAX	128
typedef struct
{
    int64       key;        /* hash key */
    int8        mode;        /* last mode we recorded */
} lock_entry;

static HTAB *dbms_lock_hash_table = NULL;

/*
 * static routines
 */
static void dbms_lock_init_hash_table();
static void dbms_lock_record_acquire(int64, int8);
static bool dbms_lock_check(int64, int8);
static bool dbms_lock_record_release(int64, int8);

/*
 * init private lock hash table
 */


static void
dbms_lock_init_hash_table(void)
{
    HASHCTL ctl;

    MemSet(&ctl, 0, sizeof(ctl));
    ctl.keysize = sizeof(int64);
    ctl.entrysize = sizeof(lock_entry);
    ctl.hash = tag_hash;

    dbms_lock_hash_table = hash_create("pg_dbms_lock table",
                             DBMS_LOCK_MAX,         
                             &ctl,
                             HASH_ELEM | HASH_FUNCTION);
}

/*
 * store lock acquire
 */
static void
dbms_lock_record_acquire(int64 key, int8 mode)
{
    bool        found;
    lock_entry *entry;

    entry = (lock_entry *) hash_search(dbms_lock_hash_table,
                                        (void *) &key,
                                        HASH_ENTER,
                                        &found);

    entry->key = key;
    entry->mode = mode;
}

/*
 * check lock is held
 */
static bool
dbms_lock_check(int64 key, int8 mode)
{
   bool        found;
   lock_entry *entry;

   entry = (lock_entry *) hash_search(dbms_lock_hash_table,
                                          (void *) &key,
                                          HASH_FIND,
                                          &found);
   if (found  && entry->mode == mode)
        return true;

    return false;
}

/*
 * store lock release
 */

static bool
dbms_lock_record_release(int64 key, int8 mode)
{
    bool        found;
    lock_entry *entry;

    entry = (lock_entry *) hash_search(dbms_lock_hash_table,
                                        (void *) &key,
                                        HASH_FIND,
                                        &found);

    if (!found)
        return false;

    if (entry->mode != mode)
	    return false;

    hash_search(dbms_lock_hash_table, (void *) &key, HASH_REMOVE, &found);

    return true;
}



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

    if (dbms_lock_hash_table == NULL)
	    dbms_lock_init_hash_table();

    PG_RETURN_TEXT_P(cstring_to_text(handle));

}


/*
 * DBMS_LOCK.REQUEST
 */
PG_FUNCTION_INFO_V1(ivorysql_dbms_lock_request);
Datum
ivorysql_dbms_lock_request(PG_FUNCTION_ARGS)
{
    text *lockhandle = PG_GETARG_TEXT_PP(0);
    int lockmode = PG_GETARG_INT32(1);     /* Oracle lock mode S=4, X=6 */
    int timeout = PG_GETARG_INT32(2);  /* seconds */
    int64 key = lockname_to_key(lockhandle);
    bool exclusive = is_exclusive_mode(lockmode);
    TimestampTz start = GetCurrentTimestamp();
    bool acquired = false;

    if (dbms_lock_hash_table == NULL)
	    dbms_lock_init_hash_table();

    if (timeout < 0)
        PG_RETURN_INT32(DBMS_LOCK_PARAM_ERROR);

    while (true)
    {
        if (exclusive)
            acquired = DatumGetBool(DirectFunctionCall1(pg_try_advisory_lock_int8, Int64GetDatum(key)));
        else
            acquired = DatumGetBool(DirectFunctionCall1(pg_try_advisory_lock_shared_int8, Int64GetDatum(key)));

        if (acquired) {
	    elog(DEBUG1, "dbms_lock_request: key=%lu mode=%d", key, lockmode);
            dbms_lock_record_acquire(key, lockmode);
            PG_RETURN_INT32(DBMS_LOCK_SUCCESS);
	}

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
    text *lockhandle = PG_GETARG_TEXT_PP(0);
    int64 key = lockname_to_key(lockhandle);
    bool lock_s_held = false;
    bool lock_x_held = false;
    bool released = false;
    int8 lockmode;

    if (dbms_lock_hash_table == NULL)
	    dbms_lock_init_hash_table();
	
    lock_s_held = dbms_lock_check(key, DBMS_LOCK_S_MODE);
    if (lock_s_held) {
       lockmode = DBMS_LOCK_S_MODE;
       released = DatumGetBool(DirectFunctionCall1(pg_advisory_unlock_shared_int8, Int64GetDatum(key)));
	elog(DEBUG1, "unlock S: key=%lu mode=%d released=%d", key, lockmode, released);
    } else {
      lock_x_held = dbms_lock_check(key, DBMS_LOCK_X_MODE);
      if (lock_x_held) {
       lockmode = DBMS_LOCK_X_MODE;
       released = DatumGetBool(DirectFunctionCall1(pg_advisory_unlock_int8, Int64GetDatum(key)));
       elog(DEBUG1, "unlock X: key=%lu mode=%d released=%d", key, lockmode, released);
      }
    };

    if (released) {
	elog(DEBUG1, "dbms_lock_release: key=%lu mode=%d", key, lockmode);
	dbms_lock_record_release(key,lockmode);
        PG_RETURN_INT32(DBMS_LOCK_SUCCESS);
    }

    PG_RETURN_INT32(DBMS_LOCK_PARAM_ERROR);
}

/*
 * DBMS_LOCK.SLEEP
 */
PG_FUNCTION_INFO_V1(ivorysql_dbms_lock_sleep);

Datum
ivorysql_dbms_lock_sleep(PG_FUNCTION_ARGS)
{
    long total_usec;
    long remaining;
    float8 seconds = PG_GETARG_FLOAT8(0);

    if (dbms_lock_hash_table == NULL)
	    dbms_lock_init_hash_table();

    if (seconds < 0)
        ereport(ERROR,
                (errmsg("DBMS_LOCK.SLEEP: seconds must be non-negative")));

    if (seconds > 100000000)
        ereport(ERROR,
                (errmsg("DBMS_LOCK.SLEEP: seconds too large")));

    total_usec = (long)(seconds * 1000000);
    remaining = total_usec;
    while (remaining > 0)
    {
        long chunk = (remaining > 1000000) ? 1000000 : remaining;
        pg_usleep(chunk);
        remaining -= chunk;
        CHECK_FOR_INTERRUPTS();
    }

    PG_RETURN_INT32(DBMS_LOCK_SUCCESS);
}

