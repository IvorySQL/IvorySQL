/*-------------------------------------------------------------------------
 *
 * analyzejoins.c
 *	  Routines for simplifying joins after initial query analysis
 *
 * While we do a great deal of join simplification in prep/prepjointree.c,
 * certain optimizations cannot be performed at that stage for lack of
 * detailed information about the query.  The routines here are invoked
 * after initsplan.c has done its work, and can do additional join removal
 * and simplification steps based on the information extracted.  The penalty
 * is that we have to work harder to clean up after ourselves when we modify
 * the query, since the derived data structures have to be updated too.
 *
 * Portions Copyright (c) 1996-2023, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/optimizer/plan/analyzejoins.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "catalog/pg_class.h"
#include "nodes/nodeFuncs.h"
#include "optimizer/clauses.h"
#include "optimizer/joininfo.h"
#include "optimizer/optimizer.h"
#include "optimizer/pathnode.h"
#include "optimizer/paths.h"
#include "optimizer/planmain.h"
#include "optimizer/restrictinfo.h"
#include "optimizer/tlist.h"
#include "utils/lsyscache.h"

/*
 * The context for replace_varno_walker() containing source and target relids.
 */
typedef struct
{
	int			from;
	int			to;
} ReplaceVarnoContext;

/*
 * The struct containing self-join candidate.  Used to find duplicate reloids.
 */
typedef struct
{
	int			relid;
	Oid			reloid;
} SelfJoinCandidate;

bool		enable_self_join_removal;

/* local functions */
static bool join_is_removable(PlannerInfo *root, SpecialJoinInfo *sjinfo);

static void remove_leftjoinrel_from_query(PlannerInfo *root, int relid,
										  SpecialJoinInfo *sjinfo);
static void remove_rel_from_restrictinfo(RestrictInfo *rinfo,
										 int relid, int ojrelid);
static void remove_rel_from_eclass(EquivalenceClass *ec,
								   int relid, int ojrelid);
static List *remove_rel_from_joinlist(List *joinlist, int relid, int *nremoved);
static bool rel_supports_distinctness(PlannerInfo *root, RelOptInfo *rel);
static bool rel_is_distinct_for(PlannerInfo *root, RelOptInfo *rel,
								List *clause_list, List **extra_clauses);
static Oid	distinct_col_search(int colno, List *colnos, List *opids);
static bool is_innerrel_unique_for(PlannerInfo *root,
								   Relids joinrelids,
								   Relids outerrelids,
								   RelOptInfo *innerrel,
								   JoinType jointype,
								   List *restrictlist,
								   List **extra_clauses);
static Bitmapset *replace_relid(Relids relids, int oldId, int newId);
static void replace_varno(Node *node, int from, int to);
static bool replace_varno_walker(Node *node, ReplaceVarnoContext *ctx);
static int	self_join_candidates_cmp(const void *a, const void *b);



/*
 * remove_useless_joins
 *		Check for relations that don't actually need to be joined at all,
 *		and remove them from the query.
 *
 * We are passed the current joinlist and return the updated list.  Other
 * data structures that have to be updated are accessible via "root".
 */
List *
remove_useless_joins(PlannerInfo *root, List *joinlist)
{
	ListCell   *lc;

	/*
	 * We are only interested in relations that are left-joined to, so we can
	 * scan the join_info_list to find them easily.
	 */
restart:
	foreach(lc, root->join_info_list)
	{
		SpecialJoinInfo *sjinfo = (SpecialJoinInfo *) lfirst(lc);
		int			innerrelid;
		int			nremoved;

		/* Skip if not removable */
		if (!join_is_removable(root, sjinfo))
			continue;

		/*
		 * Currently, join_is_removable can only succeed when the sjinfo's
		 * righthand is a single baserel.  Remove that rel from the query and
		 * joinlist.
		 */
		innerrelid = bms_singleton_member(sjinfo->min_righthand);

		remove_leftjoinrel_from_query(root, innerrelid, sjinfo);

		/* We verify that exactly one reference gets removed from joinlist */
		nremoved = 0;
		joinlist = remove_rel_from_joinlist(joinlist, innerrelid, &nremoved);
		if (nremoved != 1)
			elog(ERROR, "failed to find relation %d in joinlist", innerrelid);

		/*
		 * We can delete this SpecialJoinInfo from the list too, since it's no
		 * longer of interest.  (Since we'll restart the foreach loop
		 * immediately, we don't bother with foreach_delete_current.)
		 */
		root->join_info_list = list_delete_cell(root->join_info_list, lc);

		/*
		 * Restart the scan.  This is necessary to ensure we find all
		 * removable joins independently of ordering of the join_info_list
		 * (note that removal of attr_needed bits may make a join appear
		 * removable that did not before).
		 */
		goto restart;
	}

	return joinlist;
}

/*
 * clause_sides_match_join
 *	  Determine whether a join clause is of the right form to use in this join.
 *
 * We already know that the clause is a binary opclause referencing only the
 * rels in the current join.  The point here is to check whether it has the
 * form "outerrel_expr op innerrel_expr" or "innerrel_expr op outerrel_expr",
 * rather than mixing outer and inner vars on either side.  If it matches,
 * we set the transient flag outer_is_left to identify which side is which.
 */
static inline bool
clause_sides_match_join(RestrictInfo *rinfo, Relids outerrelids,
						Relids innerrelids)
{
	if (bms_is_subset(rinfo->left_relids, outerrelids) &&
		bms_is_subset(rinfo->right_relids, innerrelids))
	{
		/* lefthand side is outer */
		rinfo->outer_is_left = true;
		return true;
	}
	else if (bms_is_subset(rinfo->left_relids, innerrelids) &&
			 bms_is_subset(rinfo->right_relids, outerrelids))
	{
		/* righthand side is outer */
		rinfo->outer_is_left = false;
		return true;
	}
	return false;				/* no good for these input relations */
}

/*
 * join_is_removable
 *	  Check whether we need not perform this special join at all, because
 *	  it will just duplicate its left input.
 *
 * This is true for a left join for which the join condition cannot match
 * more than one inner-side row.  (There are other possibly interesting
 * cases, but we don't have the infrastructure to prove them.)  We also
 * have to check that the inner side doesn't generate any variables needed
 * above the join.
 */
static bool
join_is_removable(PlannerInfo *root, SpecialJoinInfo *sjinfo)
{
	int			innerrelid;
	RelOptInfo *innerrel;
	Relids		inputrelids;
	Relids		joinrelids;
	List	   *clause_list = NIL;
	ListCell   *l;
	int			attroff;

	/*
	 * Must be a left join to a single baserel, else we aren't going to be
	 * able to do anything with it.
	 */
	if (sjinfo->jointype != JOIN_LEFT)
		return false;

	if (!bms_get_singleton_member(sjinfo->min_righthand, &innerrelid))
		return false;

	/*
	 * Never try to eliminate a left join to the query result rel.  Although
	 * the case is syntactically impossible in standard SQL, MERGE will build
	 * a join tree that looks exactly like that.
	 */
	if (innerrelid == root->parse->resultRelation)
		return false;

	innerrel = find_base_rel(root, innerrelid);

	/*
	 * Before we go to the effort of checking whether any innerrel variables
	 * are needed above the join, make a quick check to eliminate cases in
	 * which we will surely be unable to prove uniqueness of the innerrel.
	 */
	if (!rel_supports_distinctness(root, innerrel))
		return false;

	/* Compute the relid set for the join we are considering */
	inputrelids = bms_union(sjinfo->min_lefthand, sjinfo->min_righthand);
	Assert(sjinfo->ojrelid != 0);
	joinrelids = bms_copy(inputrelids);
	joinrelids = bms_add_member(joinrelids, sjinfo->ojrelid);

	/*
	 * We can't remove the join if any inner-rel attributes are used above the
	 * join.  Here, "above" the join includes pushed-down conditions, so we
	 * should reject if attr_needed includes the OJ's own relid; therefore,
	 * compare to inputrelids not joinrelids.
	 *
	 * As a micro-optimization, it seems better to start with max_attr and
	 * count down rather than starting with min_attr and counting up, on the
	 * theory that the system attributes are somewhat less likely to be wanted
	 * and should be tested last.
	 */
	for (attroff = innerrel->max_attr - innerrel->min_attr;
		 attroff >= 0;
		 attroff--)
	{
		if (!bms_is_subset(innerrel->attr_needed[attroff], inputrelids))
			return false;
	}

	/*
	 * Similarly check that the inner rel isn't needed by any PlaceHolderVars
	 * that will be used above the join.  The PHV case is a little bit more
	 * complicated, because PHVs may have been assigned a ph_eval_at location
	 * that includes the innerrel, yet their contained expression might not
	 * actually reference the innerrel (it could be just a constant, for
	 * instance).  If such a PHV is due to be evaluated above the join then it
	 * needn't prevent join removal.
	 */
	foreach(l, root->placeholder_list)
	{
		PlaceHolderInfo *phinfo = (PlaceHolderInfo *) lfirst(l);

		if (bms_overlap(phinfo->ph_lateral, innerrel->relids))
			return false;		/* it references innerrel laterally */
		if (!bms_overlap(phinfo->ph_eval_at, innerrel->relids))
			continue;			/* it definitely doesn't reference innerrel */
		if (bms_is_subset(phinfo->ph_needed, inputrelids))
			continue;			/* PHV is not used above the join */
		if (!bms_is_member(sjinfo->ojrelid, phinfo->ph_eval_at))
			return false;		/* it has to be evaluated below the join */

		/*
		 * We need to be sure there will still be a place to evaluate the PHV
		 * if we remove the join, ie that ph_eval_at wouldn't become empty.
		 */
		if (!bms_overlap(sjinfo->min_lefthand, phinfo->ph_eval_at))
			return false;		/* there isn't any other place to eval PHV */
		/* Check contained expression last, since this is a bit expensive */
		if (bms_overlap(pull_varnos(root, (Node *) phinfo->ph_var->phexpr),
						innerrel->relids))
			return false;		/* contained expression references innerrel */
	}

	/*
	 * Search for mergejoinable clauses that constrain the inner rel against
	 * either the outer rel or a pseudoconstant.  If an operator is
	 * mergejoinable then it behaves like equality for some btree opclass, so
	 * it's what we want.  The mergejoinability test also eliminates clauses
	 * containing volatile functions, which we couldn't depend on.
	 */
	foreach(l, innerrel->joininfo)
	{
		RestrictInfo *restrictinfo = (RestrictInfo *) lfirst(l);

		/*
		 * If the current join commutes with some other outer join(s) via
		 * outer join identity 3, there will be multiple clones of its join
		 * clauses in the joininfo list.  We want to consider only the
		 * has_clone form of such clauses.  Processing more than one form
		 * would be wasteful, and also some of the others would confuse the
		 * RINFO_IS_PUSHED_DOWN test below.
		 */
		if (restrictinfo->is_clone)
			continue;			/* ignore it */

		/*
		 * If it's not a join clause for this outer join, we can't use it.
		 * Note that if the clause is pushed-down, then it is logically from
		 * above the outer join, even if it references no other rels (it might
		 * be from WHERE, for example).
		 */
		if (RINFO_IS_PUSHED_DOWN(restrictinfo, joinrelids))
			continue;			/* ignore; not useful here */

		/* Ignore if it's not a mergejoinable clause */
		if (!restrictinfo->can_join ||
			restrictinfo->mergeopfamilies == NIL)
			continue;			/* not mergejoinable */

		/*
		 * Check if clause has the form "outer op inner" or "inner op outer",
		 * and if so mark which side is inner.
		 */
		if (!clause_sides_match_join(restrictinfo, sjinfo->min_lefthand,
									 innerrel->relids))
			continue;			/* no good for these input relations */

		/* OK, add to list */
		clause_list = lappend(clause_list, restrictinfo);
	}

	/*
	 * Now that we have the relevant equality join clauses, try to prove the
	 * innerrel distinct.
	 */
	if (rel_is_distinct_for(root, innerrel, clause_list, NULL))
		return true;

	/*
	 * Some day it would be nice to check for other methods of establishing
	 * distinctness.
	 */
	return false;
}


