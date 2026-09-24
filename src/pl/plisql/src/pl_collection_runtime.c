/*-------------------------------------------------------------------------
 *
 * pl_collection_runtime.c
 *		Sparse collection runtime for Oracle nested tables and VARRAYs.
 *
 * Implements the interface in pl_collection.h: an expanded-datum collection
 * holding present elements in a sorted entry vector, so that DELETE(i)
 * leaves a hole and EXISTS/NEXT/PRIOR can traverse across holes -- the
 * defining behavior of a nested table, which the dense array representation
 * in pl_collection.c cannot express.
 *
 * WHERE THE POLICY LIVES
 *
 * This file answers for what a collection IS -- what subscripts exist, what
 * a hole is, what each operation does to the entry vector.  It does not
 * decide which of those operations a particular declared collection is
 * allowed to ask for.  That belongs to the caller, because it varies by
 * collection kind:
 *
 *		set() will create an entry at any valid subscript, because an
 *		associative array will need exactly that.  A nested table may not
 *		be grown that way, so exec_stmt_coll_assign() requires the
 *		subscript to exist already and reports a deleted one differently
 *		from one that was never allocated.
 *
 *		delete() refuses on a VARRAY here, because "dense" is a property of
 *		the kind and the kind is recorded in meta.
 *
 * Keeping the split that way is what let the compiler migrate one operation
 * at a time without the runtime having to know how far along it was.
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_collection_runtime.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "lib/stringinfo.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/json.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"

#include "pl_collection.h"

static Size plisql_collection_get_flat_size(ExpandedObjectHeader *eohptr);
static void plisql_collection_flatten_into(ExpandedObjectHeader *eohptr,
										   void *result, Size allocated_size);
static void coll_build_flat(PLiSQL_expanded_collection *coll);
static void coll_check_same_type(const PLiSQL_coll_meta *a,
								 const PLiSQL_coll_meta *b);
static void coll_enlarge(PLiSQL_expanded_collection *coll, int needed);
static void coll_store_value(PLiSQL_expanded_collection *coll, int pos,
							 Datum value, bool isnull);
static void coll_validate_flat(struct varlena *flat);
static PLiSQL_expanded_collection *coll_from_internal_flat(struct varlena *flat,
																   const PLiSQL_coll_meta *meta,
																   MemoryContext parentcontext);
static PLiSQL_expanded_collection *coll_copy(PLiSQL_expanded_collection *src,
											 MemoryContext parentcontext);

const ExpandedObjectMethods plisql_collection_methods =
{
	plisql_collection_get_flat_size,
	plisql_collection_flatten_into
};

/*
 * Oracle names two conditions this file raises -- COLLECTION_IS_NULL
 * (ORA-06531) and SUBSCRIPT_BEYOND_COUNT / SUBSCRIPT_OUTSIDE_LIMIT
 * (ORA-06533 / ORA-06532).  plisql has no condition names for them yet
 * (see plerrcodes.h), so they are raised under the closest SQLSTATEs and can
 * be caught by OTHERS or by SQLSTATE.  Adding the Oracle spellings to
 * plerrcodes.h is worth doing before this runtime is user-visible.
 */
#define ERRCODE_COLLECTION_IS_NULL	ERRCODE_NULL_VALUE_NOT_ALLOWED

/*
 * Raise if the collection was never initialized.  A NULL coll pointer is how
 * an atomically NULL collection is represented; see pl_collection.h.
 */
void
plisql_collection_check_initialized(PLiSQL_expanded_collection *coll,
								   const char *method)
{
	if (coll == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_COLLECTION_IS_NULL),
				 errmsg("reference to uninitialized collection"),
				 errdetail("Collection method \"%s\" was applied to a collection that has not been initialized.",
						   method)));
}

/*
 * Raise if idx is not a legal subscript for this collection's kind.  EXISTS
 * deliberately does not call this: Oracle defines it never to raise, which
 * is what makes it usable as a guard.
 */
void
plisql_collection_check_subscript(const PLiSQL_coll_meta *meta, int32 idx)
{
	if (idx < 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("subscript %d is outside the valid range for a collection",
						idx),
				 errdetail("Collection subscripts start at 1.")));

	if (meta->tbl_kind == PLISQL_TBL_VARRAY &&
		meta->varray_limit >= 0 && idx > meta->varray_limit)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("subscript %d exceeds the declared VARRAY limit %d",
						idx, meta->varray_limit)));
}

/*
 * A collection value is always one-dimensional: every collection-producing
 * path builds it that way, and all of the operations on it interpret the
 * value through a single (lower bound .. upper bound) subscript range.  A
 * multidimensional value has no such range, so it must be rejected at every
 * entry point rather than at some of them.
 *
 * An empty collection (ARR_NDIM == 0) passes this check: it is legal, and
 * what it means differs per operation, so each caller handles it itself.
 */
void
plisql_collection_check_ndim(ArrayType *arr)
{
	if (ARR_NDIM(arr) > 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("collection must be one-dimensional"),
				 errdetail("This collection value has %d dimensions.",
						   ARR_NDIM(arr))));
}

/*
 * Binary search for idx.  Returns the position it occupies if present, or
 * the position it would be inserted at if not; *found says which.
 */
static int
coll_search(PLiSQL_expanded_collection *coll, int32 idx, bool *found)
{
	int			lo = 0;
	int			hi = coll->nentries;

	while (lo < hi)
	{
		int			mid = lo + (hi - lo) / 2;

		if (coll->entries[mid].index < idx)
			lo = mid + 1;
		else
			hi = mid;
	}

	*found = (lo < coll->nentries && coll->entries[lo].index == idx);
	return lo;
}

/*
 * Ensure room for at least "needed" entries.  Growth is doubling, which is
 * what makes EXTEND amortized O(1) rather than unconditionally O(1).
 */
