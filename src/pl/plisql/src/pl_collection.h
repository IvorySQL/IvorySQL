/*-------------------------------------------------------------------------
 *
 * pl_collection.h
 *		Runtime interface for Oracle collections ("TYPE ... IS TABLE OF /
 *		VARRAY").
 *
 * This is the boundary that Oracle collection semantics live behind.  The
 * compiler (pl_gram.y, pl_comp.c, pl_subproc_function.c) recognizes
 * collection syntax and emits calls to the operations declared here; it
 * does not know how a collection is stored, and it no longer reconstructs
 * SQL text to get at it.  Storage may therefore change -- dense array
 * adapter today, sparse entry vector next, something else later -- without
 * touching parser contracts or every method implementation.
 *
 * WHY SPARSE
 *
 * An Oracle nested table is a sparse collection: DELETE(i) removes index i
 * and leaves a hole, EXISTS(i) reports whether an index is present, and
 * NEXT/PRIOR walk the present indexes across holes.  A dense Postgres array
 * cannot represent that.  The earlier array-backed implementation therefore
 * had to reject DELETE of any but the last element -- not a missing feature
 * but a wrong answer to the defining operation of a nested table, which is
 * why the representation is what changed.
 *
 * A VARRAY stays dense and bounded by declaration; it is modelled here as a
 * nested table whose present indexes happen to be contiguous, with
 * varray_limit enforced by the EXTEND and set paths.  Associative arrays
 * (INDEX BY) are deliberately NOT modelled here: string keys need a
 * different key representation and different initialization/iteration rules.
 * They should share operation *concepts* with this interface, not
 * necessarily its storage, and are expected to arrive as a sibling
 * implementation behind a common dispatch rather than as extra cases bolted
 * into this one.
 *
 * TWO BOUNDARIES, NOT ONE
 *
 * Sparse state is NOT merely a runtime-local detail that may be discarded
 * whenever a value leaves a variable.  There are two distinct boundaries and
 * they behave differently:
 *
 *	1. plisql-to-plisql transfer -- assignment from one collection variable
 *	   to another, arguments to a nested plisql routine, RETURN from one
 *	   plisql routine to another, package variables and cached function
 *	   state.  These MUST preserve holes.  A DELETE(2) followed by passing
 *	   the collection to another plisql function must not silently densify
 *	   it.  Use plisql_collection_get_expanded().
 *
 *	2. The SQL datum boundary -- assignment to a column, an argument to an
 *	   ordinary SQL function, a value crossing into generic executor code.
 *	   Here the value is flattened: present elements are written in ascending
 *	   index order into a contiguous 1-based array and holes are dropped.
 *	   Use plisql_collection_flatten_sql().
 *
 * Densification at (2) is the documented compatibility behavior, not a
 * limitation: Oracle renumbers a nested table's subscripts densely when it
 * is stored to and read back from a database column.  CONFIRM THIS AGAINST
 * THE COMPATIBILITY TARGET before it becomes load-bearing.
 *
 * THE IN-MEMORY COLLECTION IS NOT AN ARRAY TYPE
 *
 * An earlier design kept elem[] as the type of the in-memory value too, on
 * the theory that any generic consumer would simply flatten it and so degrade
 * to a dense array -- lossy but never wrong.  That theory is FALSE and the
 * mistake is worth recording, because the code reads plausibly either way.
 *
 * PostgreSQL's array code reaches an expanded datum on the strength of its
 * DECLARED TYPE alone: array_get_element_expanded() casts straight to
 * ExpandedArrayHeader and only asserts ea_magic (arrayfuncs.c), never
 * consulting eoh_methods.  A collection typed elem[] therefore gets read as
 * an expanded array by something as ordinary as "v[i]" -- an abort in a
 * cassert build, and silent garbage in a production one.  Flattening never
 * enters into it, because a consumer holding an expanded pointer does not
 * flatten at all.
 *
 * Hence the in-memory collection carries its own dedicated, non-array type,
 * and the array machinery cannot name it.  Which makes flatten_into() the
 * INTERNAL form rather than the SQL one: PostgreSQL may flatten an expanded
 * datum whenever it wants a flat one, and such an implicit flattening must
 * not change the value, so the internal flat form is self-describing and
 * PRESERVES HOLES.  Only the explicit plisql_collection_flatten_sql() --
 * boundary (2) above -- densifies.
 *
 * THE COMPILER CONTRACT
 *
 * A collection datum must never be exposed as an elem[] Param.  Ordinary SQL
 * references to a collection variable (RETURN v, passing v to a SQL function,
 * column assignment, ordinary operators) receive a flattened elem[]
 * conversion.  Collection-aware operations -- coll(i), COUNT, EXISTS, NEXT,
 * PRIOR, mutation, and plisql collection-to-collection assignment -- take the
 * internal collection type and must not pass through ordinary array
 * expression machinery or ordinary SQL function resolution.
 *
 * "Internal" means specifically: no collection declaration resolves to it as
 * its SQL argument or return type; no public overload resolution uses it; no
 * ordinary SQL expression can obtain it accidentally; only compiler-generated
 * paths use it.  Its input function rejects direct SQL input -- the supported
 * way in is plisql_collection_from_datum(), which imports the elem[] form.
 *
 * ATOMICALLY NULL VERSUS EMPTY
 *
 * Oracle distinguishes an atomically NULL collection ("v tab_t;", never
 * initialized) from an initialized but empty one ("v tab_t := tab_t();").
 * They are not the same value and most methods treat them differently.
 *
 * This interface represents that distinction by EXISTENCE OF THE OBJECT: a
 * PLiSQL_expanded_collection always denotes an INITIALIZED collection, and
 * an atomically NULL collection is a NULL PLiSQL_expanded_collection *.
 * Every operation below therefore accepts a NULL coll and defines its own
 * answer for that case, so the behavior stays defined in one place per
 * operation rather than being re-derived at each call site:
 *
 *		get, set				ERRCODE for "reference to uninitialized
 *								collection" (Oracle ORA-06531)
 *		delete, delete_all		likewise
 *		count					likewise
 *		first, last, next, prior	likewise
 *		extend, trim			likewise
 *		exists					FALSE, never an error
 *
 * EXISTS is the documented exception in Oracle: it is defined to be safe on
 * an atomically null collection precisely so it can be used to probe before
 * touching one.
 *
 * These were deliberate tightenings against the earlier array-backed
 * implementation, which reported COUNT as 0 for a NULL collection and raised
 * a subscript error rather than an uninitialized-collection error for
 * coll(i).  The Oracle answers above are the ones that stand.
 *
 * VALID SUBSCRIPTS
 *
 * A nested-table subscript is an integer in 1 .. 2147483647; a VARRAY
 * subscript is in 1 .. varray_limit.  Zero and negative subscripts are not
 * valid for either.  get, set and delete raise on an invalid subscript;
 * exists returns FALSE, because Oracle's EXISTS is defined never to raise
 * (that is what makes it usable as a guard).  Associative arrays will need a
 * different key domain, which is why the check lives in the runtime behind
 * this interface rather than in the compiler.
 *
 * Portions Copyright (c) 2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_collection.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PL_COLLECTION_H
#define PL_COLLECTION_H

/*
 * This header deliberately does NOT include plisql.h.  The runtime behind
 * this interface must not depend on the compiler's data structures -- that
 * is what lets the runtime be compiled and tested standalone, and what keeps
 * the boundary from leaking back the other way.  Only expandeddatum.h (and
 * what postgres.h already provides) is needed here; PLiSQL_tbl_kind is
 * therefore defined below rather than in plisql.h, which includes this file.
 */
