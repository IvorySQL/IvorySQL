/*
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
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 * contrib/btree_gist/btree_gist.h
 */
#ifndef __BTREE_GIST_H__
#define __BTREE_GIST_H__

#include "access/nbtree.h"
#include "fmgr.h"

#define BtreeGistNotEqualStrategyNumber 6

/* indexed types */

enum gbtree_type
{
	gbt_t_var,
	gbt_t_int2,
	gbt_t_int4,
	gbt_t_int8,
	gbt_t_float4,
	gbt_t_float8,
	gbt_t_numeric,
	gbt_t_ts,
	gbt_t_cash,
	gbt_t_oid,
	gbt_t_time,
	gbt_t_date,
	gbt_t_intv,
	gbt_t_macad,
	gbt_t_macad8,
	gbt_t_text,
	gbt_t_bpchar,
	gbt_t_bytea,
	gbt_t_bit,
	gbt_t_bool,
	gbt_t_inet,
	gbt_t_uuid,
	gbt_t_enum
};

#endif
