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
 * Oracle-compatible BIT_AND_AGG, BIT_OR_AGG and BIT_XOR_AGG aggregates.
 * This module is part of ivorysql_ora extension.
 *
 * Oracle aggregates its bitwise functions over NUMBER operands truncated
 * toward zero and performs the operations on the two's-complement
 * representation, so negative inputs behave as if sign-extended to an
 * unlimited width.  A signed 128-bit accumulator reproduces that exactly
 * over Oracle's documented input range (-(2^127) .. 2^127-1); values
 * beyond it are rejected here, whereas Oracle 23ai silently returns
 * meaningless results (the same artifact for 2^127, 2^128 and -2^127-1).
 *
 * An empty group, or a group whose inputs are all NULL, yields 0 for all
 * three aggregates, matching Oracle 23ai rather than the usual SQL
 * "NULL if no rows" convention.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_functions/bitwise_agg.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "libpq/pqformat.h"
#include "utils/fmgrprotos.h"
#include "utils/numeric.h"
#include "varatt.h"

#ifndef PG_INT128_TYPE
#error "BIT_AND_AGG/BIT_OR_AGG/BIT_XOR_AGG need a 128-bit integer type"
#endif

/* PostgreSQL does not ship int128 limit macros, so define our own. */
#define BITWISE_AGG_INT128_MAX	((int128) ((((uint128) 1) << 127) - 1))
#define BITWISE_AGG_INT128_MIN	((int128) (((uint128) 1) << 127))

/*
 * The transition state.  It lives in the aggregate memory context and is
 * shared by all three aggregates; only the operation applied by the
 * transition/combine functions differs.
 */
typedef struct BitwiseAggState
{
	int128		acc;			/* two's-complement accumulator */
	bool		has_value;		/* seen at least one non-NULL input */
} BitwiseAggState;

typedef enum BitwiseAggOp
{
	BITWISE_AGG_AND,
	BITWISE_AGG_OR,
	BITWISE_AGG_XOR
} BitwiseAggOp;

static int128 bitwise_apply(BitwiseAggOp op, int128 a, int128 b);
static int128 numeric_to_int128(Numeric num);
static Numeric int128_to_numeric(int128 val);
static Datum bitwise_agg_transfn_common(FunctionCallInfo fcinfo,
										BitwiseAggOp op);
static Datum bitwise_agg_combine_common(FunctionCallInfo fcinfo,
										BitwiseAggOp op);

/* SQL-callable functions */
PG_FUNCTION_INFO_V1(bit_and_agg_transfn);
PG_FUNCTION_INFO_V1(bit_or_agg_transfn);
PG_FUNCTION_INFO_V1(bit_xor_agg_transfn);
PG_FUNCTION_INFO_V1(bit_and_agg_combinefn);
PG_FUNCTION_INFO_V1(bit_or_agg_combinefn);
PG_FUNCTION_INFO_V1(bit_xor_agg_combinefn);
PG_FUNCTION_INFO_V1(bitwise_agg_finalfn);
PG_FUNCTION_INFO_V1(bitwise_agg_serialize);
PG_FUNCTION_INFO_V1(bitwise_agg_deserialize);

/*
 * bitwise_apply - the bitwise operation selected by op.
 */
static int128
bitwise_apply(BitwiseAggOp op, int128 a, int128 b)
{
	switch (op)
	{
		case BITWISE_AGG_AND:
			return a & b;
		case BITWISE_AGG_OR:
			return a | b;
		case BITWISE_AGG_XOR:
			return a ^ b;
	}

	elog(ERROR, "unrecognized bitwise aggregate operation: %d", (int) op);
	return 0;					/* keep compiler quiet */
}

/*
 * numeric_to_int128 - truncate a numeric toward zero and widen to int128.
 *
 * Going through the exact decimal text form avoids depending on the
 * internal Numeric layout and keeps the truncation explicit: digits after
 * the decimal point are simply dropped, which is what Oracle does before
 * applying the bitwise operations (BIT_OR_AGG(2.9) = 2, BIT_OR_AGG(-2.9)
 * = -2 on 23ai).
 */
