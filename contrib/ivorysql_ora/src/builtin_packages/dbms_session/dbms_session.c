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
 * Implementation of Oracle's DBMS_SESSION package (application context subset).
 * This module is part of ivorysql_ora extension.
 *
 * Provides the session application-context interfaces SET_CONTEXT,
 * CLEAR_CONTEXT, CLEAR_ALL_CONTEXT and LIST_CONTEXT, plus a reader used by
 * SYS_CONTEXT.  Context values live in a per-backend (session-scoped) hash
 * table so they can drive row-level security predicates via SYS_CONTEXT.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_session/dbms_session.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "access/hash.h"
#include "catalog/pg_collation.h"
#include "utils/builtins.h"
#include "utils/formatting.h"
#include "utils/memutils.h"
#include "utils/packagecache.h"
#include "utils/tuplestore.h"

#include "../../include/ivorysql_ora.h"

/*
 * Oracle limits namespace/attribute to identifier length (30 bytes) and the
 * value to 4000 bytes.  We use generous fixed-size key buffers and reject
 * oversized names rather than silently truncating (truncation would corrupt
 * the hash key).
 */
#define DBMS_SESSION_NAME_LEN		256
#define DBMS_SESSION_MAX_VALUE_LEN	4000
#define DBMS_SESSION_HASH_INIT_SIZE	64

/*
 * Hash key: (namespace, attribute).  The struct is compared as an opaque blob
 * (HASH_BLOBS), so it MUST be zero-filled before the names are copied in,
 * otherwise trailing garbage bytes would make equal keys compare unequal.
 */
typedef struct CtxKey
{
	char		namespace[DBMS_SESSION_NAME_LEN];
	char		attribute[DBMS_SESSION_NAME_LEN];
}			CtxKey;

typedef struct CtxEntry
{
	CtxKey		key;			/* must be first field */
	char	   *value;			/* palloc'd in DbmsSessionContext, NULL for
								 * NULL value */
}			CtxEntry;

/* Per-backend session state */
static HTAB *DbmsSessionHash = NULL;
static MemoryContext DbmsSessionContext = NULL;

/* Internal helpers */
static void dbms_session_init(void);
static bool fold_name(char *dest, const char *src, const char *kind, bool missing_ok);
static bool make_key(CtxKey * key, const char *ns, const char *attr, bool missing_ok);
static void clear_namespace(const char *ns);

/* SQL-callable function declarations */
PG_FUNCTION_INFO_V1(ora_dbms_session_set_context);
PG_FUNCTION_INFO_V1(ora_dbms_session_clear_context);
PG_FUNCTION_INFO_V1(ora_dbms_session_clear_all_context);
PG_FUNCTION_INFO_V1(ora_dbms_session_get_context);
PG_FUNCTION_INFO_V1(ora_dbms_session_list_context);
PG_FUNCTION_INFO_V1(ora_dbms_session_reset_package);

/*
 * dbms_session_init
 *
 * Lazily create the session context store.  Both the hash table and the
 * stored values live in a dedicated memory context under TopMemoryContext so
 * the whole thing can be torn down in one MemoryContextDelete on reset.
 */
static void
dbms_session_init(void)
{
	HASHCTL		ctl;

	DbmsSessionContext = AllocSetContextCreate(TopMemoryContext,
											   "DBMS_SESSION context",
											   ALLOCSET_DEFAULT_SIZES);

	MemSet(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(CtxKey);
	ctl.entrysize = sizeof(CtxEntry);
	ctl.hcxt = DbmsSessionContext;

	DbmsSessionHash = hash_create("DBMS_SESSION context hash",
								  DBMS_SESSION_HASH_INIT_SIZE,
								  &ctl,
								  HASH_ELEM | HASH_BLOBS | HASH_CONTEXT);
}

/*
 * Fold a context name using the database's default collation.  PostgreSQL's
 * case conversion handles multibyte characters and can change the byte length,
 * so check the folded result before copying it into the fixed-size hash key.
 */
static bool
fold_name(char *dest, const char *src, const char *kind, bool missing_ok)
{
	char	   *upper = str_toupper(src, strlen(src), DEFAULT_COLLATION_OID);
	size_t		len = strlen(upper);

	if (len >= DBMS_SESSION_NAME_LEN)
	{
		pfree(upper);
		if (missing_ok)
			return false;
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SESSION %s too long (max %d bytes)",
						kind, DBMS_SESSION_NAME_LEN - 1)));
	}

	memcpy(dest, upper, len + 1);
	pfree(upper);
	return true;
}

/*
 * make_key - build a zero-filled hash key from namespace/attribute names.
 *
 * Oracle treats names case-insensitively.  A read with an overlong name cannot
 * match any stored key, so callers can request a missing result instead of an
 * error.  HASH_BLOBS compares the whole key, including unused bytes.
 */