static void
coll_enlarge(PLiSQL_expanded_collection *coll, int needed)
{
	MemoryContext oldcxt;
	int64		newmax;

	if (needed <= coll->maxentries)
		return;

	/*
	 * Widen to int64 while doubling: needed can approach
	 * PLISQL_COLL_MAX_INDEX, and doubling an int past 2^30 overflows a
	 * 32-bit signed int, wrapping negative and then looping forever (the
	 * growth condition "newmax < needed" stays satisfied by a negative
	 * newmax).  AllocSizeIsValid() below is what actually turns "too big"
	 * into a clean error instead of a hang or a bogus allocation size.
	 */
	newmax = (coll->maxentries > 0) ? (int64) coll->maxentries * 2 : 16;
	while (newmax < needed)
		newmax *= 2;

	if (newmax > PG_INT32_MAX ||
		!AllocSizeIsValid((Size) newmax * sizeof(PLiSQL_collection_entry)))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("collection is too large")));

	oldcxt = MemoryContextSwitchTo(coll->ec_context);
	if (coll->entries == NULL)
		coll->entries = (PLiSQL_collection_entry *)
			palloc((Size) newmax * sizeof(PLiSQL_collection_entry));
	else
		coll->entries = (PLiSQL_collection_entry *)
			repalloc(coll->entries, (Size) newmax * sizeof(PLiSQL_collection_entry));
	MemoryContextSwitchTo(oldcxt);

	coll->maxentries = (int) newmax;
}

/*
 * Any mutation invalidates the cached flat value.
 *
 * The old copies are freed here rather than left to accumulate: every
 * consumer re-fetches through plisql_collection_flatten_sql() or the EOH
 * flatten methods before use (see their callers), and PL/iSQL execution is
 * single-threaded, so nothing can still be holding a reference to the
 * previous flat value once a mutation has invalidated it.
 *
 * An earlier version of this eager free was reverted after it appeared to
 * cause an intermittent pfree() assertion failure.  That crash is now
 * understood to have been plisql_collection_new() leaving fflat
 * uninitialized (fixed above): coll->fflat held garbage rather than NULL,
 * so "if (coll->fflat != NULL) pfree(coll->fflat)" here freed whatever
 * uninitialized memory happened to be there, not a real dangling reference.
 * With fflat properly NULL-initialized at construction, this is safe.
 */
static void
coll_invalidate_flat(PLiSQL_expanded_collection *coll)
{
	if (coll->fvalue != NULL)
	{
		pfree(coll->fvalue);
		coll->fvalue = NULL;
	}
	if (coll->fflat != NULL)
	{
		pfree(coll->fflat);
		coll->fflat = NULL;
	}
}

/*
 * Store value at position pos, copying a pass-by-reference datum into
 * ec_context so the object owns every element it holds.
 */
static void
coll_store_value(PLiSQL_expanded_collection *coll, int pos,
				 Datum value, bool isnull)
{
	if (isnull)
	{
		coll->entries[pos].value = (Datum) 0;
		coll->entries[pos].isnull = true;
	}
	else
	{
		/* datumCopy() already short-circuits the pass-by-value case */
		MemoryContext oldcxt = MemoryContextSwitchTo(coll->ec_context);

		coll->entries[pos].value = datumCopy(value, coll->meta.elmbyval,
											 coll->meta.elmlen);
		MemoryContextSwitchTo(oldcxt);
		coll->entries[pos].isnull = false;
	}
}

/*
 * A pass-by-reference value a mutation has discarded, pending pfree(); see
 * the comment on PLiSQL_expanded_collection.ec_retired for why the free is
 * deferred rather than immediate.  Lives in ec_context like everything else
 * the collection owns.
 */
typedef struct PLiSQL_coll_retired
{
	struct PLiSQL_coll_retired *next;
	Datum		value;
} PLiSQL_coll_retired;

/*
 * Queue entry's current value for freeing at the start of the NEXT mutating
 * call, rather than freeing it here.  A no-op for a NULL entry or a
 * pass-by-value type, neither of which owns any separate allocation.
 */
static void
coll_retire_value(PLiSQL_expanded_collection *coll, PLiSQL_collection_entry *entry)
{
	PLiSQL_coll_retired *node;

	if (entry->isnull || coll->meta.elmbyval)
		return;

	node = (PLiSQL_coll_retired *)
		MemoryContextAlloc(coll->ec_context, sizeof(PLiSQL_coll_retired));
	node->value = entry->value;
	node->next = (PLiSQL_coll_retired *) coll->ec_retired;
	coll->ec_retired = node;
}

/*
 * Actually free everything coll_retire_value() queued for this collection.
 * Called at the start of every mutating operation, so what it frees here was
 * queued by a PRIOR mutating call -- at least one call boundary removed from
 * anything plisql_collection_get() could still have handed out live.
 */
static void
coll_flush_retired(PLiSQL_expanded_collection *coll)
{
	PLiSQL_coll_retired *node = (PLiSQL_coll_retired *) coll->ec_retired;

	while (node != NULL)
	{
		PLiSQL_coll_retired *next = node->next;

		pfree(DatumGetPointer(node->value));
		pfree(node);
		node = next;
	}
	coll->ec_retired = NULL;
}

/*
 * Build the densified flat representation: present elements in ascending
 * index order, contiguous and 1-based, holes dropped.
 */
static void
coll_build_flat(PLiSQL_expanded_collection *coll)
{
	MemoryContext oldcxt;
	Datum	   *elems;
	bool	   *nulls;
	int			dims[1];
	int			lbs[1];
	int			i;

	oldcxt = MemoryContextSwitchTo(coll->ec_context);

	if (coll->nentries == 0)
	{
		coll->fvalue = construct_empty_array(coll->meta.elemtypoid);
		MemoryContextSwitchTo(oldcxt);
		return;
	}

	elems = (Datum *) palloc(coll->nentries * sizeof(Datum));
	nulls = (bool *) palloc(coll->nentries * sizeof(bool));
	for (i = 0; i < coll->nentries; i++)
	{
		elems[i] = coll->entries[i].value;
		nulls[i] = coll->entries[i].isnull;
	}

	dims[0] = coll->nentries;
	lbs[0] = 1;

	coll->fvalue = construct_md_array(elems, nulls, 1, dims, lbs,
									  coll->meta.elemtypoid,
									  coll->meta.elmlen,
									  coll->meta.elmbyval,
									  coll->meta.elmalign);

	pfree(elems);
	pfree(nulls);
	MemoryContextSwitchTo(oldcxt);
}