/*
 * Remove the target rel->relid and references to the target join from the
 * planner's data structures, having determined that there is no need
 * to include them in the query.  Optionally replace them with subst if subst
 * is non-negative.
 *
 * This function updates only parts needed for both left-join removal and
 * self-join removal.
 */
static void
remove_rel_from_query(PlannerInfo *root, RelOptInfo *rel,
					  int subst, SpecialJoinInfo *sjinfo,
					  Relids joinrelids)
{
	int			relid = rel->relid;
	int			ojrelid = (sjinfo != NULL) ? sjinfo->ojrelid : -1;
	Index		rti;
	ListCell   *l;

	/*
	 * Remove references to the rel from other baserels' attr_needed arrays.
	 */
	for (rti = 1; rti < root->simple_rel_array_size; rti++)
	{
		RelOptInfo *otherrel = root->simple_rel_array[rti];
		int			attroff;

		/* there may be empty slots corresponding to non-baserel RTEs */
		if (otherrel == NULL)
			continue;

		Assert(otherrel->relid == rti); /* sanity check on array */

		/* no point in processing target rel itself */
		if (otherrel == rel)
			continue;

		for (attroff = otherrel->max_attr - otherrel->min_attr;
			 attroff >= 0;
			 attroff--)
		{
			otherrel->attr_needed[attroff] =
				replace_relid(otherrel->attr_needed[attroff], relid, subst);
			otherrel->attr_needed[attroff] =
				replace_relid(otherrel->attr_needed[attroff], ojrelid, subst);
		}

		/* Update lateral references. */
		replace_varno((Node *) otherrel->lateral_vars, relid, subst);
	}

	/*
	 * Update all_baserels and related relid sets.
	 */
	root->all_baserels = replace_relid(root->all_baserels, relid, subst);
	root->outer_join_rels = replace_relid(root->outer_join_rels, ojrelid, subst);
	root->all_query_rels = replace_relid(root->all_query_rels, relid, subst);
	root->all_query_rels = replace_relid(root->all_query_rels, ojrelid, subst);

	/*
	 * Likewise remove references from SpecialJoinInfo data structures.
	 *
	 * This is relevant in case the outer join we're deleting is nested inside
	 * other outer joins: the upper joins' relid sets have to be adjusted. The
	 * RHS of the target outer join will be made empty here, but that's OK
	 * since caller will delete that SpecialJoinInfo entirely.
	 */
	foreach(l, root->join_info_list)
	{
		SpecialJoinInfo *sjinf = (SpecialJoinInfo *) lfirst(l);

		sjinf->min_lefthand = replace_relid(sjinf->min_lefthand, relid, subst);
		sjinf->min_righthand = replace_relid(sjinf->min_righthand, relid, subst);
		sjinf->syn_lefthand = replace_relid(sjinf->syn_lefthand, relid, subst);
		sjinf->syn_righthand = replace_relid(sjinf->syn_righthand, relid, subst);
		sjinf->min_lefthand = replace_relid(sjinf->min_lefthand, ojrelid, subst);
		sjinf->min_righthand = replace_relid(sjinf->min_righthand, ojrelid, subst);
		sjinf->syn_lefthand = replace_relid(sjinf->syn_lefthand, ojrelid, subst);
		sjinf->syn_righthand = replace_relid(sjinf->syn_righthand, ojrelid, subst);
		/* relid cannot appear in these fields, but ojrelid can: */
		sjinf->commute_above_l = replace_relid(sjinf->commute_above_l, ojrelid, subst);
		sjinf->commute_above_r = replace_relid(sjinf->commute_above_r, ojrelid, subst);
		sjinf->commute_below_l = replace_relid(sjinf->commute_below_l, ojrelid, subst);
		sjinf->commute_below_r = replace_relid(sjinf->commute_below_r, ojrelid, subst);

		replace_varno((Node *) sjinf->semi_rhs_exprs, relid, subst);
	}

	/*
	 * Likewise remove references from PlaceHolderVar data structures,
	 * removing any no-longer-needed placeholders entirely.
	 *
	 * Removal is a bit trickier than it might seem: we can remove PHVs that
	 * are used at the target rel and/or in the join qual, but not those that
	 * are used at join partner rels or above the join.  It's not that easy to
	 * distinguish PHVs used at partner rels from those used in the join qual,
	 * since they will both have ph_needed sets that are subsets of
	 * joinrelids.  However, a PHV used at a partner rel could not have the
	 * target rel in ph_eval_at, so we check that while deciding whether to
	 * remove or just update the PHV.  There is no corresponding test in
	 * join_is_removable because it doesn't need to distinguish those cases.
	 */
	foreach(l, root->placeholder_list)
	{
		PlaceHolderInfo *phinfo = (PlaceHolderInfo *) lfirst(l);

		Assert(sjinfo == NULL || !bms_is_member(relid, phinfo->ph_lateral));
		if (bms_is_subset(phinfo->ph_needed, joinrelids) &&
			bms_is_member(relid, phinfo->ph_eval_at) &&
			!bms_is_member(ojrelid, phinfo->ph_eval_at))
		{
			root->placeholder_list = foreach_delete_current(root->placeholder_list,
															l);
			root->placeholder_array[phinfo->phid] = NULL;
		}
		else
		{
			PlaceHolderVar *phv = phinfo->ph_var;

			phinfo->ph_eval_at = replace_relid(phinfo->ph_eval_at, relid, subst);
			phinfo->ph_eval_at = replace_relid(phinfo->ph_eval_at, ojrelid, subst);
			Assert(!bms_is_empty(phinfo->ph_eval_at));	/* checked previously */
			phinfo->ph_needed = replace_relid(phinfo->ph_needed, relid, subst);
			phinfo->ph_needed = replace_relid(phinfo->ph_needed, ojrelid, subst);
			/* ph_needed might or might not become empty */
			phinfo->ph_lateral = replace_relid(phinfo->ph_lateral, relid, subst);
			/* ph_lateral might or might not be empty */
			phv->phrels = replace_relid(phv->phrels, relid, subst);
			phv->phrels = replace_relid(phv->phrels, ojrelid, subst);
			Assert(!bms_is_empty(phv->phrels));
			replace_varno((Node *) phv->phexpr, relid, subst);
			Assert(phv->phnullingrels == NULL); /* no need to adjust */
		}
	}
}

/*
 * Remove the target relid and references to the target join from the
 * planner's data structures, having determined that there is no need
 * to include them in the query.
 *
 * We are not terribly thorough here.  We only bother to update parts of
 * the planner's data structures that will actually be consulted later.
 */
