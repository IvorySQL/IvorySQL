/*-------------------------------------------------------------------------
 *
 * win32_ivysema.c copy from win32_sema.c
 *	  Microsoft Windows Win32 Semaphores Emulation
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/interfaces/libpq/win32_ivysema.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "ivy_sema.h"

/*
 * Release semaphores at shutdown or shmem reinitialization
 *
 */
void
ReleaseSemaphores(PGSemaphore sema)
{
	CloseHandle(*sema);
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
	HANDLE		cur_handle;
	SECURITY_ATTRIBUTES sec_attrs;

	ZeroMemory(&sec_attrs, sizeof(sec_attrs));
	sec_attrs.nLength = sizeof(sec_attrs);
	sec_attrs.lpSecurityDescriptor = NULL;
	sec_attrs.bInheritHandle = TRUE;

	/* We don't need a named semaphore */
	cur_handle = CreateSemaphore(&sec_attrs, 1, 32767, NULL);
	if (cur_handle)
	{
		/* Successfully done */
		*sema = cur_handle;
		return 1;
	}
	fprintf(stderr, "could not create semaphore");
	return 0;
}


/*
 * PGSemaphoreLock
 *
 * Lock a semaphore (decrement count), blocking if count would be < 0.
 * Serve the interrupt if interruptOK is true.
 */
void
PGSemaphoreLock(PGSemaphore sema)
{
	/*
	 * during libpq use, we should ignore server signals
	 */
	HANDLE		wh[1];
	bool		done = false;

	/*
	 * Note: pgwin32_signal_event should be first to ensure that it will be
	 * reported when multiple events are set.  We want to guarantee that
	 * pending signals are serviced.
	 */
	//wh[0] = pgwin32_signal_event;
	wh[0] = *sema;

	/*
	 * As in other implementations of PGSemaphoreLock, we need to check for
	 * cancel/die interrupts each time through the loop.  But here, there is
	 * no hidden magic about whether the syscall will internally service a
	 * signal --- we do that ourselves.
	 */
	while (!done)
	{
		DWORD		rc;

		/* ignore server signals */
		//CHECK_FOR_INTERRUPTS();

		rc = WaitForMultipleObjectsEx(1, wh, FALSE, INFINITE, TRUE);
		switch (rc)
		{
			case WAIT_OBJECT_0:
				/* We got it! */
				done = true;
				break;
			case WAIT_IO_COMPLETION:

				/*
				 * The system interrupted the wait to execute an I/O
				 * completion routine or asynchronous procedure call in this
				 * thread.  PostgreSQL does not provoke either of these, but
				 * atypical loaded DLLs or even other processes might do so.
				 * Now, resume waiting.
				 */
				break;
			case WAIT_FAILED:
				fprintf(stderr, "could not lock semaphore");
				exit(-1);
				break;
			default:
				fprintf(stderr, "unexpected return code from WaitForMultipleObjectsEx(): %lu", rc);
				exit(-1);
				break;
		}
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
	if (!ReleaseSemaphore(*sema, 1, NULL))
	{
		fprintf(stderr, "could not unlock semaphore");
		exit(-1);
	}
}