/*
 * Offset of the values array within the internal flat form.
 */
static Size
coll_flat_array_offset(int nentries)
{
	return MAXALIGN(sizeof(PLiSQL_coll_flat_header) + nentries * sizeof(int32));
}

/*
 * Build the INTERNAL flat form: self-describing, holes preserved.
 *
 * PostgreSQL may flatten an expanded datum whenever it wants a flat one, and
 * such an implicit flattening must not change the value.  That is why this
 * carries the subscript vector rather than densifying the way the explicit
 * SQL boundary does.
 */
static void
coll_build_internal_flat(PLiSQL_expanded_collection *coll)
{
	MemoryContext oldcxt;
	PLiSQL_coll_flat_header *hdr;
	Size		arroff;
	Size		total;
	char	   *base;
	int32	   *indexes;
	ArrayType  *values;
	int			i;

	if (coll->fvalue == NULL)
		coll_build_flat(coll);	/* the dense value array, reused here */

	values = coll->fvalue;
	arroff = coll_flat_array_offset(coll->nentries);
	total = arroff + VARSIZE(values);

	oldcxt = MemoryContextSwitchTo(coll->ec_context);
	base = (char *) palloc0(total);
	MemoryContextSwitchTo(oldcxt);

	hdr = (PLiSQL_coll_flat_header *) base;
	SET_VARSIZE(hdr, total);
	hdr->version = PLISQL_COLL_FLAT_VERSION;
	hdr->elemtypoid = coll->meta.elemtypoid;
	hdr->elemtypmod = coll->meta.elemtypmod;
	hdr->elemcollation = coll->meta.elemcollation;
	hdr->varray_limit = coll->meta.varray_limit;
	hdr->tbl_kind = (int32) coll->meta.tbl_kind;
	hdr->nentries = coll->nentries;
	hdr->maxindex = coll->ec_maxindex;

	indexes = (int32 *) (base + sizeof(PLiSQL_coll_flat_header));
	for (i = 0; i < coll->nentries; i++)
		indexes[i] = coll->entries[i].index;

	memcpy(base + arroff, values, VARSIZE(values));

	coll->fflat = (struct varlena *) base;
}

/*
 * EOH methods.  These produce the INTERNAL flat form, not the SQL one: see
 * the comment on fvalue/fflat in pl_collection.h.
 */
static Size
plisql_collection_get_flat_size(ExpandedObjectHeader *eohptr)
{
	PLiSQL_expanded_collection *coll = (PLiSQL_expanded_collection *) eohptr;

	Assert(coll->ec_magic == PLISQL_EC_MAGIC);

	if (coll->fflat == NULL)
		coll_build_internal_flat(coll);

	return VARSIZE(coll->fflat);
}

static void
plisql_collection_flatten_into(ExpandedObjectHeader *eohptr,
							   void *result, Size allocated_size)
{
	PLiSQL_expanded_collection *coll = (PLiSQL_expanded_collection *) eohptr;

	Assert(coll->ec_magic == PLISQL_EC_MAGIC);

	if (coll->fflat == NULL)
		coll_build_internal_flat(coll);

	Assert(allocated_size == VARSIZE(coll->fflat));
	memcpy(result, coll->fflat, allocated_size);
}

/*
 * Rebuild a collection from the internal flat form, holes and all.
 */
static void
coll_validate_flat(struct varlena *flat)
{
	PLiSQL_coll_flat_header *hdr = (PLiSQL_coll_flat_header *) flat;
	Size		sz = VARSIZE(flat);
	Size		arroff;
	ArrayType  *values;
	int32	   *indexes;
	int			i;

	/*
	 * A malformed internal value must raise, never be reinterpreted -- in
	 * particular never as a dense array, which is how the same bytes would
	 * read if this encoding were ever confused with the elem[] one.
	 */
	if (sz < sizeof(PLiSQL_coll_flat_header))
		elog(ERROR, "plisql collection flat value is truncated (%zu bytes)", sz);

	if (hdr->version != PLISQL_COLL_FLAT_VERSION)
		elog(ERROR, "unrecognized plisql collection flat version %d",
			 hdr->version);

	if (hdr->nentries < 0)
		elog(ERROR, "plisql collection flat value has negative entry count %d",
			 hdr->nentries);

	if (hdr->tbl_kind != (int32) PLISQL_TBL_NESTED_TABLE &&
		hdr->tbl_kind != (int32) PLISQL_TBL_VARRAY)
		elog(ERROR, "plisql collection flat value has unrecognized kind %d",
			 hdr->tbl_kind);

	if (hdr->tbl_kind == (int32) PLISQL_TBL_VARRAY &&
		hdr->varray_limit >= 0 && hdr->nentries > hdr->varray_limit)
		elog(ERROR, "plisql collection flat value has %d entries, exceeding its VARRAY limit %d",
			 hdr->nentries, hdr->varray_limit);

	if (!OidIsValid(hdr->elemtypoid))
		elog(ERROR, "plisql collection flat value has invalid element type");

	/* payload bounds: header + subscripts + a complete array must fit */
	arroff = coll_flat_array_offset(hdr->nentries);
	if (arroff > sz || sz - arroff < VARHDRSZ)
		elog(ERROR, "plisql collection flat value is truncated before its values");

	values = (ArrayType *) ((char *) flat + arroff);
	if (VARSIZE(values) > sz - arroff)
		elog(ERROR, "plisql collection flat value's payload overruns the datum");

	if (ARR_NDIM(values) > 1)
		elog(ERROR, "plisql collection flat value has a %d-dimensional payload",
			 ARR_NDIM(values));

	/* subscripts must be ascending, unique and legal */
	indexes = (int32 *) ((char *) flat + sizeof(PLiSQL_coll_flat_header));
	for (i = 0; i < hdr->nentries; i++)
	{
		if (indexes[i] < 1)
			elog(ERROR, "plisql collection flat value has invalid subscript %d",
				 indexes[i]);
		if (i > 0 && indexes[i] <= indexes[i - 1])
			elog(ERROR, "plisql collection flat value has out-of-order or duplicate subscripts (%d after %d)",
				 indexes[i], indexes[i - 1]);
	}

	/*
	 * The high-water mark may exceed the highest present subscript -- that
	 * is what records a deleted last element -- but it can never be below
	 * it, which would say a present element was never allocated.
	 */
	if (hdr->maxindex < 0)
		elog(ERROR, "plisql collection flat value has negative maxindex %d",
			 hdr->maxindex);
	if (hdr->nentries > 0 && hdr->maxindex < indexes[hdr->nentries - 1])
		elog(ERROR, "plisql collection flat value has maxindex %d below its highest subscript %d",
			 hdr->maxindex, indexes[hdr->nentries - 1]);
}