static void
remove_leftjoinrel_from_query(PlannerInfo *root, int relid,
							  SpecialJoinInfo *sjinfo)
{
	List	   *joininfos;
	int			ojrelid = sjinfo->ojrelid;
	RelOptInfo *rel = find_base_rel(root, relid);
	Relids		join_plus_commute;
	Relids		joinrelids;
	ListCell   *l;

	/* Compute the relid set for the join we are considering */
	joinrelids = bms_union(sjinfo->min_lefthand, sjinfo->min_righthand);
	Assert(ojrelid != 0);
	joinrelids = bms_add_member(joinrelids, ojrelid);

	remove_rel_from_query(root, rel, -1, sjinfo, joinrelids);

	/*
	 * Remove any joinquals referencing the rel from the joininfo lists.
	 *
	 * In some cases, a joinqual has to be put back after deleting its
	 * reference to the target rel.  This can occur for pseudoconstant and
	 * outerjoin-delayed quals, which can get marked as requiring the rel in
	 * order to force them to be evaluated at or above the join.  We can't
	 * just discard them, though.  Only quals that logically belonged to the
	 * outer join being discarded should be removed from the query.
	 *
	 * We might encounter a qual that is a clone of a deletable qual with some
	 * outer-join relids added (see deconstruct_distribute_oj_quals).  To
	 * ensure we get rid of such clones as well, add the relids of all OJs
	 * commutable with this one to the set we test against for
	 * pushed-down-ness.
	 */
	join_plus_commute = bms_union(joinrelids,
								  sjinfo->commute_above_r);
	join_plus_commute = bms_add_members(join_plus_commute,
										sjinfo->commute_below_l);

	/*
	 * We must make a copy of the rel's old joininfo list before starting the
	 * loop, because otherwise remove_join_clause_from_rels would destroy the
	 * list while we're scanning it.
	 */
	joininfos = list_copy(rel->joininfo);
	foreach(l, joininfos)
	{
		RestrictInfo *rinfo = (RestrictInfo *) lfirst(l);

		remove_join_clause_from_rels(root, rinfo, rinfo->required_relids);

		if (RINFO_IS_PUSHED_DOWN(rinfo, join_plus_commute))
		{
			/*
			 * There might be references to relid or ojrelid in the
			 * RestrictInfo's relid sets, as a consequence of PHVs having had
			 * ph_eval_at sets that include those.  We already checked above
			 * that any such PHV is safe (and updated its ph_eval_at), so we
			 * can just drop those references.
			 */
			remove_rel_from_restrictinfo(rinfo, relid, ojrelid);

			/*
			 * Cross-check that the clause itself does not reference the
			 * target rel or join.
			 */
#ifdef USE_ASSERT_CHECKING
			{
				Relids		clause_varnos = pull_varnos(root,
														(Node *) rinfo->clause);

				Assert(!bms_is_member(relid, clause_varnos));
				Assert(!bms_is_member(ojrelid, clause_varnos));
			}
#endif
			/* Now throw it back into the joininfo lists */
			distribute_restrictinfo_to_rels(root, rinfo);
		}
	}

	/*
	 * Likewise remove references from EquivalenceClasses.
	 */
	foreach(l, root->eq_classes)
	{
		EquivalenceClass *ec = (EquivalenceClass *) lfirst(l);

		if (bms_is_member(relid, ec->ec_relids) ||
			bms_is_member(ojrelid, ec->ec_relids))
			remove_rel_from_eclass(ec, relid, ojrelid);
	}

	/*
	 * There may be references to the rel in root->fkey_list, but if so,
	 * match_foreign_keys_to_quals() will get rid of them.
	 */

	/*
	 * Finally, remove the rel from the baserel array to prevent it from being
	 * referenced again.  (We can't do this earlier because
	 * remove_join_clause_from_rels will touch it.)
	 */
	root->simple_rel_array[relid] = NULL;

	/* And nuke the RelOptInfo, just in case there's another access path */
	pfree(rel);
}

/*
 * Remove any references to relid or ojrelid from the RestrictInfo.
 *
 * We only bother to clean out bits in clause_relids and required_relids,
 * not nullingrel bits in contained Vars and PHVs.  (This might have to be
 * improved sometime.)  However, if the RestrictInfo contains an OR clause
 * we have to also clean up the sub-clauses.
 */
static void
remove_rel_from_restrictinfo(RestrictInfo *rinfo, int relid, int ojrelid)
{
	/*
	 * The clause_relids probably aren't shared with anything else, but let's
	 * copy them just to be sure.
	 */
	rinfo->clause_relids = bms_copy(rinfo->clause_relids);
	rinfo->clause_relids = bms_del_member(rinfo->clause_relids, relid);
	rinfo->clause_relids = bms_del_member(rinfo->clause_relids, ojrelid);
	/* Likewise for required_relids */
	rinfo->required_relids = bms_copy(rinfo->required_relids);
	rinfo->required_relids = bms_del_member(rinfo->required_relids, relid);
	rinfo->required_relids = bms_del_member(rinfo->required_relids, ojrelid);

	/* If it's an OR, recurse to clean up sub-clauses */
	if (restriction_is_or_clause(rinfo))
	{
		ListCell   *lc;

		Assert(is_orclause(rinfo->orclause));
		foreach(lc, ((BoolExpr *) rinfo->orclause)->args)
		{
			Node	   *orarg = (Node *) lfirst(lc);

			/* OR arguments should be ANDs or sub-RestrictInfos */
			if (is_andclause(orarg))
			{
				List	   *andargs = ((BoolExpr *) orarg)->args;
				ListCell   *lc2;

				foreach(lc2, andargs)
				{
					RestrictInfo *rinfo2 = lfirst_node(RestrictInfo, lc2);

					remove_rel_from_restrictinfo(rinfo2, relid, ojrelid);
				}
			}
			else
			{
				RestrictInfo *rinfo2 = castNode(RestrictInfo, orarg);

				remove_rel_from_restrictinfo(rinfo2, relid, ojrelid);
			}
		}
	}
}

/*
 * Remove any references to relid or ojrelid from the EquivalenceClass.
 *
 * Like remove_rel_from_restrictinfo, we don't worry about cleaning out
 * any nullingrel bits in contained Vars and PHVs.  (This might have to be
 * improved sometime.)  We do need to fix the EC and EM relid sets to ensure
 * that implied join equalities will be generated at the appropriate join
 * level(s).
 */
static void
remove_rel_from_eclass(EquivalenceClass *ec, int relid, int ojrelid)
{
	ListCell   *lc;

	/* Fix up the EC's overall relids */
	ec->ec_relids = bms_del_member(ec->ec_relids, relid);
	ec->ec_relids = bms_del_member(ec->ec_relids, ojrelid);

	/*
	 * Fix up the member expressions.  Any non-const member that ends with
	 * empty em_relids must be a Var or PHV of the removed relation.  We don't
	 * need it anymore, so we can drop it.
	 */
	foreach(lc, ec->ec_members)
	{
		EquivalenceMember *cur_em = (EquivalenceMember *) lfirst(lc);

		if (bms_is_member(relid, cur_em->em_relids) ||
			bms_is_member(ojrelid, cur_em->em_relids))
		{
			Assert(!cur_em->em_is_const);
			cur_em->em_relids = bms_del_member(cur_em->em_relids, relid);
			cur_em->em_relids = bms_del_member(cur_em->em_relids, ojrelid);
			if (bms_is_empty(cur_em->em_relids))
				ec->ec_members = foreach_delete_current(ec->ec_members, lc);
		}
	}

	/* Fix up the source clauses, in case we can re-use them later */
	foreach(lc, ec->ec_sources)
	{
		RestrictInfo *rinfo = (RestrictInfo *) lfirst(lc);

		remove_rel_from_restrictinfo(rinfo, relid, ojrelid);
	}

	/*
	 * Rather than expend code on fixing up any already-derived clauses, just
	 * drop them.  (At this point, any such clauses would be base restriction
	 * clauses, which we'd not need anymore anyway.)
	 */
	ec->ec_derives = NIL;
}

/*
 * Remove any occurrences of the target relid from a joinlist structure.
 *
 * It's easiest to build a whole new list structure, so we handle it that
 * way.  Efficiency is not a big deal here.
 *
 * *nremoved is incremented by the number of occurrences removed (there
 * should be exactly one, but the caller checks that).
 */
static List *
remove_rel_from_joinlist(List *joinlist, int relid, int *nremoved)
{
	List	   *result = NIL;
	ListCell   *jl;

	foreach(jl, joinlist)
	{
		Node	   *jlnode = (Node *) lfirst(jl);

		if (IsA(jlnode, RangeTblRef))
		{
			int			varno = ((RangeTblRef *) jlnode)->rtindex;

			if (varno == relid)
				(*nremoved)++;
			else
				result = lappend(result, jlnode);
		}
		else if (IsA(jlnode, List))
		{
			/* Recurse to handle subproblem */
			List	   *sublist;

			sublist = remove_rel_from_joinlist((List *) jlnode,
											   relid, nremoved);
			/* Avoid including empty sub-lists in the result */
			if (sublist)
				result = lappend(result, sublist);
		}
		else
		{
			elog(ERROR, "unrecognized joinlist node type: %d",
				 (int) nodeTag(jlnode));
		}
	}

	return result;
}


/*
 * reduce_unique_semijoins
 *		Check for semijoins that can be simplified to plain inner joins
 *		because the inner relation is provably unique for the join clauses.
 *
 * Ideally this would happen during reduce_outer_joins, but we don't have
 * enough information at that point.
 *
 * To perform the strength reduction when applicable, we need only delete
 * the semijoin's SpecialJoinInfo from root->join_info_list.  (We don't
 * bother fixing the join type attributed to it in the query jointree,
 * since that won't be consulted again.)
 */
void
reduce_unique_semijoins(PlannerInfo *root)
{
	ListCell   *lc;

	/*
	 * Scan the join_info_list to find semijoins.
	 */
	foreach(lc, root->join_info_list)
	{
		SpecialJoinInfo *sjinfo = (SpecialJoinInfo *) lfirst(lc);
		int			innerrelid;
		RelOptInfo *innerrel;
		Relids		joinrelids;
		List	   *restrictlist;

		/*
		 * Must be a semijoin to a single baserel, else we aren't going to be
		 * able to do anything with it.
		 */
		if (sjinfo->jointype != JOIN_SEMI)
			continue;

		if (!bms_get_singleton_member(sjinfo->min_righthand, &innerrelid))
			continue;

		innerrel = find_base_rel(root, innerrelid);

		/*
		 * Before we trouble to run generate_join_implied_equalities, make a
		 * quick check to eliminate cases in which we will surely be unable to
		 * prove uniqueness of the innerrel.
		 */
		if (!rel_supports_distinctness(root, innerrel))
			continue;

		/* Compute the relid set for the join we are considering */
		joinrelids = bms_union(sjinfo->min_lefthand, sjinfo->min_righthand);
		Assert(sjinfo->ojrelid == 0);	/* SEMI joins don't have RT indexes */

		/*
		 * Since we're only considering a single-rel RHS, any join clauses it
		 * has must be clauses linking it to the semijoin's min_lefthand.  We
		 * can also consider EC-derived join clauses.
		 */
		restrictlist =
			list_concat(generate_join_implied_equalities(root,
														 joinrelids,
														 sjinfo->min_lefthand,
														 innerrel,
														 NULL),
						innerrel->joininfo);

		/* Test whether the innerrel is unique for those clauses. */
		if (!innerrel_is_unique(root,
								joinrelids, sjinfo->min_lefthand, innerrel,
								JOIN_SEMI, restrictlist, true))
			continue;

		/* OK, remove the SpecialJoinInfo from the list. */
		root->join_info_list = foreach_delete_current(root->join_info_list, lc);
	}
}


