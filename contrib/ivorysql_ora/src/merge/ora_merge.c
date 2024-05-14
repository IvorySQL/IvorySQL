/*------------------------------------------------------------------
 *
 * Compatible with Oracle's Merge command.
 *
 * Copyright (c) 2023, Ivory SQL Global Development Team
 *
 * contrib/ivorysql_ora/src/merge/ora_merge.c
 *
 * add the file for requirement "SQL MERGE"
 *
 *------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "access/tableam.h"
#include "access/xact.h"
#include "access/multixact.h"
#include "access/subtrans.h"
#include "access/transam.h"
#include "access/xlog.h"
#include "access/xloginsert.h"
#include "access/sysattr.h"
#include "access/visibilitymapdefs.h"
#include "access/heapam_xlog.h"
#include "access/visibilitymap.h"
#include "access/heaptoast.h"
#include "catalog/catalog.h"
#include "commands/trigger.h"
#include "executor/execPartition.h"
#include "executor/executor.h"
#include "executor/nodeModifyTable.h"
#include "foreign/fdwapi.h"
#include "miscadmin.h"
#include "nodes/nodeFuncs.h"
#include "nodes/makefuncs.h"
#include "nodes/execnodes.h"
#include "rewrite/rewriteHandler.h"
#include "storage/bufmgr.h"
#include "storage/lmgr.h"
#include "storage/predicate.h"
#include "storage/procarray.h"
#include "pgstat.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/combocid.h"
#include "utils/snapmgr.h"
#include "utils/inval.h"
#include "utils/relcache.h"
#include "parser/analyze.h"
#include "parser/parse_collate.h"
#include "parser/parsetree.h"
#include "parser/parser.h"
#include "parser/parse_clause.h"
#include "parser/parse_cte.h"
#include "parser/parse_expr.h"
#include "parser/parse_merge.h"
#include "parser/parse_relation.h"
#include "parser/parse_target.h"
#include "optimizer/prep.h"
#include "optimizer/optimizer.h"
#include "access/heapam.h"

#include "../include/ivorysql_ora.h"
#include "nodes/nodes.h"


static TM_Result execDelete4Merge(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, bool changingPart);
static TM_Result heapDelete4Merge(Relation relation, ItemPointer tid,
							CommandId cid, Snapshot crosscheck, bool wait,
							TM_FailureData *tmfd, bool changingPart);
static TM_Result heapTupleSatisfiesUpdate4Merge(HeapTuple htup, CommandId curcid,
							Buffer buffer);

/*
 * IvyExecMergeMatched:
 *
 * execute oracle Merge UPDATE/UPDATE
 */