static PLiSQL_expanded_collection *
coll_from_internal_flat(struct varlena *flat, const PLiSQL_coll_meta *meta,
						MemoryContext parentcontext)
{
	PLiSQL_coll_flat_header *hdr = (PLiSQL_coll_flat_header *) flat;
	PLiSQL_expanded_collection *coll;
	PLiSQL_coll_meta flatmeta;
	int32	   *indexes;
	ArrayType  *values;
	Datum	   *elems;
	bool	   *nulls;
	int			nelems;
	int			i;

	coll_validate_flat(flat);

	/* the flat form is self-describing, so its identity can be checked */
	flatmeta = *meta;
	flatmeta.elemtypoid = hdr->elemtypoid;
	flatmeta.elemtypmod = hdr->elemtypmod;
	flatmeta.elemcollation = hdr->elemcollation;
	flatmeta.tbl_kind = (char) hdr->tbl_kind;
	flatmeta.varray_limit = hdr->varray_limit;
	coll_check_same_type(&flatmeta, meta);

	coll = plisql_collection_new(meta, parentcontext);
	coll->ec_maxindex = hdr->maxindex;
	if (hdr->nentries == 0)
		return coll;

	indexes = (int32 *) ((char *) flat + sizeof(PLiSQL_coll_flat_header));
	values = (ArrayType *) ((char *) flat + coll_flat_array_offset(hdr->nentries));

	deconstruct_array(values, meta->elemtypoid,
					  meta->elmlen, meta->elmbyval, meta->elmalign,
					  &elems, &nulls, &nelems);

	if (nelems != hdr->nentries)
		elog(ERROR, "plisql collection flat form is inconsistent: %d subscripts, %d values",
			 hdr->nentries, nelems);

	coll_enlarge(coll, nelems);
	for (i = 0; i < nelems; i++)
	{
		coll->entries[i].index = indexes[i];
		coll_store_value(coll, i, elems[i], nulls[i]);
	}
	coll->nentries = nelems;

	pfree(elems);
	pfree(nulls);

	return coll;
}

/*
 * Bring in a value of the INTERNAL collection type -- expanded or flat.
 *
 * Kept separate from plisql_collection_from_datum(), which imports the
 * SQL-visible elem[] form, because the two flat encodings are not reliably
 * distinguishable by inspection and the caller always knows which declared
 * type it is holding.  Conflating them would let a misrouted value decode as
 * garbage instead of raising.
 */
PLiSQL_expanded_collection *
plisql_collection_from_internal(Datum value, bool isnull,
								const PLiSQL_coll_meta *meta,
								MemoryContext parentcontext)
{
	if (isnull)
		return NULL;

	if (VARATT_IS_EXTERNAL_EXPANDED(DatumGetPointer(value)))
	{
		ExpandedObjectHeader *eohptr = DatumGetEOHP(value);
		PLiSQL_expanded_collection *src;

		if (eohptr->eoh_methods != &plisql_collection_methods)
			elog(ERROR, "expanded datum is not a plisql collection");

		src = (PLiSQL_expanded_collection *) eohptr;
		Assert(src->ec_magic == PLISQL_EC_MAGIC);
		coll_check_same_type(&src->meta, meta);
		return coll_copy(src, parentcontext);
	}

	return coll_from_internal_flat((struct varlena *) PG_DETOAST_DATUM(value),
								   meta, parentcontext);
}


/*
 * Construction and import
 */

PLiSQL_expanded_collection *
plisql_collection_new(const PLiSQL_coll_meta *meta, MemoryContext parentcontext)
{
	MemoryContext objcxt;
	PLiSQL_expanded_collection *coll;

	objcxt = AllocSetContextCreate(parentcontext,
								   "PL/iSQL collection",
								   ALLOCSET_SMALL_SIZES);

	coll = (PLiSQL_expanded_collection *)
		MemoryContextAlloc(objcxt, sizeof(PLiSQL_expanded_collection));

	EOH_init_header(&coll->hdr, &plisql_collection_methods, objcxt);
	coll->ec_magic = PLISQL_EC_MAGIC;
	coll->meta = *meta;
	coll->entries = NULL;
	coll->nentries = 0;
	coll->maxentries = 0;
	coll->ec_maxindex = 0;
	coll->ec_context = objcxt;
	coll->ec_retired = NULL;
	coll->fvalue = NULL;
	coll->fflat = NULL;

	return coll;
}

/*
 * Adoption guard: ec_magic identifies this implementation, not the
 * collection's type, so the type identity has to be checked separately.
 * A mismatch means the compiler emitted a transfer it should never have
 * emitted, hence elog() rather than a user-facing ereport().
 */
