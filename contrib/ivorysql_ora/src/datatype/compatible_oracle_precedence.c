/*-------------------------------------------------------------------------
 *
 * compatible_oracle_precedence.c
 *
 * Compatible with Oracle data type precedence.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/compatible_oracle_precedence.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "utils/lsyscache.h"

#include "../include/ivorysql_ora.h"

#define	ORACLE_DATATYPE_MUMBER		15

/* Oracle data type precedence array */
static const int OracleDataTypePriority[ORACLE_DATATYPE_MUMBER][2] =
{
	{ORACHARCHAROID, 1},
	{ORACHARBYTEOID, 1},
	{ORAVARCHARCHAROID, 2},   /* assume the precedence of varchar2 higher than char */
	{ORAVARCHARBYTEOID, 2},
	{NUMBEROID, 3},
	{BINARY_FLOATOID, 4},
	{BINARY_DOUBLEOID, 5},
	{ORADATEOID, 6},
	{ORATIMESTAMPOID, 6},
	{ORATIMESTAMPTZOID, 6},
	{ORATIMESTAMPLTZOID, 6},
	{YMINTERVALOID, 6},
	{DSINTERVALOID, 6},
	{InvalidOid, 0},	/* Used in the future */
	{InvalidOid, 0}		/* Used in the future */
};

/* parameter_in_priorityarray()
 * Search the left operand or the right operand is or not in the priority array.
 * Return true if successful, otherwise return false.
 */
static bool
parameter_in_priorityarray(Oid datatype)
{
	int i;

	for (i = 0; i < ORACLE_DATATYPE_MUMBER; i++)
	{
		if (datatype == (Oid)OracleDataTypePriority[i][0])
			return true;
	}

	return false;
}

/*
 * get_precedence()
 * Get precedence of oracle data type.
 * Before calling this function, we assume datatype
 * is the data type of compatible oracle .
 */
static int
get_precedence(Oid datatype)
{
	int i;
	int result = 0;

	for (i=0; i < ORACLE_DATATYPE_MUMBER; i++)
	{
		if (datatype == OracleDataTypePriority[i][0])
		{
			result = OracleDataTypePriority[i][1];
			break;
		}
	}

	return result;
}


/*
 * pg_compatible_oracle_precedence
 * The function is used to compatible with the Oracle data type precedence ,
 * It is the caller's responsibility to ensure that opname_p is not NULL.
 *
 * If the data type are in Postgresql, then return false. otherwise sucess return true;
 */
