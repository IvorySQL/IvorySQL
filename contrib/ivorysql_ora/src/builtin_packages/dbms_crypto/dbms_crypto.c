/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
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
 * Implementation of Oracle's DBMS_CRYPTO package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides cryptographic hashing, MAC generation, and random value generation:
 *   - HASH(src, typ)
 *   - MAC(src, typ, key)
 *   - RANDOMBYTES(number_bytes)
 *   - RANDOMINTEGER()
 *
 * Algorithm constants:
 *   HASH_MD4    = 1 (unsupported / deprecated)
 *   HASH_MD5    = 2
 *   HASH_SH1    = 3
 *   HASH_SH256  = 4
 *   HASH_SH384  = 5
 *   HASH_SH512  = 6
 *   HMAC_MD5    = 1
 *   HMAC_SH1    = 2
 *   HMAC_SH256  = 3
 *   HMAC_SH384  = 4
 *   HMAC_SH512  = 5
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_crypto/dbms_crypto.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "common/cryptohash.h"
#include "common/hmac.h"
#include "common/sha2.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

#define DBMS_CRYPTO_HASH_MD4	1
#define DBMS_CRYPTO_HASH_MD5	2
#define DBMS_CRYPTO_HASH_SH1	3
#define DBMS_CRYPTO_HASH_SH256	4
#define DBMS_CRYPTO_HASH_SH384	5
#define DBMS_CRYPTO_HASH_SH512	6

#define DBMS_CRYPTO_HMAC_MD5	1
#define DBMS_CRYPTO_HMAC_SH1	2
#define DBMS_CRYPTO_HMAC_SH256	3
#define DBMS_CRYPTO_HMAC_SH384	4
#define DBMS_CRYPTO_HMAC_SH512	5

/*
 * dbms_crypto_hash
 *
 * Computes a one-way hash using the specified algorithm.
 */
PG_FUNCTION_INFO_V1(dbms_crypto_hash);
Datum
dbms_crypto_hash(PG_FUNCTION_ARGS)
{
	bytea	   *src_raw;
	const uint8 *data;
	size_t		data_len;
	int32		typ;
	pg_cryptohash_type hash_type;
	size_t		digest_len;
	pg_cryptohash_ctx *ctx;
	bytea	   *result;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	src_raw = PG_GETARG_BYTEA_PP(0);
	data_len = VARSIZE_ANY_EXHDR(src_raw);
	data = (const uint8 *) VARDATA_ANY(src_raw);
	typ = PG_GETARG_INT32(1);

	switch (typ)
	{
		case DBMS_CRYPTO_HASH_MD5:
			hash_type = PG_MD5;
			digest_len = 16;
			break;
		case DBMS_CRYPTO_HASH_SH1:
			hash_type = PG_SHA1;
			digest_len = 20;
			break;
		case DBMS_CRYPTO_HASH_SH256:
			hash_type = PG_SHA256;
			digest_len = PG_SHA256_DIGEST_LENGTH;
			break;
		case DBMS_CRYPTO_HASH_SH384:
			hash_type = PG_SHA384;
			digest_len = PG_SHA384_DIGEST_LENGTH;
			break;
		case DBMS_CRYPTO_HASH_SH512:
			hash_type = PG_SHA512;
			digest_len = PG_SHA512_DIGEST_LENGTH;
			break;
		default:
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("DBMS_CRYPTO: invalid or unsupported hash algorithm: %d", typ)));
			break;
	}

	ctx = pg_cryptohash_create(hash_type);
	if (ctx == NULL)
		ereport(ERROR, (errmsg("out of memory creating cryptohash context")));

	if (pg_cryptohash_init(ctx) < 0 ||
		pg_cryptohash_update(ctx, data, data_len) < 0)
	{
		const char *err = pg_cryptohash_error(ctx);
		pg_cryptohash_free(ctx);
		ereport(ERROR, (errmsg("cryptohash failed: %s", err ? err : "unknown error")));
	}

	result = (bytea *) palloc(digest_len + VARHDRSZ);
	SET_VARSIZE(result, digest_len + VARHDRSZ);

	if (pg_cryptohash_final(ctx, (uint8 *) VARDATA(result), digest_len) < 0)
	{
		const char *err = pg_cryptohash_error(ctx);
		pg_cryptohash_free(ctx);
		pfree(result);
		ereport(ERROR, (errmsg("cryptohash final failed: %s", err ? err : "unknown error")));
	}

	pg_cryptohash_free(ctx);

	PG_RETURN_BYTEA_P(result);
}