static bool
make_key(CtxKey * key, const char *ns, const char *attr, bool missing_ok)
{
	MemSet(key, 0, sizeof(CtxKey));
	if (!fold_name(key->namespace, ns, "namespace", missing_ok))
		return false;
	if (!fold_name(key->attribute, attr, "attribute", missing_ok))
		return false;
	return true;
}

/*
 * clear_namespace - remove every attribute belonging to a namespace.
 *
 * Matching keys are collected first and removed afterwards, because dynahash
 * forbids removing entries other than the current one during a seq scan.
 */
static void
clear_namespace(const char *ns)
{
	HASH_SEQ_STATUS seq;
	CtxEntry   *entry;
	CtxKey	   *victims;
	long		nentries;
	int			nvictims = 0;
	char		ns_up[DBMS_SESSION_NAME_LEN];
	int			i;

	if (DbmsSessionHash == NULL)
		return;

	nentries = hash_get_num_entries(DbmsSessionHash);
	if (nentries == 0)
		return;

	/* An overlong namespace cannot match any stored key. */
	if (!fold_name(ns_up, ns, "namespace", true))
		return;

	victims = (CtxKey *) palloc(sizeof(CtxKey) * nentries);

	hash_seq_init(&seq, DbmsSessionHash);
	while ((entry = (CtxEntry *) hash_seq_search(&seq)) != NULL)
	{
		if (strcmp(entry->key.namespace, ns_up) == 0)
		{
			if (entry->value != NULL)
				pfree(entry->value);
			victims[nvictims++] = entry->key;
		}
	}

	for (i = 0; i < nvictims; i++)
		hash_search(DbmsSessionHash, &victims[i], HASH_REMOVE, NULL);

	pfree(victims);
}

/*
 * DBMS_SESSION.SET_CONTEXT(namespace, attribute, value)
 *
 * Stores (or overwrites) one attribute value in the session context store.
 * A NULL value is stored as an explicit NULL (the attribute still exists).
 */
Datum
ora_dbms_session_set_context(PG_FUNCTION_ARGS)
{
	char	   *ns;
	char	   *attr;
	char	   *val = NULL;
	CtxKey		key;
	CtxEntry   *entry;
	bool		found;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_SESSION.SET_CONTEXT namespace and attribute must not be NULL")));

	ns = text_to_cstring(PG_GETARG_TEXT_PP(0));
	attr = text_to_cstring(PG_GETARG_TEXT_PP(1));

	if (!PG_ARGISNULL(2))
	{
		val = text_to_cstring(PG_GETARG_TEXT_PP(2));
		if (strlen(val) > DBMS_SESSION_MAX_VALUE_LEN)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("DBMS_SESSION.SET_CONTEXT value too long (max %d bytes)",
							DBMS_SESSION_MAX_VALUE_LEN)));
	}

	if (DbmsSessionHash == NULL)
		dbms_session_init();

	make_key(&key, ns, attr, false);

	entry = (CtxEntry *) hash_search(DbmsSessionHash, &key, HASH_ENTER, &found);

	/* Release any previous value before overwriting */
	if (found && entry->value != NULL)
		pfree(entry->value);

	if (val == NULL)
		entry->value = NULL;
	else
	{
		MemoryContext oldcontext = MemoryContextSwitchTo(DbmsSessionContext);

		entry->value = pstrdup(val);
		MemoryContextSwitchTo(oldcontext);
	}

	PG_RETURN_VOID();
}

/*
 * DBMS_SESSION.CLEAR_CONTEXT(namespace, attribute)
 *
 * If attribute is NULL, clears the whole namespace; otherwise clears a single
 * attribute.
 */
Datum
ora_dbms_session_clear_context(PG_FUNCTION_ARGS)
{
	char	   *ns;

	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_SESSION.CLEAR_CONTEXT namespace must not be NULL")));

	if (DbmsSessionHash == NULL)
		PG_RETURN_VOID();

	ns = text_to_cstring(PG_GETARG_TEXT_PP(0));

	if (PG_ARGISNULL(1))
	{
		clear_namespace(ns);
	}
	else
	{
		char	   *attr = text_to_cstring(PG_GETARG_TEXT_PP(1));
		CtxKey		key;
		CtxEntry   *entry;
		bool		found;

		make_key(&key, ns, attr, false);
		entry = (CtxEntry *) hash_search(DbmsSessionHash, &key, HASH_FIND, &found);
		if (found)
		{
			if (entry->value != NULL)
				pfree(entry->value);
			hash_search(DbmsSessionHash, &key, HASH_REMOVE, NULL);
		}
	}

	PG_RETURN_VOID();
}

/*
 * DBMS_SESSION.CLEAR_ALL_CONTEXT(namespace)
 *
 * Clears every attribute of the given namespace.
 */
