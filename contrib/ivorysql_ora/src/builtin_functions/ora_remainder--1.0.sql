/***************************************************************
 *
 * REMAINDER Function
 *
 * Oracle-compatible remainder with round-half-even quotient.
 *
 * contrib/ivorysql_ora/src/builtin_functions/ora_remainder--1.0.sql
 *
 ***************************************************************/

/*
 * Oracle REMAINDER has three overloads -- NUMBER, BINARY_FLOAT and
 * BINARY_DOUBLE -- and, per the Oracle SQL Language Reference, "Oracle
 * determines the argument with the highest numeric precedence, implicitly
 * converts the remaining arguments to that data type, and returns that
 * data type."  The numeric precedence order is
 *
 *     BINARY_DOUBLE > BINARY_FLOAT > NUMBER
 *
 * The three families therefore differ in two ways:
 *
 *  * The NUMBER family computes an exact decimal remainder with a
 *    round-half-to-EVEN quotient and raises division_by_zero (Oracle
 *    ORA-01476) for a zero divisor.
 *
 *  * The BINARY_FLOAT / BINARY_DOUBLE families follow IEEE 754, as Oracle
 *    documents: "If n1 = 0 or n2 = infinity, then Oracle returns ... NaN
 *    if the arguments are BINARY_FLOAT or BINARY_DOUBLE", and "If n2 is a
 *    floating-point number, and if the remainder is 0, then the sign of
 *    the remainder is the sign of n2.  Remainders of 0 are unsigned for
 *    NUMBER values."
 *
 * Oracle names the arguments REMAINDER(n2, n1): n2 (the dividend) is the
 * first argument and n1 (the divisor) is the second.  The C implementation
 * and the SQL bodies below use the same convention.
 *
 * ---------------------------------------------------------------------
 * How calls resolve in Oracle mode
 * ---------------------------------------------------------------------
 * The three signatures mirror the already-merged sys.nanvl: the same
 * three homogeneous families over sys.number, sys.binary_float and
 * sys.binary_double.  IvorySQL's three numeric types are distinct from
 * pg_catalog.numeric, float4 and float8, and plain PostgreSQL overload
 * resolution cannot pick the family Oracle's numeric precedence requires
 * for mixed or literal calls.  In Oracle mode the function argument
 * precedence hook (oracle_funcarg_precedence_hook) completes the
 * resolution:
 *
 *   * The parser first looks the name up with the caller's real argument
 *     types, so an exact user-defined overload visible through the
 *     search_path (or a schema-qualified call) always wins.
 *
 *   * Only when that lookup does not yield an exact match are the
 *     argument types rewritten per Oracle numeric precedence -- ordinary
 *     numeric literals (int2/int4/int8/numeric, or an unknown string
 *     literal in this numeric context) behave as NUMBER values and a
 *     common target type is chosen with BINARY_DOUBLE > BINARY_FLOAT >
 *     NUMBER -- and the lookup is retried.  The real argument types are
 *     kept for the actual call so that the arguments are coerced to the
 *     selected overload.
 *
 * Observed consequences (all asserted in the regression suite, verified
 * against Oracle Database 23ai):
 *
 *   * An argument that is exactly one of the three sys types selects the
 *     matching family.  A column of type sys.number, sys.binary_float or
 *     sys.binary_double -- the common case in migrated code -- resolves
 *     to NUMBER, BINARY_FLOAT or BINARY_DOUBLE respectively, and a bare
 *     integer or decimal literal next to it is absorbed by that family
 *     (REMAINDER(number_col, 4) and REMAINDER(number_col, 1.5) both stay
 *     on the NUMBER path).
 *
 *   * Ordinary numeric literals are NUMBER values: the all-literal form
 *     REMAINDER(7, 0) reaches the NUMBER body and raises
 *     division_by_zero (ORA-01476), and a wide literal keeps its exact
 *     decimal digits (REMAINDER(10000000000000000001, 2) = 1).
 *
 *   * Mixed families follow the precedence rule:
 *     REMAINDER(number, binary_float) resolves to BINARY_FLOAT;
 *     NUMBER combined with BINARY_DOUBLE, and BINARY_FLOAT combined
 *     with BINARY_DOUBLE, both resolve to BINARY_DOUBLE.
 */