#include "utils/array.h"
#include "utils/expandeddatum.h"

/* Highest legal nested-table subscript, per Oracle */
#define PLISQL_COLL_MAX_INDEX	2147483647

/*
 * Kind of an Oracle collection type declaration.
 */
typedef enum PLiSQL_tbl_kind
{
	PLISQL_TBL_NESTED_TABLE = 'n',	/* TYPE t IS TABLE OF elem (unbounded) */
	PLISQL_TBL_VARRAY = 'v'		/* TYPE t IS VARRAY(n) OF elem (bounded) */
}			PLiSQL_tbl_kind;

/*
 * Static, per-declaration properties of a collection type, copied out of the
 * PLiSQL_tbl_type the variable was declared from so the runtime never has to
 * reach back into compiler data structures.
 *
 * The first five fields are also the type identity checked when adopting an
 * already-expanded collection; see plisql_collection_from_datum().
 */
typedef struct PLiSQL_coll_meta
{
	Oid			elemtypoid;		/* element type OID */
	int32		elemtypmod;
	Oid			elemcollation;
	char		tbl_kind;		/* a PLiSQL_tbl_kind value */
	int32		varray_limit;	/* declared max size for VARRAY, else -1 */

	Oid			arraytypoid;	/* elem[]: the flat/SQL-visible type */
	/* element storage properties, from get_typlenbyvalalign() */
	int16		elmlen;
	bool		elmbyval;
	char		elmalign;
}			PLiSQL_coll_meta;