static void
coll_check_same_type(const PLiSQL_coll_meta *a, const PLiSQL_coll_meta *b)
{
	if (a->elemtypoid != b->elemtypoid ||
		a->elemtypmod != b->elemtypmod ||
		a->elemcollation != b->elemcollation ||
		a->tbl_kind != b->tbl_kind ||
		a->varray_limit != b->varray_limit)
		elog(ERROR, "collection type mismatch in expanded collection transfer");
}

/*
 * Copy an expanded collection, preserving holes, into a new object under
 * parentcontext.
 *
 * Copying rather than adopting the incoming object outright is the
 * conservative choice: the source may be a read-only expanded pointer, or
 * owned by a context that outlives or underlives the destination.  A
 * transfer fast path for the case where the caller holds a read-write
 * pointer it owns (TransferExpandedObject, no copy) is a worthwhile
 * optimization once the transfer sites are all converted, but correctness
 * does not depend on it.
 */
static PLiSQL_expanded_collection *
coll_copy(PLiSQL_expanded_collection *src, MemoryContext parentcontext)
{
	PLiSQL_expanded_collection *coll;
	int			i;

	coll = plisql_collection_new(&src->meta, parentcontext);

	/*
	 * Carry the high-water mark across.  Without it a transfer would forget
	 * that the highest subscript had been deleted, and reading it in the
	 * copy would report "out of bounds" where the original said
	 * NO_DATA_FOUND.
	 */
	coll->ec_maxindex = src->ec_maxindex;

	if (src->nentries == 0)
		return coll;

	coll_enlarge(coll, src->nentries);
	for (i = 0; i < src->nentries; i++)
	{
		coll->entries[i].index = src->entries[i].index;
		coll_store_value(coll, i, src->entries[i].value, src->entries[i].isnull);
	}
	coll->nentries = src->nentries;

	return coll;
}

PLiSQL_expanded_collection *
plisql_collection_from_datum(Datum value, bool isnull,
							 const PLiSQL_coll_meta *meta,
							 MemoryContext parentcontext)
{
	PLiSQL_expanded_collection *coll;
	ArrayType  *arr;
	Datum	   *elems;
	bool	   *nulls;
	int			nelems;
	int32		lb;
	int			i;

	/* An atomically NULL collection: no object at all.  See the header. */
	if (isnull)
		return NULL;

	/* Already one of ours?  Adopt it with its holes intact. */
	if (VARATT_IS_EXTERNAL_EXPANDED(DatumGetPointer(value)))
	{
		ExpandedObjectHeader *eohptr = DatumGetEOHP(value);

		if (eohptr->eoh_methods == &plisql_collection_methods)
		{
			PLiSQL_expanded_collection *src;

			src = (PLiSQL_expanded_collection *) eohptr;
			Assert(src->ec_magic == PLISQL_EC_MAGIC);
			coll_check_same_type(&src->meta, meta);
			return coll_copy(src, parentcontext);
		}
		/* some other expanded object (an expanded array): fall through */
	}

	/*
	 * A flat or expanded array arriving from SQL.  This is the one place a
	 * foreign array value enters the runtime, so it is the one place the
	 * one-dimensional invariant has to be enforced.
	 */
	arr = DatumGetArrayTypeP(value);

	plisql_collection_check_ndim(arr);

	coll = plisql_collection_new(meta, parentcontext);

	if (ARR_NDIM(arr) == 0)
		return coll;			/* initialized but empty */

	lb = ARR_LBOUND(arr)[0];

	/*
	 * A VARRAY is dense and 1-based by definition (see the invariants on
	 * PLiSQL_expanded_collection), and nothing downstream re-derives that
	 * from the entries -- EXTEND and the VARRAY limit check both reason
	 * directly from ec_maxindex as if it were the element count.  A foreign
	 * array with any other lower bound would import as a VARRAY whose
	 * indexes don't start at 1, silently breaking that.  A nested table has
	 * no such invariant, so it keeps whatever origin the incoming array
	 * carries.
	 */
	if (meta->tbl_kind == PLISQL_TBL_VARRAY && lb != 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("VARRAY subscripts must start at 1"),
				 errdetail("The imported array's lower bound is %d.", lb)));

	/*
	 * The array carries its own subscript origin, and an array built outside
	 * the runtime can have one the runtime would never produce.  Validate
	 * the whole resulting index range rather than silently renumbering it.
	 */
	plisql_collection_check_subscript(meta, lb);
	plisql_collection_check_subscript(meta, lb + ARR_DIMS(arr)[0] - 1);

	deconstruct_array(arr, meta->elemtypoid,
					  meta->elmlen, meta->elmbyval, meta->elmalign,
					  &elems, &nulls, &nelems);

	coll_enlarge(coll, nelems);
	for (i = 0; i < nelems; i++)
	{
		coll->entries[i].index = lb + i;
		coll_store_value(coll, i, elems[i], nulls[i]);
	}
	coll->nentries = nelems;
	coll->ec_maxindex = lb + nelems - 1;

	pfree(elems);
	pfree(nulls);

	return coll;
}


/*
 * Datum boundaries
 */

Datum
plisql_collection_get_expanded(PLiSQL_expanded_collection *coll, bool *isnull)
{
	if (coll == NULL)
	{
		*isnull = true;
		return (Datum) 0;
	}

	*isnull = false;
	return EOHPGetRWDatum(&coll->hdr);
}

Datum
plisql_collection_flatten_sql(PLiSQL_expanded_collection *coll, bool *isnull)
{
	if (coll == NULL)
	{
		*isnull = true;
		return (Datum) 0;
	}

	if (coll->fvalue == NULL)
		coll_build_flat(coll);

	*isnull = false;
	return PointerGetDatum(coll->fvalue);
}


/*
 * Operations
 */

