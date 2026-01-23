/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * This file contains code borrowed from orafce by Pavel Stehule (0-Clause BSD)
 * 
 * utl_file.c
 *
 * Implementation of Oracle's UTL_FILE package functions.
 * This module is part of ivorysql_ora extension but calls the PL/iSQL
 * API to access exception context information.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_file/utl_file.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>

#include "executor/spi.h"

#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "funcapi.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "port.h"
#include "storage/fd.h"
#include "storage/ipc.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

#define int2size(v)			v
#define size2int(v)			v

#define INVALID_FILEHANDLE		"INVALID_FILEHANDLE"
#define INVALID_MAXLINESIZE		"INVALID_MAXLINESIZE"
#define INVALID_MODE			"INVALID_MODE"
#define INVALID_OPERATION		"INVALID_OPERATION"
#define	INVALID_PATH			"INVALID_PATH"
#define READ_ERROR				"READ_ERROR"
#define VALUE_ERROR				"VALUE_ERROR"
#define WRITE_ERROR				"WRITE_ERROR"

/* ora_utl_file functions */
PG_FUNCTION_INFO_V1(ora_utl_file_fopen);
PG_FUNCTION_INFO_V1(ora_utl_file_is_open);
PG_FUNCTION_INFO_V1(ora_utl_file_fclose);
PG_FUNCTION_INFO_V1(ora_utl_file_fclose_all);
PG_FUNCTION_INFO_V1(ora_utl_file_put_line);

/* Helper functions */
static void check_secure_locality(const char *path);
static char *safe_named_location(text *location);
static char *get_safe_path(text *location, text *filename);
static void close_all_files(void);
static void put_lines(FILE *fd, int lines);
static FILE *do_put(PG_FUNCTION_ARGS);
static size_t
do_write(PG_FUNCTION_ARGS, int n, FILE *fd,
	size_t max_linesize, int encoding);
static FILE *
get_file_handle_from_slot(uint32 sid, size_t *max_linesize, int *encoding);
static void do_flush(FILE *fd);
static char *
encode_text(int encoding, text *t, size_t *length);

/* Cleanup callback functions */
static void BeforeShmemExit_Files(int code, Datum arg);
static void
resource_cleanup_callback(ResourceReleasePhase phase,
                         bool isCommit,
                         bool isTopLevel,
                         void *arg);
static FILE *free_slot(uint32 sid);
static uint32 reserve_slot(FILE *fd, int max_linesize, int encoding);

/* Helper macros */
#define CUSTOM_EXCEPTION(msg, detail) \
	ereport(ERROR, \
		(errcode(ERRCODE_RAISE_EXCEPTION), \
		 errmsg("%s", msg), \
		 errdetail("%s", detail)))

#define CUSTOM_WARNING(msg, detail) \
	ereport(WARNING, \
		(errcode(ERRCODE_RAISE_EXCEPTION), \
		 errmsg("%s", msg), \
		 errdetail("%s", detail)))

#define STRERROR_EXCEPTION(msg) \
	do { char *strerr = strerror(errno); CUSTOM_EXCEPTION(msg, strerr); } while(0);

#define INVALID_FILEHANDLE_EXCEPTION()	CUSTOM_EXCEPTION(INVALID_FILEHANDLE, "File handle is invalid.")
#define INVALID_FILEHANDLE_WARNING()	CUSTOM_WARNING(INVALID_FILEHANDLE, "File handle is invalid.")

#define NON_EMPTY_TEXT(dat) \
	if (VARSIZE(dat) - VARHDRSZ == 0) \
		ereport(ERROR, \
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE), \
			 errmsg("invalid parameter"), \
			 errdetail("Empty string isn't allowed.")));

#define NOT_NULL_ARG(n) \
	if (PG_ARGISNULL(n)) \
		ereport(ERROR, \
			(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED), \
			 errmsg("null value not allowed"), \
			 errhint("%dth argument is NULL.", n)));

#define MAX_LINESIZE		32767
#define CHECK_LINESIZE(max_linesize) \
	do { \
		if ((max_linesize) < 1 || (max_linesize) > MAX_LINESIZE) \
			CUSTOM_EXCEPTION(INVALID_MAXLINESIZE, "The max_linesize value for FOPEN() is invalid; it should be within the range 1 to 32767."); \
	} while(0)