/*
 * One present element: its subscript, value and null flag kept together.
 *
 * Deliberately one array of entries rather than three parallel arrays, so
 * that the memmove() done by an insertion or a middle DELETE moves index,
 * value and null flag atomically and the three can never drift out of
 * alignment.  The cost is padding (24 bytes per entry on 64-bit against 13
 * packed) and a wider stride for the binary searches below; that is accepted
 * knowingly, because at the collection sizes nested tables actually reach
 * the search advantage of a compact index vector is theoretical while the
 * misalignment hazard would be permanent.
 */
typedef struct PLiSQL_collection_entry
{
	int32		index;
	Datum		value;
	bool		isnull;
}			PLiSQL_collection_entry;

/*
 * An expanded collection value.  Its existence means "initialized"; see
 * "ATOMICALLY NULL VERSUS EMPTY" above.
 *
 * entries[0 .. nentries-1] is sorted strictly ascending by .index.  Sorted
 * order is what gives:
 *
 *		FIRST / LAST				O(1)
 *		EXISTS						O(log n)	binary search
 *		NEXT / PRIOR				O(log n)	binary search
 *		EXTEND						amortized O(1)	append plus vector growth
 *		set at an existing index	O(log n)
 *		set at a new index			O(n)		insertion memmove
 *		DELETE of a middle index	O(n)		compaction memmove
 *		DELETE of the last index	O(1)
 *
 * A vector rather than a tree is a deliberate starting choice: the whole
 * object lives in its own memory context, so one contiguous allocation beats
 * per-node allocation at these sizes.  If mutation volume ever justifies a
 * tree, it replaces the entries/nentries/maxentries fields and nothing above
 * this header changes -- which is the reason this interface exists.
 *
 * ELEMENT OWNERSHIP
 *
 * The object owns its elements.  A pass-by-reference element Datum handed to
 * plisql_collection_set() may point into a shorter-lived context, into a
 * detoasted temporary, or into another expanded object, so it MUST be copied
 * into ec_context according to meta.elmlen / meta.elmbyval / meta.elmalign
 * (datumCopy() with those parameters) rather than retained by pointer.  The
 * same applies when importing from a flat array: deconstruct_array() hands
 * back pointers into the source varlena, which the caller may free.
 * Pass-by-value elements are stored directly.  Nothing in ec_context may
 * point outside it, so that deleting the object is a single context delete
 * and transferring it is a single context reparent.
 *
 * Invariants:
 *	- entries[] is strictly ascending by .index
 *	- every index is a valid subscript for meta.tbl_kind
 *	- for a VARRAY, indexes are contiguous and 1-based, nentries <= limit
 *	- every pass-by-reference value lives in ec_context
 */