/*
 * rel_supports_distinctness
 *		Could the relation possibly be proven distinct on some set of columns?
 *
 * This is effectively a pre-checking function for rel_is_distinct_for().
 * It must return true if rel_is_distinct_for() could possibly return true
 * with this rel, but it should not expend a lot of cycles.  The idea is
 * that callers can avoid doing possibly-expensive processing to compute
 * rel_is_distinct_for()'s argument lists if the call could not possibly
 * succeed.
 */
static bool
rel_supports_distinctness(PlannerInfo *root, RelOptInfo *rel)
{
	/* We only know about baserels ... */
	if (rel->reloptkind != RELOPT_BASEREL)
		return false;
	if (rel->rtekind == RTE_RELATION)
	{
		/*
		 * For a plain relation, we only know how to prove uniqueness by
		 * reference to unique indexes.  Make sure there's at least one
		 * suitable unique index.  It must be immediately enforced, and not a
		 * partial index. (Keep these conditions in sync with
		 * relation_has_unique_index_for!)
		 */
		ListCell   *lc;

		foreach(lc, rel->indexlist)
		{
			IndexOptInfo *ind = (IndexOptInfo *) lfirst(lc);

			if (ind->unique && ind->immediate && ind->indpred == NIL)
				return true;
		}
	}
	else if (rel->rtekind == RTE_SUBQUERY)
	{
		Query	   *subquery = root->simple_rte_array[rel->relid]->subquery;

		/* Check if the subquery has any qualities that support distinctness */
		if (query_supports_distinctness(subquery))
			return true;
	}
	/* We have no proof rules for any other rtekinds. */
	return false;
}

/*
 * rel_is_distinct_for
 *		Does the relation return only distinct rows according to clause_list?
 *
 * clause_list is a list of join restriction clauses involving this rel and
 * some other one.  Return true if no two rows emitted by this rel could
 * possibly join to the same row of the other rel.
 *
 * The caller must have already determined that each condition is a
 * mergejoinable equality with an expression in this relation on one side, and
 * an expression not involving this relation on the other.  The transient
 * outer_is_left flag is used to identify which side references this relation:
 * left side if outer_is_left is false, right side if it is true.
 *
 * Note that the passed-in clause_list may be destructively modified!  This
 * is OK for current uses, because the clause_list is built by the caller for
 * the sole purpose of passing to this function.
 *
 * outer_exprs contains the right sides of baserestrictinfo clauses looking
 * like x = const if distinctness is derived from such clauses, not joininfo
 * clause.  Pass NULL to the outer_exprs, if its value is not needed.
 */
static bool
rel_is_distinct_for(PlannerInfo *root, RelOptInfo *rel, List *clause_list,
					List **extra_clauses)
{
	/*
	 * We could skip a couple of tests here if we assume all callers checked
	 * rel_supports_distinctness first, but it doesn't seem worth taking any
	 * risk for.
	 */
	if (rel->reloptkind != RELOPT_BASEREL)
		return false;
	if (rel->rtekind == RTE_RELATION)
	{
		/*
		 * Examine the indexes to see if we have a matching unique index.
		 * relation_has_unique_index_ext automatically adds any usable
		 * restriction clauses for the rel, so we needn't do that here.
		 */
		if (relation_has_unique_index_ext(root, rel, clause_list, NIL, NIL,
										  extra_clauses))
			return true;
	}
	else if (rel->rtekind == RTE_SUBQUERY)
	{
		Index		relid = rel->relid;
		Query	   *subquery = root->simple_rte_array[relid]->subquery;
		List	   *colnos = NIL;
		List	   *opids = NIL;
		ListCell   *l;

		/*
		 * Build the argument lists for query_is_distinct_for: a list of
		 * output column numbers that the query needs to be distinct over, and
		 * a list of equality operators that the output columns need to be
		 * distinct according to.
		 *
		 * (XXX we are not considering restriction clauses attached to the
		 * subquery; is that worth doing?)
		 */
		foreach(l, clause_list)
		{
			RestrictInfo *rinfo = lfirst_node(RestrictInfo, l);
			Oid			op;
			Var		   *var;

			/*
			 * Get the equality operator we need uniqueness according to.
			 * (This might be a cross-type operator and thus not exactly the
			 * same operator the subquery would consider; that's all right
			 * since query_is_distinct_for can resolve such cases.)  The
			 * caller's mergejoinability test should have selected only
			 * OpExprs.
			 */
			op = castNode(OpExpr, rinfo->clause)->opno;

			/* caller identified the inner side for us */
			if (rinfo->outer_is_left)
				var = (Var *) get_rightop(rinfo->clause);
			else
				var = (Var *) get_leftop(rinfo->clause);

			/*
			 * We may ignore any RelabelType node above the operand.  (There
			 * won't be more than one, since eval_const_expressions() has been
			 * applied already.)
			 */
			if (var && IsA(var, RelabelType))
				var = (Var *) ((RelabelType *) var)->arg;

			/*
			 * If inner side isn't a Var referencing a subquery output column,
			 * this clause doesn't help us.
			 */
			if (!var || !IsA(var, Var) ||
				var->varno != relid || var->varlevelsup != 0)
				continue;

			colnos = lappend_int(colnos, var->varattno);
			opids = lappend_oid(opids, op);
		}

		if (query_is_distinct_for(subquery, colnos, opids))
			return true;
	}
	return false;
}


/*
 * query_supports_distinctness - could the query possibly be proven distinct
 *		on some set of output columns?
 *
 * This is effectively a pre-checking function for query_is_distinct_for().
 * It must return true if query_is_distinct_for() could possibly return true
 * with this query, but it should not expend a lot of cycles.  The idea is
 * that callers can avoid doing possibly-expensive processing to compute
 * query_is_distinct_for()'s argument lists if the call could not possibly
 * succeed.
 */
bool
query_supports_distinctness(Query *query)
{
	/* SRFs break distinctness except with DISTINCT, see below */
	if (query->hasTargetSRFs && query->distinctClause == NIL)
		return false;

	/* check for features we can prove distinctness with */
	if (query->distinctClause != NIL ||
		query->groupClause != NIL ||
		query->groupingSets != NIL ||
		query->hasAggs ||
		query->havingQual ||
		query->setOperations)
		return true;

	return false;
}

/*
 * query_is_distinct_for - does query never return duplicates of the
 *		specified columns?
 *
 * query is a not-yet-planned subquery (in current usage, it's always from
 * a subquery RTE, which the planner avoids scribbling on).
 *
 * colnos is an integer list of output column numbers (resno's).  We are
 * interested in whether rows consisting of just these columns are certain
 * to be distinct.  "Distinctness" is defined according to whether the
 * corresponding upper-level equality operators listed in opids would think
 * the values are distinct.  (Note: the opids entries could be cross-type
 * operators, and thus not exactly the equality operators that the subquery
 * would use itself.  We use equality_ops_are_compatible() to check
 * compatibility.  That looks at btree or hash opfamily membership, and so
 * should give trustworthy answers for all operators that we might need
 * to deal with here.)
 */
bool
query_is_distinct_for(Query *query, List *colnos, List *opids)
{
	ListCell   *l;
	Oid			opid;

	Assert(list_length(colnos) == list_length(opids));

	/*
	 * DISTINCT (including DISTINCT ON) guarantees uniqueness if all the
	 * columns in the DISTINCT clause appear in colnos and operator semantics
	 * match.  This is true even if there are SRFs in the DISTINCT columns or
	 * elsewhere in the tlist.
	 */
	if (query->distinctClause)
	{
		foreach(l, query->distinctClause)
		{
			SortGroupClause *sgc = (SortGroupClause *) lfirst(l);
			TargetEntry *tle = get_sortgroupclause_tle(sgc,
													   query->targetList);

			opid = distinct_col_search(tle->resno, colnos, opids);
			if (!OidIsValid(opid) ||
				!equality_ops_are_compatible(opid, sgc->eqop))
				break;			/* exit early if no match */
		}
		if (l == NULL)			/* had matches for all? */
			return true;
	}

	/*
	 * Otherwise, a set-returning function in the query's targetlist can
	 * result in returning duplicate rows, despite any grouping that might
	 * occur before tlist evaluation.  (If all tlist SRFs are within GROUP BY
	 * columns, it would be safe because they'd be expanded before grouping.
	 * But it doesn't currently seem worth the effort to check for that.)
	 */
	if (query->hasTargetSRFs)
		return false;

	/*
	 * Similarly, GROUP BY without GROUPING SETS guarantees uniqueness if all
	 * the grouped columns appear in colnos and operator semantics match.
	 */
	if (query->groupClause && !query->groupingSets)
	{
		foreach(l, query->groupClause)
		{
			SortGroupClause *sgc = (SortGroupClause *) lfirst(l);
			TargetEntry *tle = get_sortgroupclause_tle(sgc,
													   query->targetList);

			opid = distinct_col_search(tle->resno, colnos, opids);
			if (!OidIsValid(opid) ||
				!equality_ops_are_compatible(opid, sgc->eqop))
				break;			/* exit early if no match */
		}
		if (l == NULL)			/* had matches for all? */
			return true;
	}
	else if (query->groupingSets)
	{
		/*
		 * If we have grouping sets with expressions, we probably don't have
		 * uniqueness and analysis would be hard. Punt.
		 */
		if (query->groupClause)
			return false;

		/*
		 * If we have no groupClause (therefore no grouping expressions), we
		 * might have one or many empty grouping sets. If there's just one,
		 * then we're returning only one row and are certainly unique. But
		 * otherwise, we know we're certainly not unique.
		 */
		if (list_length(query->groupingSets) == 1 &&
			((GroupingSet *) linitial(query->groupingSets))->kind == GROUPING_SET_EMPTY)
			return true;
		else
			return false;
	}
	else
	{
		/*
		 * If we have no GROUP BY, but do have aggregates or HAVING, then the
		 * result is at most one row so it's surely unique, for any operators.
		 */
		if (query->hasAggs || query->havingQual)
			return true;
	}

	/*
	 * UNION, INTERSECT, EXCEPT guarantee uniqueness of the whole output row,
	 * except with ALL.
	 */
	if (query->setOperations)
	{
		SetOperationStmt *topop = castNode(SetOperationStmt, query->setOperations);

		Assert(topop->op != SETOP_NONE);

		if (!topop->all)
		{
			ListCell   *lg;

			/* We're good if all the nonjunk output columns are in colnos */
			lg = list_head(topop->groupClauses);
			foreach(l, query->targetList)
			{
				TargetEntry *tle = (TargetEntry *) lfirst(l);
				SortGroupClause *sgc;

				if (tle->resjunk)
					continue;	/* ignore resjunk columns */

				/* non-resjunk columns should have grouping clauses */
				Assert(lg != NULL);
				sgc = (SortGroupClause *) lfirst(lg);
				lg = lnext(topop->groupClauses, lg);

				opid = distinct_col_search(tle->resno, colnos, opids);
				if (!OidIsValid(opid) ||
					!equality_ops_are_compatible(opid, sgc->eqop))
					break;		/* exit early if no match */
			}
			if (l == NULL)		/* had matches for all? */
				return true;
		}
	}

	/*
	 * XXX Are there any other cases in which we can easily see the result
	 * must be distinct?
	 *
	 * If you do add more smarts to this function, be sure to update
	 * query_supports_distinctness() to match.
	 */

	return false;
}