Datum
plisql_collection_get(PLiSQL_expanded_collection *coll, int32 idx, bool *isnull)
{
	int			pos;
	bool		found;

	plisql_collection_check_initialized(coll, "coll(i)");
	plisql_collection_check_subscript(&coll->meta, idx);

	pos = coll_search(coll, idx, &found);
	if (!found)
	{
		/*
		 * Oracle distinguishes these: a subscript that was allocated and
		 * then deleted names a hole (NO_DATA_FOUND), while one that was
		 * never allocated is out of bounds (SUBSCRIPT_BEYOND_COUNT).  That
		 * is what ec_maxindex is for -- the surviving entries cannot tell
		 * them apart once the deleted element was the first or the last.
		 */
		if (idx <= coll->ec_maxindex)
			ereport(ERROR,
					(errcode(ERRCODE_NO_DATA_FOUND),
					 errmsg("no data found at collection subscript %d", idx),
					 errdetail("The element at that subscript has been deleted.")));

		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("subscript %d is outside the current collection bounds",
						idx)));
	}

	*isnull = coll->entries[pos].isnull;
	return coll->entries[pos].value;
}

/*
 * Indexed assignment.
 *
 * Deliberately permissive: this creates an entry at any valid subscript,
 * including one beyond LAST and one whose element was DELETEd.  That is the
 * general facility, and an associative array will need it.
 *
 * It is NOT what a nested table or VARRAY permits, and the difference is
 * enforced by the caller rather than here -- see exec_stmt_coll_assign(),
 * which requires the subscript to already exist and distinguishes a deleted
 * one from one that was never allocated.  See "WHERE THE POLICY LIVES" at
 * the top of this file.
 */
void
plisql_collection_set(PLiSQL_expanded_collection *coll, int32 idx,
					  Datum value, bool isnull)
{
	int			pos;
	bool		found;

	plisql_collection_check_initialized(coll, "coll(i) := ...");
	plisql_collection_check_subscript(&coll->meta, idx);

	coll_flush_retired(coll);

	pos = coll_search(coll, idx, &found);

	if (!found)
	{
		if (coll->meta.tbl_kind == PLISQL_TBL_VARRAY &&
			coll->meta.varray_limit >= 0 &&
			coll->nentries + 1 > coll->meta.varray_limit)
			ereport(ERROR,
					(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
					 errmsg("VARRAY limit exceeded: declared %d",
							coll->meta.varray_limit)));
	}

	/*
	 * Copy the element BEFORE touching the entries vector.  datumCopy() can
	 * fail, and doing it after the structural insert would leave behind an
	 * entry at this subscript holding whatever the slot happened to contain
	 * -- so a failed assignment would have created a garbage element that
	 * EXISTS and COUNT would then report.
	 *
	 * What remains below can still fail -- coll_enlarge() calls repalloc()
	 * -- but only before nentries changes, so the collection is either fully
	 * updated or exactly as it was.  (A copy stranded by such a failure is
	 * harmless: it belongs to ec_context and dies with the object.)
	 */
	if (!isnull)
	{
		/* datumCopy() already short-circuits the pass-by-value case */
		MemoryContext oldcxt = MemoryContextSwitchTo(coll->ec_context);

		value = datumCopy(value, coll->meta.elmbyval, coll->meta.elmlen);
		MemoryContextSwitchTo(oldcxt);
	}

	if (!found)
	{
		coll_enlarge(coll, coll->nentries + 1);
		if (pos < coll->nentries)
			memmove(&coll->entries[pos + 1], &coll->entries[pos],
					(coll->nentries - pos) * sizeof(PLiSQL_collection_entry));
		coll->entries[pos].index = idx;
		coll->nentries++;
		if (idx > coll->ec_maxindex)
			coll->ec_maxindex = idx;
	}

	if (found)
		coll_retire_value(coll, &coll->entries[pos]);

	if (isnull)
	{
		coll->entries[pos].value = (Datum) 0;
		coll->entries[pos].isnull = true;
	}
	else
	{
		coll->entries[pos].value = value;
		coll->entries[pos].isnull = false;
	}

	coll_invalidate_flat(coll);
}

bool
plisql_collection_was_deleted(PLiSQL_expanded_collection *coll, int32 idx)
{
	bool		found;

	if (coll == NULL || idx < 1 || idx > coll->ec_maxindex)
		return false;

	(void) coll_search(coll, idx, &found);
	return !found;
}

bool
plisql_collection_exists(PLiSQL_expanded_collection *coll, int32 idx)
{
	bool		found;

	/*
	 * EXISTS never raises -- not on an uninitialized collection, not on a
	 * subscript outside the legal range.  That is precisely what makes it
	 * usable as a guard before touching either.
	 */
	if (coll == NULL)
		return false;

	(void) coll_search(coll, idx, &found);
	return found;
}

void
plisql_collection_delete(PLiSQL_expanded_collection *coll, int32 idx)
{
	int			pos;
	bool		found;

	plisql_collection_check_initialized(coll, "DELETE(i)");

	coll_flush_retired(coll);

	/*
	 * A VARRAY is dense by definition: it has no way to represent the hole
	 * DELETE(i) would leave, and Oracle likewise allows only TRIM and the
	 * argument-less DELETE on one.
	 */
	if (coll->meta.tbl_kind == PLISQL_TBL_VARRAY)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("DELETE of an individual element is not allowed for a VARRAY"),
				 errhint("Use TRIM to remove trailing elements, or DELETE with no argument to clear the collection.")));

	plisql_collection_check_subscript(&coll->meta, idx);

	pos = coll_search(coll, idx, &found);
	if (!found)
		return;					/* deleting an absent index is a no-op */

	coll_retire_value(coll, &coll->entries[pos]);

	if (pos < coll->nentries - 1)
		memmove(&coll->entries[pos], &coll->entries[pos + 1],
				(coll->nentries - pos - 1) * sizeof(PLiSQL_collection_entry));
	coll->nentries--;

	coll_invalidate_flat(coll);
}