/*
 * dbms_crypto_mac
 *
 * Computes a keyed Message Authentication Code (HMAC).
 */
PG_FUNCTION_INFO_V1(dbms_crypto_mac);
Datum
dbms_crypto_mac(PG_FUNCTION_ARGS)
{
	bytea	   *src_raw;
	bytea	   *key_raw;
	const uint8 *data;
	size_t		data_len;
	const uint8 *key;
	size_t		key_len;
	int32		typ;
	pg_cryptohash_type hash_type;
	size_t		digest_len;
	pg_hmac_ctx *ctx;
	bytea	   *result;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2))
		PG_RETURN_NULL();

	src_raw = PG_GETARG_BYTEA_PP(0);
	typ = PG_GETARG_INT32(1);
	key_raw = PG_GETARG_BYTEA_PP(2);

	data_len = VARSIZE_ANY_EXHDR(src_raw);
	data = (const uint8 *) VARDATA_ANY(src_raw);

	key_len = VARSIZE_ANY_EXHDR(key_raw);
	key = (const uint8 *) VARDATA_ANY(key_raw);

	switch (typ)
	{
		case DBMS_CRYPTO_HMAC_MD5:
			hash_type = PG_MD5;
			digest_len = 16;
			break;
		case DBMS_CRYPTO_HMAC_SH1:
			hash_type = PG_SHA1;
			digest_len = 20;
			break;
		case DBMS_CRYPTO_HMAC_SH256:
			hash_type = PG_SHA256;
			digest_len = PG_SHA256_DIGEST_LENGTH;
			break;
		case DBMS_CRYPTO_HMAC_SH384:
			hash_type = PG_SHA384;
			digest_len = PG_SHA384_DIGEST_LENGTH;
			break;
		case DBMS_CRYPTO_HMAC_SH512:
			hash_type = PG_SHA512;
			digest_len = PG_SHA512_DIGEST_LENGTH;
			break;
		default:
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("DBMS_CRYPTO: invalid or unsupported MAC algorithm: %d", typ)));
			break;
	}

	ctx = pg_hmac_create(hash_type);
	if (ctx == NULL)
		ereport(ERROR, (errmsg("out of memory creating HMAC context")));

	if (pg_hmac_init(ctx, key, key_len) < 0 ||
		pg_hmac_update(ctx, data, data_len) < 0)
	{
		const char *err = pg_hmac_error(ctx);
		pg_hmac_free(ctx);
		ereport(ERROR, (errmsg("HMAC failed: %s", err ? err : "unknown error")));
	}

	result = (bytea *) palloc(digest_len + VARHDRSZ);
	SET_VARSIZE(result, digest_len + VARHDRSZ);

	if (pg_hmac_final(ctx, (uint8 *) VARDATA(result), digest_len) < 0)
	{
		const char *err = pg_hmac_error(ctx);
		pg_hmac_free(ctx);
		pfree(result);
		ereport(ERROR, (errmsg("HMAC final failed: %s", err ? err : "unknown error")));
	}

	pg_hmac_free(ctx);

	PG_RETURN_BYTEA_P(result);
}

/*
 * dbms_crypto_randombytes
 *
 * Generates random bytes of requested length.
 */
PG_FUNCTION_INFO_V1(dbms_crypto_randombytes);
Datum
dbms_crypto_randombytes(PG_FUNCTION_ARGS)
{
	int32		num_bytes;
	bytea	   *result;
	int			i;
	uint8	   *p;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	num_bytes = PG_GETARG_INT32(0);
	if (num_bytes <= 0 || num_bytes > 32767)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_CRYPTO: number_bytes must be between 1 and 32767")));

	result = (bytea *) palloc(num_bytes + VARHDRSZ);
	SET_VARSIZE(result, num_bytes + VARHDRSZ);
	p = (uint8 *) VARDATA(result);

	/* Populate with pseudo-random bytes */
	for (i = 0; i < num_bytes; i++)
		p[i] = (uint8) (random() & 0xFF);

	PG_RETURN_BYTEA_P(result);
}

/*
 * dbms_crypto_randominteger
 *
 * Returns a random 32-bit signed integer.
 */
PG_FUNCTION_INFO_V1(dbms_crypto_randominteger);
Datum
dbms_crypto_randominteger(PG_FUNCTION_ARGS)
{
	int32 r = (int32) ((random() << 1) ^ random());
	PG_RETURN_INT32(r);
}