Datum
ora_dbms_session_clear_all_context(PG_FUNCTION_ARGS)
{
	char	   *ns;

	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_SESSION.CLEAR_ALL_CONTEXT namespace must not be NULL")));

	if (DbmsSessionHash == NULL)
		PG_RETURN_VOID();

	ns = text_to_cstring(PG_GETARG_TEXT_PP(0));
	clear_namespace(ns);

	PG_RETURN_VOID();
}

/*
 * sys.ora_dbms_session_get_context(namespace, attribute) -> text
 *
 * Reader used by SYS_CONTEXT for custom namespaces.  Returns NULL when the
 * attribute is absent or was set to NULL.
 */
Datum
ora_dbms_session_get_context(PG_FUNCTION_ARGS)
{
	char	   *ns;
	char	   *attr;
	CtxKey		key;
	CtxEntry   *entry;
	bool		found;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	if (DbmsSessionHash == NULL)
		PG_RETURN_NULL();

	ns = text_to_cstring(PG_GETARG_TEXT_PP(0));
	attr = text_to_cstring(PG_GETARG_TEXT_PP(1));

	/*
	 * Read path: an over-long name can never match a stored key (set/clear
	 * reject them at insert time), so return NULL rather than letting
	 * make_key raise an error.  This keeps SYS_CONTEXT() usable in predicates
	 * without aborting the query on an oversized argument.
	 */
	if (strlen(ns) >= DBMS_SESSION_NAME_LEN || strlen(attr) >= DBMS_SESSION_NAME_LEN)
		PG_RETURN_NULL();

	if (!make_key(&key, ns, attr, true))
		PG_RETURN_NULL();
	entry = (CtxEntry *) hash_search(DbmsSessionHash, &key, HASH_FIND, &found);

	if (!found || entry->value == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(entry->value));
}

/*
 * sys.ora_dbms_session_list_context() -> SETOF (namespace, attribute, value)
 *
 * Lists all active context entries in the current session.  Implemented as a
 * materialize-mode set-returning function.
 */
Datum
ora_dbms_session_list_context(PG_FUNCTION_ARGS)
{
	ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;
	TupleDesc	tupdesc;
	Tuplestorestate *tupstore;
	MemoryContext per_query_ctx;
	MemoryContext oldcontext;

	if (rsinfo == NULL || !IsA(rsinfo, ReturnSetInfo))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("set-valued function called in context that cannot accept a set")));
	if (!(rsinfo->allowedModes & SFRM_Materialize))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("materialize mode required, but it is not allowed in this context")));

	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	per_query_ctx = rsinfo->econtext->ecxt_per_query_memory;
	oldcontext = MemoryContextSwitchTo(per_query_ctx);

	tupdesc = CreateTupleDescCopy(tupdesc);
	tupstore = tuplestore_begin_heap(true, false, work_mem);
	rsinfo->returnMode = SFRM_Materialize;
	rsinfo->setResult = tupstore;
	rsinfo->setDesc = tupdesc;

	MemoryContextSwitchTo(oldcontext);

	if (DbmsSessionHash != NULL)
	{
		HASH_SEQ_STATUS seq;
		CtxEntry   *entry;

		hash_seq_init(&seq, DbmsSessionHash);
		while ((entry = (CtxEntry *) hash_seq_search(&seq)) != NULL)
		{
			Datum		values[3];
			bool		nulls[3] = {false, false, false};

			values[0] = CStringGetTextDatum(entry->key.namespace);
			values[1] = CStringGetTextDatum(entry->key.attribute);
			if (entry->value == NULL)
				nulls[2] = true;
			else
				values[2] = CStringGetTextDatum(entry->value);

			tuplestore_putvalues(tupstore, tupdesc, values, nulls);
		}
	}

	return (Datum) 0;
}

/*
 * DBMS_SESSION.RESET_PACKAGE
 *
 * Resets all PL/iSQL package state in the current session (Oracle semantics):
 * closes refcursors, frees variable memory, and marks every package
 * uninitialized so the full init sequence runs lazily on next access.
 * Session-local only — does not affect other sessions.
 */
Datum
ora_dbms_session_reset_package(PG_FUNCTION_ARGS)
{
	ResetAllPackagesContext();
	PG_RETURN_VOID();
}

/*
 * ora_dbms_session_reset
 *
 * Drop all session context state.  Called by DISCARD ALL/PACKAGES so that a
 * pooled connection does not leak one client's context to the next.
 */
void
ora_dbms_session_reset(void)
{
	if (DbmsSessionContext != NULL)
	{
		MemoryContextDelete(DbmsSessionContext);
		DbmsSessionContext = NULL;
		DbmsSessionHash = NULL;
	}
}