/*
 * distinct_col_search - subroutine for query_is_distinct_for
 *
 * If colno is in colnos, return the corresponding element of opids,
 * else return InvalidOid.  (Ordinarily colnos would not contain duplicates,
 * but if it does, we arbitrarily select the first match.)
 */
static Oid
distinct_col_search(int colno, List *colnos, List *opids)
{
	ListCell   *lc1,
			   *lc2;

	forboth(lc1, colnos, lc2, opids)
	{
		if (colno == lfirst_int(lc1))
			return lfirst_oid(lc2);
	}
	return InvalidOid;
}


/*
 * innerrel_is_unique
 *	  Check if the innerrel provably contains at most one tuple matching any
 *	  tuple from the outerrel, based on join clauses in the 'restrictlist'.
 *
 * We need an actual RelOptInfo for the innerrel, but it's sufficient to
 * identify the outerrel by its Relids.  This asymmetry supports use of this
 * function before joinrels have been built.  (The caller is expected to
 * also supply the joinrelids, just to save recalculating that.)
 *
 * The proof must be made based only on clauses that will be "joinquals"
 * rather than "otherquals" at execution.  For an inner join there's no
 * difference; but if the join is outer, we must ignore pushed-down quals,
 * as those will become "otherquals".  Note that this means the answer might
 * vary depending on whether IS_OUTER_JOIN(jointype); since we cache the
 * answer without regard to that, callers must take care not to call this
 * with jointypes that would be classified differently by IS_OUTER_JOIN().
 *
 * The actual proof is undertaken by is_innerrel_unique_for(); this function
 * is a frontend that is mainly concerned with caching the answers.
 * In particular, the force_cache argument allows overriding the internal
 * heuristic about whether to cache negative answers; it should be "true"
 * if making an inquiry that is not part of the normal bottom-up join search
 * sequence.
 */
bool
innerrel_is_unique(PlannerInfo *root,
				   Relids joinrelids,
				   Relids outerrelids,
				   RelOptInfo *innerrel,
				   JoinType jointype,
				   List *restrictlist,
				   bool force_cache)
{
	return innerrel_is_unique_ext(root, joinrelids, outerrelids, innerrel,
								  jointype, restrictlist, force_cache, NULL);
}

/*
 * innerrel_is_unique_ext
 *	  Do the same as innerrel_is_unique(), but also return additional clauses
 *	  from a baserestrictinfo list that were used to prove uniqueness.
 */
bool
innerrel_is_unique_ext(PlannerInfo *root,
					   Relids joinrelids,
					   Relids outerrelids,
					   RelOptInfo *innerrel,
					   JoinType jointype,
					   List *restrictlist,
					   bool force_cache,
					   List **extra_clauses)
{
	MemoryContext old_context;
	ListCell   *lc;
	UniqueRelInfo *uniqueRelInfo;
	List	   *outer_exprs = NIL;

	/* Certainly can't prove uniqueness when there are no joinclauses */
	if (restrictlist == NIL)
		return false;

	/*
	 * Make a quick check to eliminate cases in which we will surely be unable
	 * to prove uniqueness of the innerrel.
	 */
	if (!rel_supports_distinctness(root, innerrel))
		return false;

	/*
	 * Query the cache to see if we've managed to prove that innerrel is
	 * unique for any subset of this outerrel.  We don't need an exact match,
	 * as extra outerrels can't make the innerrel any less unique (or more
	 * formally, the restrictlist for a join to a superset outerrel must be a
	 * superset of the conditions we successfully used before).
	 */
	foreach(lc, innerrel->unique_for_rels)
	{
		uniqueRelInfo = (UniqueRelInfo *) lfirst(lc);

		if (bms_is_subset(uniqueRelInfo->outerrelids, outerrelids))
		{
			if (extra_clauses)
				*extra_clauses = uniqueRelInfo->extra_clauses;
			return true;		/* Success! */
		}
	}

	/*
	 * Conversely, we may have already determined that this outerrel, or some
	 * superset thereof, cannot prove this innerrel to be unique.
	 */
	foreach(lc, innerrel->non_unique_for_rels)
	{
		Relids		unique_for_rels = (Relids) lfirst(lc);

		if (bms_is_subset(outerrelids, unique_for_rels))
			return false;
	}

	/* No cached information, so try to make the proof. */
	if (is_innerrel_unique_for(root, joinrelids, outerrelids, innerrel,
							   jointype, restrictlist, &outer_exprs))
	{
		/*
		 * Cache the positive result for future probes, being sure to keep it
		 * in the planner_cxt even if we are working in GEQO.
		 *
		 * Note: one might consider trying to isolate the minimal subset of
		 * the outerrels that proved the innerrel unique.  But it's not worth
		 * the trouble, because the planner builds up joinrels incrementally
		 * and so we'll see the minimally sufficient outerrels before any
		 * supersets of them anyway.
		 */
		old_context = MemoryContextSwitchTo(root->planner_cxt);
		uniqueRelInfo = makeNode(UniqueRelInfo);
		uniqueRelInfo->extra_clauses = outer_exprs;
		uniqueRelInfo->outerrelids = bms_copy(outerrelids);
		innerrel->unique_for_rels = lappend(innerrel->unique_for_rels,
											uniqueRelInfo);
		MemoryContextSwitchTo(old_context);

		if (extra_clauses)
			*extra_clauses = outer_exprs;
		return true;			/* Success! */
	}
	else
	{
		/*
		 * None of the join conditions for outerrel proved innerrel unique, so
		 * we can safely reject this outerrel or any subset of it in future
		 * checks.
		 *
		 * However, in normal planning mode, caching this knowledge is totally
		 * pointless; it won't be queried again, because we build up joinrels
		 * from smaller to larger.  It is useful in GEQO mode, where the
		 * knowledge can be carried across successive planning attempts; and
		 * it's likely to be useful when using join-search plugins, too. Hence
		 * cache when join_search_private is non-NULL.  (Yeah, that's a hack,
		 * but it seems reasonable.)
		 *
		 * Also, allow callers to override that heuristic and force caching;
		 * that's useful for reduce_unique_semijoins, which calls here before
		 * the normal join search starts.
		 */
		if (force_cache || root->join_search_private)
		{
			old_context = MemoryContextSwitchTo(root->planner_cxt);
			innerrel->non_unique_for_rels =
				lappend(innerrel->non_unique_for_rels,
						bms_copy(outerrelids));
			MemoryContextSwitchTo(old_context);
		}

		return false;
	}
}

/*
 * is_innerrel_unique_for
 *	  Check if the innerrel provably contains at most one tuple matching any
 *	  tuple from the outerrel, based on join clauses in the 'restrictlist'.
 */
static bool
is_innerrel_unique_for(PlannerInfo *root,
					   Relids joinrelids,
					   Relids outerrelids,
					   RelOptInfo *innerrel,
					   JoinType jointype,
					   List *restrictlist,
					   List **extra_clauses)
{
	List	   *clause_list = NIL;
	ListCell   *lc;

	/*
	 * Search for mergejoinable clauses that constrain the inner rel against
	 * the outer rel.  If an operator is mergejoinable then it behaves like
	 * equality for some btree opclass, so it's what we want.  The
	 * mergejoinability test also eliminates clauses containing volatile
	 * functions, which we couldn't depend on.
	 */
	foreach(lc, restrictlist)
	{
		RestrictInfo *restrictinfo = (RestrictInfo *) lfirst(lc);

		/*
		 * As noted above, if it's a pushed-down clause and we're at an outer
		 * join, we can't use it.
		 */
		if (IS_OUTER_JOIN(jointype) &&
			RINFO_IS_PUSHED_DOWN(restrictinfo, joinrelids))
			continue;

		/* Ignore if it's not a mergejoinable clause */
		if (!restrictinfo->can_join ||
			restrictinfo->mergeopfamilies == NIL)
			continue;			/* not mergejoinable */

		/*
		 * Check if the clause has the form "outer op inner" or "inner op
		 * outer", and if so mark which side is inner.
		 */
		if (!clause_sides_match_join(restrictinfo, outerrelids,
									 innerrel->relids))
			continue;			/* no good for these input relations */

		/* OK, add to the list */
		clause_list = lappend(clause_list, restrictinfo);
	}

	/* Let rel_is_distinct_for() do the hard work */
	return rel_is_distinct_for(root, innerrel, clause_list, extra_clauses);
}

/*
 * Replace each occurrence of removing relid with the keeping one
 */
static void
replace_varno(Node *node, int from, int to)
{
	ReplaceVarnoContext ctx;

	if (to <= 0)
		return;

	ctx.from = from;
	ctx.to = to;
	replace_varno_walker(node, &ctx);
}

/*
 * Walker function for replace_varno()
 */
