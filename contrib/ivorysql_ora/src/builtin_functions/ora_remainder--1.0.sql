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
 * REMAINDER: Oracle-compatible remainder of n1 divided by n2.
 *
 * Oracle defines REMAINDER(n1, n2) as n1 - (n2 * m), where m is the
 * quotient n1/n2 rounded to the nearest integer.  When the quotient is
 * exactly halfway between two integers, Oracle rounds to the EVEN
 * neighbour: REMAINDER(2.5, 1) = 0.5 but REMAINDER(1.5, 1) = -0.5
 * (verified on Oracle Database 23ai).  Neither PostgreSQL building block
 * reproduces this: round() rounds halfway cases away from zero and
 * mod() floors the quotient, so the rounding of m has to be spelled out.
 *
 * The tie detection compares abs(2 * (q - trunc(q))) against 1 on the
 * quotient q = n1/n2.  This comparison must run on the exact expansion,
 * which is always available for a tie (x.5 terminates after one decimal
 * digit) -- but PostgreSQL's numeric division picks its result scale from
 * the inputs and the significance of the integral digits, so a wide
 * quotient such as 10000000000000000001/2 comes back with no fractional
 * digits at all and the tie digit would be lost.  Scaling the dividend by
 * 1e-38 (1.00000000000000000000000000000000000000) pins the quotient
 * scale well past Oracle's 38-digit NUMBER precision, which makes every
 * tie visible and keeps the detection exact for any input Oracle can
 * represent.
 *
 * STRICT: Oracle returns NULL when either argument is NULL.  A zero
 * divisor raises division_by_zero (SQLSTATE 22012), matching Oracle's
 * ORA-01476.  IMMUTABLE and PARALLEL SAFE: the result depends only on
 * the two arguments.
 */
CREATE FUNCTION sys.remainder(numeric, numeric)
RETURNS numeric
AS $$
    WITH scaled AS (
        SELECT $1 AS n1,
               $2 AS n2,
               $1 * 1.00000000000000000000000000000000000000 / $2 AS q
    ),
    parts AS (
        SELECT n1,
               n2,
               q,
               trunc(q) AS tq,
               abs(2 * (q - trunc(q))) AS frac2
        FROM scaled
    )
    SELECT n1 - n2 *
           (CASE
                WHEN frac2 < 1 THEN tq
                WHEN frac2 > 1 THEN tq + sign(q)
                WHEN mod(tq, 2) = 0 THEN tq
                ELSE tq + sign(q)
            END)
    FROM parts
$$
LANGUAGE sql
STRICT
IMMUTABLE
PARALLEL SAFE;

/* End - REMAINDER */