bool
IvyExecMergeMatched(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
				  ItemPointer tupleid, bool canSetTag)
{
	ModifyTableState *mtstate = context->mtstate;
	TupleTableSlot *newslot;
	EState 	*estate = context->estate;
	ExprContext *econtext = mtstate->ps.ps_ExprContext;
	bool		 isNull;
	EPQState	*epqstate = &mtstate->mt_epqstate;
	ListCell	*l;

	/*
	 * If there are no WHEN MATCHED actions, we are done.
	 */
	if (resultRelInfo->ri_matchedMergeAction == NIL)
		return true;

	/*
	 * Make tuple and any needed join variables available to ExecQual and
	 * ExecProject. The target's existing tuple is installed in the scantuple.
	 * Again, this target relation's slot is required only in the case of a
	 * MATCHED tuple and UPDATE/DELETE actions.
	 */
	econtext->ecxt_scantuple = resultRelInfo->ri_oldTupleSlot;
	econtext->ecxt_innertuple = context->planSlot;
	econtext->ecxt_outertuple = NULL;

lmerge_matched:;

	/*
	 * This routine is only invoked for matched rows, and we must have found
	 * the tupleid of the target row in that case; fetch that tuple.
	 *
	 * We use SnapshotAny for this because we might get called again after
	 * EvalPlanQual returns us a new tuple, which may not be visible to our
	 * MVCC snapshot.
	 */

	if (!table_tuple_fetch_row_version(resultRelInfo->ri_RelationDesc,
										tupleid,
										SnapshotAny,
										resultRelInfo->ri_oldTupleSlot))
		elog(ERROR, "failed to fetch the target tuple");

	foreach(l, resultRelInfo->ri_matchedMergeAction)
	{
		MergeActionState *relaction = (MergeActionState *) lfirst(l);
		CmdType	 commandType = relaction->mas_action->commandType;
		TM_Result	 result;
		UpdateContext updateCxt = {0};

		/*
		 * Test condition, if any.
		 *
		 * In the absence of any condition, we perform the action
		 * unconditionally (no need to check separately since ExecQual() will
		 * return true if there are no conditions to evaluate).
		 */
		if (!ExecQual(relaction->mas_whenqual, econtext))
			continue;

		/*
		 * Check if the existing target tuple meets the USING checks of
		 * UPDATE/DELETE RLS policies. If those checks fail, we throw an
		 * error.
		 *
		 * The WITH CHECK quals are applied in ExecUpdate() and hence we need
		 * not do anything special to handle them.
		 *
		 * NOTE: We must do this after WHEN quals are evaluated, so that we
		 * check policies only when they matter.
		 */
		if (resultRelInfo->ri_WithCheckOptions)
		{
			ExecWithCheckOptions(commandType == CMD_UPDATE ?
						  WCO_RLS_MERGE_UPDATE_CHECK : WCO_RLS_MERGE_DELETE_CHECK,
						  resultRelInfo,
						  resultRelInfo->ri_oldTupleSlot,
						  context->mtstate->ps.state);
		}

		/* Perform stated action */
		switch (commandType)
		{
			case CMD_UPDATE:
			{
				MergeActionState *del;
				ListCell		  *ld = lnext(resultRelInfo->ri_matchedMergeAction, l);

				/*
				 * Project the output tuple, and use that to update the table.
				 * We don't need to filter out junk attributes, because the
				 * UPDATE action's targetlist doesn't have any.
				 */
				newslot = ExecProject(relaction->mas_proj);

				context->relaction = relaction;
				context->cpUpdateRetrySlot = NULL;

				/* Fire row-level before update trigger */
				if (!ExecUpdatePrologue(context, resultRelInfo,
										 tupleid, NULL, newslot, NULL))
				{
					result = TM_Ok;
					break;
				}

				result = ExecUpdateAct(context, resultRelInfo, tupleid, NULL,
										 newslot, mtstate->canSetTag, &updateCxt);
				if (result == TM_Ok && updateCxt.updated)
				{
					/* Fire row-level after update trigger */
					ExecUpdateEpilogue(context, &updateCxt, resultRelInfo,
										 tupleid, NULL, newslot);
					mtstate->mt_merge_updated += 1;

					if (canSetTag)
						(estate->es_processed)++;
				}

				if (ld)
				{
					del = (MergeActionState *) lfirst(ld);
					if (del->mas_action->commandType == CMD_DELETE)
					{
						econtext->ecxt_scantuple = newslot;
						if (ExecQual(del->mas_whenqual, econtext))
						{
							/* Fire row-level before delete trigger */
							if (!ExecDeletePrologue(context, resultRelInfo, &newslot->tts_tid, NULL, NULL, NULL))
							{
								result = TM_Ok;
								break;
							}
							result = execDelete4Merge(context, resultRelInfo, &newslot->tts_tid, false);
							if (result == TM_Ok)
							{
								/* Fire row-level after delete trigger */
								ExecDeleteEpilogue(context, resultRelInfo, &newslot->tts_tid, NULL, false);
								mtstate->mt_merge_deleted += 1;
							}
						}
						else
						{
							econtext->ecxt_scantuple = resultRelInfo->ri_oldTupleSlot;
						}
					}
				}
			}
				break;

			case CMD_DELETE:
				 result = TM_Ok;
				 break;

			case CMD_NOTHING:
				/* Doing nothing is always OK */
				result = TM_Ok;
				break;

			default:
				elog(ERROR, "unknown action in MERGE WHEN MATCHED clause");
		}

		switch (result)
		{
			case TM_Ok:
				break;

			case TM_SelfModified:

				/*
				 * The SQL standard disallows this for MERGE.
				 */
				if (TransactionIdIsCurrentTransactionId(context->tmfd.xmax))
					ereport(ERROR,
							(errcode(ERRCODE_CARDINALITY_VIOLATION),
					/* translator: %s is a SQL command name */
							 errmsg("%s command cannot affect row a second time",
									 "MERGE"),
							 errhint("Ensure that not more than one source row matches any one target row.")));
				/* This shouldn't happen */
				elog(ERROR, "attempted to update or delete invisible tuple");
				break;

			case TM_Deleted:
				if (IsolationUsesXactSnapshot())
					ereport(ERROR,
							(errcode(ERRCODE_T_R_SERIALIZATION_FAILURE),
							 errmsg("could not serialize access due to concurrent delete")));

				/*
				 * If the tuple was already deleted, return to let caller
				 * handle it under NOT MATCHED clauses.
				 */
				return false;

			case TM_Updated:
				{
					Relation	 resultRelationDesc;
					TupleTableSlot *epqslot,
								*inputslot;
					LockTupleMode lockmode;

					/*
					 * The target tuple was concurrently updated by some other
					 * transaction.
					 */

					/*
					 * If cpUpdateRetrySlot is set, ExecCrossPartitionUpdate()
					 * must have detected that the tuple was concurrently
					 * updated, so we restart the search for an appropriate
					 * WHEN MATCHED clause to process the updated tuple.
					 *
					 * In this case, ExecDelete() would already have performed
					 * EvalPlanQual() on the latest version of the tuple,
					 * which in turn would already have been loaded into
					 * ri_oldTupleSlot, so no need to do either of those
					 * things.
					 *
					 * XXX why do we not check the WHEN NOT MATCHED list in
					 * this case?
					 */
					if (!TupIsNull(context->cpUpdateRetrySlot))
						goto lmerge_matched;

					/*
					 * Otherwise, we run the EvalPlanQual() with the new
					 * version of the tuple. If EvalPlanQual() does not return
					 * a tuple, then we switch to the NOT MATCHED list of
					 * actions. If it does return a tuple and the join qual is
					 * still satisfied, then we just need to recheck the
					 * MATCHED actions, starting from the top, and execute the
					 * first qualifying action.
					 */
					resultRelationDesc = resultRelInfo->ri_RelationDesc;
					lockmode = ExecUpdateLockMode(estate, resultRelInfo);

					inputslot = EvalPlanQualSlot(epqstate, resultRelationDesc,
												 resultRelInfo->ri_RangeTableIndex);

					result = table_tuple_lock(resultRelationDesc, tupleid,
											  estate->es_snapshot,
											  inputslot, estate->es_output_cid,
											  lockmode, LockWaitBlock,
											  TUPLE_LOCK_FLAG_FIND_LAST_VERSION,
											  &context->tmfd);
					switch (result)
					{
						case TM_Ok:
							epqslot = EvalPlanQual(epqstate,
													resultRelationDesc,
													resultRelInfo->ri_RangeTableIndex,
													inputslot);

							/*
							 * If we got no tuple, or the tuple we get has a
							 * NULL ctid, go back to caller: this one is not a
							 * MATCHED tuple anymore, so they can retry with
							 * NOT MATCHED actions.
							 */
							if (TupIsNull(epqslot))
								return false;

							(void) ExecGetJunkAttribute(epqslot,
														resultRelInfo->ri_RowIdAttNo,
														&isNull);
							if (isNull)
								return false;

							/*
							 * When a tuple was updated and migrated to
							 * another partition concurrently, the current
							 * MERGE implementation can't follow.	There's
							 * probably a better way to handle this case, but
							 * it'd require recognizing the relation to which
							 * the tuple moved, and setting our current
							 * resultRelInfo to that.
							 */
							if (ItemPointerIndicatesMovedPartitions(&context->tmfd.ctid))
								ereport(ERROR,
										 (errcode(ERRCODE_T_R_SERIALIZATION_FAILURE),
										 errmsg("tuple to be deleted was already moved to another partition due to concurrent update")));

							/*
							 * A non-NULL ctid means that we are still dealing
							 * with MATCHED case. Restart the loop so that we
							 * apply all the MATCHED rules again, to ensure
							 * that the first qualifying WHEN MATCHED action
							 * is executed.
							 *
							 * Update tupleid to that of the new tuple, for
							 * the refetch we do at the top.
							 */
							ItemPointerCopy(&context->tmfd.ctid, tupleid);
							goto lmerge_matched;

						case TM_Deleted:

							/*
							 * tuple already deleted; tell caller to run NOT
							 * MATCHED actions
							 */
							return false;

						case TM_SelfModified:

							/*
							 * This can be reached when following an update
							 * chain from a tuple updated by another session,
							 * reaching a tuple that was already updated in
							 * this transaction. If previously modified by
							 * this command, ignore the redundant update,
							 * otherwise error out.
							 *
							 * See also response to TM_SelfModified in
							 * ExecUpdate().
							 */
							if (context->tmfd.cmax != estate->es_output_cid)
								ereport(ERROR,
										(errcode(ERRCODE_TRIGGERED_DATA_CHANGE_VIOLATION),
										 errmsg("tuple to be updated or deleted was already modified by an operation triggered by the current command"),
										 errhint("Consider using an AFTER trigger instead of a BEFORE trigger to propagate changes to other rows.")));
							return false;

						default:
							/* see table_tuple_lock call in ExecDelete() */
							elog(ERROR, "unexpected table_tuple_lock status: %u",
								 result);
							return false;
					}
				}

			case TM_Invisible:
			case TM_WouldBlock:
			case TM_BeingModified:
				/* these should not occur */
				elog(ERROR, "unexpected tuple operation result: %d", result);
				break;
		}

		/*
		 * We've activated one of the WHEN clauses, so we don't search
		 * further. This is required behaviour, not an optimization.
		 */
		break;
	}

	/*
	 * Successfully executed an action or no qualifying action was found.
	 */
	return true;
}

