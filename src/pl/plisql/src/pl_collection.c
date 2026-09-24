/*-------------------------------------------------------------------------
 *
 * pl_collection.c
 *		Backing functions for Oracle collection ("TYPE ... IS TABLE OF /
 *		VARRAY") method and constructor syntax.
 *
 * Phase 1 represents a declared collection as an ordinary Postgres array
 * value.  Phase 2 adds Oracle's own collection syntax -- coll(i) indexing,
 * coll.EXISTS(i)/.COUNT/.FIRST/.LAST, the type-name(...) constructor, and
 * the mutating .EXTEND/.TRIM/.DELETE pseudo-procedures -- on top of that
 * representation.  Every one of those forms is implemented as one of the
 * small polymorphic functions in this file; pl_subproc_function.c's parser
 * hook, pl_comp.c's ColumnRef hook and pl_gram.y's statement compilation
 * redirect Oracle collection syntax to them (see
 * try_resolve_collection_call(), build_coll_count_expr()/
 * build_coll_bound_expr(), and the collection-method statement handling in
 * stmt_execsql, respectively).  Even the read-only, argument-less forms
 * (.COUNT/.FIRST/.LAST), which Postgres's own array_length()/array_lower()/
 * array_upper() could otherwise answer, go through functions here so that
 * the one-dimensionality check below applies to them too.
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_collection.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "utils/array.h"
#include "utils/lsyscache.h"

#include "plisql.h"

/*
 * Bridge from the compiler's collection declaration to the runtime's
 * metadata.  This lives here, on the compiler side of the boundary, because
 * the runtime deliberately knows nothing about PLiSQL_tbl_type -- see the
 * note at the top of pl_collection.h.
 */
void
plisql_coll_meta_from_tbltype(const PLiSQL_tbl_type *tbltype,
							  PLiSQL_coll_meta *meta)
{
	meta->elemtypoid = tbltype->elemtypoid;
	meta->elemtypmod = tbltype->elemtypmod;
	meta->elemcollation = tbltype->elemcollation;
	meta->tbl_kind = tbltype->tbl_kind;
	meta->varray_limit = (tbltype->tbl_kind == PLISQL_TBL_VARRAY) ?
		tbltype->varray_limit : -1;
	meta->arraytypoid = tbltype->arraytypoid;
	get_typlenbyvalalign(tbltype->elemtypoid, &meta->elmlen, &meta->elmbyval,
						 &meta->elmalign);
}


/*
 * Turn a collection variable's value into an expanded collection owned by
 * mc, and hand back the R/W expanded Datum to store in the variable.
 *
 * This is what makes a declared collection variable hold sparse state
 * between statements, instead of the expanded *array* that plisql gives
 * ordinary array variables.  A NULL value stays NULL: an atomically NULL
 * collection is not the same as an initialized empty one, and inventing an
 * object here would erase that distinction at the first assignment.
 */
Datum
plisql_coll_expand_datum(Datum value, bool isnull,
						 const PLiSQL_tbl_type *tbltype,
						 MemoryContext mc, bool *resnull)
{
	PLiSQL_coll_meta meta;
	PLiSQL_expanded_collection *coll;

	if (isnull)
	{
		*resnull = true;
		return (Datum) 0;
	}

	plisql_coll_meta_from_tbltype(tbltype, &meta);
	coll = plisql_collection_from_datum(value, false, &meta, mc);

	return plisql_collection_get_expanded(coll, resnull);
}

/*
 * plisql_coll_construct
 *		Backs the "type_name(...)" collection constructor.  Postgres's own
 *		VARIADIC anyarray parameter-passing convention already packs the
 *		call's scalar arguments into an array of the matching element type
 *		before this function ever runs, so there is nothing left to do.
 */
PG_FUNCTION_INFO_V1(plisql_coll_construct);

