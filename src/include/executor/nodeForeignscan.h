/*-------------------------------------------------------------------------
 *
 * nodeForeignscan.h
 *
 *
 *
 * Portions Copyright (c) 1996-2021, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/executor/nodeForeignscan.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef NODEFOREIGNSCAN_H
#define NODEFOREIGNSCAN_H

#include "access/parallel.h"
#include "nodes/execnodes.h"

extern ForeignScanState *ExecInitForeignScan(ForeignScan *node, EState *estate, int eflags);
extern void ExecEndForeignScan(ForeignScanState *node);
extern void ExecReScanForeignScan(ForeignScanState *node);

extern void ExecForeignScanEstimate(ForeignScanState *node,
									ParallelContext *pcxt);
extern void ExecForeignScanInitializeDSM(ForeignScanState *node,
										 ParallelContext *pcxt);
extern void ExecForeignScanReInitializeDSM(ForeignScanState *node,
										   ParallelContext *pcxt);
extern void ExecForeignScanInitializeWorker(ForeignScanState *node,
											ParallelWorkerContext *pwcxt);
extern void ExecShutdownForeignScan(ForeignScanState *node);

extern void ExecAsyncForeignScanRequest(AsyncRequest *areq);
extern void ExecAsyncForeignScanConfigureWait(AsyncRequest *areq);
extern void ExecAsyncForeignScanNotify(AsyncRequest *areq);
extern void ExecForeignTableEletsScan(const char *dblinkname, const char *schemaname, const char *relname, Oid srvowner, Oid srvoid, bool *reloidNotExistOk, Oid *mappingreloid);

#endif							/* NODEFOREIGNSCAN_H */