#define CHECK_ERRNO_PUT()  \
	switch (errno) \
	{ \
		case EBADF: \
			CUSTOM_EXCEPTION(INVALID_OPERATION, "File could not be opened or operated on as requested."); \
			break; \
		default: \
			STRERROR_EXCEPTION(WRITE_ERROR); \
	}

#define PG_GETARG_IF_EXISTS(n, type, defval) \
	((PG_NARGS() > (n) && !PG_ARGISNULL(n)) ? PG_GETARG_##type(n) : (defval))

typedef struct FileSlot
{
	FILE	*fd;
	int		max_linesize;
	int		encoding;
	uint32	id;
} FileSlot;

#define MAX_SLOTS		50			/* Oracle 10g supports 50 files */
#define INVALID_SLOTID	0			/* invalid slot id */

static FileSlot	slots[MAX_SLOTS];	/* initialized with zeros */

static uint32	slotid = INVALID_SLOTID;			/* next slot id */
#define NEXT_SLOTID(sid) \
    ((sid) == UINT32_MAX ? 1 : (++(sid)))

/*
 * Find any free slot, saves handle in that
 * Returns slot ID or INVALID_SLOTID if no free slot found
 */
static uint32
reserve_slot(FILE *fd, int max_linesize, int encoding)
{
	if(fd == NULL)
	{
		INVALID_FILEHANDLE_WARNING();
		return INVALID_SLOTID;
	}

	for (int i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id != INVALID_SLOTID)
			continue;

		slots[i].id = NEXT_SLOTID(slotid);
		slots[i].fd = fd;
		slots[i].max_linesize = max_linesize;
		slots[i].encoding = encoding;

		return slots[i].id;
	}

	return INVALID_SLOTID;
}

/*
 * Clears the slot with given ID
 * Returns File* that was stored in the slot
 * Caller must close the returned handle, if not required anymore.
 */
static FILE *
free_slot(uint32 sid)
{
	FILE *fd = NULL;

	for (int i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id == sid)
		{
			fd = slots[i].fd;

			slots[i].id = INVALID_SLOTID;
			slots[i].fd = NULL;
			slots[i].max_linesize = 0;
			slots[i].encoding = 0;

			return fd;
		}
	}

	return NULL;
}

static void
IO_EXCEPTION(void)
{
	switch (errno)
	{
		case EACCES:
		case ENAMETOOLONG:
		case ENOENT:
		case ENOTDIR:
			STRERROR_EXCEPTION(INVALID_PATH);
			break;

		default:
			STRERROR_EXCEPTION(INVALID_OPERATION);
	}
}

/*
 * FUNCTION UTL_FILE.FOPEN(location text,
 *			   filename text,
 *			   open_mode text,
 *			   max_linesize integer
 *			   [, encoding text ])
 *          RETURNS UTL_FILE.FILE_TYPE;
 *
 * The FOPEN function opens specified file and returns file handle (i.e. FILE_TYPE).
 *  open_mode: ['R', 'W', 'A']
 *  max_linesize: [1 .. 32767]
 *
 * Exceptions:
 *  INVALID_MODE, INVALID_OPERATION, INVALID_PATH, INVALID_MAXLINESIZE
 */
