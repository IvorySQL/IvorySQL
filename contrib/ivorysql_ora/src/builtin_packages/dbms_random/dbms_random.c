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
 * Implementation of Oracle's DBMS_RANDOM package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides INITIALIZE, SEED, TERMINATE, NORMAL, RANDOM, STRING and VALUE.
 * The generator state is per-backend (session-scoped) and seeded from
 * PostgreSQL's portable PRNG (pg_prng), so a session that calls
 * INITIALIZE/SEED with a given seed observes a deterministic sequence -
 * which is what Oracle migrations use these interfaces for.  As with
 * orafce, the produced sequences are not bit-for-bit identical to
 * Oracle's proprietary generator.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_random/dbms_random.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "varatt.h"

#include "fmgr.h"
#include "miscadmin.h"
#include "common/hashfn.h"
#include "common/pg_prng.h"
#include "utils/builtins.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"

#include "../../include/ivorysql_ora.h"

/* Oracle's DBMS_RANDOM.STRING() maximum length */
#define DBMS_RANDOM_MAX_STRING_LEN	4000

/* Per-backend generator state */
static pg_prng_state random_state;
static bool		state_seeded = false;

/* SQL-callable function declarations */
PG_FUNCTION_INFO_V1(ora_dbms_random_initialize);
PG_FUNCTION_INFO_V1(ora_dbms_random_seed_number);
PG_FUNCTION_INFO_V1(ora_dbms_random_seed_text);
PG_FUNCTION_INFO_V1(ora_dbms_random_terminate);
PG_FUNCTION_INFO_V1(ora_dbms_random_normal);
PG_FUNCTION_INFO_V1(ora_dbms_random_random);
PG_FUNCTION_INFO_V1(ora_dbms_random_string);
PG_FUNCTION_INFO_V1(ora_dbms_random_value);
PG_FUNCTION_INFO_V1(ora_dbms_random_value_range);

/*
 * ensure_seeded - lazily initialize the generator.
 *
 * Oracle initializes DBMS_RANDOM automatically when the session first uses
 * it; we mirror that by seeding from session-unique entropy on first use.
 */
static void
ensure_seeded(void)
{
	if (!state_seeded)
	{
		pg_prng_seed(&random_state,
					 (uint64) GetCurrentTimestamp() ^ ((uint64) MyProcPid << 32));
		state_seeded = true;
	}
}

/*
 * seed_from_numeric - reseed from a numeric seed value.
 *
 * Oracle accepts any NUMBER for INITIALIZE/SEED and truncates it to an
 * integer seed.
 */
static void
seed_from_numeric(Numeric num)
{
	int64		seed;

	seed = DatumGetInt64(DirectFunctionCall1(numeric_int8,
											 NumericGetDatum(num)));
	pg_prng_seed(&random_state, (uint64) seed);
	state_seeded = true;
}

/*
 * DBMS_RANDOM.INITIALIZE(seed)
 *
 * Initializes the generator with the given seed.  Present for Oracle
 * compatibility; equivalent to SEED in this implementation.
 */
Datum
ora_dbms_random_initialize(PG_FUNCTION_ARGS)
{
	seed_from_numeric(PG_GETARG_NUMERIC(0));
	PG_RETURN_VOID();
}

/*
 * DBMS_RANDOM.SEED(seed)
 *
 * Reseeds the generator.  Overloads take NUMBER or VARCHAR2; a string seed
 * is hashed to 64 bits.
 */
Datum
ora_dbms_random_seed_number(PG_FUNCTION_ARGS)
{
	seed_from_numeric(PG_GETARG_NUMERIC(0));
	PG_RETURN_VOID();
}

Datum
ora_dbms_random_seed_text(PG_FUNCTION_ARGS)
{
	text	   *seed = PG_GETARG_TEXT_PP(0);
	const char *bytes = VARDATA_ANY(seed);
	int			len = VARSIZE_ANY_EXHDR(seed);
	uint64		hash;

	hash = DatumGetUInt64(hash_any_extended((const unsigned char *) bytes,
											len, 0));
	pg_prng_seed(&random_state, hash);
	state_seeded = true;
	PG_RETURN_VOID();
}

/*
 * DBMS_RANDOM.TERMINATE
 *
 * Deprecated by Oracle and a no-op there; retained so migrated code runs.
 */
Datum
ora_dbms_random_terminate(PG_FUNCTION_ARGS)
{
	PG_RETURN_VOID();
}

/*
 * DBMS_RANDOM.NORMAL
 *
 * Returns a random NUMBER from a normal distribution with mean 0 and
 * standard deviation 1.
 */
Datum
ora_dbms_random_normal(PG_FUNCTION_ARGS)
{
	double		val;

	ensure_seeded();
	val = pg_prng_double_normal(&random_state);

	PG_RETURN_DATUM(DirectFunctionCall1(float8_numeric,
										Float8GetDatum(val)));
}

/*
 * DBMS_RANDOM.RANDOM
 *
 * Returns a random BINARY_INTEGER in [-2147483648, 2147483647].
 */
Datum
ora_dbms_random_random(PG_FUNCTION_ARGS)
{
	ensure_seeded();

	PG_RETURN_DATUM(DirectFunctionCall1(int4_numeric,
										Int32GetDatum((int32) pg_prng_uint32(&random_state))));
}