typedef struct PLiSQL_expanded_collection
{
	ExpandedObjectHeader hdr;
	int			ec_magic;		/* PLISQL_EC_MAGIC; identifies the
								 * implementation, NOT the collection type --
								 * see from_datum() on why that is not
								 * sufficient for adoption */

	PLiSQL_coll_meta meta;

	PLiSQL_collection_entry *entries;	/* ascending by .index */
	int			nentries;		/* number of present elements */
	int			maxentries;		/* allocated length of entries[] */

	/*
	 * Highest subscript ever allocated in this collection and not since
	 * removed from the end; 0 when nothing has been.
	 *
	 * This exists solely so that reading a missing subscript can tell "was
	 * here and was DELETEd" (NO_DATA_FOUND) from "never was here"
	 * (subscript out of bounds).  The surviving entries cannot answer that:
	 * once the first or last element is the one deleted, the deleted
	 * subscript falls outside the range of what remains and is
	 * indistinguishable from one that was never allocated.
	 *
	 * DELETE(i) deliberately does NOT lower it -- that is the hole it is
	 * supposed to leave.  TRIM does, because Oracle makes trimmed
	 * subscripts genuinely beyond the collection again, and so does
	 * DELETE with no argument, which clears the collection outright.
	 */
	int32		ec_maxindex;

	MemoryContext ec_context;	/* all of the above lives here */

	/*
	 * Pass-by-reference values a mutation has discarded (overwritten by
	 * coll(i) := ..., or dropped by DELETE(i)/DELETE/TRIM), pending an
	 * actual pfree().
	 *
	 * plisql_collection_get() hands out the entry's raw Datum -- borrowed,
	 * not copied -- so freeing a discarded value immediately could pull it
	 * out from under a get() an earlier step of the same expression already
	 * returned.  Freeing is deferred to the START of the NEXT mutating call
	 * instead: the usual C API contract of "valid until the next call that
	 * could invalidate it."  Opaque here (a private list type in
	 * pl_collection_runtime.c) because nothing outside coll_retire_value()
	 * and coll_flush_retired() needs to know its shape.
	 */
	void	   *ec_retired;

	/*
	 * Two different flattenings, cached lazily and both invalidated by any
	 * mutation.  They are not interchangeable:
	 *
	 * fvalue is the DENSIFIED elem[] handed across the SQL boundary by
	 * plisql_collection_flatten_sql(); holes are dropped and the survivors
	 * renumbered from 1.
	 *
	 * fflat is the INTERNAL flat form produced by the expanded-object
	 * flatten_into() method, which PostgreSQL may invoke at any time it
	 * needs a flat datum of the collection type.  It is self-describing and
	 * PRESERVES HOLES, because an implicit flattening must not silently
	 * change the value -- unlike the SQL boundary, which is an explicit,
	 * documented densification.
	 */
	ArrayType  *fvalue;
	struct varlena *fflat;
}			PLiSQL_expanded_collection;

/*
 * Internal flat form: a self-describing header, then the present subscripts,
 * then the present values as a dense 1-based array.  Holes survive because
 * the subscript vector is carried explicitly.
 *
 * Laid out as:
 *		PLiSQL_coll_flat_header
 *		int32 index[nentries]
 *		(MAXALIGN padding)
 *		ArrayType of the nentries present values, dense and 1-based
 */
typedef struct PLiSQL_coll_flat_header
{
	int32		vl_len_;		/* varlena header (do not touch directly) */
	int32		version;		/* PLISQL_COLL_FLAT_VERSION */
	Oid			elemtypoid;
	int32		elemtypmod;
	Oid			elemcollation;
	int32		varray_limit;
	int32		tbl_kind;		/* a PLiSQL_tbl_kind value, widened for
								 * alignment */
	int32		nentries;
	int32		maxindex;		/* see PLiSQL_expanded_collection.ec_maxindex;
								 * carried explicitly because it is not
								 * derivable from the present subscripts once
								 * the highest one has been deleted */
}			PLiSQL_coll_flat_header;

