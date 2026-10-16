/*-------------------------------------------------------------------------
 *
 * posix_ivysema.c s based on posix_sema.c
 *	  Implement PGSemaphores using POSIX semaphore facilities
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/interfaces/libpq/posix_ivysema.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include "ivy_sema.h"

#ifdef USE_NAMED_POSIX_SEMAPHORES
#define PG_SEM_REF(x)	(*(x))
#else
#define PG_SEM_REF(x)	(x)
#endif

#define IPCProtection	(0600)	

#ifdef USE_NAMED_POSIX_SEMAPHORES
static int	nextSemKey;			/* next to try */


/*
 * PosixSemaphoreCreate
 *
 * Attempt to create a new named semaphore.
 *
 * If we fail with a failure code other than collision-with-existing-sema,
 * print out an error and abort.  Other types of errors suggest nonrecoverable
 * problems.
 */
static sem_t *
PosixSemaphoreCreate(void)
{
	int	semKey;
	char	semname[64];
	sem_t   *mySem;

	for (;;)
	{
		semKey = nextSemKey++;

		snprintf(semname, sizeof(semname), "/libpq-%d", semKey);

		mySem = sem_open(semname, O_CREAT | O_EXCL,
					 (mode_t) IPCProtection, (unsigned) 1);

#ifdef SEM_FAILED
		if (mySem != (sem_t *) SEM_FAILED)
			break;
#else
		if (mySem != (sem_t *) (-1))
			break;
#endif

		/* Loop if error indicates a collision */
		if (errno == EEXIST || errno == EACCES || errno == EINTR)
			continue;

		/*
		 * Else complain and abort
		 */
		fprintf(stderr, "sem_open(\"%s\") failed: %m", semname);
		return NULL;
	}

	/*
	 * Unlink the semaphore immediately, so it can't be accessed externally.
	 * This also ensures that it will go away if we crash.
	 */
	sem_unlink(semname);

	return mySem;
}
#else							/* !USE_NAMED_POSIX_SEMAPHORES */

/*
 * PosixSemaphoreCreate
 *
 * Attempt to create a new unnamed semaphore.
 */
static int
PosixSemaphoreCreate(sem_t * sem)
{
	if (sem_init(sem, 1, 1) < 0)
	{
		fprintf(stderr, "sem_init failed: %m");
		return -1;
	}

	return 1;
}
#endif   /* USE_NAMED_POSIX_SEMAPHORES */


/*
 * PosixSemaphoreKill	- removes a semaphore
 */
static void
PosixSemaphoreKill(sem_t * sem)
{
#ifdef USE_NAMED_POSIX_SEMAPHORES
	/* use sem_close for named semaphores */
	if (sem_close(sem) < 0)
	{
		fprintf(stderr, "sem_close failed: %m");
		return;
	}
#else
	/* use sem_destroy for unnamed semaphores */
	if (sem_destroy(sem) < 0)
	{
		fprintf(stderr, "sem_destroy failed: %m");
		return;
	}
#endif
}


/*
 * Release semaphores at shutdown or shmem reinitialization
 *
 */
void
ReleaseSemaphores(PGSemaphore sema)
{
#ifdef USE_NAMED_POSIX_SEMAPHORES
	PosixSemaphoreKill(*sema);
#else
	PosixSemaphoreKill(sema);
#endif
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
	int result;

#ifdef USE_NAMED_POSIX_SEMAPHORES
	*sema = PosixSemaphoreCreate();

	if (*sema != 0)
		result = 1;
	else
		result = 0;
#else
	result = PosixSemaphoreCreate(sema);
#endif
	return result;
}

/*
 * PGSemaphoreLock
 *
 * Lock a semaphore (decrement count), blocking if count would be < 0
 */
void
PGSemaphoreLock(PGSemaphore sema)
{
	int	errStatus;

	do
	{
		errStatus = sem_wait(PG_SEM_REF(sema));
	} while (errStatus < 0 && errno == EINTR);

	if (errStatus < 0)
	{
		fprintf(stderr, "sem_wait failed: %m");
		return;
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
	int	errStatus;

	/*
	 * Note: if errStatus is less than 0 and errno == EINTR then it means
	 *  we returned from the operation prematurely because we were sent a signal. 
	 *  So we try and unlock the semaphore again. 
	 */
	do
	{
		errStatus = sem_post(PG_SEM_REF(sema));
	} while (errStatus < 0 && errno == EINTR);

	if (errStatus < 0)
	{
		fprintf(stderr, "sem_post failed: %m");
		return;
	}
}
