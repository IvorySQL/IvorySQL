/*-------------------------------------------------------------------------
 *
 * sysv_ivysema.c copy from sysv_sema.c
 *	  Implement PGSemaphores using SysV semaphore facilities
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/interfaces/libpq/sysv_ivysema.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <signal.h>
#include <unistd.h>
#include <sys/file.h>

#ifdef HAVE_SYS_IPC_H
#include <sys/ipc.h>
#endif

#ifdef HAVE_SYS_SEM_H
#include <sys/sem.h>
#endif

#include "ivy_sema.h"


#ifndef HAVE_UNION_SEMUN
union semun
{
	int	val;
	struct semid_ds *buf;
	unsigned short *array;
};
#endif

typedef key_t IpcSemaphoreKey;	/* semaphore key passed to semget(2) */
typedef int IpcSemaphoreId;	/* semaphore ID returned by semget(2) */


#define IPCProtection	(0600)	

#define PGSemaMagic	537		/* must be less than SEMVMX */
#ifdef SEMVMX
StaticAssertDecl(PGSemaMagic < SEMVMX, "PGSemaMagic must be less than SEMVMX");
#endif

static IpcSemaphoreKey nextSemaKey;		/* next key to try */


static IpcSemaphoreId InternalIpcSemaphoreCreate(IpcSemaphoreKey semKey,
						   int numSems);
static void IpcSemaphoreInitialize(IpcSemaphoreId semId, int semNum,
					   int value);
static void IpcSemaphoreKill(IpcSemaphoreId semId);
static int	IpcSemaphoreGetValue(IpcSemaphoreId semId, int semNum);
static pid_t IpcSemaphoreGetLastPID(IpcSemaphoreId semId, int semNum);
static IpcSemaphoreId IpcSemaphoreCreate(int numSems);


/*
 * InternalIpcSemaphoreCreate
 *
 * Attempt to create a new semaphore set with the specified key.
 * Will fail (return -1) if such a set already exists.
 *
 * If we fail with a failure code other than collision-with-existing-set,
 * print out an error and abort.  Other types of errors suggest nonrecoverable
 * problems.
 */
static IpcSemaphoreId
InternalIpcSemaphoreCreate(IpcSemaphoreKey semKey, int numSems)
{
	int	semId;

	semId = semget(semKey, numSems, IPC_CREAT | IPC_EXCL | IPCProtection);

	if (semId < 0)
	{
		int	saved_errno = errno;

		/*
		 * Fail quietly if error indicates a collision with existing set. One
		 * would expect EEXIST, given that we said IPC_EXCL, but perhaps we
		 * could get a permission violation instead?  Also, EIDRM might occur
		 * if an old set is slated for destruction but not gone yet.
		 */
		if (saved_errno == EEXIST || saved_errno == EACCES
#ifdef EIDRM
			|| saved_errno == EIDRM
#endif
			)
			return -1;
		/*
		 * Else complain and abort
		 */
		fprintf(stderr, "Failed system call was semget"
				"This error does *not* mean that you have run out of disk space.  "
				"It occurs when either the system limit for the maximum number of "
				"semaphore sets (SEMMNI), or the system wide maximum number of "
				"semaphores (SEMMNS), would be exceeded.  You need to raise the "
				"respective kernel parameter");

		return -1;
	}

	return semId;
}

/*
 * Initialize a semaphore to the specified value.
 */
static void
IpcSemaphoreInitialize(IpcSemaphoreId semId, int semNum, int value)
{
	union semun semun;

	semun.val = value;
	if (semctl(semId, semNum, SETVAL, semun) < 0)
	{
		int			saved_errno = errno;

		fprintf(stderr, "semctl(%d, %d, SETVAL, %d) failed: %m", semId, semNum, value);
		if (saved_errno == ERANGE)
			fprintf(stderr, "You possibly need to raise your kernel's SEMVMX value to be at least %d "
					"Look into the PostgreSQL documentation for details.", value);
		exit(-1);
	}
}

/*
 * IpcSemaphoreKill(semId)	- removes a semaphore set
 */
static void
IpcSemaphoreKill(IpcSemaphoreId semId)
{
	union semun semun;

	semun.val = 0;				/* unused, but keep compiler quiet */

	if (semctl(semId, 0, IPC_RMID, semun) < 0)
	{
		fprintf(stderr, "semctl(%d, 0, IPC_RMID, ...) failed: %m", semId);
		return;
	}
}

/* Get the current value (semval) of the semaphore */
static int
IpcSemaphoreGetValue(IpcSemaphoreId semId, int semNum)
{
	union semun dummy;			/* for Solaris */

	dummy.val = 0;				/* unused */

	return semctl(semId, semNum, GETVAL, dummy);
}

/* Get the PID of the last process to do semop() on the semaphore */
static pid_t
IpcSemaphoreGetLastPID(IpcSemaphoreId semId, int semNum)
{
	union semun dummy;			/* for Solaris */

	dummy.val = 0;				/* unused */

	return semctl(semId, semNum, GETPID, dummy);
}


/*
 * Create a semaphore set with the given number of useful semaphores
 * (an additional sema is actually allocated to serve as identifier).
 * Dead Postgres sema sets are recycled if found, but we do not fail
 * upon collision with non-Postgres sema sets.
 *
 * The idea here is to detect and re-use keys that may have been assigned
 * by a crashed postmaster or backend.
 */
