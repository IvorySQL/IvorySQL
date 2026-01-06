/*-------------------------------------------------------------------------
 *
 * nodeModifyTable.h
 *
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * src/include/executor/nodeModifyTable.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef NODEMODIFYTABLE_H
#define NODEMODIFYTABLE_H

#include "nodes/execnodes.h"
#include "access/tableam.h"


/*
 * Context struct for a ModifyTable operation, containing basic execution
 * state and some output variables populated by ExecUpdateAct() and
 * ExecDeleteAct() to report the result of their actions to callers.
 */
typedef struct IvyModifyTableContext
{
	/* Operation state */
	ModifyTableState *mtstate;
	EPQState   *epqstate;
	EState	   *estate;

	/*
	 * Slot containing tuple obtained from ModifyTable's subplan.  Used to
	 * access "junk" columns that are not going to be stored.
	 */
	TupleTableSlot *planSlot;

	/*
	 * Information about the changes that were made concurrently to a tuple
	 * being updated or deleted
	 */
	TM_FailureData tmfd;

	/*
	 * The tuple deleted when doing a cross-partition UPDATE with a RETURNING
	 * clause that refers to OLD columns (converted to the root's tuple
	 * descriptor).
	 */
	TupleTableSlot *cpDeletedSlot;

	/*
	 * The tuple projected by the INSERT's RETURNING clause, when doing a
	 * cross-partition UPDATE
	 */
	TupleTableSlot *cpUpdateReturningSlot;
} IvyModifyTableContext;

/*
 * Context struct containing output data specific to UPDATE operations.
 */
typedef struct IvyUpdateContext
{
	bool		crossPartUpdate;	/* was it a cross-partition update? */
	TU_UpdateIndexes updateIndexes;	/* Which index updates are required? */

	/*
	 * Lock mode to acquire on the latest tuple version before performing
	 * EvalPlanQual on it
	 */
	LockTupleMode lockmode;
} IvyUpdateContext;

extern void ExecInitGenerated(ResultRelInfo *resultRelInfo,
							  EState *estate,
							  CmdType cmdtype);

extern void ExecComputeStoredGenerated(ResultRelInfo *resultRelInfo,
									   EState *estate, TupleTableSlot *slot,
									   CmdType cmdtype);

extern ModifyTableState *ExecInitModifyTable(ModifyTable *node, EState *estate, int eflags);
extern void ExecEndModifyTable(ModifyTableState *node);
extern void ExecReScanModifyTable(ModifyTableState *node);

extern void ExecInitMergeTupleSlots(ModifyTableState *mtstate,
									ResultRelInfo *resultRelInfo);

extern bool ExecDeletePrologue(IvyModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple,
							TupleTableSlot **epqreturnslot, TM_Result *result);
extern TM_Result ExecDeleteAct(IvyModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, bool changingPart);
extern void ExecDeleteEpilogue(IvyModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple, bool changingPart);
extern TM_Result ExecUpdateAct(IvyModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple, TupleTableSlot *slot,
							bool canSetTag, IvyUpdateContext *updateCxt);
extern void ExecUpdateEpilogue(IvyModifyTableContext *context, IvyUpdateContext *updateCxt,
							ResultRelInfo *resultRelInfo, ItemPointer tupleid,
							HeapTuple oldtuple, TupleTableSlot *slot);
extern bool ExecUpdatePrologue(IvyModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple, TupleTableSlot *slot,
							TM_Result *result);
extern void ExecUpdatePrepareSlot(ResultRelInfo *resultRelInfo,
							TupleTableSlot *slot, EState *estate);
extern TupleTableSlot *ExecMergeMatched(IvyModifyTableContext *context,
										ResultRelInfo *resultRelInfo,
										ItemPointer tupleid,
										HeapTuple oldtuple,
										bool canSetTag,
										bool *matched);
typedef TupleTableSlot *(* exec_merge_matched_hook_type)(IvyModifyTableContext *context, ResultRelInfo *resultRelInfo,
									ItemPointer tupleid, HeapTuple oldtuple, 
									bool canSetTag, bool *matched);
extern PGDLLIMPORT exec_merge_matched_hook_type pg_exec_merge_matched_hook;
extern PGDLLIMPORT exec_merge_matched_hook_type ora_exec_merge_matched_hook;

#endif							/* NODEMODIFYTABLE_H */