static bool
replace_varno_walker(Node *node, ReplaceVarnoContext *ctx)
{
	if (node == NULL)
		return false;

	if (IsA(node, Var))
	{
		Var		   *var = (Var *) node;

		if (var->varno == ctx->from)
		{
			var->varno = ctx->to;
			var->varnosyn = ctx->to;
		}
		return false;
	}
	else if (IsA(node, PlaceHolderVar))
	{
		PlaceHolderVar *phv = (PlaceHolderVar *) node;

		phv->phrels = replace_relid(phv->phrels, ctx->from, ctx->to);
		phv->phnullingrels = replace_relid(phv->phnullingrels, ctx->from, ctx->to);

		/* fall through to recurse into the placeholder's expression */
	}
	else if (IsA(node, RestrictInfo))
	{
		RestrictInfo *rinfo = (RestrictInfo *) node;
		int			relid = -1;
		bool		is_req_equal =
			(rinfo->required_relids == rinfo->clause_relids);

		if (bms_is_member(ctx->from, rinfo->clause_relids))
		{
			replace_varno((Node *) rinfo->clause, ctx->from, ctx->to);
			replace_varno((Node *) rinfo->orclause, ctx->from, ctx->to);
			rinfo->clause_relids = replace_relid(rinfo->clause_relids, ctx->from, ctx->to);
			rinfo->left_relids = replace_relid(rinfo->left_relids, ctx->from, ctx->to);
			rinfo->right_relids = replace_relid(rinfo->right_relids, ctx->from, ctx->to);
		}

		if (is_req_equal)
			rinfo->required_relids = rinfo->clause_relids;
		else
			rinfo->required_relids = replace_relid(rinfo->required_relids, ctx->from, ctx->to);

		rinfo->outer_relids = replace_relid(rinfo->outer_relids, ctx->from, ctx->to);
		rinfo->incompatible_relids = replace_relid(rinfo->incompatible_relids, ctx->from, ctx->to);

		if (rinfo->mergeopfamilies &&
			bms_get_singleton_member(rinfo->clause_relids, &relid) &&
			relid == ctx->to && IsA(rinfo->clause, OpExpr))
		{
			Expr	   *leftOp;
			Expr	   *rightOp;

			leftOp = (Expr *) get_leftop(rinfo->clause);
			rightOp = (Expr *) get_rightop(rinfo->clause);

			if (leftOp != NULL && equal(leftOp, rightOp))
			{
				NullTest   *ntest = makeNode(NullTest);

				ntest->arg = leftOp;
				ntest->nulltesttype = IS_NOT_NULL;
				ntest->argisrow = false;
				ntest->location = -1;
				rinfo->clause = (Expr *) ntest;
				rinfo->mergeopfamilies = NIL;
			}
			Assert(rinfo->orclause == NULL);
		}

		return false;
	}
	return expression_tree_walker(node, replace_varno_walker, (void *) ctx);
}

/*
 * Substitute newId by oldId in relids.
 *
 * We must make a copy of the original Bitmapset before making any
 * modifications, because the same pointer to it might be shared among
 * different places.
 */
static Bitmapset *
replace_relid(Relids relids, int oldId, int newId)
{
	if (oldId < 0)
		return relids;

	/* Delete relid without substitution. */
	if (newId < 0)
		return bms_del_member(bms_copy(relids), oldId);

	/* Substitute newId for oldId. */
	if (bms_is_member(oldId, relids))
		return bms_add_member(bms_del_member(bms_copy(relids), oldId), newId);

	return relids;
}

/*
 * Update EC members to point to the remaining relation instead of the removed
 * one, removing duplicates.
 *
 * Restriction clauses for base relations are already distributed to
 * the respective baserestrictinfo lists (see
 * generate_implied_equalities_for_column). The above code has already processed
 * this list, and updated these clauses to reference the remaining
 * relation, so we can skip them here based on their relids.
 *
 * Likewise, we have already processed the join clauses that join the
 * removed relation to the remaining one.
 *
 * Finally, there are join clauses that join the removed relation to
 * some third relation. We can't just delete the source clauses and
 * regenerate them from the EC because the corresponding equality
 * operators might be missing (see the handling of ec_broken).
 * Therefore, we will update the references in the source clauses.
 *
 * Derived clauses can be generated again, so it is simpler to just
 * delete them.
 */
static void
update_eclasses(EquivalenceClass *ec, int from, int to)
{
	List	   *new_members = NIL;
	List	   *new_sources = NIL;
	ListCell   *lc;
	ListCell   *lc1;

	foreach(lc, ec->ec_members)
	{
		EquivalenceMember *em = lfirst_node(EquivalenceMember, lc);
		bool		is_redundant = false;

		if (!bms_is_member(from, em->em_relids))
		{
			new_members = lappend(new_members, em);
			continue;
		}

		em->em_relids = replace_relid(em->em_relids, from, to);
		em->em_jdomain->jd_relids = replace_relid(em->em_jdomain->jd_relids, from, to);

		/* We only process inner joins */
		replace_varno((Node *) em->em_expr, from, to);

		foreach(lc1, new_members)
		{
			EquivalenceMember *other = lfirst_node(EquivalenceMember, lc1);

			if (!equal(em->em_relids, other->em_relids))
				continue;

			if (equal(em->em_expr, other->em_expr))
			{
				is_redundant = true;
				break;
			}
		}

		if (!is_redundant)
			new_members = lappend(new_members, em);
	}

	list_free(ec->ec_members);
	ec->ec_members = new_members;

	list_free(ec->ec_derives);
	ec->ec_derives = NULL;

	/* Update EC source expressions */
	foreach(lc, ec->ec_sources)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);
		bool		is_redundant = false;

		if (!bms_is_member(from, rinfo->required_relids))
		{
			new_sources = lappend(new_sources, rinfo);
			continue;
		}

		replace_varno((Node *) rinfo, from, to);

		/*
		 * After switching the clause to the remaining relation, check it for
		 * redundancy with existing ones. We don't have to check for
		 * redundancy with derived clauses, because we've just deleted them.
		 */
		foreach(lc1, new_sources)
		{
			RestrictInfo *other = lfirst_node(RestrictInfo, lc1);

			if (!equal(rinfo->clause_relids, other->clause_relids))
				continue;

			if (equal(rinfo->clause, other->clause))
			{
				is_redundant = true;
				break;
			}
		}

		if (!is_redundant)
			new_sources = lappend(new_sources, rinfo);
	}

	list_free(ec->ec_sources);
	ec->ec_sources = new_sources;
	ec->ec_relids = replace_relid(ec->ec_relids, from, to);
}

/*
 * Remove a relation after we have proven that it participates only in an
 * unneeded unique self join.
 *
 * Replace any links in planner info structures.
 *
 * Transfer join and restriction clauses from the removed relation to the
 * remaining one. We change the Vars of the clause to point to the
 * remaining relation instead of the removed one. The clauses that require
 * a subset of joinrelids become restriction clauses of the remaining
 * relation, and others remain join clauses. We append them to
 * baserestrictinfo and joininfo respectively, trying not to introduce
 * duplicates.
 *
 * We also have to process the 'joinclauses' list here, because it
 * contains EC-derived join clauses which must become filter clauses. It
 * is not enough to just correct the ECs because the EC-derived
 * restrictions are generated before join removal (see
 * generate_base_implied_equalities).
 */