void
plisql_collection_delete_all(PLiSQL_expanded_collection *coll)
{
	int			i;

	plisql_collection_check_initialized(coll, "DELETE");

	coll_flush_retired(coll);

	for (i = 0; i < coll->nentries; i++)
		coll_retire_value(coll, &coll->entries[i]);
	coll->nentries = 0;

	/*
	 * Clearing the collection is not the same as punching holes in it: there
	 * is nothing left to be a hole, so every subscript is out of bounds
	 * again rather than NO_DATA_FOUND.
	 */
	coll->ec_maxindex = 0;

	coll_invalidate_flat(coll);
}

int32
plisql_collection_count(PLiSQL_expanded_collection *coll)
{
	plisql_collection_check_initialized(coll, "COUNT");

	return coll->nentries;
}

bool
plisql_collection_first(PLiSQL_expanded_collection *coll, int32 *idx_out)
{
	plisql_collection_check_initialized(coll, "FIRST");

	if (coll->nentries == 0)
		return false;

	*idx_out = coll->entries[0].index;
	return true;
}

bool
plisql_collection_last(PLiSQL_expanded_collection *coll, int32 *idx_out)
{
	plisql_collection_check_initialized(coll, "LAST");

	if (coll->nentries == 0)
		return false;

	*idx_out = coll->entries[coll->nentries - 1].index;
	return true;
}

bool
plisql_collection_next(PLiSQL_expanded_collection *coll, int32 idx,
					   int32 *idx_out)
{
	int			pos;
	bool		found;

	plisql_collection_check_initialized(coll, "NEXT");

	/*
	 * coll_search returns the first entry with index >= idx, so the first
	 * entry strictly greater is that one when idx is absent, and the one
	 * after it when idx is present.  idx itself need not be present.
	 */
	pos = coll_search(coll, idx, &found);
	if (found)
		pos++;

	if (pos >= coll->nentries)
		return false;

	*idx_out = coll->entries[pos].index;
	return true;
}

bool
plisql_collection_prior(PLiSQL_expanded_collection *coll, int32 idx,
						int32 *idx_out)
{
	int			pos;
	bool		found;

	plisql_collection_check_initialized(coll, "PRIOR");

	/* the entry before the first one with index >= idx */
	pos = coll_search(coll, idx, &found);
	if (pos == 0)
		return false;

	*idx_out = coll->entries[pos - 1].index;
	return true;
}

void
plisql_collection_extend(PLiSQL_expanded_collection *coll, int32 n)
{
	int32		nextidx;
	int			i;

	plisql_collection_check_initialized(coll, "EXTEND");

	if (n < 0)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("EXTEND count must not be negative")));

	if (n == 0)
		return;

	if (coll->meta.tbl_kind == PLISQL_TBL_VARRAY &&
		coll->meta.varray_limit >= 0 &&
		n > coll->meta.varray_limit - coll->ec_maxindex)
	{
		/*
		 * ec_maxindex + n can itself overflow int32 (that is exactly what is
		 * being rejected), so compute the reported target in int64 and cap
		 * it for display rather than let the message print a wrapped value.
		 */
		int64		reach = (int64) coll->ec_maxindex + n;

		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("VARRAY limit exceeded: declared %d, EXTEND would reach %d",
						coll->meta.varray_limit,
						(int32) Min(reach, PLISQL_COLL_MAX_INDEX))));
	}

	if (coll->ec_maxindex > PLISQL_COLL_MAX_INDEX - n)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("EXTEND would exceed the maximum collection subscript %d",
						PLISQL_COLL_MAX_INDEX)));

	/* New elements go after the allocated range, including deleted holes. */
	nextidx = (coll->ec_maxindex == 0) ? 1 : coll->ec_maxindex + 1;

	coll_enlarge(coll, coll->nentries + n);
	for (i = 0; i < n; i++)
	{
		coll->entries[coll->nentries + i].index = nextidx + i;
		coll->entries[coll->nentries + i].value = (Datum) 0;
		coll->entries[coll->nentries + i].isnull = true;
	}
	coll->nentries += n;
	{
		/*
		 * The check above guarantees nextidx + n - 1 <= PLISQL_COLL_MAX_INDEX
		 * (== INT32_MAX), but computing it directly in int32 can still
		 * overflow the intermediate "nextidx + n" sum before the final
		 * value is reached; int64 keeps the intermediate step in range.
		 */
		int64		newmaxindex = (int64) nextidx + n - 1;

		if (newmaxindex > coll->ec_maxindex)
			coll->ec_maxindex = (int32) newmaxindex;
	}

	coll_invalidate_flat(coll);
}

void
plisql_collection_trim(PLiSQL_expanded_collection *coll, int32 n)
{
	int32		newmaxindex;
	int			nkeep;

	plisql_collection_check_initialized(coll, "TRIM");

	coll_flush_retired(coll);

	if (n < 0)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("TRIM count must not be negative")));

	if (n > coll->ec_maxindex)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("TRIM count %d exceeds the collection's current size %d",
						n, coll->ec_maxindex)));

	/*
	 * Oracle's TRIM works off the collection's internal size, which counts
	 * every subscript ever allocated -- including ones DELETE(i) has since
	 * punched holes in -- not just the PRESENT entries.  ec_maxindex tracks
	 * that internal size (DELETE(i) deliberately leaves it alone), so TRIM
	 * shrinks it directly and then drops any PRESENT entries that fall in
	 * the trimmed-away range.
	 */
	newmaxindex = coll->ec_maxindex - n;

	nkeep = coll->nentries;
	while (nkeep > 0 && coll->entries[nkeep - 1].index > newmaxindex)
	{
		nkeep--;
		coll_retire_value(coll, &coll->entries[nkeep]);
	}
	coll->nentries = nkeep;

	coll->ec_maxindex = newmaxindex;

	coll_invalidate_flat(coll);
}


/*
 * Render an internal flat collection value for the type's output function.
 *
 * Deterministic and diagnostic by design: it shows the subscripts as well as
 * the values, so the sparse shape is visible and the rendering can never be
 * mistaken for -- or silently become -- the densified elem[] form.  Output
 * from the internal type must not densify; densification is only ever the
 * explicit plisql_collection_flatten_sql() boundary.
 */