/*
 * IvytransformMergeStmt
 *
 * transform oracle Merge statement
 */
Query *
IvytransformMergeStmt(ParseState *pstate, MergeStmt *stmt)
{
	Query	   *qry = makeNode(Query);
	ListCell   *l;
	AclMode		targetPerms = ACL_NO_RIGHTS;
	bool		is_terminal[2];
	Index		sourceRTI;
	List	   *mergeActionList;
	Node	   *joinExpr;
	ParseNamespaceItem *nsitem;
	int			delete_clause = -1;

	/* There can't be any outer WITH to worry about */
	Assert(pstate->p_ctenamespace == NIL);

	qry->commandType = CMD_MERGE;
	qry->hasRecursive = false;

	/* process the WITH clause independently of all else */
	if (stmt->withClause)
	{
		if (stmt->withClause->recursive)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("WITH RECURSIVE is not supported for MERGE statement")));

		qry->cteList = transformWithClause(pstate, stmt->withClause);
		qry->hasModifyingCTE = pstate->p_hasModifyingCTE;
	}

	/*
	 * Check WHEN clauses for permissions and sanity
	 */
	is_terminal[0] = false;
	is_terminal[1] = false;
	foreach(l, stmt->mergeWhenClauses)
	{
		MergeWhenClause *mergeWhenClause = (MergeWhenClause *) lfirst(l);
		int				 when_type = (mergeWhenClause->matched ? 0 : 1);
		MergeWhenClause *delstmt = NULL;

		/*
		 * Collect action types so we can check target permissions
		 */
		switch (mergeWhenClause->commandType)
		{
			case CMD_INSERT:
				targetPerms |= ACL_INSERT;
				break;
			case CMD_UPDATE:
				/* In compatibility syntax, DELETE is part of MERGE/UPDATE statement. */
				delstmt = mergeWhenClause->update_delete;
				if (delstmt != NULL)
				{
					/*
					 * Here we add the DELETE part of the syntax to MERGE statement's
					 * WHEN/MATCHED list. Also ensure that the DELETE is added at the
					 * end of WHEN/MATCHED lists.
					 */
					stmt->mergeWhenClauses = lappend(stmt->mergeWhenClauses, mergeWhenClause->update_delete);
					mergeWhenClause->update_delete = NULL;
					delete_clause = 1;
				}
				targetPerms |= ACL_UPDATE;
				break;
			case CMD_DELETE:
				targetPerms |= ACL_DELETE;
				break;
			case CMD_NOTHING:
				break;
			default:
				elog(ERROR, "unknown action in MERGE WHEN clause");
		}

		/*
		 * Check for unreachable WHEN clauses
		 */
		if (mergeWhenClause->condition == NULL && delete_clause == -1)
			is_terminal[when_type] = true;
		else if (is_terminal[when_type])
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("unreachable WHEN clause specified after unconditional WHEN clause")));
	}

	/* Set up the MERGE target table. */
	qry->resultRelation = setTargetTable(pstate, stmt->relation,
										 stmt->relation->inh,
										 false, targetPerms);

	/*
	 * MERGE is unsupported in various cases
	 */
	if (pstate->p_target_relation->rd_rel->relkind != RELKIND_RELATION &&
		pstate->p_target_relation->rd_rel->relkind != RELKIND_PARTITIONED_TABLE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("cannot execute MERGE on relation \"%s\"",
						RelationGetRelationName(pstate->p_target_relation)),
				 errdetail_relkind_not_supported(pstate->p_target_relation->rd_rel->relkind)));
	if (pstate->p_target_relation->rd_rel->relhasrules)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("cannot execute MERGE on relation \"%s\"",
						RelationGetRelationName(pstate->p_target_relation)),
				 errdetail("MERGE is not supported for relations with rules.")));

	/* Now transform the source relation to produce the source RTE. */
	transformFromClause(pstate,
						list_make1(stmt->sourceRelation));
	sourceRTI = list_length(pstate->p_rtable);
	nsitem = GetNSItemByRangeTablePosn(pstate, sourceRTI, 0);

	/*
	 * Check that the target table doesn't conflict with the source table.
	 * This would typically be a checkNameSpaceConflicts call, but we want a
	 * more specific error message.
	 */
	if (strcmp(pstate->p_target_nsitem->p_names->aliasname,
			   nsitem->p_names->aliasname) == 0)
		ereport(ERROR,
				errcode(ERRCODE_DUPLICATE_ALIAS),
				errmsg("name \"%s\" specified more than once",
					   pstate->p_target_nsitem->p_names->aliasname),
				errdetail("The name is used both as MERGE target table and data source."));

	qry->targetList = expandNSItemAttrs(pstate, nsitem, 0, false,
										exprLocation(stmt->sourceRelation));

	qry->rtable = pstate->p_rtable;
	qry->rteperminfos = pstate->p_rteperminfos;

	/*
	 * Transform the join condition.  This includes references to the target
	 * side, so add that to the namespace.
	 */
	addNSItemToQuery(pstate, pstate->p_target_nsitem, false, true, true);

	pstate->merge_on_attr_size = list_length(pstate->p_target_nsitem->p_names->colnames);
	pstate->merge_on_attrno = (uint8 *)palloc(pstate->merge_on_attr_size * sizeof(uint8));
	memset(pstate->merge_on_attrno, 0, pstate->merge_on_attr_size * sizeof(uint8));

	joinExpr = transformExpr(pstate, stmt->joinCondition,
							 EXPR_KIND_JOIN_ON);

	/*
	 * Create the temporary query's jointree using the joinlist we built using
	 * just the source relation; the target relation is not included.  The
	 * quals we use are the join conditions to the merge target.  The join
	 * will be constructed fully by transform_MERGE_to_join.
	 */
	qry->jointree = makeFromExpr(pstate->p_joinlist, joinExpr);

	/*
	 * We now have a good query shape, so now look at the WHEN conditions and
	 * action targetlists.
	 *
	 * Overall, the MERGE Query's targetlist is NIL.
	 *
	 * Each individual action has its own targetlist that needs separate
	 * transformation. These transforms don't do anything to the overall
	 * targetlist, since that is only used for resjunk columns.
	 *
	 * We can reference any column in Target or Source, which is OK because
	 * both of those already have RTEs. There is nothing like the EXCLUDED
	 * pseudo-relation for INSERT ON CONFLICT.
	 */
	mergeActionList = NIL;
	foreach(l, stmt->mergeWhenClauses)
	{
		MergeWhenClause *mergeWhenClause = lfirst_node(MergeWhenClause, l);
		MergeAction *action;

		action = makeNode(MergeAction);
		action->commandType = mergeWhenClause->commandType;
		action->matched = mergeWhenClause->matched;

		/* Use an outer join if any INSERT actions exist in the command. */
		if (action->commandType == CMD_INSERT)
			qry->mergeUseOuterJoin = true;

		/*
		 * Set namespace for the specific action. This must be done before
		 * analyzing the WHEN quals and the action targetlist.
		 */
		setNamespaceForMergeWhen(pstate, mergeWhenClause,
								 qry->resultRelation,
								 sourceRTI);

		/*
		 * Transform the WHEN condition.
		 *
		 * Note that these quals are NOT added to the join quals; instead they
		 * are evaluated separately during execution to decide which of the
		 * WHEN MATCHED or WHEN NOT MATCHED actions to execute.
		 */
		action->qual = transformWhereClause(pstate, mergeWhenClause->condition,
											EXPR_KIND_MERGE_WHEN, "WHEN");

		/*
		 * Transform target lists for each INSERT and UPDATE action stmt
		 */
		switch (action->commandType)
		{
			case CMD_INSERT:
				{
					List	   *exprList = NIL;
					ListCell   *lc;
					RTEPermissionInfo *perminfo;
					ListCell   *icols;
					ListCell   *attnos;
					List	   *icolumns;
					List	   *attrnos;

					pstate->p_is_insert = true;

					icolumns = checkInsertTargets(pstate,
												  mergeWhenClause->targetList,
												  &attrnos);
					Assert(list_length(icolumns) == list_length(attrnos));

					action->override = mergeWhenClause->override;

					/*
					 * Handle INSERT much like in transformInsertStmt
					 */
					if (mergeWhenClause->values == NIL)
					{
						/*
						 * We have INSERT ... DEFAULT VALUES.  We can handle
						 * this case by emitting an empty targetlist --- all
						 * columns will be defaulted when the planner expands
						 * the targetlist.
						 */
						exprList = NIL;
					}
					else
					{
						/*
						 * Process INSERT ... VALUES with a single VALUES
						 * sublist.  We treat this case separately for
						 * efficiency.  The sublist is just computed directly
						 * as the Query's targetlist, with no VALUES RTE.  So
						 * it works just like a SELECT without any FROM.
						 */

						/*
						 * Do basic expression transformation (same as a ROW()
						 * expr, but allow SetToDefault at top level)
						 */
						exprList = transformExpressionList(pstate,
														   mergeWhenClause->values,
														   EXPR_KIND_VALUES_SINGLE,
														   true);

						/* Prepare row for assignment to target table */
						exprList = transformInsertRow(pstate, exprList,
													  mergeWhenClause->targetList,
													  icolumns, attrnos,
													  false);
					}

					/*
					 * Generate action's target list using the computed list
					 * of expressions. Also, mark all the target columns as
					 * needing insert permissions.
					 */
					perminfo = pstate->p_target_nsitem->p_perminfo;
					forthree(lc, exprList, icols, icolumns, attnos, attrnos)
					{
						Expr	   *expr = (Expr *) lfirst(lc);
						ResTarget  *col = lfirst_node(ResTarget, icols);
						AttrNumber	attr_num = (AttrNumber) lfirst_int(attnos);
						TargetEntry *tle;

						tle = makeTargetEntry(expr,
											  attr_num,
											  col->name,
											  false);
						action->targetList = lappend(action->targetList, tle);

						perminfo->insertedCols =
							bms_add_member(perminfo->insertedCols,
										   attr_num - FirstLowInvalidHeapAttributeNumber);
					}
				}
				break;
			case CMD_UPDATE:
				{
					ListCell    *l1;
					char		*rname = NULL;

					pstate->p_is_insert = false;
					action->targetList =
						transformUpdateTargetList(pstate, mergeWhenClause->targetList);
					/*
					 * Prevent the columns referenced in the ON clause can be updated.
					 */
					foreach(l1, action->targetList)
					{
						TargetEntry *tle = (TargetEntry *) lfirst(l1);

						if (pstate->merge_on_attrno[tle->resno - 1] == 1)
						{
							rname = get_rte_attribute_name(pstate->p_target_nsitem->p_rte, tle->resno);
							elog(ERROR, "Columns referenced in the ON Clause cannot be updated: %s.%s",
								RelationGetRelationName(pstate->p_target_relation), rname);
						}
					}
				}
				break;
			case CMD_DELETE:
				break;

			case CMD_NOTHING:
				action->targetList = NIL;
				break;
			default:
				elog(ERROR, "unknown action in MERGE WHEN clause");
		}

		mergeActionList = lappend(mergeActionList, action);
	}

	qry->mergeActionList = mergeActionList;

	/* RETURNING could potentially be added in the future, but not in SQL std */
	qry->returningList = NULL;

	qry->hasTargetSRFs = false;
	qry->hasSubLinks = pstate->p_hasSubLinks;

	assign_query_collations(pstate, qry);

	return qry;
}

