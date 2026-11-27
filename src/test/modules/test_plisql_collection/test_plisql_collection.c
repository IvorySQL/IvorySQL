/*--------------------------------------------------------------------------
 *
 * test_plisql_collection.c
 *		Test harness for the plisql sparse collection runtime.
 *
 * The runtime in src/pl/plisql/src/pl_collection_runtime.c is not reachable
 * from SQL until the plisql compiler is switched over to it, and plisql is
 * built with hidden symbol visibility so this module cannot call into
 * plisql.dylib.  This module therefore compiles pl_collection_runtime.c
 * directly -- which it can, because pl_collection.h deliberately depends on
 * nothing from the plisql compiler -- and exposes thin SQL wrappers so the
 * runtime contract can be locked down independently of, and before, the
 * compiler cutover.
 *
 * The wrappers are private to this test extension: no pg_proc.dat entries,
 * no catalog version implications.  They are a test harness, not an API.
 *
 * Collections live in slots keyed by a small integer handle so that a test
 * can script an arbitrary sequence of operations from SQL.  Slots are
 * allocated under TopMemoryContext, so they survive both statement
 * boundaries and the transaction aborts that the error tests provoke.
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *		src/test/modules/test_plisql_collection/test_plisql_collection.c
 *
 * -------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "catalog/pg_type.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"

#include "pl_collection.h"

PG_MODULE_MAGIC;

#define MAX_SLOTS 64

/*
 * A slot holds either an initialized collection or, deliberately, a NULL
 * pointer standing for an atomically NULL collection -- the distinction the
 * runtime encodes by existence of the object.  "used" tells an unallocated
 * slot from an allocated one holding NULL.
 */
typedef struct
{
	bool		used;
	PLiSQL_expanded_collection *coll;
	PLiSQL_coll_meta meta;
}			test_slot;

static test_slot slots[MAX_SLOTS];

static int
slot_alloc(void)
{
	int			i;

	for (i = 0; i < MAX_SLOTS; i++)
	{
		if (!slots[i].used)
		{
			slots[i].used = true;
			slots[i].coll = NULL;
			return i;
		}
	}
	elog(ERROR, "out of collection test slots");
	return -1;					/* keep compiler quiet */
}

static test_slot *
slot_get(int32 handle)
{
	if (handle < 0 || handle >= MAX_SLOTS || !slots[handle].used)
		elog(ERROR, "invalid collection handle %d", handle);
	return &slots[handle];
}

/* Build the metadata a collection of the given element type needs */
static void
fill_meta(PLiSQL_coll_meta *meta, Oid elemtype, char kind, int32 limit)
{
	meta->elemtypoid = elemtype;
	meta->elemtypmod = -1;
	meta->elemcollation = get_typcollation(elemtype);
	meta->tbl_kind = kind;
	meta->varray_limit = limit;
	meta->arraytypoid = get_array_type(elemtype);
	get_typlenbyvalalign(elemtype, &meta->elmlen, &meta->elmbyval,
						 &meta->elmalign);
}

/* Render a Datum through its type's output function */
static text *
datum_to_text(Oid typoid, Datum d)
{
	Oid			outfunc;
	bool		isvarlena;

	getTypeOutputInfo(typoid, &outfunc, &isvarlena);
	return cstring_to_text(OidOutputFunctionCall(outfunc, d));
}

static char
kind_from_text(text *t)
{
	char	   *s = text_to_cstring(t);

	if (strcmp(s, "table") == 0)
		return PLISQL_TBL_NESTED_TABLE;
	if (strcmp(s, "varray") == 0)
		return PLISQL_TBL_VARRAY;
	elog(ERROR, "unrecognized collection kind \"%s\"", s);
	return '\0';
}

/*
 * coll_new(elemtype regtype, kind text, varray_limit int) -> handle
 *		A new, INITIALIZED, empty collection.
 */
PG_FUNCTION_INFO_V1(test_coll_new);

Datum
test_coll_new(PG_FUNCTION_ARGS)
{
	Oid			elemtype = PG_GETARG_OID(0);
	char		kind = kind_from_text(PG_GETARG_TEXT_PP(1));
	int32		limit = PG_ARGISNULL(2) ? -1 : PG_GETARG_INT32(2);
	int			h = slot_alloc();

	fill_meta(&slots[h].meta, elemtype, kind, limit);
	slots[h].coll = plisql_collection_new(&slots[h].meta, TopMemoryContext);

	PG_RETURN_INT32(h);
}

