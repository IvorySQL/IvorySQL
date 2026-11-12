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
int
PGSemaphoreLock(PGSemaphore sema)
{
        HANDLE          wh[1];
        bool            done = false;

        wh[0] = *sema;

        while (!done)
        {
                DWORD           rc;

                rc = WaitForMultipleObjectsEx(1, wh, FALSE, INFINITE, TRUE);
                switch (rc)
                {
                        case WAIT_OBJECT_0:
                                done = true;
                                break;

                        case WAIT_IO_COMPLETION:
                                break;

                        case WAIT_FAILED:
                                fprintf(stderr,
                                                "could not lock semaphore: error %lu\n",
                                                (unsigned long) GetLastError());
                                return 0;

                        default:
                                fprintf(stderr,
                                                "unexpected return code from WaitForMultipleObjectsEx(): %lu\n",
                                                (unsigned long) rc);
                                return 0;
                }
        }

        return 1;
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
                fprintf(stderr,
                                "could not unlock semaphore: error %lu\n",
                                (unsigned long) GetLastError());
                return;
        }
}