Datum
plisql_coll_construct(PG_FUNCTION_ARGS)
{
	ArrayType  *arr;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	arr = PG_GETARG_ARRAYTYPE_P(0);
	plisql_collection_check_ndim(arr);		/* cannot fail via variadic
											 * packing, but this is also
											 * reachable by a direct SQL
											 * call */
	PG_RETURN_ARRAYTYPE_P(arr);
}

/*
 * plisql_coll_construct_empty
 *		Backs the zero-argument form of the constructor, e.g.
 *		"v tab_t := tab_t();".  Postgres cannot resolve a purely-variadic
 *		ANYELEMENT parameter (plisql_coll_construct above) from zero
 *		actual arguments -- there is nothing to infer the element type
 *		from -- so this takes a single, non-variadic ANYELEMENT argument
 *		used only to anchor the type (the caller passes a typed NULL built
 *		from the collection's compile-time-known element type; the actual
 *		argument value is ignored).
 */
PG_FUNCTION_INFO_V1(plisql_coll_construct_empty);

Datum
plisql_coll_construct_empty(PG_FUNCTION_ARGS)
{
	Oid			elemtype = get_fn_expr_argtype(fcinfo->flinfo, 0);

	if (!OidIsValid(elemtype))
		elog(ERROR, "could not determine collection element type");
	PG_RETURN_ARRAYTYPE_P(construct_empty_array(elemtype));
}


/*
 * I/O functions for the internal collection type (pg_type "plisql_collection").
 *
 * The type is an INTERNAL implementation type: no collection declaration
 * resolves to it as a SQL argument or return type, no public overload
 * resolution uses it, and no ordinary SQL expression can obtain one.  It
 * exists so that the in-memory sparse collection is not typed as an array --
 * see "THE IN-MEMORY COLLECTION IS NOT AN ARRAY TYPE" in pl_collection.h for
 * why that distinction is a safety property and not a stylistic one.
 */

/*
 * There is deliberately no textual input syntax.  The supported way in is
 * plisql_collection_from_datum(), which imports the SQL-visible elem[] form;
 * the internal encoding is produced only by this implementation.  Compare
 * pg_node_tree, which rejects input the same way and for the same reason.
 */
PG_FUNCTION_INFO_V1(plisql_collection_in);

Datum
plisql_collection_in(PG_FUNCTION_ARGS)
{
	ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			 errmsg("cannot accept a value of type plisql_collection"),
			 errdetail("plisql_collection is an internal type with no textual input syntax; collections enter from their elem[] form.")));

	PG_RETURN_VOID();			/* keep compiler quiet */
}

/*
 * Output is diagnostic, and deliberately not the densified elem[] rendering:
 * showing subscripts alongside values keeps the sparse shape visible and
 * prevents this from quietly becoming a second, lossy densification path.
 */
PG_FUNCTION_INFO_V1(plisql_collection_out);

Datum
plisql_collection_out(PG_FUNCTION_ARGS)
{
	struct varlena *flat = PG_GETARG_VARLENA_PP(0);

	PG_RETURN_CSTRING(plisql_collection_flat_describe(flat));
}


/* -------------------------------------------------------------------------
 * Internal-type adapters  (MIGRATION SHIMS -- NOT PUBLIC API)
 *
 * These take the internal pg_catalog.plisql_collection type and dispatch
 * straight to the collection runtime.  They exist only because expression-
 * position collection syntax is evaluated as SQL, so something SQL-callable
 * has to stand between the expression and the runtime.
 *
 * They are NOT an API and must not be treated as one:
 *
 *	- every compiler-generated call is schema-qualified to pg_catalog, so
 *	  resolution never depends on search_path;
 *	- their argument type is plisql_collection, never anyarray, so an
 *	  ordinary SQL expression cannot produce a value to call them with --
 *	  there is no input function and no cast that yields one;
 *	- they are to be REMOVED once direct runtime nodes replace the
 *	  compiler-generated SQL expression path for collection operations.
 *
 * Only plisql_coll_get_internal needs a third argument: with the collection
 * typed plisql_collection there is no polymorphic source for the element
 * return type, so the compiler passes a typed NULL of the declared element
 * type purely to anchor it -- the same device plisql_coll_construct_empty
 * already uses, and for the same reason.
 * -------------------------------------------------------------------------
 */

