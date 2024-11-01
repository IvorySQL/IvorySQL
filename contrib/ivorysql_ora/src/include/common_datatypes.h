/*-------------------------------------------------------------------------
 * 
 * File: common_datatypes.h
 *
 * Abstract: 
 * 		This file contains extern declarations for datatype common routines.
 *
 * Copyright:
 * Portions Copyright (c) 2024, Ivory SQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/include/common_datatypes.h
 *
 *-------------------------------------------------------------------------
 */

#include "datatype/timestamp.h"

#define ORACLE_MAX_TIMESTAMP_PRECISION	9
#define ORACLE_MAX_INTERVAL_PRECISION	9
#define REGEXP_REPLACE_BACKREF_CNT		10	

#define SAMESIGN(a,b)	(((a) < 0) == ((b) < 0))

/* Macros to handle packing and unpacking the typmod field for INTERVAL DAY TO SECOND */
#define DSINTERVAL_RANGE_MASK (0x7FFF)

#define DSINTERVAL_PRECISION_MASK (0xFF)

#define INTERVAL_DAY_TYPMOD(p,r) ((((r) & DSINTERVAL_RANGE_MASK) << 16) | (((p) & DSINTERVAL_PRECISION_MASK) << 8))

#define INTERVAL_SECOND_TYPMOD(p,r) ((((r) & DSINTERVAL_RANGE_MASK) << 16) | ((p) & DSINTERVAL_PRECISION_MASK))

#define INTERVAL_DS_TYPMOD(sp,dp,r) ((((r) & DSINTERVAL_RANGE_MASK) << 16) | \
									(((dp) & DSINTERVAL_PRECISION_MASK) << 8) | \
									((sp) & DSINTERVAL_PRECISION_MASK))
									
#define INTERVAL_DAY_PRECISION(t) (((t) >> 8) & DSINTERVAL_PRECISION_MASK)

#define INTERVAL_SECOND_PRECISION(t) ((t) & DSINTERVAL_PRECISION_MASK)

/* common_datatypes.c */
extern text *ora_dotrim(const char *string, int stringlen, const char *set, int setlen, bool doltrim, bool dortrim);

/* oratimestamp.c */
extern void OraAdjustTimestampForTypmod(Timestamp *time, int32 typmod);

/* dsinterval.c */
extern Datum dsinterval_out(PG_FUNCTION_ARGS);
extern Datum dsinterval_in(PG_FUNCTION_ARGS);

/* yminterval.c */
extern Datum yminterval_out(PG_FUNCTION_ARGS);
extern Datum yminterval_in(PG_FUNCTION_ARGS);