char *
plisql_collection_flat_describe(struct varlena *flat)
{
	PLiSQL_coll_flat_header *hdr = (PLiSQL_coll_flat_header *) flat;
	StringInfoData buf;
	int32	   *indexes;
	ArrayType  *values;
	Datum	   *elems;
	bool	   *nulls;
	int			nelems;
	int16		elmlen;
	bool		elmbyval;
	char		elmalign;
	Oid			outfunc;
	bool		isvarlena;
	int			i;

	coll_validate_flat(flat);

	indexes = (int32 *) ((char *) flat + sizeof(PLiSQL_coll_flat_header));
	values = (ArrayType *) ((char *) flat + coll_flat_array_offset(hdr->nentries));

	initStringInfo(&buf);
	appendStringInfo(&buf, "{\"kind\":\"%s\",\"elemtype\":%u,\"limit\":%d,\"count\":%d,\"elements\":[",
					 (hdr->tbl_kind == (int32) PLISQL_TBL_VARRAY) ? "varray" : "table",
					 hdr->elemtypoid, hdr->varray_limit, hdr->nentries);

	if (hdr->nentries > 0)
	{
		get_typlenbyvalalign(hdr->elemtypoid, &elmlen, &elmbyval, &elmalign);
		deconstruct_array(values, hdr->elemtypoid, elmlen, elmbyval, elmalign,
						  &elems, &nulls, &nelems);

		if (nelems != hdr->nentries)
			elog(ERROR, "plisql collection flat value is inconsistent: %d subscripts, %d values",
				 hdr->nentries, nelems);

		getTypeOutputInfo(hdr->elemtypoid, &outfunc, &isvarlena);

		for (i = 0; i < nelems; i++)
		{
			if (i > 0)
				appendStringInfoChar(&buf, ',');
			if (nulls[i])
				appendStringInfo(&buf, "[%d,null]", indexes[i]);
			else
			{
				appendStringInfo(&buf, "[%d,", indexes[i]);
				escape_json(&buf, OidOutputFunctionCall(outfunc, elems[i]));
				appendStringInfoChar(&buf, ']');
			}
		}

		pfree(elems);
		pfree(nulls);
	}

	appendStringInfoString(&buf, "]}");
	return buf.data;
}


/*
 * Borrow the collection behind an internal-type Datum, without copying.
 *
 * For read-only operations (coll(i), EXISTS, COUNT, FIRST, LAST) reached from
 * an expression: the value was produced by the collection-context param-eval
 * bridge and is owned by the expression context, so there is nothing to adopt
 * and no ownership to take.  A flat value is expanded into cxt.
 *
 * Unlike plisql_collection_from_internal(), this takes no expected metadata
 * and performs no type-identity check: the caller is an adapter that only
 * reads.  Anything that keeps or mutates the result must go through
 * from_internal() instead, so the identity check is not skipped.
 */
PLiSQL_expanded_collection *
plisql_collection_ref(Datum value, MemoryContext cxt)
{
	if (VARATT_IS_EXTERNAL_EXPANDED(DatumGetPointer(value)))
	{
		ExpandedObjectHeader *eohptr = DatumGetEOHP(value);
		PLiSQL_expanded_collection *coll;

		if (eohptr->eoh_methods != &plisql_collection_methods)
			elog(ERROR, "expanded datum is not a plisql collection");

		coll = (PLiSQL_expanded_collection *) eohptr;
		Assert(coll->ec_magic == PLISQL_EC_MAGIC);
		return coll;
	}

	/*
	 * A flat internal value: rebuild it.  Its own header is the only
	 * available metadata, so pass it as its own expectation -- the structural
	 * validation in coll_validate_flat() still applies.
	 */
	{
		struct varlena *flat = (struct varlena *) PG_DETOAST_DATUM(value);
		PLiSQL_coll_flat_header *hdr = (PLiSQL_coll_flat_header *) flat;
		PLiSQL_coll_meta meta;

		coll_validate_flat(flat);

		meta.elemtypoid = hdr->elemtypoid;
		meta.elemtypmod = hdr->elemtypmod;
		meta.elemcollation = hdr->elemcollation;
		meta.tbl_kind = (char) hdr->tbl_kind;
		meta.varray_limit = hdr->varray_limit;
		meta.arraytypoid = get_array_type(hdr->elemtypoid);
		get_typlenbyvalalign(hdr->elemtypoid, &meta.elmlen, &meta.elmbyval,
							 &meta.elmalign);

		return coll_from_internal_flat(flat, &meta, cxt);
	}
}

/*
 * Read-only expanded pointer.
 *
 * The collection-context param-eval bridge hands expressions a R/O pointer:
 * an expression evaluation must not be able to mutate a collection, and a R/W
 * pointer is exactly the authorization to do so in place.
 */
Datum
plisql_collection_get_expanded_ro(PLiSQL_expanded_collection *coll, bool *isnull)
{
	if (coll == NULL)
	{
		*isnull = true;
		return (Datum) 0;
	}

	*isnull = false;
	return EOHPGetRODatum(&coll->hdr);
}


/*
 * Public copy, for an adapter handed a read-only collection it must mutate.
 * Read-only is not advisory: the caller copies, then mutates the copy.
 */
PLiSQL_expanded_collection *
plisql_collection_copy(PLiSQL_expanded_collection *src, MemoryContext cxt)
{
	return coll_copy(src, cxt);
}

void
plisql_collection_free(PLiSQL_expanded_collection *coll)
{
	if (coll == NULL)
		return;

	Assert(coll->ec_magic == PLISQL_EC_MAGIC);

	/*
	 * Deleting the object's context is the whole of it.  Do not try to
	 * DeleteExpandedObject() instead: that is for objects reached through a
	 * read-write Datum, and a collection owned by a PLiSQL variable is
	 * reached through the C pointer.
	 */
	MemoryContextDelete(coll->ec_context);
}