/*
 * Adopt the collection behind SQL argument 0 of one of the internal-type
 * adapters below, or NULL for a SQL NULL (an atomically NULL collection; the
 * runtime operation itself defines the answer for that, per pl_collection.h).
 */
static PLiSQL_expanded_collection *
coll_arg0(FunctionCallInfo fcinfo)
{
	return PG_ARGISNULL(0) ? NULL :
		plisql_collection_ref(PG_GETARG_DATUM(0), CurrentMemoryContext);
}

PG_FUNCTION_INFO_V1(plisql_coll_get_internal);

Datum
plisql_coll_get_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;
	Datum		result;
	bool		isnull;

	if (PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("collection subscript must not be null")));

	coll = coll_arg0(fcinfo);

	result = plisql_collection_get(coll, PG_GETARG_INT32(1), &isnull);
	if (isnull)
		PG_RETURN_NULL();
	PG_RETURN_DATUM(result);
}

PG_FUNCTION_INFO_V1(plisql_coll_exists_internal);

Datum
plisql_coll_exists_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;

	if (PG_ARGISNULL(1))
		PG_RETURN_NULL();

	coll = coll_arg0(fcinfo);

	PG_RETURN_BOOL(plisql_collection_exists(coll, PG_GETARG_INT32(1)));
}

/*
 * NEXT(i) / PRIOR(i): the nearest present subscript after / before i.
 *
 * Oracle returns NULL at the ends of the collection rather than raising, so
 * the runtime's "no such index" answer becomes SQL NULL here.  Neither
 * requires i itself to be present -- that is what makes them usable to walk
 * across holes left by DELETE(i).
 */
PG_FUNCTION_INFO_V1(plisql_coll_next_internal);
Datum
plisql_coll_next_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;
	int32		idx_out;

	/*
	 * Uninitialized takes precedence over a null subscript, matching
	 * coll(i)/plisql_coll_get_internal: "t.NEXT(NULL)" on an uninitialized
	 * t must raise, not quietly answer NULL.
	 */
	coll = coll_arg0(fcinfo);
	plisql_collection_check_initialized(coll, "NEXT");

	if (PG_ARGISNULL(1))
		PG_RETURN_NULL();

	if (!plisql_collection_next(coll, PG_GETARG_INT32(1), &idx_out))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx_out);
}

PG_FUNCTION_INFO_V1(plisql_coll_prior_internal);
Datum
plisql_coll_prior_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;
	int32		idx_out;

	/* See plisql_coll_next_internal(): uninitialized takes precedence. */
	coll = coll_arg0(fcinfo);
	plisql_collection_check_initialized(coll, "PRIOR");

	if (PG_ARGISNULL(1))
		PG_RETURN_NULL();

	if (!plisql_collection_prior(coll, PG_GETARG_INT32(1), &idx_out))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx_out);
}

PG_FUNCTION_INFO_V1(plisql_coll_count_internal);

Datum
plisql_coll_count_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;

	coll = coll_arg0(fcinfo);

	PG_RETURN_INT32(plisql_collection_count(coll));
}

PG_FUNCTION_INFO_V1(plisql_coll_first_internal);

Datum
plisql_coll_first_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;
	int32		idx;

	coll = coll_arg0(fcinfo);

	if (!plisql_collection_first(coll, &idx))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx);
}

PG_FUNCTION_INFO_V1(plisql_coll_last_internal);

Datum
plisql_coll_last_internal(PG_FUNCTION_ARGS)
{
	PLiSQL_expanded_collection *coll;
	int32		idx;

	coll = coll_arg0(fcinfo);

	if (!plisql_collection_last(coll, &idx))
		PG_RETURN_NULL();
	PG_RETURN_INT32(idx);
}