/*
 * DBMS_RANDOM.STRING(opt, len)
 *
 * Returns a random string of `len` characters drawn from the character
 * class selected by `opt`:
 *
 *   'u', 'U'  uppercase letters
 *   'l', 'L'  lowercase letters
 *   'a', 'A'  mixed-case letters
 *   'x', 'X'  uppercase alphanumeric
 *   'p', 'P'  any printable character
 */
Datum
ora_dbms_random_string(PG_FUNCTION_ARGS)
{
	const char *upper_alnum = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
	const char *alpha_mixed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
	const char *lower_only = "abcdefghijklmnopqrstuvwxyz";
	const char *upper_only = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
	const char *printable = "`1234567890-=qwertyuiop[]asdfghjkl;'zxcvbnm,./"
							"!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"
							" \\~";
	const char *charset;
	size_t		chrset_size;
	StringInfoData str;
	const char *opt;
	Numeric		truncated_len;
	int			len;
	int			i;

	if (PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("an argument is NULL")));

	if (PG_ARGISNULL(0))
		opt = "U";
	else
	{
		opt = text_to_cstring(PG_GETARG_TEXT_PP(0));
		if (opt[0] == '\0')
			opt = "U";
	}

	if (opt[1] != '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("the character class must be a single character: u, l, a, x or p")));

	switch (opt[0])
	{
		case 'u':
		case 'U':
			charset = upper_only;
			chrset_size = 26;
			break;
		case 'l':
		case 'L':
			charset = lower_only;
			chrset_size = 26;
			break;
		case 'a':
		case 'A':
			charset = alpha_mixed;
			chrset_size = 52;
			break;
		case 'x':
		case 'X':
			charset = upper_alnum;
			chrset_size = 36;
			break;
		case 'p':
		case 'P':
			charset = printable;
			chrset_size = strlen(printable);
			break;
		default:
			/* Oracle defaults an unrecognized option to uppercase letters. */
			charset = upper_only;
			chrset_size = 26;
			break;
	}

	truncated_len = DatumGetNumeric(DirectFunctionCall2(numeric_trunc,
															NumericGetDatum(PG_GETARG_NUMERIC(1)),
															Int32GetDatum(0)));
	if (DatumGetInt32(DirectFunctionCall2(numeric_cmp,
														NumericGetDatum(truncated_len),
														DirectFunctionCall1(int4_numeric,
																			Int32GetDatum(0)))) <= 0)
		PG_RETURN_NULL();

	if (DatumGetInt32(DirectFunctionCall2(numeric_cmp,
														NumericGetDatum(truncated_len),
														DirectFunctionCall1(int4_numeric,
																			Int32GetDatum(DBMS_RANDOM_MAX_STRING_LEN)))) > 0)
		len = DBMS_RANDOM_MAX_STRING_LEN;
	else
		len = DatumGetInt32(DirectFunctionCall1(numeric_int4,
														NumericGetDatum(truncated_len)));

	ensure_seeded();

	initStringInfo(&str);
	for (i = 0; i < len; i++)
	{
		size_t		pos = (size_t) (pg_prng_double(&random_state) * chrset_size);

		/* pg_prng_double() returns [0,1); guard the 1-in-2^53 clamp case */
		if (pos >= chrset_size)
			pos = chrset_size - 1;
		appendStringInfoChar(&str, charset[pos]);
	}

	PG_RETURN_TEXT_P(cstring_to_text(str.data));
}

/*
 * DBMS_RANDOM.VALUE
 *
 * One-argument-free form: returns a random NUMBER in [0.0, 1.0).
 */
Datum
ora_dbms_random_value(PG_FUNCTION_ARGS)
{
	double		val;

	ensure_seeded();
	val = pg_prng_double(&random_state);

	PG_RETURN_DATUM(DirectFunctionCall1(float8_numeric,
										Float8GetDatum(val)));
}

/*
 * DBMS_RANDOM.VALUE(low, high)
 *
 * Returns a random NUMBER in [low, high).  An empty or inverted range cannot
 * satisfy that contract, so report an equivalent parameter error.
 */
Datum
ora_dbms_random_value_range(PG_FUNCTION_ARGS)
{
	Numeric		low;
	Numeric		high;
	Numeric		fraction;
	Numeric		range;
	Numeric		offset;
	Numeric		result;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	low = PG_GETARG_NUMERIC(0);
	high = PG_GETARG_NUMERIC(1);

	if (DatumGetInt32(DirectFunctionCall2(numeric_cmp,
											NumericGetDatum(low),
											NumericGetDatum(high))) >= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("the lower bound must not be greater than the upper bound")));

	ensure_seeded();
	fraction = DatumGetNumeric(DirectFunctionCall1(float8_numeric,
													Float8GetDatum(pg_prng_double(&random_state))));
	range = DatumGetNumeric(DirectFunctionCall2(numeric_sub,
													NumericGetDatum(high),
													NumericGetDatum(low)));
	offset = DatumGetNumeric(DirectFunctionCall2(numeric_mul,
													 NumericGetDatum(range),
													 NumericGetDatum(fraction)));
	result = DatumGetNumeric(DirectFunctionCall2(numeric_add,
													NumericGetDatum(low),
													NumericGetDatum(offset)));

	PG_RETURN_NUMERIC(result);
}

/*
 * ora_dbms_random_reset
 *
 * Drop the generator state.  Called by DISCARD ALL/PACKAGES so that a
 * pooled connection does not carry one client's generator sequence to the
 * next; the next call reseeds from entropy.
 */
void
ora_dbms_random_reset(void)
{
	state_seeded = false;
}
