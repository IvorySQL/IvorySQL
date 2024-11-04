/*-------------------------------------------------------------------------
 *
 * nodeModifyTable.h
 *
 *
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
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
typedef struct ModifyTableContext
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

	/* MERGE specific */
	MergeActionState *relaction;	/* MERGE action in progress */

	/*
	 * Information about the changes that were made concurrently to a tuple
	 * being updated or deleted
	 */
	TM_FailureData tmfd;

	/*
	 * The tuple produced by EvalPlanQual to retry from, if a cross-partition
	 * UPDATE requires it
	 */
	TupleTableSlot *cpUpdateRetrySlot;

	/*
	 * The tuple projected by the INSERT's RETURNING clause, when doing a
	 * cross-partition UPDATE
	 */
	TupleTableSlot *cpUpdateReturningSlot;
} ModifyTableContext;

/*
 * Context struct containing output data specific to UPDATE operations.
 */
typedef struct UpdateContext
{
	bool		crossPartUpdate;	/* was it a cross-partition update? */
	TU_UpdateIndexes updateIndexes;	/* Which index updates are required? */

	/*
	 * Lock mode to acquire on the latest tuple version before performing
	 * EvalPlanQual on it
	 */
	LockTupleMode lockmode;
} UpdateContext;

extern void ExecInitStoredGenerated(ResultRelInfo *resultRelInfo,
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

extern bool ExecDeletePrologue(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple,
							TupleTableSlot **epqreturnslot, TM_Result *result);
extern TM_Result ExecDeleteAct(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, bool changingPart);
extern void ExecDeleteEpilogue(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple, bool changingPart);
extern TM_Result ExecUpdateAct(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple, TupleTableSlot *slot,
							bool canSetTag, UpdateContext *updateCxt);
extern void ExecUpdateEpilogue(ModifyTableContext *context, UpdateContext *updateCxt,
							ResultRelInfo *resultRelInfo, ItemPointer tupleid,
							HeapTuple oldtuple, TupleTableSlot *slot);
extern bool ExecUpdatePrologue(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
							ItemPointer tupleid, HeapTuple oldtuple, TupleTableSlot *slot,
							TM_Result *result);
extern void ExecUpdatePrepareSlot(ResultRelInfo *resultRelInfo,
							TupleTableSlot *slot, EState *estate);
extern bool ExecMergeMatched(ModifyTableContext *context,
							 ResultRelInfo *resultRelInfo,
							 ItemPointer tupleid,
							 HeapTuple oldtuple,
							 bool canSetTag);
typedef bool (* exec_merge_matched_hook_type)(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
									ItemPointer tupleid, HeapTuple oldtuple, bool canSetTag);
extern PGDLLIMPORT exec_merge_matched_hook_type pg_exec_merge_matched_hook;
extern PGDLLIMPORT exec_merge_matched_hook_type ora_exec_merge_matched_hook;

#endif							/* NODEMODIFYTABLE_H */