static void
remove_self_join_rel(PlannerInfo *root, PlanRowMark *kmark, PlanRowMark *rmark,
					 RelOptInfo *toKeep, RelOptInfo *toRemove,
					 List *restrictlist)
{
	List	   *joininfos;
	ListCell   *lc;
	int			i;
	List	   *jinfo_candidates = NIL;
	List	   *binfo_candidates = NIL;
	ReplaceVarnoContext ctx = {.from = toRemove->relid,.to = toKeep->relid};

	Assert(toKeep->relid != -1);

	/*
	 * Replace the index of the removing table with the keeping one. The
	 * technique of removing/distributing restrictinfo is used here to attach
	 * just appeared (for keeping relation) join clauses and avoid adding
	 * duplicates of those that already exist in the joininfo list.
	 */
	joininfos = list_copy(toRemove->joininfo);
	foreach(lc, joininfos)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);

		remove_join_clause_from_rels(root, rinfo, rinfo->required_relids);
		replace_varno((Node *) rinfo, toRemove->relid, toKeep->relid);

		if (bms_membership(rinfo->required_relids) == BMS_MULTIPLE)
			jinfo_candidates = lappend(jinfo_candidates, rinfo);
		else
			binfo_candidates = lappend(binfo_candidates, rinfo);
	}

	/*
	 * Concatenate restrictlist to the list of base restrictions of the
	 * removing table just to simplify the replacement procedure: all of them
	 * weren't connected to any keeping relations and need to be added to some
	 * rels.
	 */
	toRemove->baserestrictinfo = list_concat(toRemove->baserestrictinfo,
											 restrictlist);
	foreach(lc, toRemove->baserestrictinfo)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);

		replace_varno((Node *) rinfo, toRemove->relid, toKeep->relid);

		if (bms_membership(rinfo->required_relids) == BMS_MULTIPLE)
			jinfo_candidates = lappend(jinfo_candidates, rinfo);
		else
			binfo_candidates = lappend(binfo_candidates, rinfo);
	}

	/*
	 * Now, add all non-redundant clauses to the keeping relation.
	 * Contradictory operation. On the one side, we reduce the length of
	 * restrict lists that can impact planning or executing time.
	 * Additionally, we improve the accuracy of cardinality estimation. On the
	 * other side, it is one more place that can make planning time much
	 * longer in specific cases. It would have been better to avoid calling
	 * the equal() function here, but it's the only way to detect duplicated
	 * inequality expressions.
	 */
	foreach(lc, binfo_candidates)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);
		ListCell   *olc = NULL;
		bool		is_redundant = false;

		Assert(!bms_is_member(toRemove->relid, rinfo->required_relids));

		foreach(olc, toKeep->baserestrictinfo)
		{
			RestrictInfo *src = lfirst_node(RestrictInfo, olc);

			if (!bms_equal(src->clause_relids, rinfo->clause_relids))
				/* Const and non-const expressions can't be equal */
				continue;

			if (src == rinfo ||
				(rinfo->parent_ec != NULL
				 && src->parent_ec == rinfo->parent_ec)
				|| equal(rinfo->clause, src->clause))
			{
				is_redundant = true;
				break;
			}
		}
		if (!is_redundant)
			distribute_restrictinfo_to_rels(root, rinfo);
	}
	foreach(lc, jinfo_candidates)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);
		ListCell   *olc = NULL;
		bool		is_redundant = false;

		Assert(!bms_is_member(toRemove->relid, rinfo->required_relids));

		foreach(olc, toKeep->joininfo)
		{
			RestrictInfo *src = lfirst_node(RestrictInfo, olc);

			if (!bms_equal(src->clause_relids, rinfo->clause_relids))
				/* Can't compare trivially different clauses */
				continue;

			if (src == rinfo ||
				(rinfo->parent_ec != NULL
				 && src->parent_ec == rinfo->parent_ec)
				|| equal(rinfo->clause, src->clause))
			{
				is_redundant = true;
				break;
			}
		}
		if (!is_redundant)
			distribute_restrictinfo_to_rels(root, rinfo);
	}
	list_free(binfo_candidates);
	list_free(jinfo_candidates);

	/*
	 * Arrange equivalence classes, mentioned removing a table, with the
	 * keeping one: varno of removing table should be replaced in members and
	 * sources lists. Also, remove duplicated elements if this replacement
	 * procedure created them.
	 */
	i = -1;
	while ((i = bms_next_member(toRemove->eclass_indexes, i)) >= 0)
	{
		EquivalenceClass *ec = (EquivalenceClass *) list_nth(root->eq_classes, i);

		update_eclasses(ec, toRemove->relid, toKeep->relid);
		toKeep->eclass_indexes = bms_add_member(toKeep->eclass_indexes, i);
	}

	/*
	 * Transfer the targetlist and attr_needed flags.
	 */

	foreach(lc, toRemove->reltarget->exprs)
	{
		Node	   *node = lfirst(lc);

		replace_varno(node, toRemove->relid, toKeep->relid);
		if (!list_member(toKeep->reltarget->exprs, node))
			toKeep->reltarget->exprs = lappend(toKeep->reltarget->exprs, node);
	}

	for (i = toKeep->min_attr; i <= toKeep->max_attr; i++)
	{
		int			attno = i - toKeep->min_attr;

		toRemove->attr_needed[attno] = replace_relid(toRemove->attr_needed[attno],
													 toRemove->relid, toKeep->relid);
		toKeep->attr_needed[attno] = bms_add_members(toKeep->attr_needed[attno],
													 toRemove->attr_needed[attno]);
	}

	/*
	 * If the removed relation has a row mark, transfer it to the remaining
	 * one.
	 *
	 * If both rels have row marks, just keep the one corresponding to the
	 * remaining relation, because we verified earlier that they have the same
	 * strength.
	 */
	if (rmark)
	{
		if (kmark)
		{
			Assert(kmark->markType == rmark->markType);

			root->rowMarks = list_delete_ptr(root->rowMarks, rmark);
		}
		else
		{
			/* Shouldn't have inheritance children here. */
			Assert(rmark->rti == rmark->prti);

			rmark->rti = rmark->prti = toKeep->relid;
		}
	}

	/* Replace varno in all the query structures */
	query_tree_walker(root->parse, replace_varno_walker, &ctx,
					  QTW_EXAMINE_SORTGROUP);

	/* Replace links in the planner info */
	remove_rel_from_query(root, toRemove, toKeep->relid, NULL, NULL);

	/* At last, replace varno in root targetlist and HAVING clause */
	replace_varno((Node *) root->processed_tlist,
				  toRemove->relid, toKeep->relid);
	replace_varno((Node *) root->processed_groupClause,
				  toRemove->relid, toKeep->relid);

	/*
	 * There may be references to the rel in root->fkey_list, but if so,
	 * match_foreign_keys_to_quals() will get rid of them.
	 */

	/*
	 * Finally, remove the rel from the baserel array to prevent it from being
	 * referenced again.  (We can't do this earlier because
	 * remove_join_clause_from_rels will touch it.)
	 */
	root->simple_rel_array[toRemove->relid] = NULL;

	/* And nuke the RelOptInfo, just in case there's another access path */
	pfree(toRemove);
}

/*
 * split_selfjoin_quals
 *		Processes 'joinquals' by building two lists: one containing the quals
 *		where the columns/exprs are on either side of the join match, and
 *		another one containing the remaining quals.
 *
 * 'joinquals' must only contain quals for a RTE_RELATION being joined to
 * itself.
 */
static void
split_selfjoin_quals(PlannerInfo *root, List *joinquals, List **selfjoinquals,
					 List **otherjoinquals, int from, int to)
{
	ListCell   *lc;
	List	   *sjoinquals = NIL;
	List	   *ojoinquals = NIL;

	foreach(lc, joinquals)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);
		OpExpr	   *expr;
		Node	   *leftexpr;
		Node	   *rightexpr;

		/* In general, clause looks like F(arg1) = G(arg2) */
		if (!rinfo->mergeopfamilies ||
			bms_num_members(rinfo->clause_relids) != 2 ||
			bms_membership(rinfo->left_relids) != BMS_SINGLETON ||
			bms_membership(rinfo->right_relids) != BMS_SINGLETON)
		{
			ojoinquals = lappend(ojoinquals, rinfo);
			continue;
		}

		expr = (OpExpr *) rinfo->clause;

		if (!IsA(expr, OpExpr) || list_length(expr->args) != 2)
		{
			ojoinquals = lappend(ojoinquals, rinfo);
			continue;
		}

		leftexpr = get_leftop(rinfo->clause);
		rightexpr = copyObject(get_rightop(rinfo->clause));

		if (leftexpr && IsA(leftexpr, RelabelType))
			leftexpr = (Node *) ((RelabelType *) leftexpr)->arg;
		if (rightexpr && IsA(rightexpr, RelabelType))
			rightexpr = (Node *) ((RelabelType *) rightexpr)->arg;

		/*
		 * Quite an expensive operation, narrowing the use case. For example,
		 * when we have cast of the same var to different (but compatible)
		 * types.
		 */
		replace_varno(rightexpr, bms_singleton_member(rinfo->right_relids),
					  bms_singleton_member(rinfo->left_relids));

		if (equal(leftexpr, rightexpr))
			sjoinquals = lappend(sjoinquals, rinfo);
		else
			ojoinquals = lappend(ojoinquals, rinfo);
	}

	*selfjoinquals = sjoinquals;
	*otherjoinquals = ojoinquals;
}

/*
 * Check for a case when uniqueness is at least partly derived from a
 * baserestrictinfo clause. In this case, we have a chance to return only
 * one row (if such clauses on both sides of SJ are equal) or nothing (if they
 * are different).
 */
static bool
match_unique_clauses(PlannerInfo *root, RelOptInfo *outer, List *uclauses,
					 Index relid)
{
	ListCell   *lc;

	foreach(lc, uclauses)
	{
		RestrictInfo *rinfo = lfirst_node(RestrictInfo, lc);
		Expr	   *clause;
		Node	   *iclause;
		Node	   *c1;
		bool		matched = false;
		ListCell   *olc;

		Assert(outer->relid > 0 && relid > 0);

		/* Only filters like f(R.x1,...,R.xN) == expr we should consider. */
		Assert(bms_is_empty(rinfo->left_relids) ^
			   bms_is_empty(rinfo->right_relids));

		clause = (Expr *) copyObject(rinfo->clause);
		replace_varno((Node *) clause, relid, outer->relid);

		iclause = bms_is_empty(rinfo->left_relids) ? get_rightop(clause) :
			get_leftop(clause);
		c1 = bms_is_empty(rinfo->left_relids) ? get_leftop(clause) :
			get_rightop(clause);

		/*
		 * Compare these left and right sides with the corresponding sides of
		 * the outer's filters. If no one is detected - return immediately.
		 */
		foreach(olc, outer->baserestrictinfo)
		{
			RestrictInfo *orinfo = lfirst_node(RestrictInfo, olc);
			Node	   *oclause;
			Node	   *c2;

			if (orinfo->mergeopfamilies == NIL)
				/* Don't consider clauses which aren't similar to 'F(X)=G(Y)' */
				continue;

			Assert(is_opclause(orinfo->clause));

			oclause = bms_is_empty(orinfo->left_relids) ?
				get_rightop(orinfo->clause) : get_leftop(orinfo->clause);
			c2 = (bms_is_empty(orinfo->left_relids) ?
				  get_leftop(orinfo->clause) : get_rightop(orinfo->clause));

			if (equal(iclause, oclause) && equal(c1, c2))
			{
				matched = true;
				break;
			}
		}

		if (!matched)
			return false;
	}

	return true;
}

/*
 * Find and remove unique self joins in a group of base relations that have
 * the same Oid.
 *
 * Returns a set of relids that were removed.
 */