static IpcSemaphoreId
IpcSemaphoreCreate(int numSems)
{
	IpcSemaphoreId semId;
	union semun semun;
	PGSemaphoreData mysema;

	/* Loop till we find a free IPC key */
	for (nextSemaKey++;; nextSemaKey++)
	{
		pid_t		creatorPID;

		/* Try to create new semaphore set */
		semId = InternalIpcSemaphoreCreate(nextSemaKey, numSems + 1);
		if (semId >= 0)
			break;				/* successful create */

		/* See if it looks to be leftover from a dead Postgres process */
		semId = semget(nextSemaKey, numSems + 1, 0);
		if (semId < 0)
			continue;			/* failed: must be some other app's */
		if (IpcSemaphoreGetValue(semId, numSems) != PGSemaMagic)
			continue;			/* sema belongs to a non-Postgres app */

		/*
		 * If the creator PID is my own PID or does not belong to any extant
		 * process, it's safe to zap it.
		 */
		creatorPID = IpcSemaphoreGetLastPID(semId, numSems);
		if (creatorPID <= 0)
			continue;			/* oops, GETPID failed */
		if (creatorPID != getpid())
		{
			if (kill(creatorPID, 0) == 0 || errno != ESRCH)
				continue;		/* sema belongs to a live process */
		}

		/*
		 * The sema set appears to be from a dead Postgres process, or from a
		 * previous cycle of life in this same process.  Zap it, if possible.
		 * This probably shouldn't fail, but if it does, assume the sema set
		 * belongs to someone else after all, and continue quietly.
		 */
		semun.val = 0;			/* unused, but keep compiler quiet */
		if (semctl(semId, 0, IPC_RMID, semun) < 0)
			continue;

		/*
		 * Now try again to create the sema set.
		 */
		semId = InternalIpcSemaphoreCreate(nextSemaKey, numSems + 1);
		if (semId >= 0)
			break;				/* successful create */

		/*
		 * Can only get here if some other process managed to create the same
		 * sema key before we did.  Let him have that one, loop around to try
		 * next key.
		 */
	}

	/*
	 * OK, we created a new sema set.  Mark it as created by this process. We
	 * do this by setting the spare semaphore to PGSemaMagic-1 and then
	 * incrementing it with semop().  That leaves it with value PGSemaMagic
	 * and sempid referencing this process.
	 */
	IpcSemaphoreInitialize(semId, numSems, PGSemaMagic - 1);
	mysema.semId = semId;
	mysema.semNum = numSems;
	PGSemaphoreUnlock(&mysema);

	return semId;
}


/*
 * Release semaphores at shutdown or shmem reinitialization
 *
 * (called as an on_shmem_exit callback, hence funny argument list)
 */
void
ReleaseSemaphores(PGSemaphore sema)
{
	IpcSemaphoreKill(sema->semId);
	return;
}

/*
 * PGSemaphoreCreate
 *
 * Initialize a PGSemaphore structure to represent a sema with count 1
 */
int
PGSemaphoreCreate(PGSemaphore sema)
{
	IpcSemaphoreId id;

	id = IpcSemaphoreCreate(1);
	/* failed, we return zero */
	if (id < 0)
		return 0;

	/* Assign the next free semaphore in the current set */
	sema->semId = id;
	sema->semNum = 1;
	/* Initialize it to count 1 */
	IpcSemaphoreInitialize(sema->semId, sema->semNum, 1);
	return 1;
}


/*
 * PGSemaphoreLock
 *
 * Lock a semaphore (decrement count), blocking if count would be < 0
 */
void
PGSemaphoreLock(PGSemaphore sema)
{
	int			errStatus;
	struct sembuf sops;

	sops.sem_op = -1;			/* decrement */
	sops.sem_flg = 0;
	sops.sem_num = sema->semNum;

	/*
	 * Note: if errStatus is -1 and errno == EINTR then it means we returned
	 * from the operation prematurely because we were sent a signal.  So we
	 * try and lock the semaphore again.
	 *
	 * We used to check interrupts here, but that required servicing
	 * interrupts directly from signal handlers. Which is hard to do safely
	 * and portably.
	 */
	do
	{
		errStatus = semop(sema->semId, &sops, 1);
	} while (errStatus < 0 && errno == EINTR);

	if (errStatus < 0)
	{
		fprintf(stderr, "semop(id=%d) failed: %m", sema->semId);
		exit(-1);
	}
}


/*
 * PGSemaphoreUnlock
 *
 * Unlock a semaphore (increment count)
 */
void
PGSemaphoreUnlock(PGSemaphore sema)
{
	int			errStatus;
	struct sembuf sops;

	sops.sem_op = 1;			/* increment */
	sops.sem_flg = 0;
	sops.sem_num = sema->semNum;

	/*
	 * Note: if errStatus is -1 and errno == EINTR then it means we returned
	 * from the operation prematurely because we were sent a signal.  So we
	 * try and unlock the semaphore again. Not clear this can really happen,
	 * but might as well cope.
	 */
	do
	{
		errStatus = semop(sema->semId, &sops, 1);
	} while (errStatus < 0 && errno == EINTR);

	if (errStatus < 0)
	{
		fprintf(stderr, "semop(id=%d) failed: %m", sema->semId);
		return;
	}
}