#define PLISQL_COLL_FLAT_VERSION	2

#define PLISQL_EC_MAGIC 0x7C011EC7

/*
 * EOH method table; flatten_into() produces the internal flat form, which
 * PRESERVES HOLES -- densification only ever happens at the explicit
 * plisql_collection_flatten_sql() boundary, never implicitly here.
 */
extern const ExpandedObjectMethods plisql_collection_methods;

/*
 * Is this Datum an expanded collection?
 *
 * The centralized form of the check every caller needs, so that "is this the
 * internal representation" is asked in one way rather than several.  Note it
 * tests eoh_methods, NOT merely VARATT_IS_EXTERNAL_EXPANDED -- the whole
 * reason collections need their own type is that PostgreSQL's array code
 * omits exactly this check (see "THE IN-MEMORY COLLECTION IS NOT AN ARRAY
 * TYPE" above).
 *
 * Callers must have established the Datum is non-NULL first.
 */
static inline bool
DatumIsExpandedCollection(Datum d)
{
	void	   *p = DatumGetPointer(d);

	if (p == NULL || !VARATT_IS_EXTERNAL_EXPANDED(p))
		return false;
	return DatumGetEOHP(d)->eoh_methods == &plisql_collection_methods;
}

/*
 * Construction and import.
 */

/*
 * Validate and render an internal flat collection value.  Deterministic and
 * diagnostic: it shows subscripts alongside values, so the sparse shape is
 * visible and the rendering can never be confused with the densified elem[]
 * form.  Used by the internal type's output function, which must not densify.
 */
extern char *plisql_collection_flat_describe(struct varlena *flat);

/*
 * Import a value of the INTERNAL collection type (expanded or flat),
 * preserving holes.  Distinct from plisql_collection_from_datum() below,
 * which imports the SQL-visible elem[] form: the caller always knows which
 * declared type it holds, and conflating them would decode garbage rather
 * than raise.
 */
extern PLiSQL_expanded_collection *plisql_collection_from_internal(Datum value,
																   bool isnull,
																   const PLiSQL_coll_meta *meta,
																   MemoryContext parentcontext);

extern PLiSQL_expanded_collection *plisql_collection_new(const PLiSQL_coll_meta *meta,
														 MemoryContext parentcontext);

/*
 * Bring a Datum into the runtime.
 *
 * isnull says whether the source datum is SQL NULL, which is how an
 * atomically NULL collection arrives; this returns NULL in that case, and
 * callers pass that NULL straight to the operations below rather than
 * inventing an empty collection.  That is the whole reason isnull is a
 * parameter: without it an uninitialized collection and an initialized empty
 * one would both arrive as nentries == 0 and every method that distinguishes
 * them would be wrong.
 *
 * If value is already an expanded collection, it is adopted WITH its holes
 * intact.  Adoption is guarded by more than ec_magic, which identifies only
 * the implementation: elemtypoid, elemtypmod, elemcollation, tbl_kind and
 * varray_limit must all match meta, or this raises.  Otherwise a collection
 * expanded from NUMBER[] could be adopted where VARCHAR[] or a bounded
 * VARRAY is expected.  A mismatch is an internal error -- the compiler
 * should never emit such a transfer -- not a user-facing one.
 *
 * If value is a flat or expanded ARRAY arriving from SQL, it is imported
 * densely.  This is the single point at which a foreign array value enters
 * the runtime, and therefore the one place the one-dimensional invariant has
 * to be enforced: there is no such thing as a multidimensional expanded
 * collection.
 */
extern PLiSQL_expanded_collection *plisql_collection_from_datum(Datum value,
																bool isnull,
																const PLiSQL_coll_meta *meta,
																MemoryContext parentcontext);

/*
 * Datum boundaries.  See "TWO BOUNDARIES, NOT ONE" above -- picking the
 * wrong one of these is how sparse state gets silently lost.
 */