static TM_Result
execDelete4Merge(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
			  				ItemPointer tupleid, bool changingPart)
{
	EState	   *estate = context->estate;

	return heapDelete4Merge(resultRelInfo->ri_RelationDesc, tupleid,
							estate->es_output_cid,
							estate->es_crosscheck_snapshot,
							true /* wait for commit */ ,
							&context->tmfd,
							changingPart);
}

static TM_Result
heapDelete4Merge(Relation relation, ItemPointer tid,
							CommandId cid, Snapshot crosscheck, bool wait,
							TM_FailureData *tmfd, bool changingPart)
{
	TM_Result	result;
	TransactionId xid = GetCurrentTransactionId();
	ItemId		lp;
	HeapTupleData tp;
	Page		page;
	BlockNumber block;
	Buffer		buffer;
	Buffer		vmbuffer = InvalidBuffer;
	TransactionId new_xmax;
	uint16		new_infomask,
				new_infomask2;
	bool		have_tuple_lock = false;
	bool		iscombo;
	bool		all_visible_cleared = false;
	HeapTuple	old_key_tuple = NULL;	/* replica identity of the tuple */
	bool		old_key_copied = false;
	if (!ItemPointerIsValid(tid))
		ereport(ERROR,
				(errcode(ERRCODE_NO_DATA),
				 errmsg("specified row no longer exists")));

	Assert(ItemPointerIsValid(tid));

	/*
	 * Forbid this during a parallel operation, lest it allocate a combo CID.
	 * Other workers might need that combo CID for visibility checks, and we
	 * have no provision for broadcasting it to them.
	 */
	if (IsInParallelMode())
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TRANSACTION_STATE),
				 errmsg("cannot delete tuples during a parallel operation")));

	block = ItemPointerGetBlockNumber(tid);
	buffer = ReadBuffer(relation, block);
	page = BufferGetPage(buffer);

	/*
	 * Before locking the buffer, pin the visibility map page if it appears to
	 * be necessary.  Since we haven't got the lock yet, someone else might be
	 * in the middle of changing this, so we'll need to recheck after we have
	 * the lock.
	 */
	if (PageIsAllVisible(page))
		visibilitymap_pin(relation, block, &vmbuffer);

	LockBuffer(buffer, BUFFER_LOCK_EXCLUSIVE);

	/*
	 * If we didn't pin the visibility map page and the page has become all
	 * visible while we were busy locking the buffer, we'll have to unlock and
	 * re-lock, to avoid holding the buffer lock across an I/O.  That's a bit
	 * unfortunate, but hopefully shouldn't happen often.
	 */
	if (vmbuffer == InvalidBuffer && PageIsAllVisible(page))
	{
		LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
		visibilitymap_pin(relation, block, &vmbuffer);
		LockBuffer(buffer, BUFFER_LOCK_EXCLUSIVE);
	}

	lp = PageGetItemId(page, ItemPointerGetOffsetNumber(tid));
	Assert(ItemIdIsNormal(lp));

	tp.t_tableOid = RelationGetRelid(relation);
	tp.t_data = (HeapTupleHeader) PageGetItem(page, lp);
	tp.t_len = ItemIdGetLength(lp);
	tp.t_self = *tid;