/*
 * coll_import(arr anyarray, elemtype regtype, kind text, limit int) -> handle
 *		The flat-array import path.  A NULL arr is an atomically NULL
 *		collection, which is why this is non-strict and why elemtype is
 *		passed separately rather than read off the array.
 */
PG_FUNCTION_INFO_V1(test_coll_import);

Datum
test_coll_import(PG_FUNCTION_ARGS)
{
	Oid			elemtype = PG_GETARG_OID(1);
	char		kind = kind_from_text(PG_GETARG_TEXT_PP(2));
	int32		limit = PG_ARGISNULL(3) ? -1 : PG_GETARG_INT32(3);
	int			h = slot_alloc();
	bool		isnull = PG_ARGISNULL(0);

	fill_meta(&slots[h].meta, elemtype, kind, limit);
	slots[h].coll = plisql_collection_from_datum(isnull ? (Datum) 0 : PG_GETARG_DATUM(0),
												 isnull,
												 &slots[h].meta,
												 TopMemoryContext);
	PG_RETURN_INT32(h);
}

/*
 * coll_is_null(handle) -> bool
 *		Whether the slot holds an atomically NULL collection rather than an
 *		initialized (possibly empty) one.
 */
PG_FUNCTION_INFO_V1(test_coll_is_null);

Datum
test_coll_is_null(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	PG_RETURN_BOOL(s->coll == NULL);
}

/*
 * coll_roundtrip_expanded(handle) -> handle
 *		Boundary (1): hand the collection out as an expanded datum and bring
 *		it back.  Holes must survive.
 */
PG_FUNCTION_INFO_V1(test_coll_roundtrip_expanded);

Datum
test_coll_roundtrip_expanded(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	Datum		d;
	bool		isnull;
	int			h;

	d = plisql_collection_get_expanded(s->coll, &isnull);

	h = slot_alloc();
	slots[h].meta = s->meta;
	slots[h].coll = plisql_collection_from_datum(d, isnull, &slots[h].meta,
												 TopMemoryContext);
	PG_RETURN_INT32(h);
}

/*
 * coll_roundtrip_flat(handle) -> handle
 *		Boundary (2): flatten to SQL and import the result back.  Holes must
 *		NOT survive; the result must be dense and 1-based.
 */
PG_FUNCTION_INFO_V1(test_coll_roundtrip_flat);

Datum
test_coll_roundtrip_flat(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	Datum		d;
	bool		isnull;
	int			h;

	d = plisql_collection_flatten_sql(s->coll, &isnull);

	h = slot_alloc();
	slots[h].meta = s->meta;
	slots[h].coll = plisql_collection_from_datum(d, isnull, &slots[h].meta,
												 TopMemoryContext);
	PG_RETURN_INT32(h);
}

/*
 * coll_flatten(handle) -> text
 *		The densified SQL value, rendered through the array type's output
 *		function so the test can see both contents and subscript bounds.
 */
PG_FUNCTION_INFO_V1(test_coll_flatten);

Datum
test_coll_flatten(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	Datum		d;
	bool		isnull;

	d = plisql_collection_flatten_sql(s->coll, &isnull);
	if (isnull)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(datum_to_text(s->meta.arraytypoid, d));
}

PG_FUNCTION_INFO_V1(test_coll_set);

Datum
test_coll_set(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	int32		idx = PG_GETARG_INT32(1);

	plisql_collection_set(s->coll, idx,
						  PG_ARGISNULL(2) ? (Datum) 0 : PG_GETARG_DATUM(2),
						  PG_ARGISNULL(2));
	PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(test_coll_get);

Datum
test_coll_get(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	int32		idx = PG_GETARG_INT32(1);
	Datum		d;
	bool		isnull;

	d = plisql_collection_get(s->coll, idx, &isnull);
	if (isnull)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(datum_to_text(s->meta.elemtypoid, d));
}

PG_FUNCTION_INFO_V1(test_coll_exists);

Datum
test_coll_exists(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	PG_RETURN_BOOL(plisql_collection_exists(s->coll, PG_GETARG_INT32(1)));
}

PG_FUNCTION_INFO_V1(test_coll_delete);

Datum
test_coll_delete(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	plisql_collection_delete(s->coll, PG_GETARG_INT32(1));
	PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(test_coll_delete_all);

Datum
test_coll_delete_all(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	plisql_collection_delete_all(s->coll);
	PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(test_coll_count);

Datum
test_coll_count(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	PG_RETURN_INT32(plisql_collection_count(s->coll));
}

PG_FUNCTION_INFO_V1(test_coll_first);

Datum
test_coll_first(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	int32		idx;

	if (!plisql_collection_first(s->coll, &idx))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx);
}

PG_FUNCTION_INFO_V1(test_coll_last);

Datum
test_coll_last(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	int32		idx;

	if (!plisql_collection_last(s->coll, &idx))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx);
}

PG_FUNCTION_INFO_V1(test_coll_next);

Datum
test_coll_next(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	int32		idx;

	if (!plisql_collection_next(s->coll, PG_GETARG_INT32(1), &idx))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx);
}