Datum
ora_utl_file_fopen(PG_FUNCTION_ARGS)
{
	text			*open_mode;
	int				max_linesize;
	int				encoding;
	const char		*mode = NULL;
	FILE			*fd;
	const char		*fullname;
	uint32			sid;
	static bool 	callback_registered = false;

	NOT_NULL_ARG(0);
	NOT_NULL_ARG(1);
	NOT_NULL_ARG(2);
	NOT_NULL_ARG(3);

	open_mode = PG_GETARG_TEXT_P(2);

	NON_EMPTY_TEXT(open_mode);

	max_linesize = PG_GETARG_INT32(3);
	CHECK_LINESIZE(max_linesize);

	if (PG_NARGS() > 4 && !PG_ARGISNULL(4))
	{
		const char *encname = NameStr(*PG_GETARG_NAME(4));
		encoding = pg_char_to_encoding(encname);
		if (encoding < 0)
			ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid encoding name \"%s\"", encname)));
	}
	else
		encoding = GetDatabaseEncoding();

	if (VARSIZE(open_mode) - VARHDRSZ != 1)
		CUSTOM_EXCEPTION(INVALID_MODE, "The open_mode parameter in FOPEN is invalid.");

	switch (*((char*)VARDATA(open_mode)))
	{
		case 'a':
		case 'A':
			mode = "a";
			break;

		case 'r':
		case 'R':
			mode = "r";
			break;

		case 'w':
		case 'W':
			mode = "w";
			break;

		default:
			CUSTOM_EXCEPTION(INVALID_MODE, "The open_mode parameter in FOPEN is invalid.");
	}

	fullname = get_safe_path(PG_GETARG_TEXT_P(0), PG_GETARG_TEXT_P(1));

	/*
	 * PostgreSQL's file management APIs (src/include/storage/fd.h) are not used here
	 * because functions like AllocateFile perform automatic cleanup at transaction
	 * commit or abort. Since this module requires files to remain open for Oracle compatibility,
	 * we implement separate file handling.
	 */

	fd = fopen(fullname, mode);

	if (fd == NULL)
		IO_EXCEPTION();

	sid = reserve_slot(fd, max_linesize, encoding);
	if (sid == INVALID_SLOTID)
	{
		fclose(fd);
		ereport(ERROR,
		    (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
		     errmsg("program limit exceeded"),
		     errdetail("Maximum number of open files exceeded"),
		     errhint("You can have a maximum of %d files open simultaneously.", MAX_SLOTS)));
	}

	/* Register cleanup callbacks */
	if(!callback_registered)
	{
		/* Register cleanup callback only once */
		RegisterResourceReleaseCallback(resource_cleanup_callback, NULL);

		/*
		* Register before-shmem-exit hook to ensure temp files are dropped while
		* we can still report stats.
		*/
		before_shmem_exit(BeforeShmemExit_Files, 0);
		callback_registered = true;
	}

	PG_RETURN_UINT32(sid);
}

Datum
ora_utl_file_is_open(PG_FUNCTION_ARGS)
{
	int	sid = PG_GETARG_INT32(0);

	if(sid == INVALID_SLOTID)
		PG_RETURN_BOOL(false);

	for (int i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id == sid)
			PG_RETURN_BOOL(slots[i].fd != NULL);
	}

	PG_RETURN_BOOL(false);
}

#define CHECK_LENGTH(l) \
	if (l > max_linesize) \
		CUSTOM_EXCEPTION(VALUE_ERROR, "buffer is too short");

/*
 * FUNCTION UTL_FILE.FCLOSE(file UTL_FILE.FILE_TYPE)
 *          RETURNS NULL
 *
 * Closes a file. It also resets an occupied slot.
 *
 * Exception:
 *  INVALID_FILEHANDLE, WRITE_ERROR
 */
Datum
ora_utl_file_fclose(PG_FUNCTION_ARGS)
{
	FILE *fd = free_slot(PG_GETARG_INT32(0));

	if(fd == NULL)
	{
		INVALID_FILEHANDLE_WARNING();
		PG_RETURN_NULL();
	}

	if (fclose(fd) == 0)
		PG_RETURN_NULL();

	/* file was not closed, throw appropriate exception */
	if (errno == EBADF)
		INVALID_FILEHANDLE_EXCEPTION();
	else
		STRERROR_EXCEPTION(WRITE_ERROR);
}

/*
 * FUNCTION UTL_FILE.FCLOSE_ALL()
 *          RETURNS void
 *
 * Closes all open file handles
 *
 * Exceptions: WRITE_ERROR
 */
Datum
ora_utl_file_fclose_all(PG_FUNCTION_ARGS)
{
	close_all_files();
	PG_RETURN_VOID();
}

Datum
ora_utl_file_put_line(PG_FUNCTION_ARGS)
{
	FILE   *fd;
	bool	autoflush;

	fd = do_put(fcinfo);

	autoflush = PG_GETARG_IF_EXISTS(2, BOOL, false);

	put_lines(fd, 1);

	if (autoflush)
		do_flush(fd);

	PG_RETURN_BOOL(true);
}

/*
 * sys.utl_file_directory security .. is solved with aux. table.
 *
 * Raise exception if don't find string in table.
 */