l1:
	result = heapTupleSatisfiesUpdate4Merge(&tp, cid, buffer);

	if (result == TM_Invisible)
	{
		UnlockReleaseBuffer(buffer);
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("attempted to delete invisible tuple")));
	}
	else if (result == TM_BeingModified && wait)
	{
		TransactionId xwait;
		uint16		infomask;

		/* must copy state data before unlocking buffer */
		xwait = HeapTupleHeaderGetRawXmax(tp.t_data);
		infomask = tp.t_data->t_infomask;

		/*
		 * Sleep until concurrent transaction ends -- except when there's a
		 * single locker and it's our own transaction.  Note we don't care
		 * which lock mode the locker has, because we need the strongest one.
		 *
		 * Before sleeping, we need to acquire tuple lock to establish our
		 * priority for the tuple (see heap_lock_tuple).  LockTuple will
		 * release us when we are next-in-line for the tuple.
		 *
		 * If we are forced to "start over" below, we keep the tuple lock;
		 * this arranges that we stay at the head of the line while rechecking
		 * tuple state.
		 */
		if (infomask & HEAP_XMAX_IS_MULTI)
		{
			bool		current_is_member = false;

			if (DoesMultiXactIdConflict((MultiXactId) xwait, infomask,
										LockTupleExclusive, &current_is_member))
			{
				LockBuffer(buffer, BUFFER_LOCK_UNLOCK);

				/*
				 * Acquire the lock, if necessary (but skip it when we're
				 * requesting a lock and already have one; avoids deadlock).
				 */
				if (!current_is_member)
					heap_acquire_tuplock(relation, &(tp.t_self), LockTupleExclusive,
										 LockWaitBlock, &have_tuple_lock);

				/* wait for multixact */
				MultiXactIdWait((MultiXactId) xwait, MultiXactStatusUpdate, infomask,
								relation, &(tp.t_self), XLTW_Delete,
								NULL);
				LockBuffer(buffer, BUFFER_LOCK_EXCLUSIVE);

				/*
				 * If xwait had just locked the tuple then some other xact
				 * could update this tuple before we get to this point.  Check
				 * for xmax change, and start over if so.
				 */
				if (xmax_infomask_changed(tp.t_data->t_infomask, infomask) ||
					!TransactionIdEquals(HeapTupleHeaderGetRawXmax(tp.t_data),
										 xwait))
					goto l1;
			}

			/*
			 * You might think the multixact is necessarily done here, but not
			 * so: it could have surviving members, namely our own xact or
			 * other subxacts of this backend.  It is legal for us to delete
			 * the tuple in either case, however (the latter case is
			 * essentially a situation of upgrading our former shared lock to
			 * exclusive).  We don't bother changing the on-disk hint bits
			 * since we are about to overwrite the xmax altogether.
			 */
		}
		else if (!TransactionIdIsCurrentTransactionId(xwait))
		{
			/*
			 * Wait for regular transaction to end; but first, acquire tuple
			 * lock.
			 */
			LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
			heap_acquire_tuplock(relation, &(tp.t_self), LockTupleExclusive,
								 LockWaitBlock, &have_tuple_lock);
			XactLockTableWait(xwait, relation, &(tp.t_self), XLTW_Delete);
			LockBuffer(buffer, BUFFER_LOCK_EXCLUSIVE);

			/*
			 * xwait is done, but if xwait had just locked the tuple then some
			 * other xact could update this tuple before we get to this point.
			 * Check for xmax change, and start over if so.
			 */
			if (xmax_infomask_changed(tp.t_data->t_infomask, infomask) ||
				!TransactionIdEquals(HeapTupleHeaderGetRawXmax(tp.t_data),
									 xwait))
				goto l1;

			/* Otherwise check if it committed or aborted */
			UpdateXmaxHintBits(tp.t_data, buffer, xwait);
		}

		/*
		 * We may overwrite if previous xmax aborted, or if it committed but
		 * only locked the tuple without updating it.
		 */
		if ((tp.t_data->t_infomask & HEAP_XMAX_INVALID) ||
			HEAP_XMAX_IS_LOCKED_ONLY(tp.t_data->t_infomask) ||
			HeapTupleHeaderIsOnlyLocked(tp.t_data))
			result = TM_Ok;
		else if (!ItemPointerEquals(&tp.t_self, &tp.t_data->t_ctid))
			result = TM_Updated;
		else
			result = TM_Deleted;
	}

	if (crosscheck != InvalidSnapshot && result == TM_Ok)
	{
		/* Perform additional check for transaction-snapshot mode RI updates */
		if (!HeapTupleSatisfiesVisibility(&tp, crosscheck, buffer))
			result = TM_Updated;
	}

	if (result != TM_Ok)
	{
		Assert(result == TM_SelfModified ||
			   result == TM_Updated ||
			   result == TM_Deleted ||
			   result == TM_BeingModified);
		Assert(!(tp.t_data->t_infomask & HEAP_XMAX_INVALID));
		Assert(result != TM_Updated ||
			   !ItemPointerEquals(&tp.t_self, &tp.t_data->t_ctid));
		tmfd->ctid = tp.t_data->t_ctid;
		tmfd->xmax = HeapTupleHeaderGetUpdateXid(tp.t_data);
		if (result == TM_SelfModified)
			tmfd->cmax = HeapTupleHeaderGetCmax(tp.t_data);
		else
			tmfd->cmax = InvalidCommandId;
		UnlockReleaseBuffer(buffer);
		if (have_tuple_lock)
			UnlockTupleTuplock(relation, &(tp.t_self), LockTupleExclusive);
		if (vmbuffer != InvalidBuffer)
			ReleaseBuffer(vmbuffer);
		return result;
	}

	/*
	 * We're about to do the actual delete -- check for conflict first, to
	 * avoid possibly having to roll back work we've just done.
	 *
	 * This is safe without a recheck as long as there is no possibility of
	 * another process scanning the page between this check and the delete
	 * being visible to the scan (i.e., an exclusive buffer content lock is
	 * continuously held from this point until the tuple delete is visible).
	 */
	CheckForSerializableConflictIn(relation, tid, BufferGetBlockNumber(buffer));

	/* replace cid with a combo CID if necessary */
	HeapTupleHeaderAdjustCmax(tp.t_data, &cid, &iscombo);

	/*
	 * Compute replica identity tuple before entering the critical section so
	 * we don't PANIC upon a memory allocation failure.
	 */
	old_key_tuple = ExtractReplicaIdentity(relation, &tp, true, &old_key_copied);

	/*
	 * If this is the first possibly-multixact-able operation in the current
	 * transaction, set my per-backend OldestMemberMXactId setting. We can be
	 * certain that the transaction will never become a member of any older
	 * MultiXactIds than that.  (We have to do this even if we end up just
	 * using our own TransactionId below, since some other backend could
	 * incorporate our XID into a MultiXact immediately afterwards.)
	 */
	MultiXactIdSetOldestMember();

	compute_new_xmax_infomask(HeapTupleHeaderGetRawXmax(tp.t_data),
							  tp.t_data->t_infomask, tp.t_data->t_infomask2,
							  xid, LockTupleExclusive, true,
							  &new_xmax, &new_infomask, &new_infomask2);

	START_CRIT_SECTION();

	/*
	 * If this transaction commits, the tuple will become DEAD sooner or
	 * later.  Set flag that this page is a candidate for pruning once our xid
	 * falls below the OldestXmin horizon.  If the transaction finally aborts,
	 * the subsequent page pruning will be a no-op and the hint will be
	 * cleared.
	 */
	PageSetPrunable(page, xid);

	if (PageIsAllVisible(page))
	{
		all_visible_cleared = true;
		PageClearAllVisible(page);
		visibilitymap_clear(relation, BufferGetBlockNumber(buffer),
							vmbuffer, VISIBILITYMAP_VALID_BITS);
	}

	/* store transaction information of xact deleting the tuple */
	tp.t_data->t_infomask &= ~(HEAP_XMAX_BITS | HEAP_MOVED);
	tp.t_data->t_infomask2 &= ~HEAP_KEYS_UPDATED;
	tp.t_data->t_infomask |= new_infomask;
	tp.t_data->t_infomask2 |= new_infomask2;
	HeapTupleHeaderClearHotUpdated(tp.t_data);
	HeapTupleHeaderSetXmax(tp.t_data, new_xmax);
	HeapTupleHeaderSetCmax(tp.t_data, cid, iscombo);
	/* Make sure there is no forward chain link in t_ctid */
	tp.t_data->t_ctid = tp.t_self;

	/* Signal that this is actually a move into another partition */
	if (changingPart)
		HeapTupleHeaderSetMovedPartitions(tp.t_data);

	MarkBufferDirty(buffer);

	/*
	 * XLOG stuff
	 *
	 * NB: heap_abort_speculative() uses the same xlog record and replay
	 * routines.
	 */
	if (RelationNeedsWAL(relation))
	{
		xl_heap_delete xlrec;
		xl_heap_header xlhdr;
		XLogRecPtr	recptr;

		/*
		 * For logical decode we need combo CIDs to properly decode the
		 * catalog
		 */
		if (RelationIsAccessibleInLogicalDecoding(relation))
			log_heap_new_cid(relation, &tp);

		xlrec.flags = 0;
		if (all_visible_cleared)
			xlrec.flags |= XLH_DELETE_ALL_VISIBLE_CLEARED;
		if (changingPart)
			xlrec.flags |= XLH_DELETE_IS_PARTITION_MOVE;
		xlrec.infobits_set = compute_infobits(tp.t_data->t_infomask,
											  tp.t_data->t_infomask2);
		xlrec.offnum = ItemPointerGetOffsetNumber(&tp.t_self);
		xlrec.xmax = new_xmax;

		if (old_key_tuple != NULL)
		{
			if (relation->rd_rel->relreplident == REPLICA_IDENTITY_FULL)
				xlrec.flags |= XLH_DELETE_CONTAINS_OLD_TUPLE;
			else
				xlrec.flags |= XLH_DELETE_CONTAINS_OLD_KEY;
		}

		XLogBeginInsert();
		XLogRegisterData((char *) &xlrec, SizeOfHeapDelete);

		XLogRegisterBuffer(0, buffer, REGBUF_STANDARD);

		/*
		 * Log replica identity of the deleted tuple if there is one
		 */
		if (old_key_tuple != NULL)
		{
			xlhdr.t_infomask2 = old_key_tuple->t_data->t_infomask2;
			xlhdr.t_infomask = old_key_tuple->t_data->t_infomask;
			xlhdr.t_hoff = old_key_tuple->t_data->t_hoff;

			XLogRegisterData((char *) &xlhdr, SizeOfHeapHeader);
			XLogRegisterData((char *) old_key_tuple->t_data
							 + SizeofHeapTupleHeader,
							 old_key_tuple->t_len
							 - SizeofHeapTupleHeader);
		}

		/* filtering by origin on a row level is much more efficient */
		XLogSetRecordFlags(XLOG_INCLUDE_ORIGIN);

		recptr = XLogInsert(RM_HEAP_ID, XLOG_HEAP_DELETE);

		PageSetLSN(page, recptr);
	}

	END_CRIT_SECTION();

	LockBuffer(buffer, BUFFER_LOCK_UNLOCK);

	if (vmbuffer != InvalidBuffer)
		ReleaseBuffer(vmbuffer);

	/*
	 * If the tuple has toasted out-of-line attributes, we need to delete
	 * those items too.  We have to do this before releasing the buffer
	 * because we need to look at the contents of the tuple, but it's OK to
	 * release the content lock on the buffer first.
	 */
	if (relation->rd_rel->relkind != RELKIND_RELATION &&
		relation->rd_rel->relkind != RELKIND_MATVIEW)
	{
		/* toast table entries should never be recursively toasted */
		Assert(!HeapTupleHasExternal(&tp));
	}
	else if (HeapTupleHasExternal(&tp))
		heap_toast_delete(relation, &tp, false);

	/*
	 * Mark tuple for invalidation from system caches at next command
	 * boundary. We have to do this before releasing the buffer because we
	 * need to look at the contents of the tuple.
	 */
	CacheInvalidateHeapTuple(relation, &tp, NULL);

	/* Now we can release the buffer */
	ReleaseBuffer(buffer);

	/*
	 * Release the lmgr tuple lock, if we had it.
	 */
	if (have_tuple_lock)
		UnlockTupleTuplock(relation, &(tp.t_self), LockTupleExclusive);

	pgstat_count_heap_delete(relation);

	if (old_key_tuple != NULL && old_key_copied)
		heap_freetuple(old_key_tuple);

	return TM_Ok;
}