bool
pg_compatible_oracle_precedence(Oid arg1, Oid arg2, char *opname_p, Oid *result_arg1, Oid *result_arg2)
{
	bool	arg1_is_oracle = false;
	bool	arg2_is_oracle = false;
	int		arg1_precedence = 0;
	int		arg2_precedence = 0;

	/* 
	 * Compatible Oracle text literals properties.
	 * In Postgresql text literals 'abc' is UNKNOWN data type.
	 * In Oracle text literals 'abc' is CHAR data type , except
	 * that maximum length is 4000 bytes.
	 */
	if (arg1 == UNKNOWNOID)
		arg1 = ORACHARCHAROID;
	if (arg2 == UNKNOWNOID)
		arg2 = ORACHARCHAROID;

	/* If arg1 or arg2 is a domain, reduce them to their base types */
	arg1 = getBaseType(arg1);
	arg2 = getBaseType(arg2);

	arg1_is_oracle = parameter_in_priorityarray(arg1);
	arg2_is_oracle = parameter_in_priorityarray(arg2);

	/* Compatible Oracle
	 * If the left operand or right operand is compatible with oracle's data type and
	 * and the other operand is the data type of POSTGREQSL. We convert to compatible
	 * oracle data types.
	 */
	if (arg1_is_oracle && arg2_is_oracle)
	{
		/* Both arg1 and arg2 are Oracle data type , so do nothing */
	}
	else if (arg1_is_oracle)
	{
		switch(arg2)
		{
			case BPCHAROID:
				arg2 = ORACHARCHAROID;
				break;

			case VARCHAROID:
				arg2 = ORAVARCHARCHAROID;
				break;

			case NUMERICOID:
			case INT2OID:
			case INT4OID:
			case INT8OID:
				arg2 = NUMBEROID;
				break;

			case FLOAT4OID:
				arg2 = BINARY_FLOATOID;
				break;

			case FLOAT8OID:
				arg2 = BINARY_DOUBLEOID;
				break;

			case DATEOID:
				arg2 = ORADATEOID;
				break;

			case TIMESTAMPOID:
				arg2 = ORATIMESTAMPOID;
				break;

			case TIMESTAMPTZOID:
				arg2 = ORATIMESTAMPTZOID;
				break;

			case INTERVALOID:
			default:
				;
				/* do nothing */
		}
	}
	else if (arg2_is_oracle)
	{
		switch(arg1)
		{
			case BPCHAROID:
				arg1 = ORACHARCHAROID;
				break;

			case VARCHAROID:
				arg1 = ORAVARCHARCHAROID;
				break;

			case NUMERICOID:
			case INT2OID:
			case INT4OID:
			case INT8OID:
				arg1 = NUMBEROID;
				break;

			case FLOAT4OID:
				arg1 = BINARY_FLOATOID;
				break;

			case FLOAT8OID:
				arg1 = BINARY_DOUBLEOID;
				break;

			case DATEOID:
				arg1 = ORADATEOID;
				break;

			case TIMESTAMPOID:
				arg1 = ORATIMESTAMPOID;
				break;

			case TIMESTAMPTZOID:
				arg1 = ORATIMESTAMPTZOID;
				break;

			case INTERVALOID:
			default:
				;
				/* do nothing */
		}
	}
	else
	{
		/* Both arg1 and arg2 are Postgresql data type, return -1 */
		PG_RETURN_BOOL(false);
	}

	/* At this point,be sure both arg1 and arg2 are oracle data type */
	arg1_is_oracle = parameter_in_priorityarray(arg1);
	arg2_is_oracle = parameter_in_priorityarray(arg2);

	if (arg1_is_oracle && arg2_is_oracle)
	{
		arg1_precedence = get_precedence(arg1);
		arg2_precedence = get_precedence(arg2);

		/* Compatible Oracle implicit conversion
		 * In arithmetic operations between CHAR/VARCHAR2 and NCHAR/NVARCHAR2,
		 * Oracle converts CHAR/VARCHAR2 to a NUMBER.
		 */
		if ((arg1_precedence == 1 || arg1_precedence == 2) &&
			(arg2_precedence == 1 || arg2_precedence == 2) &&
			(strcmp(opname_p, "+") == 0 ||
			 strcmp(opname_p, "-") == 0 ||
			 strcmp(opname_p, "*") == 0 ||
			 strcmp(opname_p, "/") == 0))
		{
			*result_arg1 = NUMBEROID;
			*result_arg2 = NUMBEROID;	

			PG_RETURN_BOOL(true);	
		}

		/* Compatible Oracle
		 * If the operational is Datetime/Interval Arithmetic,
		 * in this case, we do not adhere to the priority policy.
		 */
		if ((arg1_precedence == 6 &&
			 (arg2_precedence == 3 ||
			  arg2_precedence == 4 ||
			  arg2_precedence == 5)) &&
			(strcmp(opname_p, "+") == 0 ||
			 strcmp(opname_p, "-") == 0 ||
			 strcmp(opname_p, "*") == 0 ||
			 strcmp(opname_p, "/") == 0))
		{
			/* Compatible Oracle
			 * Oracle implicitly converts BINARY_FLOAT and BINARY_DOUBLE
			 * operands to NUMBER in Datetime/Interval Arithmetic.
			 */
			if (arg2_precedence == 4 || arg2_precedence == 5)
			{
				*result_arg2 = NUMBEROID;
				*result_arg1 = arg1;

				PG_RETURN_BOOL(true);
			}
			else
			{
				*result_arg2 = arg2;
				*result_arg1 = arg1;
				
				PG_RETURN_BOOL(true);
			}	
		}
		else if ((arg2_precedence == 6 &&
				 (arg1_precedence == 3 ||
				  arg1_precedence == 4 ||
				  arg1_precedence == 5)) &&
				(strcmp(opname_p, "+") == 0 ||
				 strcmp(opname_p, "-") == 0 ||
				 strcmp(opname_p, "*") == 0 ||
				 strcmp(opname_p, "/") == 0))
		{
			/* Compatible Oracle
			 * Oracle implicitly converts BINARY_FLOAT and BINARY_DOUBLE
			 * operands to NUMBER in Datetime/Interval Arithmetic.
			 */
			if (arg1_precedence == 4 || arg1_precedence == 5)
			{
				*result_arg1 = NUMBEROID;
				*result_arg2 = arg2;

				PG_RETURN_BOOL(true);
			}
			else
			{
				*result_arg2 = arg2;
				*result_arg1 = arg1;
				
				PG_RETURN_BOOL(true);
			}
		}		

		if (arg1_precedence == arg2_precedence)
		{
			*result_arg1 = arg1;
			*result_arg2 = arg2;
		}
		else if (arg1_precedence > arg2_precedence)
		{
			*result_arg1 = arg1;
			*result_arg2 = arg1;
		}
		else
		{
			*result_arg1 = arg2;
			*result_arg2 = arg2;
		}
	}
	else
	{
		/* arg1 and arg2 is postgresql data type */
		*result_arg1 = InvalidOid;
		*result_arg2 = InvalidOid;
		PG_RETURN_BOOL(false);
	}

	PG_RETURN_BOOL(true);
}