/*
 * plisql-to-plisql transfer: the expanded object as a Datum, preserving the
 * sparse representation.  For variable-to-variable assignment, nested plisql
 * call arguments, RETURN into a plisql caller, and package/cached state.
 *
 * OWNERSHIP: this returns a BORROWED read-write pointer (EOHPGetRWDatum).
 * It does NOT reparent the object, and the returned Datum is valid only as
 * long as coll's context is.  To move ownership, the caller applies the
 * standard Postgres API to the result:
 *
 *		TransferExpandedObject(plisql_collection_get_expanded(coll, &isnull),
 *							   new_parent);
 *
 * Sets *isnull when coll is NULL (an atomically NULL collection), in which
 * case the returned Datum is 0 and must not be dereferenced.
 */
extern Datum plisql_collection_get_expanded(PLiSQL_expanded_collection *coll,
											bool *isnull);

/*
 * SQL datum boundary: densify to a flat, contiguous, 1-based elem[] and hand
 * back that varlena.  Holes are dropped and the remaining elements
 * renumbered, per the documented compatibility behavior.  Sets *isnull when
 * coll is NULL; an initialized but empty collection flattens to an empty
 * array, which is exactly the distinction this preserves.
 */
extern Datum plisql_collection_flatten_sql(PLiSQL_expanded_collection *coll,
										   bool *isnull);

/*
 * Read-only expanded pointer, for handing a collection to an expression that
 * must not be able to mutate it in place.
 */
extern Datum plisql_collection_get_expanded_ro(PLiSQL_expanded_collection *coll,
											   bool *isnull);

/*
 * Borrow the collection behind an internal-type Datum without copying, for
 * read-only adapters.  Performs no type-identity check -- anything that keeps
 * or mutates the result must use plisql_collection_from_internal() instead.
 */
extern PLiSQL_expanded_collection *plisql_collection_ref(Datum value,
														 MemoryContext cxt);

/*
 * Copy a collection, for an adapter that was handed a read-only one and must
 * mutate.  Read-only is not advisory.
 */
extern PLiSQL_expanded_collection *plisql_collection_copy(PLiSQL_expanded_collection *src,
														  MemoryContext cxt);

/*
 * Release a collection and everything it owns.
 *
 * Ownership here is context ownership: the entries vector, every
 * pass-by-reference element, and any cached flat value all live in the
 * object's own context, so one delete releases the lot.  That includes the
 * Datum handed back by plisql_collection_flatten_sql(), which is why a
 * caller holding one must be done with it before calling this.
 *
 * Accepts NULL, meaning an atomically NULL collection, so callers need not
 * special-case it.
 */
extern void plisql_collection_free(PLiSQL_expanded_collection *coll);

/*
 * Validators, exposed so a caller that layers an additional rule on top of
 * an operation can still raise the operation's own errors first, in Oracle's
 * order.  exec_stmt_coll_assign() uses them for exactly that: an
 * uninitialized collection and an out-of-range subscript have to be reported
 * as such before "subscript beyond count" is even considered.
 */
extern void plisql_collection_check_initialized(PLiSQL_expanded_collection *coll,
												const char *method);
extern void plisql_collection_check_subscript(const PLiSQL_coll_meta *meta,
											  int32 idx);

/*
 * Raise unless arr is one-dimensional (an empty, zero-dimensional array
 * passes).  A collection value is always one-dimensional; see the comment on
 * this check's only implementation, in pl_collection_runtime.c, for why.
 * Shared by every entry point a foreign array can arrive through --
 * plisql_collection_from_datum() and the SQL-callable constructors in
 * pl_collection.c -- so the error text and enforcement cannot drift apart.
 */
extern void plisql_collection_check_ndim(ArrayType *arr);

/*
 * True when idx names an element that WAS allocated and has since been
 * deleted, as opposed to one that was never allocated at all.  Both are
 * absent from the entries vector; only the high-water mark separates them.
 *
 * The rule lives here so that reads (NO_DATA_FOUND versus out of bounds)
 * and writes (a deleted slot cannot be reused, versus EXTEND would help)
 * cannot drift apart.
 */