static void
check_secure_locality(const char *path)
{
	static SPIPlanPtr	plan = NULL;

	Datum	values[1];
	char	nulls[1] = {' '};

	values[0] = CStringGetTextDatum(path);

	/*
	 * SELECT 1 FROM sys.utl_file_directory
	 *   WHERE CASE WHEN substring(dir from '.$') = '/' THEN
	 *     substring($1, 1, length(dir)) = dir
	 *   ELSE
	 *     substring($1, 1, length(dir) + 1) = dir || '/'
	 *   END
	 */

	if (SPI_connect() < 0)
		ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("SPI_connect failed")));

	if (!plan)
	{
		Oid		argtypes[] = {TEXTOID};

		/*
		 * Directory names may contain '_' or '%' characters, 
		 * so we prefer equality over LIKE operator to bypass
		 * the '_' and '%' special handling.
		 */
		SPIPlanPtr p = SPI_prepare(
		    "SELECT 1 FROM sys.utl_file_directory"
	 	        " WHERE CASE WHEN substring(dir from '.$') = '/' THEN"
	 	        "  substring($1, 1, length(dir)) = dir"
	 	        " ELSE"
	 	        "  substring($1, 1, length(dir) + 1) = dir || '/'"
	 	        " END",
		    1, argtypes);

		if (p == NULL || (plan = SPI_saveplan(p)) == NULL)
			ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("SPI_prepare_failed")));
	}

	if (SPI_OK_SELECT != SPI_execute_plan(plan, values, nulls, false, 1))
		ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("can't execute sql")));

	if (SPI_processed == 0)
		ereport(ERROR,
			(errcode(ERRCODE_RAISE_EXCEPTION),
			 errmsg(INVALID_PATH),
			 errdetail("File location is invalid."),
			 errhint("locality is not found in sys.utl_file_directory table")));
	SPI_finish();
}

static char *
safe_named_location(text *location)
{
	static SPIPlanPtr	plan = NULL;
	MemoryContext		old_cxt;

	Datum	values[1];
	char	nulls[1] = {' '};
	char   *result;

	old_cxt = CurrentMemoryContext;

	values[0] = PointerGetDatum(location);

	if (SPI_connect() < 0)
		ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("SPI_connect failed")));

	if (!plan)
	{
		Oid		argtypes[] = {TEXTOID};

		/* Don't use LIKE not to escape '_' and '%' */
		SPIPlanPtr p = SPI_prepare(
		    "SELECT dir FROM sys.utl_file_directory WHERE dirname = $1",
		    1, argtypes);

		if (p == NULL || (plan = SPI_saveplan(p)) == NULL)
			ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("SPI_prepare_failed")));
	}

	if (SPI_OK_SELECT != SPI_execute_plan(plan, values, nulls, false, 1))
		ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("can't execute sql")));

	if (SPI_processed > 0)
	{
		char	   *loc = SPI_getvalue(SPI_tuptable->vals[0],
									   SPI_tuptable->tupdesc, 1);
		if (loc)
			result = MemoryContextStrdup(old_cxt, loc);
		else
			result = NULL;
	}
	else
		result = NULL;

	SPI_finish();

	return result;
}

/*
 * get_safe_path - make a fullpath and check security.
 */
static char *
get_safe_path(text *location_or_dirname, text *filename)
{
	char	   *fullname;
	char	   *location;
	bool		check_locality;

	NON_EMPTY_TEXT(location_or_dirname);
	NON_EMPTY_TEXT(filename);

	location = safe_named_location(location_or_dirname);
	if (location)
	{
		int		aux_pos = size2int(strlen(location));
		int		aux_len = VARSIZE_ANY_EXHDR(filename);

		fullname = palloc(aux_pos + 1 + aux_len + 1);
		strcpy(fullname, location);
		fullname[aux_pos] = '/';
		memcpy(fullname + aux_pos + 1, VARDATA(filename), aux_len);
		fullname[aux_pos + aux_len + 1] = '\0';

		/* location is safe (ensured by dirname) */
		check_locality = false;
		pfree(location);
	}
	else
	{
		int aux_pos = VARSIZE_ANY_EXHDR(location_or_dirname);
		int aux_len = VARSIZE_ANY_EXHDR(filename);

		fullname = palloc(aux_pos + 1 + aux_len + 1);
		memcpy(fullname, VARDATA(location_or_dirname), aux_pos);
		fullname[aux_pos] = '/';
		memcpy(fullname + aux_pos + 1, VARDATA(filename), aux_len);
		fullname[aux_pos + aux_len + 1] = '\0';

		check_locality = true;
	}

	/* check locality in canonizalized form of path */
	canonicalize_path(fullname);

	if (check_locality)
		check_secure_locality(fullname);

	return fullname;
}

