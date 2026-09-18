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
#include "utils/builtins.h"
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
 *
 * ns_len / attr_len record the true byte length of each name.  They are part
 * of the blob so a stored name containing an embedded NUL (e.g. 'AB'||chr(0))
 * is never matched by a shorter name that happens to share the same prefix
 * (strcmp would stop at the NUL and wrongly equate them).  Storing the length
 * also lets readers return the full byte content instead of truncating at the
 * first NUL.
 */
typedef struct CtxKey
{
	int			ns_len;
	int			attr_len;
	char		namespace[DBMS_SESSION_NAME_LEN];
	char		attribute[DBMS_SESSION_NAME_LEN];
} CtxKey;

typedef struct CtxEntry
{
	CtxKey		key;			/* must be first field */
	char	   *value;			/* palloc'd in DbmsSessionContext, NULL for NULL value */
	int			value_len;		/* byte length of value; -1 when value is NULL */
} CtxEntry;

/* Per-backend session state */
static HTAB *DbmsSessionHash = NULL;
static MemoryContext DbmsSessionContext = NULL;

/* Internal helpers */
static void dbms_session_init(void);
static void make_key(CtxKey *key, text *ns_text, text *attr_text);
static void clear_namespace(text *ns_text);

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
 * make_key - build a zero-filled hash key from namespace/attribute names.
 *
 * Oracle treats namespace and attribute names case-insensitively (it folds
 * them to upper case internally), so we upper-case both while copying.  This
 * makes SET_CONTEXT('app', 'usr', ...) readable via SYS_CONTEXT('APP', 'USR'),
 * matching Oracle.  Rejects names that do not fit the fixed-size key buffer.
 */
static void
make_key(CtxKey *key, text *ns_text, text *attr_text)
{
	int			i;
	int			ns_len = VARSIZE_ANY_EXHDR(ns_text);
	int			attr_len = VARSIZE_ANY_EXHDR(attr_text);
	char	   *ns_data = VARDATA_ANY(ns_text);
	char	   *attr_data = VARDATA_ANY(attr_text);

	if (ns_len >= DBMS_SESSION_NAME_LEN)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SESSION namespace too long (max %d bytes)",
						DBMS_SESSION_NAME_LEN - 1)));
	if (attr_len >= DBMS_SESSION_NAME_LEN)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SESSION attribute too long (max %d bytes)",
						DBMS_SESSION_NAME_LEN - 1)));

	/* MemSet first: HASH_BLOBS compares the whole struct as bytes. */
	MemSet(key, 0, sizeof(CtxKey));
	for (i = 0; i < ns_len; i++)
		key->namespace[i] = pg_toupper((unsigned char) ns_data[i]);
	for (i = 0; i < attr_len; i++)
		key->attribute[i] = pg_toupper((unsigned char) attr_data[i]);
	key->ns_len = ns_len;
	key->attr_len = attr_len;
}

/*
 * clear_namespace - remove every attribute belonging to a namespace.
 *
 * Matching keys are collected first and removed afterwards, because dynahash
 * forbids removing entries other than the current one during a seq scan.
 *
 * Length-aware: the namespace is taken from a text datum (so embedded NULs do
 * not truncate it) and matched against stored keys by exact byte length plus
 * memcmp.  Using strcmp here would stop at the first NUL and wrongly delete a
 * stored 'AB'||chr(0)||'C' entry when asked to clear 'AB'.
 */