static TM_Result
heapTupleSatisfiesUpdate4Merge(HeapTuple htup, CommandId curcid,
						 Buffer buffer)
{
	HeapTupleHeader tuple = htup->t_data;

	Assert(ItemPointerIsValid(&htup->t_self));
	Assert(htup->t_tableOid != InvalidOid);

	if (!HeapTupleHeaderXminCommitted(tuple))
	{
		if (HeapTupleHeaderXminInvalid(tuple))
			return TM_Invisible;

		/* Used by pre-9.0 binary upgrades */
		if (tuple->t_infomask & HEAP_MOVED_OFF)
		{
			TransactionId xvac = HeapTupleHeaderGetXvac(tuple);

			if (TransactionIdIsCurrentTransactionId(xvac))
				return TM_Invisible;
			if (!TransactionIdIsInProgress(xvac))
			{
				if (TransactionIdDidCommit(xvac))
				{
					SetHintBits(tuple, buffer, HEAP_XMIN_INVALID,
								InvalidTransactionId);
					return TM_Invisible;
				}
				SetHintBits(tuple, buffer, HEAP_XMIN_COMMITTED,
							InvalidTransactionId);
			}
		}
		/* Used by pre-9.0 binary upgrades */
		else if (tuple->t_infomask & HEAP_MOVED_IN)
		{
			TransactionId xvac = HeapTupleHeaderGetXvac(tuple);

			if (!TransactionIdIsCurrentTransactionId(xvac))
			{
				if (TransactionIdIsInProgress(xvac))
					return TM_Invisible;
				if (TransactionIdDidCommit(xvac))
					SetHintBits(tuple, buffer, HEAP_XMIN_COMMITTED,
								InvalidTransactionId);
				else
				{
					SetHintBits(tuple, buffer, HEAP_XMIN_INVALID,
								InvalidTransactionId);
					return TM_Invisible;
				}
			}
		}
		else if (TransactionIdIsCurrentTransactionId(HeapTupleHeaderGetRawXmin(tuple)))
		{
			if (HeapTupleHeaderGetCmin(tuple) >= curcid)
			{
				 /* Only for compatible oracle MERGE */
				return TM_Ok;	/* inserted after scan started */
			}
		}

	}
	return TM_Invisible;
}