static void
close_all_files(void)
{
	FILE *fd = NULL;
	bool report_error = false;

	for (int i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id != INVALID_SLOTID)
		{
			fd = slots[i].fd;

			slots[i].id = INVALID_SLOTID;
			slots[i].fd = NULL;
			slots[i].max_linesize = 0;
			slots[i].encoding = 0;

			/* 
			 * Oracle documentation says: FCLOSE_ALL does not alter the state of the 
			 * open file handles held by the user. This means that an IS_OPEN test on
			 * a file handle after an FCLOSE_ALL call still returns TRUE, even though
			 * the file has been closed. No further read or write operations can be
			 * performed on a file that was open before an FCLOSE_ALL. 
			 * 
			 * However, 
			 * 
			 * we choose to close the file handles and free the slots here 
			 * to avoid dangling file handles.
			 */

			if(fd != NULL && fclose(fd) == 0)
				continue;
			else
				report_error = true;
		}
	}

	/* some file(s) were not closed, throw exception */
	if(report_error)
		STRERROR_EXCEPTION(WRITE_ERROR);
}

/*
 * Callback function that closes all opened files
 * Runs when session ends abnormally (crash, disconnect, commit/rollback/abort)
 */
static void
resource_cleanup_callback(ResourceReleasePhase phase,
                         bool isCommit,
                         bool isTopLevel,
                         void *arg)
{
	/*
	 * Only run in the final cleanup phase
     * isTopLevel = true only for top-level transaction (session end)
     * When session ends, this is always true
     */
    if (phase != RESOURCE_RELEASE_AFTER_LOCKS || !isTopLevel)
	{
        return;
	}

	/* Close all files if session ended abnormally */
	if(!isCommit)
	{
		close_all_files();
	}
}

/*
 * BeforeShmemExit_Files
 *
 * before_shmem_exit hook to closes all opened files during backend shutdown.
 */
static void
BeforeShmemExit_Files(int code, Datum arg)
{
	close_all_files();
}

static void
put_lines(FILE *fd, int lines)
{
	for (int i = 0; i < lines; i++)
	{
		if (fputc('\n', fd) == EOF)
		    CHECK_ERRNO_PUT();
	}
}

static FILE *
do_put(PG_FUNCTION_ARGS)
{
	FILE   *fd;
	size_t	max_linesize = 0;
	int		encoding = 0;

	if (PG_ARGISNULL(0))
		INVALID_FILEHANDLE_EXCEPTION();

	fd = get_file_handle_from_slot(PG_GETARG_UINT32(0), &max_linesize, &encoding);

	NOT_NULL_ARG(1);
	do_write(fcinfo, 1, fd, max_linesize, encoding);
	return fd;
}

/* fwrite(encode(args[n], encoding), fd) */
static size_t
do_write(PG_FUNCTION_ARGS, int n, FILE *fd, size_t max_linesize, int encoding)
{
	text	*arg = PG_GETARG_TEXT_P(n);
	char	*str;
	size_t	len;

	str = encode_text(encoding, arg, &len);
	CHECK_LENGTH(len);

	if (fwrite(str, 1, len, fd) != len)
		CHECK_ERRNO_PUT();

	if (VARDATA(arg) != str)
		pfree(str);
	PG_FREE_IF_COPY(arg, n);

	return len;
}

/* 
 * Returns stored FILE handle
 * Also, sets max_linesize and encoding
 */
static FILE *
get_file_handle_from_slot(uint32 sid, size_t *max_linesize, int *encoding)
{
	int i;

	if (sid == INVALID_SLOTID)
		INVALID_FILEHANDLE_EXCEPTION();

	for (i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id == sid)
		{
			if (max_linesize)
				*max_linesize = slots[i].max_linesize;
			if (encoding)
				*encoding = slots[i].encoding;
			return slots[i].fd;
		}
	}

	INVALID_FILEHANDLE_WARNING();
	return NULL;
}

static void
do_flush(FILE *fd)
{
	if (fflush(fd) != 0)
	{
		if (errno == EBADF)
			CUSTOM_EXCEPTION(INVALID_OPERATION, "File could not be opened or operated on as requested.");
		else
			STRERROR_EXCEPTION(WRITE_ERROR);
	}
}

/* encode(t, encoding) */
static char *
encode_text(int encoding, text *t, size_t *length)
{
	char	   *src = VARDATA_ANY(t);
	char	   *encoded;

	encoded = (char *) pg_do_encoding_conversion((unsigned char *) src,
					VARSIZE_ANY_EXHDR(t), GetDatabaseEncoding(), encoding);

	*length = (src == encoded ? VARSIZE_ANY_EXHDR(t) : strlen(encoded));
	return encoded;
}