/*
 * REMAINDER: NUMBER family.
 *
 * Oracle defines REMAINDER(n2, n1) as n2 - (n1 * N), where N is the
 * integer nearest n2/n1.  When the quotient is exactly halfway between
 * two integers, Oracle rounds to the EVEN neighbour: REMAINDER(2.5, 1)
 * = 0.5 but REMAINDER(1.5, 1) = -0.5 (verified on Oracle Database 23ai).
 * Neither PostgreSQL building block reproduces this: round() rounds
 * halfway cases away from zero, and mod() computes x - trunc(x/y) * y
 * (it truncates the quotient rather than flooring it), so the rounding
 * of N has to be spelled out.
 *
 * The tie detection compares abs(2 * (q - trunc(q))) against 1 on the
 * quotient q = n2/n1.  This comparison must run on the exact expansion,
 * which is always available for a tie (x.5 terminates after one decimal
 * digit) -- but PostgreSQL's numeric division picks its result scale from
 * the inputs and the significance of the integral digits, so a wide
 * quotient such as 10000000000000000001/2 comes back with no fractional
 * digits at all and the tie digit would be lost.  Multiplying the dividend
 * by a scale-38 representation of 1 (the literal
 * 1.00000000000000000000000000000000000000, whose value is exactly 1 but
 * whose declared scale is 38) forces the division to carry 38 fractional
 * digits, which pins the quotient scale well past Oracle's 38-digit
 * NUMBER precision, makes every tie visible and keeps the detection exact
 * for any input Oracle can represent.  Multiplying by 1 does not change
 * the dividend's value; only the result scale of the division grows.
 *
 * The body works on pg_catalog.numeric: trunc(), mod() and sign() are not
 * defined for sys.number, so the arguments are cast to numeric up front
 * (a binary-coercible, relabel-only cast) and the result is cast back to
 * sys.number, the type Oracle's NUMBER overload returns.
 *
 * STRICT: Oracle returns NULL when either argument is NULL.  A zero
 * divisor raises division_by_zero (SQLSTATE 22012), matching Oracle's
 * ORA-01476.  IMMUTABLE and PARALLEL SAFE: the result depends only on
 * the two arguments.
 */
CREATE FUNCTION sys.remainder(sys.number, sys.number)
RETURNS sys.number
AS $$
    WITH scaled AS (
        SELECT $1::pg_catalog.numeric AS n2,
               $2::pg_catalog.numeric AS n1,
               $1::pg_catalog.numeric * 1.00000000000000000000000000000000000000
                   / $2::pg_catalog.numeric AS q
    ),
    parts AS (
        SELECT n2,
               n1,
               q,
               trunc(q) AS tq,
               abs(2 * (q - trunc(q))) AS frac2
        FROM scaled
    )
    SELECT (n2 - n1 *
           (CASE
                WHEN frac2 < 1 THEN tq
                WHEN frac2 > 1 THEN tq + sign(q)
                WHEN mod(tq, 2) = 0 THEN tq
                ELSE tq + sign(q)
            END))::sys.number
    FROM parts
$$
LANGUAGE sql
STRICT
IMMUTABLE
PARALLEL SAFE;

COMMENT ON FUNCTION sys.remainder(sys.number, sys.number)
IS 'Oracle-compatible REMAINDER for NUMBER (round-half-even quotient, ORA-01476 on zero divisor)';

/*
 * REMAINDER: BINARY_FLOAT family.
 *
 * IEEE 754 remainder (libm remainderf): a zero divisor and an infinite
 * dividend both yield NaN, and a zero result keeps the sign of the
 * dividend.  Implemented in C because PostgreSQL's float division raises
 * division_by_zero before the remainder could be computed.
 */
CREATE FUNCTION sys.remainder(sys.binary_float, sys.binary_float)
RETURNS sys.binary_float
AS 'MODULE_PATHNAME','binary_float_remainder'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

COMMENT ON FUNCTION sys.remainder(sys.binary_float, sys.binary_float)
IS 'Oracle-compatible REMAINDER for BINARY_FLOAT (IEEE 754: NaN on zero divisor / infinite dividend)';

/*
 * REMAINDER: BINARY_DOUBLE family.
 *
 * IEEE 754 remainder (libm remainder).  Same documented behaviour as the
 * BINARY_FLOAT family, at double precision.
 */
CREATE FUNCTION sys.remainder(sys.binary_double, sys.binary_double)
RETURNS sys.binary_double
AS 'MODULE_PATHNAME','binary_double_remainder'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

COMMENT ON FUNCTION sys.remainder(sys.binary_double, sys.binary_double)
IS 'Oracle-compatible REMAINDER for BINARY_DOUBLE (IEEE 754: NaN on zero divisor / infinite dividend)';

/* End - REMAINDER */
