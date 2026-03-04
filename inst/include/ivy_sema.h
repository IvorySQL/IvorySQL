/*-------------------------------------------------------------------------
 *
 * ivy_sema.h 
 *        Platform-independent API for semaphores. 
 *        copy from pg_sema.h 
 * 
 * PostgreSQL requires counting semaphores (the kind that keep track of
 * multiple unlock operations, and will allow an same number of subsequent
 * lock operations before blocking).  The underlying implementation is
 * not the same on each platform.  This file defines the API that must
 * be provided by each port.
 *
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * src/interfaces/libpq/ivy_sema.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef IVY_SEMA_H
#define IVY_SEMA_H

/*
 * PGSemaphoreData and pointer type PGSemaphore are the data structure
 * representing an individual semaphore.  The contents of PGSemaphoreData
 * vary across implementations and must never be touched by platform-
 * independent code.  PGSemaphoreData structures are always allocated
 * in shared memory (to support implementations where the data changes during
 * lock/unlock).
 *
 * pg_config.h must define exactly one of the USE_xxx_SEMAPHORES symbols.
 */

#ifdef USE_NAMED_POSIX_SEMAPHORES

#include <semaphore.h>

typedef sem_t *PGSemaphoreData;
#endif

#ifdef USE_UNNAMED_POSIX_SEMAPHORES

#include <semaphore.h>

typedef sem_t PGSemaphoreData;
#endif

#ifdef USE_SYSV_SEMAPHORES

typedef struct PGSemaphoreData
{
	int	semId;			/* semaphore set identifier */
	int	semNum;			/* semaphore number within set */
} PGSemaphoreData;
#endif

#ifdef USE_WIN32_SEMAPHORES

typedef HANDLE PGSemaphoreData;
#endif

typedef PGSemaphoreData *PGSemaphore;


/* Initialize a PGSemaphore structure to represent a sema with count 1 */
extern int PGSemaphoreCreate(PGSemaphore sema);

/* Lock a semaphore (decrement count), blocking if count would be < 0 */
extern void PGSemaphoreLock(PGSemaphore sema);

/* Unlock a semaphore (increment count) */
extern void PGSemaphoreUnlock(PGSemaphore sema);

/* release a semaphore */
extern void ReleaseSemaphores(PGSemaphore sema);

#endif   /* IVY_SEMA_H */