PG_FUNCTION_INFO_V1(test_coll_prior);

Datum
test_coll_prior(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	int32		idx;

	if (!plisql_collection_prior(s->coll, PG_GETARG_INT32(1), &idx))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx);
}

PG_FUNCTION_INFO_V1(test_coll_extend);

Datum
test_coll_extend(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	plisql_collection_extend(s->coll, PG_GETARG_INT32(1));
	PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(test_coll_trim);

Datum
test_coll_trim(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));

	plisql_collection_trim(s->coll, PG_GETARG_INT32(1));
	PG_RETURN_VOID();
}

/* -------------------------------------------------------------------------
 * Type-boundary prototype
 *
 * The crash that stopped the compiler cutover came from PostgreSQL's array
 * code casting our expanded object to ExpandedArrayHeader on the strength of
 * its DECLARED TYPE alone (arrayfuncs.c checks VARATT_IS_EXTERNAL_EXPANDED
 * and then casts, without consulting eoh_methods).  The fix is for the
 * in-memory collection to stop being typed as an array.
 *
 * This prototypes that: a dedicated "plisql_collection" type, created inside
 * this test extension so the experiment costs no pg_type.dat row and no
 * catalog version bump.  A value of that type carries the very same expanded
 * collection object -- what changes is only what SQL believes it is.  The
 * accompanying test then shows that array machinery can no longer reach it.
 *
 * Note what the output function below does and array code does not: it
 * consults eoh_methods before casting.  That is the discipline the dedicated
 * type makes enforceable rather than merely advisable.
 * -------------------------------------------------------------------------
 */

/*
 * coll_as_type(handle) -> plisql_collection
 *		The same expanded object the runtime already holds, handed to SQL
 *		under the dedicated type instead of under elem[].
 */
PG_FUNCTION_INFO_V1(test_coll_as_type);

Datum
test_coll_as_type(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	Datum		d;
	bool		isnull;

	d = plisql_collection_get_expanded(s->coll, &isnull);
	if (isnull)
		PG_RETURN_NULL();
	PG_RETURN_DATUM(d);
}

/*
 * A collection-aware operation whose argument is the dedicated type: this is
 * the shape the compiler's expression-position calls would take.
 */
PG_FUNCTION_INFO_V1(test_coll_type_count);

Datum
test_coll_type_count(PG_FUNCTION_ARGS)
{
	ExpandedObjectHeader *eohptr = DatumGetEOHP(PG_GETARG_DATUM(0));

	if (eohptr->eoh_methods != &plisql_collection_methods)
		elog(ERROR, "not an expanded plisql collection");

	PG_RETURN_INT32(plisql_collection_count((PLiSQL_expanded_collection *) eohptr));
}

/*
 * The explicit conversion boundary: dedicated type -> elem[].
 */
PG_FUNCTION_INFO_V1(test_coll_type_flatten);

Datum
test_coll_type_flatten(PG_FUNCTION_ARGS)
{
	ExpandedObjectHeader *eohptr = DatumGetEOHP(PG_GETARG_DATUM(0));
	PLiSQL_expanded_collection *coll;
	Datum		flat;
	bool		isnull;

	if (eohptr->eoh_methods != &plisql_collection_methods)
		elog(ERROR, "not an expanded plisql collection");

	coll = (PLiSQL_expanded_collection *) eohptr;
	flat = plisql_collection_flatten_sql(coll, &isnull);
	if (isnull)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(datum_to_text(coll->meta.arraytypoid, flat));
}