static Relids
remove_self_joins_one_group(PlannerInfo *root, Relids relids)
{
	Relids		result = NULL;
	int			k;				/* Index of kept relation */
	int			r = -1;			/* Index of removed relation */

	while ((r = bms_next_member(relids, r)) > 0)
	{
		RelOptInfo *inner = root->simple_rel_array[r];

		k = r;

		while ((k = bms_next_member(relids, k)) > 0)
		{
			Relids		joinrelids = NULL;
			RelOptInfo *outer = root->simple_rel_array[k];
			List	   *restrictlist;
			List	   *selfjoinquals;
			List	   *otherjoinquals;
			ListCell   *lc;
			bool		jinfo_check = true;
			PlanRowMark *omark = NULL;
			PlanRowMark *imark = NULL;
			List	   *uclauses = NIL;

			/* A sanity check: the relations have the same Oid. */
			Assert(root->simple_rte_array[k]->relid ==
				   root->simple_rte_array[r]->relid);

			/*
			 * It is impossible to eliminate join of two relations if they
			 * belong to different rules of order. Otherwise planner can't be
			 * able to find any variants of correct query plan.
			 */
			foreach(lc, root->join_info_list)
			{
				SpecialJoinInfo *info = (SpecialJoinInfo *) lfirst(lc);

				if ((bms_is_member(k, info->syn_lefthand) ^
					 bms_is_member(r, info->syn_lefthand)) ||
					(bms_is_member(k, info->syn_righthand) ^
					 bms_is_member(r, info->syn_righthand)))
				{
					jinfo_check = false;
					break;
				}
			}
			if (!jinfo_check)
				continue;

			/*
			 * Check Row Marks equivalence.  We can't remove the join if the
			 * relations have row marks of different strength (e.g. one is
			 * locked FOR UPDATE and another just has ROW_MARK_REFERENCE for
			 * EvalPlanQual rechecking).
			 */
			foreach(lc, root->rowMarks)
			{
				PlanRowMark *rowMark = (PlanRowMark *) lfirst(lc);

				if (rowMark->rti == k)
				{
					Assert(imark == NULL);
					imark = rowMark;
				}
				else if (rowMark->rti == r)
				{
					Assert(omark == NULL);
					omark = rowMark;
				}

				if (omark && imark)
					break;
			}
			if (omark && imark && omark->markType != imark->markType)
				continue;

			/*
			 * We only deal with base rels here, so their relids bitset
			 * contains only one member -- their relid.
			 */
			joinrelids = bms_add_member(joinrelids, r);
			joinrelids = bms_add_member(joinrelids, k);

			/*
			 * PHVs should not impose any constraints on removing self joins.
			 */

			/*
			 * At this stage, joininfo lists of inner and outer can contain
			 * only clauses, required for a superior outer join that can't
			 * influence this optimization. So, we can avoid to call the
			 * build_joinrel_restrictlist() routine.
			 */
			restrictlist = generate_join_implied_equalities(root, joinrelids,
															inner->relids,
															outer, NULL);

			/*
			 * Process restrictlist to separate the self join quals out of the
			 * other quals. e.g x = x goes to selfjoinquals and a = b to
			 * otherjoinquals.
			 */
			split_selfjoin_quals(root, restrictlist, &selfjoinquals,
								 &otherjoinquals, inner->relid, outer->relid);

			/*
			 * To enable SJE for the only degenerate case without any self
			 * join clauses at all, add baserestrictinfo to this list. The
			 * degenerate case works only if both sides have the same clause.
			 * So doesn't matter which side to add.
			 */
			selfjoinquals = list_concat(selfjoinquals, outer->baserestrictinfo);

			/*
			 * Determine if the inner table can duplicate outer rows.  We must
			 * bypass the unique rel cache here since we're possibly using a
			 * subset of join quals. We can use 'force_cache' == true when all
			 * join quals are self-join quals.  Otherwise, we could end up
			 * putting false negatives in the cache.
			 */
			if (!innerrel_is_unique_ext(root, joinrelids, inner->relids,
										outer, JOIN_INNER, selfjoinquals,
										list_length(otherjoinquals) == 0,
										&uclauses))
				continue;

			/*
			 * We have proven that for both relations, the same unique index
			 * guarantees that there is at most one row where columns equal
			 * given values. These values must be the same for both relations,
			 * or else we won't match the same row on each side of the join.
			 */
			if (!match_unique_clauses(root, inner, uclauses, outer->relid))
				continue;

			/*
			 * We can remove either relation, so remove the inner one in order
			 * to simplify this loop.
			 */
			remove_self_join_rel(root, omark, imark, outer, inner, restrictlist);

			result = bms_add_member(result, r);

			/* We have removed the outer relation, try the next one. */
			break;
		}
	}

	return result;
}

/*
 * Gather indexes of base relations from the joinlist and try to eliminate self
 * joins.
 */
static Relids
remove_self_joins_recurse(PlannerInfo *root, List *joinlist, Relids toRemove)
{
	ListCell   *jl;
	Relids		relids = NULL;
	SelfJoinCandidate *candidates = NULL;
	int			i;
	int			j;
	int			numRels;

	/* Collect indexes of base relations of the join tree */
	foreach(jl, joinlist)
	{
		Node	   *jlnode = (Node *) lfirst(jl);

		if (IsA(jlnode, RangeTblRef))
		{
			RangeTblRef *ref = (RangeTblRef *) jlnode;
			RangeTblEntry *rte = root->simple_rte_array[ref->rtindex];

			/*
			 * We only care about base relations from which we select
			 * something.
			 */
			if (rte->rtekind == RTE_RELATION &&
				rte->relkind == RELKIND_RELATION &&
				root->simple_rel_array[ref->rtindex] != NULL)
			{
				Assert(!bms_is_member(ref->rtindex, relids));
				relids = bms_add_member(relids, ref->rtindex);
			}
		}
		else if (IsA(jlnode, List))
			/* Recursively go inside the sub-joinlist */
			toRemove = remove_self_joins_recurse(root, (List *) jlnode,
												 toRemove);
		else
			elog(ERROR, "unrecognized joinlist node type: %d",
				 (int) nodeTag(jlnode));
	}

	numRels = bms_num_members(relids);

	/* Need at least two relations for the join */
	if (numRels < 2)
		return toRemove;

	/*
	 * In order to find relations with the same oid we first build an array of
	 * candidates and then sort it by oid.
	 */
	candidates = (SelfJoinCandidate *) palloc(sizeof(SelfJoinCandidate) *
											  numRels);
	i = -1;
	j = 0;
	while ((i = bms_next_member(relids, i)) >= 0)
	{
		candidates[j].relid = i;
		candidates[j].reloid = root->simple_rte_array[i]->relid;
		j++;
	}

	pg_qsort(candidates, numRels, sizeof(SelfJoinCandidate),
			 self_join_candidates_cmp);

	/*
	 * Iteratively form a group of relation indexes with the same oid and
	 * launch the routine that detects self-joins in this group and removes
	 * excessive range table entries.
	 *
	 * At the end of the iteration, exclude the group from the overall relids
	 * list. So each next iteration of the cycle will involve less and less
	 * value of relids.
	 */
	i = 0;
	for (j = 1; j < numRels + 1; j++)
	{
		if (j == numRels || candidates[j].reloid != candidates[i].reloid)
		{
			if (j - i >= 2)
			{
				/* Create a group of relation indexes with the same oid */
				Relids		group = NULL;
				Relids		removed;

				while (i < j)
				{
					group = bms_add_member(group, candidates[i].relid);
					i++;
				}

				relids = bms_del_members(relids, group);

				/*
				 * Try to remove self-joins from a group of identical entries.
				 * Make the next attempt iteratively - if something is deleted
				 * from a group, changes in clauses and equivalence classes
				 * can give us a chance to find more candidates.
				 */
				do
				{
					Assert(!bms_overlap(group, toRemove));
					removed = remove_self_joins_one_group(root, group);
					toRemove = bms_add_members(toRemove, removed);
					group = bms_del_members(group, removed);
				} while (!bms_is_empty(removed) &&
						 bms_membership(group) == BMS_MULTIPLE);
				bms_free(removed);
				bms_free(group);
			}
			else
			{
				/* Single relation, just remove it from the set */
				relids = bms_del_member(relids, candidates[i].relid);
				i = j;
			}
		}
	}

	Assert(bms_is_empty(relids));

	return toRemove;
}

/*
 * Compare self-join candidates by their oids.
 */
static int
self_join_candidates_cmp(const void *a, const void *b)
{
	const SelfJoinCandidate *ca = (const SelfJoinCandidate *) a;
	const SelfJoinCandidate *cb = (const SelfJoinCandidate *) b;

	if (ca->reloid != cb->reloid)
		return (ca->reloid < cb->reloid ? -1 : 1);
	else
		return 0;
}

/*
 * Find and remove useless self joins.
 *
 * Search for joins where a relation is joined to itself. If the join clause
 * for each tuple from one side of the join is proven to match the same
 * physical row (or nothing) on the other side, that self-join can be
 * eliminated from the query.  Suitable join clauses are assumed to be in the
 * form of X = X, and can be replaced with NOT NULL clauses.
 *
 * For the sake of simplicity, we don't apply this optimization to special
 * joins. Here is a list of what we could do in some particular cases:
 * 'a a1 semi join a a2': is reduced to inner by reduce_unique_semijoins,
 * and then removed normally.
 * 'a a1 anti join a a2': could simplify to a scan with 'outer quals AND
 * (IS NULL on join columns OR NOT inner quals)'.
 * 'a a1 left join a a2': could simplify to a scan like inner but without
 * NOT NULL conditions on join columns.
 * 'a a1 left join (a a2 join b)': can't simplify this, because join to b
 * can both remove rows and introduce duplicates.
 *
 * To search for removable joins, we order all the relations on their Oid,
 * go over each set with the same Oid, and consider each pair of relations
 * in this set.
 *
 * To remove the join, we mark one of the participating relations as dead
 * and rewrite all references to it to point to the remaining relation.
 * This includes modifying RestrictInfos, EquivalenceClasses, and
 * EquivalenceMembers. We also have to modify the row marks. The join clauses
 * of the removed relation become either restriction or join clauses, based on
 * whether they reference any relations not participating in the removed join.
 *
 * 'targetlist' is the top-level targetlist of the query. If it has any
 * references to the removed relations, we update them to point to the
 * remaining ones.
 */
List *
remove_useless_self_joins(PlannerInfo *root, List *joinlist)
{
	Relids		toRemove = NULL;
	int			relid = -1;

	if (!enable_self_join_removal || joinlist == NIL ||
		(list_length(joinlist) == 1 && !IsA(linitial(joinlist), List)))
		return joinlist;

	/*
	 * Merge pairs of relations participated in self-join. Remove unnecessary
	 * range table entries.
	 */
	toRemove = remove_self_joins_recurse(root, joinlist, toRemove);

	if (unlikely(toRemove != NULL))
	{
		int			nremoved = 0;

		/* At the end, remove orphaned relation links */
		while ((relid = bms_next_member(toRemove, relid)) >= 0)
			joinlist = remove_rel_from_joinlist(joinlist, relid, &nremoved);
	}

	return joinlist;
}