static int128
numeric_to_int128(Numeric num)
{
	char	   *str = DatumGetCString(DirectFunctionCall1(numeric_out,
														   NumericGetDatum(num)));
	const char *p = str;
	bool		neg = false;
	uint128		mag = 0;
	uint128		maxmag = (uint128) 1 << 127;	/* 2^127: legal only as
												 * INT128_MIN when negative */

	if (*p == '+' || *p == '-')
		neg = (*p++ == '-');

	/*
	 * numeric_out emits no digits for NaN, 'Infinity' and '-Infinity';
	 * reject them here instead of silently converting them to zero
	 * (Oracle reports ORA-01426 numeric overflow for such inputs).
	 */
	if (*p < '0' || *p > '9')
		goto invalid_input;

	while (*p >= '0' && *p <= '9')
	{
		int			d = *p++ - '0';

		if (mag > maxmag / 10 ||
			(mag == maxmag / 10 && (uint128) d > maxmag % 10))
			goto out_of_range;
		mag = mag * 10 + (uint128) d;
	}
	/* digits after the decimal point are truncated away; numeric_out never
	 * produces an exponent, so nothing else can follow but a fraction */

	if (neg)
	{
		if (mag > maxmag)
			goto out_of_range;
		if (mag == maxmag)
			return BITWISE_AGG_INT128_MIN;
		return -(int128) mag;
	}

	if (mag > (uint128) BITWISE_AGG_INT128_MAX)
		goto out_of_range;

	return (int128) mag;

invalid_input:
out_of_range:
	ereport(ERROR,
			(errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
			 errmsg("value \"%s\" is out of range for a 128-bit integer",
					str)));
	return 0;					/* keep compiler quiet */
}

/*
 * int128_to_numeric - narrow the accumulator back to numeric by rendering
 * its exact decimal form and letting numeric_in parse it.
 */
static Numeric
int128_to_numeric(int128 val)
{
	char		buf[48];
	char	   *p = buf + sizeof(buf) - 1;
	uint128		mag;
	bool		neg = val < 0;

	mag = neg ? ~(uint128) val + 1 : (uint128) val;

	*p = '\0';
	do
	{
		*--p = '0' + (char) (mag % 10);
		mag /= 10;
	} while (mag != 0);

	if (neg)
		*--p = '-';

	return DatumGetNumeric(DirectFunctionCall3(numeric_in,
											   CStringGetDatum(p),
											   ObjectIdGetDatum(InvalidOid),
											   Int32GetDatum(-1)));
}

/*
 * Common transition logic.  NULL inputs are skipped; the first non-NULL
 * input seeds the accumulator so AND does not need an all-ones identity.
 *
 * The previous state is never modified: window aggregation keeps several
 * transition states alive at once (internal is pass-by-pointer, so their
 * "copies" alias), and every call therefore hands back a freshly
 * allocated state.
 */
static Datum
bitwise_agg_transfn_common(FunctionCallInfo fcinfo, BitwiseAggOp op)
{
	MemoryContext aggcontext;
	MemoryContext oldcontext;
	BitwiseAggState *state;

	if (!AggCheckCallContext(fcinfo, &aggcontext))
		elog(ERROR, "bitwise aggregate transition function called in non-aggregate context");

	oldcontext = MemoryContextSwitchTo(aggcontext);
	state = (BitwiseAggState *) palloc(sizeof(BitwiseAggState));
	MemoryContextSwitchTo(oldcontext);

	state->has_value = false;
	state->acc = 0;

	if (!PG_ARGISNULL(0))
	{
		BitwiseAggState *prev = (BitwiseAggState *) PG_GETARG_POINTER(0);

		if (prev->has_value)
		{
			state->acc = prev->acc;
			state->has_value = true;
		}
	}

	if (!PG_ARGISNULL(1))
	{
		int128		v = numeric_to_int128(PG_GETARG_NUMERIC(1));

		state->acc = state->has_value ? bitwise_apply(op, state->acc, v) : v;
		state->has_value = true;
	}

	PG_RETURN_POINTER(state);
}

/*
 * Common combine logic for parallel and window aggregation.  Neither
 * input may be modified (see the transition function), so the result is
 * always a freshly allocated state.  A state that has not seen any value
 * must not be folded in: 0 is the identity of OR/XOR but not of AND.
 */
static Datum
bitwise_agg_combine_common(FunctionCallInfo fcinfo, BitwiseAggOp op)
{
	MemoryContext aggcontext;
	MemoryContext oldcontext;
	BitwiseAggState *state1;
	BitwiseAggState *state2;
	BitwiseAggState *result;
	int128		acc;
	bool		has;

	if (!AggCheckCallContext(fcinfo, &aggcontext))
		elog(ERROR, "bitwise aggregate combine function called in non-aggregate context");

	state1 = PG_ARGISNULL(0) ? NULL : (BitwiseAggState *) PG_GETARG_POINTER(0);
	state2 = PG_ARGISNULL(1) ? NULL : (BitwiseAggState *) PG_GETARG_POINTER(1);

	has = (state1 != NULL && state1->has_value) ||
		(state2 != NULL && state2->has_value);
	if (!has)
		acc = 0;
	else if (state1 != NULL && state1->has_value &&
			 state2 != NULL && state2->has_value)
		acc = bitwise_apply(op, state1->acc, state2->acc);
	else if (state1 != NULL && state1->has_value)
		acc = state1->acc;
	else
		acc = state2->acc;

	oldcontext = MemoryContextSwitchTo(aggcontext);
	result = (BitwiseAggState *) palloc(sizeof(BitwiseAggState));
	result->acc = acc;
	result->has_value = has;
	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_POINTER(result);
}