extern bool plisql_collection_was_deleted(PLiSQL_expanded_collection *coll,
										  int32 idx);

/*
 * Operations.
 *
 * These are the whole Oracle-visible surface.  Each raises the Oracle-
 * appropriate error itself rather than returning a status the caller has to
 * translate, so that error text and SQLSTATE are defined in exactly one
 * place per operation.  Each accepts a NULL coll, meaning an atomically NULL
 * collection, and answers per the table at the top of this file.
 *
 * The idx_out-style operations return false for "no such index" instead of
 * raising, because FIRST/LAST/NEXT/PRIOR on an empty collection or at the
 * end of a run yield NULL in Oracle rather than an error.
 */

/* indexed read: raises on an absent or invalid index, like Oracle's coll(i) */
extern Datum plisql_collection_get(PLiSQL_expanded_collection *coll,
								   int32 idx, bool *isnull);

/*
 * Indexed assignment.  Copies value into the collection's own context.
 *
 * Deliberately permissive: assigning to a subscript that is not currently
 * present INSERTS it, including one beyond LAST and one whose element was
 * DELETEd.  That is the general facility; an associative array will need it.
 *
 * A nested table and a VARRAY permit neither.  Oracle raises ORA-06533 for a
 * subscript beyond the count and does not let a DELETEd subscript be reused,
 * and exec_stmt_coll_assign() enforces both before calling this -- which is
 * also where the two are told apart, since only the collection's high-water
 * mark distinguishes a deleted subscript from one never allocated.
 */
extern void plisql_collection_set(PLiSQL_expanded_collection *coll,
								  int32 idx, Datum value, bool isnull);

/* EXISTS(i): present-or-not.  Never raises -- not on an invalid subscript,
 * not on an atomically NULL collection. */
extern bool plisql_collection_exists(PLiSQL_expanded_collection *coll,
									 int32 idx);

/* DELETE(i): remove one index, leaving a hole.  No-op if already absent. */
extern void plisql_collection_delete(PLiSQL_expanded_collection *coll,
									 int32 idx);

/* DELETE: remove every element */
extern void plisql_collection_delete_all(PLiSQL_expanded_collection *coll);

/* COUNT: number of PRESENT elements, not LAST - FIRST + 1 */
extern int32 plisql_collection_count(PLiSQL_expanded_collection *coll);

/* FIRST / LAST: lowest / highest present index; false if none */
extern bool plisql_collection_first(PLiSQL_expanded_collection *coll,
									int32 *idx_out);
extern bool plisql_collection_last(PLiSQL_expanded_collection *coll,
								   int32 *idx_out);

/*
 * NEXT / PRIOR: nearest present index strictly after / before idx, skipping
 * holes; false if there is none.  idx itself need not be present, matching
 * Oracle.
 */
extern bool plisql_collection_next(PLiSQL_expanded_collection *coll,
								   int32 idx, int32 *idx_out);
extern bool plisql_collection_prior(PLiSQL_expanded_collection *coll,
									int32 idx, int32 *idx_out);

/*
 * EXTEND(n): append n NULL elements after ec_maxindex (or at 1 when empty),
 * i.e. after the collection's internal size, not merely its highest PRESENT
 * index -- a preceding DELETE(i) of the last element does not free up its
 * subscript for EXTEND to reuse.  Raises if a VARRAY's declared limit would
 * be exceeded.
 */
extern void plisql_collection_extend(PLiSQL_expanded_collection *coll,
									 int32 n);

/*
 * TRIM(n): lower ec_maxindex by n and drop any PRESENT entries that fall
 * beyond the new value.  Oracle's TRIM works off the collection's internal
 * size, not the count of PRESENT elements, so a subscript DELETE(i) already
 * turned into a hole still counts toward n.
 */
extern void plisql_collection_trim(PLiSQL_expanded_collection *coll, int32 n);

#endif							/* PL_COLLECTION_H */
