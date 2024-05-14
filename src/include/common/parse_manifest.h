/*-------------------------------------------------------------------------
 *
 * parse_manifest.h
 *	  Parse a backup manifest in JSON format.
 *
 * Portions Copyright (c) 1996-2023, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/common/parse_manifest.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PARSE_MANIFEST_H
#define PARSE_MANIFEST_H

#include "access/xlogdefs.h"
#include "common/checksum_helper.h"
#include "mb/pg_wchar.h"

struct JsonManifestParseContext;
typedef struct JsonManifestParseContext JsonManifestParseContext;

typedef void (*json_manifest_per_file_callback) (JsonManifestParseContext *,
												 char *pathname,
												 size_t size, pg_checksum_type checksum_type,
												 int checksum_length, uint8 *checksum_payload);
typedef void (*json_manifest_per_wal_range_callback) (JsonManifestParseContext *,
													  TimeLineID tli,
													  XLogRecPtr start_lsn, XLogRecPtr end_lsn);
typedef void (*json_manifest_error_callback) (JsonManifestParseContext *,
											  const char *fmt,...) pg_attribute_printf(2, 3)
			pg_attribute_noreturn();

struct JsonManifestParseContext
{
	void	   *private_data;
	json_manifest_per_file_callback per_file_cb;
	json_manifest_per_wal_range_callback per_wal_range_cb;
	json_manifest_error_callback error_cb;
};

extern void json_parse_manifest(JsonManifestParseContext *context,
								char *buffer, size_t size);

#endif