static void
clear_namespace(text *ns_text)
{
	HASH_SEQ_STATUS seq;
	CtxEntry   *entry;
	CtxKey	   *victims;
	long		nentries;
	int			nvictims = 0;
	int			ns_len = VARSIZE_ANY_EXHDR(ns_text);
	char	   *ns_data = VARDATA_ANY(ns_text);
	char		ns_up[DBMS_SESSION_NAME_LEN];
	int			i;

	if (DbmsSessionHash == NULL)
		return;

	nentries = hash_get_num_entries(DbmsSessionHash);
	if (nentries == 0)
		return;

	/*
	 * Stored keys are upper-cased (see make_key), so upper-case the namespace
	 * here too before comparing.  An over-long namespace cannot match any
	 * stored key (those are length-checked at insert time).
	 */
	if (ns_len >= DBMS_SESSION_NAME_LEN)
		return;
	for (i = 0; i < ns_len; i++)
		ns_up[i] = pg_toupper((unsigned char) ns_data[i]);

	victims = (CtxKey *) palloc(sizeof(CtxKey) * nentries);

	hash_seq_init(&seq, DbmsSessionHash);
	while ((entry = (CtxEntry *) hash_seq_search(&seq)) != NULL)
	{
		if (entry->key.ns_len == ns_len &&
			memcmp(entry->key.namespace, ns_up, ns_len) == 0)
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
	text	   *ns_text;
	text	   *attr_text;
	text	   *val_text = NULL;
	CtxKey		key;
	CtxEntry   *entry;
	bool		found;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_SESSION.SET_CONTEXT namespace and attribute must not be NULL")));

	ns_text = PG_GETARG_TEXT_PP(0);
	attr_text = PG_GETARG_TEXT_PP(1);

	if (!PG_ARGISNULL(2))
	{
		val_text = PG_GETARG_TEXT_PP(2);
		if (VARSIZE_ANY_EXHDR(val_text) > DBMS_SESSION_MAX_VALUE_LEN)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("DBMS_SESSION.SET_CONTEXT value too long (max %d bytes)",
							DBMS_SESSION_MAX_VALUE_LEN)));
	}

	if (DbmsSessionHash == NULL)
		dbms_session_init();

	make_key(&key, ns_text, attr_text);

	entry = (CtxEntry *) hash_search(DbmsSessionHash, &key, HASH_ENTER, &found);

	/* Release any previous value before overwriting */
	if (found && entry->value != NULL)
		pfree(entry->value);

	if (val_text == NULL)
	{
		entry->value = NULL;
		entry->value_len = -1;
	}
	else
	{
		MemoryContext oldcontext = MemoryContextSwitchTo(DbmsSessionContext);
		int			val_len = VARSIZE_ANY_EXHDR(val_text);

		entry->value = palloc(val_len + 1);
		memcpy(entry->value, VARDATA_ANY(val_text), val_len);
		entry->value[val_len] = '\0';
		entry->value_len = val_len;
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
	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_SESSION.CLEAR_CONTEXT namespace must not be NULL")));

	if (DbmsSessionHash == NULL)
		PG_RETURN_VOID();

	if (PG_ARGISNULL(1))
	{
		clear_namespace(PG_GETARG_TEXT_PP(0));
	}
	else
	{
		CtxKey		key;
		CtxEntry   *entry;
		bool		found;

		make_key(&key, PG_GETARG_TEXT_PP(0), PG_GETARG_TEXT_PP(1));
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
	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_SESSION.CLEAR_ALL_CONTEXT namespace must not be NULL")));

	if (DbmsSessionHash == NULL)
		PG_RETURN_VOID();

	clear_namespace(PG_GETARG_TEXT_PP(0));

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
	CtxKey		key;
	CtxEntry   *entry;
	bool		found;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	if (DbmsSessionHash == NULL)
		PG_RETURN_NULL();

	/*
	 * Read path: an over-long name can never match a stored key (set/clear
	 * reject them at insert time), so return NULL rather than letting make_key
	 * raise an error.  This keeps SYS_CONTEXT() usable in predicates without
	 * aborting the query on an oversized argument.  Guard on the true byte
	 * length (VARSIZE_ANY_EXHDR), not strlen(), so an argument containing an
	 * embedded NUL is not mis-measured as short and then rejected by make_key.
	 */
	if (VARSIZE_ANY_EXHDR(PG_GETARG_TEXT_PP(0)) >= DBMS_SESSION_NAME_LEN ||
		VARSIZE_ANY_EXHDR(PG_GETARG_TEXT_PP(1)) >= DBMS_SESSION_NAME_LEN)
		PG_RETURN_NULL();

	make_key(&key, PG_GETARG_TEXT_PP(0), PG_GETARG_TEXT_PP(1));
	entry = (CtxEntry *) hash_search(DbmsSessionHash, &key, HASH_FIND, &found);

	if (!found || entry->value == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text_with_len(entry->value, entry->value_len));
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

			values[0] = PointerGetDatum(cstring_to_text_with_len(entry->key.namespace,
																entry->key.ns_len));
			values[1] = PointerGetDatum(cstring_to_text_with_len(entry->key.attribute,
																entry->key.attr_len));
			if (entry->value == NULL)
				nulls[2] = true;
			else
				values[2] = PointerGetDatum(cstring_to_text_with_len(entry->value,
																	entry->value_len));

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