/*
 * Shared final function: Oracle answers 0 for an empty or all-NULL group,
 * not NULL.  The result is built in the aggregate context because window
 * aggregation may re-emit a cached result after the per-tuple context has
 * been reset.
 */
Datum
bitwise_agg_finalfn(PG_FUNCTION_ARGS)
{
	MemoryContext aggcontext = NULL;
	MemoryContext oldcontext = NULL;
	BitwiseAggState *state = PG_ARGISNULL(0) ? NULL :
		(BitwiseAggState *) PG_GETARG_POINTER(0);
	Datum		result;

	if (AggCheckCallContext(fcinfo, &aggcontext))
		oldcontext = MemoryContextSwitchTo(aggcontext);

	if (state == NULL || !state->has_value)
		result = DirectFunctionCall3(numeric_in,
										  CStringGetDatum("0"),
										  ObjectIdGetDatum(InvalidOid),
										  Int32GetDatum(-1));
	else
		result = NumericGetDatum(int128_to_numeric(state->acc));

	if (oldcontext != NULL)
		MemoryContextSwitchTo(oldcontext);

	PG_RETURN_DATUM(result);
}

/*
 * Shared serialize/deserialize support for PARALLEL SAFE internal state:
 * one flag byte (0 = no value yet, 1 = non-negative, 2 = negative)
 * followed by the magnitude of the accumulator as two big-endian 64-bit
 * halves.
 */
Datum
bitwise_agg_serialize(PG_FUNCTION_ARGS)
{
	BitwiseAggState *state = (BitwiseAggState *) PG_GETARG_POINTER(0);
	StringInfoData buf;
	uint128		mag;
	bool		neg = state->acc < 0;

	mag = neg ? ~(uint128) state->acc + 1 : (uint128) state->acc;

	pq_begintypsend(&buf);
	pq_sendbyte(&buf, state->has_value ? (neg ? 2 : 1) : 0);
	pq_sendint64(&buf, (int64) (mag >> 64));
	pq_sendint64(&buf, (int64) (uint64) mag);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

Datum
bitwise_agg_deserialize(PG_FUNCTION_ARGS)
{
	MemoryContext aggcontext;
	MemoryContext oldcontext;
	BitwiseAggState *state;
	bytea	   *sstate;
	StringInfoData buf;
	uint128		mag;
	int			flag;

	if (!AggCheckCallContext(fcinfo, &aggcontext))
		elog(ERROR, "bitwise aggregate deserialize function called in non-aggregate context");

	sstate = PG_GETARG_BYTEA_PP(0);

	buf.data = (char *) VARDATA_ANY(sstate);
	buf.len = VARSIZE_ANY_EXHDR(sstate);
	buf.cursor = 0;

	flag = pq_getmsgbyte(&buf);
	mag = ((uint128) (uint64) pq_getmsgint64(&buf)) << 64;
	mag |= (uint128) (uint64) pq_getmsgint64(&buf);
	pq_getmsgend(&buf);

	oldcontext = MemoryContextSwitchTo(aggcontext);
	state = (BitwiseAggState *) palloc(sizeof(BitwiseAggState));
	MemoryContextSwitchTo(oldcontext);

	state->has_value = (flag != 0);
	if (flag == 2)
	{
		state->acc = (mag == ((uint128) 1 << 127))
			? BITWISE_AGG_INT128_MIN
			: -(int128) mag;
	}
	else
		state->acc = (int128) mag;

	PG_RETURN_POINTER(state);
}

Datum
bit_and_agg_transfn(PG_FUNCTION_ARGS)
{
	return bitwise_agg_transfn_common(fcinfo, BITWISE_AGG_AND);
}

Datum
bit_or_agg_transfn(PG_FUNCTION_ARGS)
{
	return bitwise_agg_transfn_common(fcinfo, BITWISE_AGG_OR);
}

Datum
bit_xor_agg_transfn(PG_FUNCTION_ARGS)
{
	return bitwise_agg_transfn_common(fcinfo, BITWISE_AGG_XOR);
}

Datum
bit_and_agg_combinefn(PG_FUNCTION_ARGS)
{
	return bitwise_agg_combine_common(fcinfo, BITWISE_AGG_AND);
}

Datum
bit_or_agg_combinefn(PG_FUNCTION_ARGS)
{
	return bitwise_agg_combine_common(fcinfo, BITWISE_AGG_OR);
}

Datum
bit_xor_agg_combinefn(PG_FUNCTION_ARGS)
{
	return bitwise_agg_combine_common(fcinfo, BITWISE_AGG_XOR);
}