/*
 * coll_roundtrip_internal_flat(handle) -> handle
 *		Force the value through the INTERNAL flat form and back.
 *
 * PostgreSQL can flatten an expanded datum whenever it wants a flat one, so
 * this is not a hypothetical path -- and unlike the SQL boundary it must
 * preserve holes, because an implicit flattening must not change the value.
 */
PG_FUNCTION_INFO_V1(test_coll_roundtrip_internal_flat);

Datum
test_coll_roundtrip_internal_flat(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	ExpandedObjectHeader *eohptr;
	Size		sz;
	char	   *flat;
	int			h;

	if (s->coll == NULL)
	{
		h = slot_alloc();
		slots[h].meta = s->meta;
		slots[h].coll = NULL;
		PG_RETURN_INT32(h);
	}

	/* flatten exactly the way the core would */
	eohptr = &s->coll->hdr;
	sz = EOH_get_flat_size(eohptr);
	flat = MemoryContextAlloc(TopMemoryContext, sz);
	EOH_flatten_into(eohptr, flat, sz);

	h = slot_alloc();
	slots[h].meta = s->meta;
	slots[h].coll = plisql_collection_from_internal(PointerGetDatum(flat), false,
													&slots[h].meta,
													TopMemoryContext);
	PG_RETURN_INT32(h);
}

/*
 * coll_corrupt_internal(handle, field) -> void
 *		Flatten, damage one field of the internal form, and try to re-import.
 *
 * The requirement being tested is that a malformed internal value RAISES --
 * never that it gets reinterpreted, and in particular never that it is read
 * as a dense array, which is how these same bytes would decode if the two
 * flat encodings were ever confused for one another.
 */
PG_FUNCTION_INFO_V1(test_coll_corrupt_internal);

Datum
test_coll_corrupt_internal(PG_FUNCTION_ARGS)
{
	test_slot  *s = slot_get(PG_GETARG_INT32(0));
	char	   *what = text_to_cstring(PG_GETARG_TEXT_PP(1));
	ExpandedObjectHeader *eohptr;
	PLiSQL_coll_flat_header *hdr;
	Size		sz;
	char	   *flat;
	int32	   *indexes;

	if (s->coll == NULL)
		elog(ERROR, "coll_corrupt_internal: slot holds an atomically NULL collection");

	eohptr = &s->coll->hdr;
	sz = EOH_get_flat_size(eohptr);
	flat = palloc(sz);
	EOH_flatten_into(eohptr, flat, sz);
	hdr = (PLiSQL_coll_flat_header *) flat;
	indexes = (int32 *) (flat + sizeof(PLiSQL_coll_flat_header));

	if (strcmp(what, "version") == 0)
		hdr->version = 99;
	else if (strcmp(what, "count") == 0)
		hdr->nentries = -1;
	else if (strcmp(what, "count_high") == 0)
		hdr->nentries = 1000000;
	else if (strcmp(what, "kind") == 0)
		hdr->tbl_kind = 'x';
	else if (strcmp(what, "elemtype") == 0)
		hdr->elemtypoid = InvalidOid;
	else if (strcmp(what, "order") == 0)
	{
		int32		tmp;

		if (hdr->nentries < 2)
			elog(ERROR, "coll_corrupt_internal('order') needs at least 2 entries, slot has %d",
				 hdr->nentries);
		tmp = indexes[0];
		indexes[0] = indexes[hdr->nentries - 1];
		indexes[hdr->nentries - 1] = tmp;
	}
	else if (strcmp(what, "duplicate") == 0)
	{
		if (hdr->nentries < 2)
			elog(ERROR, "coll_corrupt_internal('duplicate') needs at least 2 entries, slot has %d",
				 hdr->nentries);
		indexes[1] = indexes[0];
	}
	else if (strcmp(what, "subscript") == 0)
	{
		if (hdr->nentries < 1)
			elog(ERROR, "coll_corrupt_internal('subscript') needs at least 1 entry, slot has %d",
				 hdr->nentries);
		indexes[0] = 0;
	}
	else if (strcmp(what, "truncate") == 0)
		SET_VARSIZE(hdr, sizeof(PLiSQL_coll_flat_header) - 1);
	else
		elog(ERROR, "unknown corruption \"%s\"", what);

	(void) plisql_collection_from_internal(PointerGetDatum(flat), false,
										   &s->meta, TopMemoryContext);
	PG_RETURN_VOID();
}
