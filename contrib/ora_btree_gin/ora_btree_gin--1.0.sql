/*
 * contrib/ora_btree_gin/ora_btree_gin--1.0.sql
 * GIN index ops
 */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION ora_btree_gin" to load this file. \quit

CREATE FUNCTION sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;


--
--
--
-- number ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_number(number, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_number(number, number, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_number(number, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_number_cmp(number, number)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS sys.gin_number_ops
DEFAULT FOR TYPE sys.number USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.gin_number_cmp(number, number),
	FUNCTION		2		sys.gin_extract_value_number(number, internal),
	FUNCTION		3		sys.gin_extract_query_number(number, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_number(number, number, int2, internal),
STORAGE			number;

--
--
--
-- varchar2 ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_varchar2(sys.oravarcharchar, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_varchar2(sys.oravarcharchar, sys.oravarcharchar, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_varchar2(sys.oravarcharchar, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_value_varchar2(sys.oravarcharbyte, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_varchar2(sys.oravarcharbyte, sys.oravarcharbyte, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_varchar2(sys.oravarcharbyte, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_varchar2(sys.oravarcharchar, sys.oravarcharbyte, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_varchar2(sys.oravarcharbyte, sys.oravarcharchar, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

/* CREATE OPERATOR FAMILY */
CREATE OPERATOR FAMILY sys.gin_oravarchar2_ops USING gin;

/* CREATE OPERATOR CLASS for 'oravarcharchar' */
CREATE OPERATOR CLASS sys.gin_oravarcharchar_ops
DEFAULT FOR TYPE sys.oravarcharchar USING gin FAMILY sys.gin_oravarchar2_ops
AS
	OPERATOR		1		<  (sys.oravarcharchar, sys.oravarcharchar),
	OPERATOR		2		<= (sys.oravarcharchar, sys.oravarcharchar),
	OPERATOR		3		=  (sys.oravarcharchar, sys.oravarcharchar),
	OPERATOR		4		>= (sys.oravarcharchar, sys.oravarcharchar),
	OPERATOR		5		>  (sys.oravarcharchar, sys.oravarcharchar),
	FUNCTION		1		sys.bt_oravarchar_cmp(sys.oravarcharchar, sys.oravarcharchar),
	FUNCTION		2		sys.gin_extract_value_varchar2(sys.oravarcharchar, internal),
	FUNCTION		3		sys.gin_extract_query_varchar2(sys.oravarcharchar, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_varchar2(sys.oravarcharchar, sys.oravarcharchar, int2, internal),
STORAGE			sys.oravarcharchar;

/* CREATE OPERATOR CLASS for 'oravarcharbyte' */
CREATE OPERATOR CLASS sys.gin_oravarcharbyte_ops
DEFAULT FOR TYPE sys.oravarcharbyte USING gin FAMILY sys.gin_oravarchar2_ops
AS
	OPERATOR		1		<  (sys.oravarcharbyte, sys.oravarcharbyte),
	OPERATOR		2		<= (sys.oravarcharbyte, sys.oravarcharbyte),
	OPERATOR		3		=  (sys.oravarcharbyte, sys.oravarcharbyte),
	OPERATOR		4		>= (sys.oravarcharbyte, sys.oravarcharbyte),
	OPERATOR		5		>  (sys.oravarcharbyte, sys.oravarcharbyte),
	FUNCTION		1		sys.bt_oravarchar_cmp(sys.oravarcharbyte, sys.oravarcharbyte),
	FUNCTION		2		sys.gin_extract_value_varchar2(sys.oravarcharbyte, internal),
	FUNCTION		3		sys.gin_extract_query_varchar2(sys.oravarcharbyte, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_varchar2(sys.oravarcharbyte, sys.oravarcharbyte, int2, internal),
STORAGE			sys.oravarcharbyte;

ALTER OPERATOR FAMILY sys.gin_oravarchar2_ops USING gin ADD
	-- Cross data type comparison
	OPERATOR		1		<  (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR		2		<= (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR		3		=  (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR		4		>= (sys.oravarcharchar, sys.oravarcharbyte),
	OPERATOR		5		>  (sys.oravarcharchar, sys.oravarcharbyte),
	-- Cross data type comparison
	OPERATOR		1		<  (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR		2		<= (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR		3		=  (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR		4		>= (sys.oravarcharbyte, sys.oravarcharchar),
	OPERATOR		5		>  (sys.oravarcharbyte, sys.oravarcharchar);

--
--
--
-- binary_float ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_binary_float(binary_float, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_binary_float(binary_float, binary_float, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_binary_float(binary_float, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS sys.gin_binary_float_ops
DEFAULT FOR TYPE sys.binary_float USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.bt_binary_float_cmp(sys.binary_float, sys.binary_float),
	FUNCTION		2		sys.gin_extract_value_binary_float(sys.binary_float, internal),
	FUNCTION		3		sys.gin_extract_query_binary_float(sys.binary_float, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_binary_float(sys.binary_float, sys.binary_float, int2, internal),
STORAGE		binary_float;

--
--
--
-- binary_double ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_binary_double(binary_double, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_binary_double(binary_double, binary_double, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_binary_double(binary_double, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS sys.gin_binary_double_ops
DEFAULT FOR TYPE sys.binary_double USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.bt_binary_double_cmp(sys.binary_double, sys.binary_double),
	FUNCTION		2		sys.gin_extract_value_binary_double(sys.binary_double, internal),
	FUNCTION		3		sys.gin_extract_query_binary_double(sys.binary_double, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_binary_double(sys.binary_double, sys.binary_double, int2, internal),
STORAGE		binary_double;

--
--
--
-- oratimestamp ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_oratimestamp(sys.oratimestamp, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_oratimestamp(sys.oratimestamp, sys.oratimestamp, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_oratimestamp(sys.oratimestamp, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS gin_oratimestamp_ops
DEFAULT FOR TYPE sys.oratimestamp USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.oratimestamp_cmp(sys.oratimestamp, sys.oratimestamp),
	FUNCTION		2		sys.gin_extract_value_oratimestamp(sys.oratimestamp, internal),
	FUNCTION		3		sys.gin_extract_query_oratimestamp(sys.oratimestamp, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_oratimestamp(sys.oratimestamp, sys.oratimestamp, int2, internal),
STORAGE		sys.oratimestamp;

--
--
--
-- oratimestamptz ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_oratimestamptz(sys.oratimestamptz, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_oratimestamptz(sys.oratimestamptz, sys.oratimestamptz, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_oratimestamptz(sys.oratimestamptz, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS gin_oratimestamptz_ops
DEFAULT FOR TYPE sys.oratimestamptz USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.oratimestamptz_cmp(sys.oratimestamptz, sys.oratimestamptz),
	FUNCTION		2		sys.gin_extract_value_oratimestamptz(sys.oratimestamptz, internal),
	FUNCTION		3		sys.gin_extract_query_oratimestamptz(sys.oratimestamptz, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_oratimestamptz(sys.oratimestamptz, sys.oratimestamptz, int2, internal),
STORAGE		sys.oratimestamptz;

--
--
--
-- oratimestampltz ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_oratimestampltz(sys.oratimestampltz, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_oratimestampltz(sys.oratimestampltz, sys.oratimestampltz, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_oratimestampltz(sys.oratimestampltz, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS gin_oratimestampltz_ops
DEFAULT FOR TYPE sys.oratimestampltz USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.oratimestampltz_cmp(sys.oratimestampltz, sys.oratimestampltz),
	FUNCTION		2		sys.gin_extract_value_oratimestampltz(sys.oratimestampltz, internal),
	FUNCTION		3		sys.gin_extract_query_oratimestampltz(sys.oratimestampltz, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_oratimestampltz(sys.oratimestampltz, sys.oratimestampltz, int2, internal),
STORAGE		sys.oratimestampltz;

--
--
--
-- oradate ops
--
--
--
-- define the GIN support methods

CREATE FUNCTION sys.gin_extract_value_oradate(sys.oradate, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_compare_prefix_oradate(sys.oradate, sys.oradate, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION sys.gin_extract_query_oradate(sys.oradate, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS gin_oradate_ops
DEFAULT FOR TYPE sys.oradate USING gin
AS
	OPERATOR		1		<,
	OPERATOR		2		<=,
	OPERATOR		3		=,
	OPERATOR		4		>=,
	OPERATOR		5		>,
	FUNCTION		1		sys.oradate_cmp(sys.oradate, sys.oradate),
	FUNCTION		2		sys.gin_extract_value_oradate(sys.oradate, internal),
	FUNCTION		3		sys.gin_extract_query_oradate(sys.oradate, internal, int2, internal, internal),
	FUNCTION		4		sys.gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
	FUNCTION		5		sys.gin_compare_prefix_oradate(sys.oradate, sys.oradate, int2, internal),
STORAGE		sys.oradate;
