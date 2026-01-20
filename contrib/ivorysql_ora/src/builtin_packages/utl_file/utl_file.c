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

PG_FUNCTION_INFO_V1(ora_utl_file_fopen);
PG_FUNCTION_INFO_V1(ora_utl_file_is_open);
PG_FUNCTION_INFO_V1(ora_utl_file_fclose);
PG_FUNCTION_INFO_V1(ora_utl_file_fclose_all);

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
			CUSTOM_EXCEPTION(INVALID_MAXLINESIZE, "The MAX_LINESIZE value for FOPEN() is invalid; it should be within the range 1 to 32767."); \
	} while(0)

typedef struct FileSlot
{
	FILE   *file;
	int		max_linesize;
	int		encoding;
	int32	id;
} FileSlot;

#define MAX_SLOTS		50			/* Oracle 10g supports 50 files */
#define INVALID_SLOTID	0			/* invalid slot id */

static FileSlot	slots[MAX_SLOTS];	/* initilaized with zeros */
static int32	slotid = INVALID_SLOTID;			/* next slot id */

static void check_secure_locality(const char *path);
static char *safe_named_location(text *location);
static char *get_safe_path(text *location, text *filename);

/*
 * reserve_file_handle_slot(FILE *file) find any free slot for FILE pointer.
 */
static int
reserve_file_handle_slot(FILE *file, int max_linesize, int encoding)
{
	for (int i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id == INVALID_SLOTID)
		{
			slots[i].id = ++slotid;
			/* XXX - to be removed. unnecessary check */
			//if (slots[i].id == INVALID_SLOTID)
			//	slots[i].id = ++slotid;	/* skip INVALID_SLOTID */
			slots[i].file = file;
			slots[i].max_linesize = max_linesize;
			slots[i].encoding = encoding;
			return slots[i].id;
		}
	}

	return INVALID_SLOTID;
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
 * The FOPEN function opens specified file and returns file handle.
 *  open_mode: ['R', 'W', 'A']
 *  max_linesize: [1 .. 32767]
 *
 * Exceptions:
 *  INVALID_MODE, INVALID_OPERATION, INVALID_PATH, INVALID_MAXLINESIZE
 */
Datum
ora_utl_file_fopen(PG_FUNCTION_ARGS)
{
	text	   *open_mode;
	int			max_linesize;
	int			encoding;
	const char *mode = NULL;
	FILE	   *file;
	char	   *fullname;
	int			d;

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
		CUSTOM_EXCEPTION(INVALID_MODE, "open mode is different than [R,W,A]");

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
			CUSTOM_EXCEPTION(INVALID_MODE, "open mode is different than [R,W,A]");
	}

	/* open file */
	fullname = get_safe_path(PG_GETARG_TEXT_P(0), PG_GETARG_TEXT_P(1));

	/*
	 * PostgreSQL's file management APIs (src/include/storage/fd.h) are not used here
	 * because functions like AllocateFile perform automatic cleanup at transaction
	 * commit or abort. Since this module requires files to remain open for Oracle compatibility,
	 * we implement separate file handling.
	 */

	file = fopen(fullname, mode);

	if (!file)
		IO_EXCEPTION();

	d = reserve_file_handle_slot(file, max_linesize, encoding);
	if (d == INVALID_SLOTID)
	{
		fclose(file);
		ereport(ERROR,
		    (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
		     errmsg("program limit exceeded"),
		     errdetail("Maximum number of open files exceeded"),
		     errhint("You can have a maximum of %d files open simultaneously.", MAX_SLOTS)));
	}

	PG_RETURN_INT32(d);
}

Datum
ora_utl_file_is_open(PG_FUNCTION_ARGS)
{
	if (!PG_ARGISNULL(0))
	{
		int	i;
		int	d = PG_GETARG_INT32(0);

		for (i = 0; i < MAX_SLOTS; i++)
		{
			if (slots[i].id == d)
				PG_RETURN_BOOL(slots[i].file != NULL);
		}
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
	int i;
	int	d = PG_GETARG_INT32(0);

	for (i = 0; i < MAX_SLOTS; i++)
	{
		if (slots[i].id == d)
		{
			if (slots[i].file && fclose(slots[i].file) != 0)
			{
				if (errno == EBADF)
					INVALID_FILEHANDLE_EXCEPTION();
				else
					STRERROR_EXCEPTION(WRITE_ERROR);
			}
			slots[i].file = NULL;
			slots[i].id = INVALID_SLOTID;
			PG_RETURN_NULL();
		}
	}

	INVALID_FILEHANDLE_WARNING();
	PG_RETURN_NULL();
}


/*
 * sys.ora_utl_file_dir security .. is solved with aux. table.
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
	 * SELECT 1 FROM sys.ora_utl_file_dir
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
		    "SELECT 1 FROM sys.ora_utl_file_dir"
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
			 errhint("locality is not found in sys.ora_utl_file_dir table")));
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
		    "SELECT dir FROM sys.ora_utl_file_dir WHERE dirname = $1",
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
