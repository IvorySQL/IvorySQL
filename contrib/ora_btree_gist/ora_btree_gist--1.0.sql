/*
 * contrib/ora_btree_gist/ora_btree_gist--1.0.sql
 * Gist/GIN index ops
 */

CREATE FUNCTION sys.gbtreekey8_in(cstring)
RETURNS sys.gbtreekey8
AS 'MODULE_PATHNAME', 'gbtreekey_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbtreekey8_out(sys.gbtreekey8)
RETURNS cstring
AS 'MODULE_PATHNAME', 'gbtreekey_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE sys.gbtreekey8 (
	INTERNALLENGTH = 8,
	INPUT  = sys.gbtreekey8_in,
	OUTPUT = sys.gbtreekey8_out
);

CREATE FUNCTION sys.gbtreekey16_in(cstring)
RETURNS sys.gbtreekey16
AS 'MODULE_PATHNAME', 'gbtreekey_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbtreekey16_out(sys.gbtreekey16)
RETURNS cstring
AS 'MODULE_PATHNAME', 'gbtreekey_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE sys.gbtreekey16 (
	INTERNALLENGTH = 16,
	INPUT  = sys.gbtreekey16_in,
	OUTPUT = sys.gbtreekey16_out
);

CREATE FUNCTION sys.gbtreekey32_in(cstring)
RETURNS sys.gbtreekey32
AS 'MODULE_PATHNAME', 'gbtreekey_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbtreekey32_out(sys.gbtreekey32)
RETURNS cstring
AS 'MODULE_PATHNAME', 'gbtreekey_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE sys.gbtreekey32 (
	INTERNALLENGTH = 32,
	INPUT  = sys.gbtreekey32_in,
	OUTPUT = sys.gbtreekey32_out
);

CREATE FUNCTION sys.gbtreekey_var_in(cstring)
RETURNS sys.gbtreekey_var
AS 'MODULE_PATHNAME', 'gbtreekey_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbtreekey_var_out(gbtreekey_var)
RETURNS cstring
AS 'MODULE_PATHNAME', 'gbtreekey_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE sys.gbtreekey_var (
	INTERNALLENGTH = VARIABLE,
	INPUT  = sys.gbtreekey_var_in,
	OUTPUT = sys.gbtreekey_var_out,
	STORAGE = EXTENDED
);

--distance operators

CREATE FUNCTION binary_float_dist(binary_float, binary_float)
RETURNS binary_float
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = binary_float,
	RIGHTARG = binary_float,
	PROCEDURE = binary_float_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION binary_double_dist(binary_double, binary_double)
RETURNS binary_double
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = binary_double,
	RIGHTARG = binary_double,
	PROCEDURE = binary_double_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION sys.ts_dist(sys.oratimestamp, sys.oratimestamp)
RETURNS pg_catalog.interval
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = sys.oratimestamp,
	RIGHTARG = sys.oratimestamp,
	PROCEDURE = sys.ts_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION sys.tstz_dist(sys.oratimestamptz, sys.oratimestamptz)
RETURNS pg_catalog.interval
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = sys.oratimestamptz,
	RIGHTARG = sys.oratimestamptz,
	PROCEDURE = sys.tstz_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION sys.tstz_dist(sys.oratimestampltz, sys.oratimestampltz)
RETURNS pg_catalog.interval
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = sys.oratimestampltz,
	RIGHTARG = sys.oratimestampltz,
	PROCEDURE = sys.tstz_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION sys.ts_dist(sys.oradate, sys.oradate)
RETURNS pg_catalog.interval
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = sys.oradate,
	RIGHTARG = sys.oradate,
	PROCEDURE = sys.ts_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION sys.yminterval_dist(sys.yminterval, sys.yminterval)
RETURNS sys.yminterval
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = sys.yminterval,
	RIGHTARG = sys.yminterval,
	PROCEDURE = sys.yminterval_dist,
	COMMUTATOR = '<->'
);

CREATE FUNCTION sys.dsinterval_dist(sys.dsinterval, sys.dsinterval)
RETURNS sys.dsinterval
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <-> (
	LEFTARG = sys.dsinterval,
	RIGHTARG = sys.dsinterval,
	PROCEDURE = sys.dsinterval_dist,
	COMMUTATOR = '<->'
);

--
--
--
-- number ops
--
--
--
-- define the GiST support methods

CREATE FUNCTION sys.gbt_decompress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_var_decompress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_var_fetch(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_number_consistent(internal, number, int2, oid, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_number_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_number_penalty(internal, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_number_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_number_union(internal, internal)
RETURNS sys.gbtreekey_var
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_number_same(sys.gbtreekey_var, sys.gbtreekey_var, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

-- Create the operator class
CREATE OPERATOR CLASS sys.gist_number_ops
DEFAULT FOR TYPE number USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_number_consistent (internal, number, int2, oid, internal),
	FUNCTION	2	sys.gbt_number_union (internal, internal),
	FUNCTION	3	sys.gbt_number_compress (internal),
	FUNCTION	4	sys.gbt_var_decompress (internal),
	FUNCTION	5	sys.gbt_number_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_number_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_number_same (sys.gbtreekey_var, sys.gbtreekey_var, internal),
	STORAGE			sys.gbtreekey_var;

ALTER OPERATOR FAMILY sys.gist_number_ops USING gist ADD
	OPERATOR	6	<> (number, number) ,
	FUNCTION	9 (number, number) sys.gbt_var_fetch (internal) ;

--
--
--
-- varcharchar ops
--
--
--
-- define the GiST support methods
CREATE FUNCTION sys.gbt_varcharchar_consistent(internal, sys.oravarcharchar, int2, oid, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_varcharchar_consistent(internal, sys.oravarcharbyte, int2, oid, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_varcharchar_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_text_penalty(internal,internal,internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_text_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_text_union(internal, internal)
RETURNS sys.gbtreekey_var
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_text_same(sys.gbtreekey_var, sys.gbtreekey_var, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

---- Create the operator family
CREATE OPERATOR FAMILY gist_varchar2_ops USING gist;

---- Create the operator class
CREATE OPERATOR CLASS gist_varcharchar_ops
DEFAULT FOR TYPE sys.oravarcharchar USING gist FAMILY gist_varchar2_ops
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_varcharchar_consistent (internal, sys.oravarcharchar, int2, oid, internal),
	FUNCTION	2	sys.gbt_text_union (internal, internal),
	FUNCTION	3	sys.gbt_varcharchar_compress (internal),
	FUNCTION	4	sys.gbt_var_decompress (internal),
	FUNCTION	5	sys.gbt_text_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_text_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_text_same (sys.gbtreekey_var, sys.gbtreekey_var, internal),
	STORAGE 		sys.gbtreekey_var;

ALTER OPERATOR FAMILY gist_varchar2_ops USING gist ADD
	OPERATOR	6	<> (sys.oravarcharchar, sys.oravarcharchar) ,
	FUNCTION	9 (sys.oravarcharchar, sys.oravarcharchar) sys.gbt_var_fetch (internal) ;

---- Create the operator class
CREATE OPERATOR CLASS gist_varcharbyte_ops
DEFAULT FOR TYPE sys.oravarcharbyte USING gist FAMILY gist_varchar2_ops
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_varcharchar_consistent (internal, sys.oravarcharbyte, int2, oid, internal),
	FUNCTION	2	sys.gbt_text_union (internal, internal),
	FUNCTION	3	sys.gbt_varcharchar_compress (internal),
	FUNCTION	4	sys.gbt_var_decompress (internal),
	FUNCTION	5	sys.gbt_text_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_text_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_text_same (sys.gbtreekey_var, sys.gbtreekey_var, internal),
	STORAGE 		sys.gbtreekey_var;

ALTER OPERATOR FAMILY gist_varchar2_ops USING gist ADD
	OPERATOR	6	<> (sys.oravarcharbyte, sys.oravarcharbyte) ,
	FUNCTION	9 (sys.oravarcharbyte, sys.oravarcharbyte) sys.gbt_var_fetch (internal) ;

--
--
--
-- binary_float ops
--
--
--
-- define the GiST support methods
CREATE FUNCTION sys.gbt_binary_float_consistent(internal,binary_float,int2,oid,internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_distance(internal,binary_float,int2,oid,internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_fetch(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_penalty(internal,internal,internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_union(internal, internal)
RETURNS sys.gbtreekey8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_float_same(sys.gbtreekey8, sys.gbtreekey8, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

-- Create the operator class
CREATE OPERATOR CLASS gist_binary_float_ops
DEFAULT FOR TYPE binary_float USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_binary_float_consistent (internal, binary_float, int2, oid, internal),
	FUNCTION	2	sys.gbt_binary_float_union (internal, internal),
	FUNCTION	3	sys.gbt_binary_float_compress (internal),
	FUNCTION	4	sys.gbt_decompress (internal),
	FUNCTION	5	sys.gbt_binary_float_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_binary_float_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_binary_float_same (sys.gbtreekey8, sys.gbtreekey8, internal),
	STORAGE 	sys.gbtreekey8;

ALTER OPERATOR FAMILY gist_binary_float_ops USING gist ADD
	OPERATOR	6	<> (binary_float, binary_float) ,
	OPERATOR	15	<-> (binary_float, binary_float) FOR ORDER BY sys.binary_ops ,
	FUNCTION	8 (binary_float, binary_float) sys.gbt_binary_float_distance (internal, binary_float, int2, oid, internal) ,
	FUNCTION	9 (binary_float, binary_float) sys.gbt_binary_float_fetch (internal) ;

--
--
--
-- binary_double ops
--
--
--
-- define the GiST support methods
CREATE FUNCTION sys.gbt_binary_double_consistent(internal,binary_double,int2,oid,internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_distance(internal, binary_double, int2, oid, internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_fetch(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_penalty(internal, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_union(internal, internal)
RETURNS sys.gbtreekey16
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_binary_double_same(sys.gbtreekey16, sys.gbtreekey16, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

-- Create the operator class
CREATE OPERATOR CLASS gist_binary_double_ops
DEFAULT FOR TYPE binary_double USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_binary_double_consistent (internal, binary_double, int2, oid, internal),
	FUNCTION	2	sys.gbt_binary_double_union (internal, internal),
	FUNCTION	3	sys.gbt_binary_double_compress (internal),
	FUNCTION	4	sys.gbt_decompress (internal),
	FUNCTION	5	sys.gbt_binary_double_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_binary_double_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_binary_double_same (sys.gbtreekey16, sys.gbtreekey16, internal),
	STORAGE 	sys.gbtreekey16;

ALTER OPERATOR FAMILY gist_binary_double_ops USING gist ADD
	OPERATOR	6	<> (binary_double, binary_double) ,
	OPERATOR	15	<-> (binary_double, binary_double) FOR ORDER BY sys.binary_ops ,
	FUNCTION	8 (binary_double, binary_double) sys.gbt_binary_double_distance (internal, binary_double, int2, oid, internal) ,
	FUNCTION	9 (binary_double, binary_double) sys.gbt_binary_double_fetch (internal) ;

--
--
--
-- oratimestamp ops
--
--
--
CREATE FUNCTION sys.gbt_ts_consistent(internal,sys.oratimestamp,int2,oid,internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_distance(internal,sys.oratimestamp,int2,oid,internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_tstz_consistent(internal,sys.oratimestamptz,int2,oid,internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_tstz_consistent(internal,sys.oratimestampltz,int2,oid,internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_tstz_distance(internal,sys.oratimestamptz,int2,oid,internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_tstz_distance(internal,sys.oratimestampltz,int2,oid,internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_tstz_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_fetch(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_penalty(internal,internal,internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_union(internal, internal)
RETURNS sys.gbtreekey16
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_same(sys.gbtreekey16, sys.gbtreekey16, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

-- Create the operator class
CREATE OPERATOR CLASS gist_oratimestamp_ops
DEFAULT FOR TYPE sys.oratimestamp USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_ts_consistent (internal, sys.oratimestamp, int2, oid, internal),
	FUNCTION	2	sys.gbt_ts_union (internal, internal),
	FUNCTION	3	sys.gbt_ts_compress (internal),
	FUNCTION	4	sys.gbt_decompress (internal),
	FUNCTION	5	sys.gbt_ts_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_ts_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_ts_same (sys.gbtreekey16, sys.gbtreekey16, internal),
	STORAGE 	sys.gbtreekey16;

ALTER OPERATOR FAMILY gist_oratimestamp_ops USING gist ADD
	OPERATOR	6	<> (sys.oratimestamp, sys.oratimestamp) ,
	OPERATOR	15	<-> (sys.oratimestamp, sys.oratimestamp) FOR ORDER BY pg_catalog.interval_ops ,
	FUNCTION	8 (sys.oratimestamp, sys.oratimestamp) sys.gbt_ts_distance (internal, sys.oratimestamp, int2, oid, internal) ,
	FUNCTION	9 (sys.oratimestamp, sys.oratimestamp) sys.gbt_ts_fetch (internal) ;

-- Create the operator class
CREATE OPERATOR CLASS gist_oratimestamptz_ops
DEFAULT FOR TYPE sys.oratimestamptz USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_tstz_consistent (internal, sys.oratimestamptz, int2, oid, internal),
	FUNCTION	2	sys.gbt_ts_union (internal, internal),
	FUNCTION	3	sys.gbt_tstz_compress (internal),
	FUNCTION	4	sys.gbt_decompress (internal),
	FUNCTION	5	sys.gbt_ts_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_ts_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_ts_same (sys.gbtreekey16, sys.gbtreekey16, internal),
	STORAGE 	sys.gbtreekey16;

ALTER OPERATOR FAMILY gist_oratimestamptz_ops USING gist ADD
	OPERATOR	6	<> (sys.oratimestamptz, sys.oratimestamptz) ,
	OPERATOR	15	<-> (sys.oratimestamptz, sys.oratimestamptz) FOR ORDER BY pg_catalog.interval_ops ,
	FUNCTION	8 (sys.oratimestamptz, sys.oratimestamptz) sys.gbt_tstz_distance (internal, sys.oratimestamptz, int2, oid, internal) ,
	FUNCTION	9 (sys.oratimestamptz, sys.oratimestamptz) sys.gbt_ts_fetch (internal) ;

-- Create the operator class
CREATE OPERATOR CLASS gist_oratimestampltz_ops
DEFAULT FOR TYPE sys.oratimestampltz USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_tstz_consistent (internal, sys.oratimestampltz, int2, oid, internal),
	FUNCTION	2	sys.gbt_ts_union (internal, internal),
	FUNCTION	3	sys.gbt_tstz_compress (internal),
	FUNCTION	4	sys.gbt_decompress (internal),
	FUNCTION	5	sys.gbt_ts_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_ts_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_ts_same (sys.gbtreekey16, sys.gbtreekey16, internal),
	STORAGE 	sys.gbtreekey16;

ALTER OPERATOR FAMILY gist_oratimestampltz_ops USING gist ADD
	OPERATOR	6	<> (sys.oratimestampltz, sys.oratimestampltz) ,
	OPERATOR	15	<-> (sys.oratimestampltz, sys.oratimestampltz) FOR ORDER BY pg_catalog.interval_ops ,
	FUNCTION	8 (sys.oratimestampltz, sys.oratimestampltz) sys.gbt_tstz_distance (internal, sys.oratimestampltz, int2, oid, internal) ,
	FUNCTION	9 (sys.oratimestampltz, sys.oratimestampltz) sys.gbt_ts_fetch (internal) ;

--
--
--
-- oradate ops
--
--
--
-- Create the operator class
CREATE FUNCTION sys.gbt_ts_consistent(internal,sys.oradate,int2,oid,internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.gbt_ts_distance(internal,sys.oradate,int2,oid,internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR CLASS gist_oradate_ops
DEFAULT FOR TYPE sys.oradate USING gist
AS
	OPERATOR	1	<  ,
	OPERATOR	2	<= ,
	OPERATOR	3	=  ,
	OPERATOR	4	>= ,
	OPERATOR	5	>  ,
	FUNCTION	1	sys.gbt_ts_consistent (internal, sys.oradate, int2, oid, internal),
	FUNCTION	2	sys.gbt_ts_union (internal, internal),
	FUNCTION	3	sys.gbt_ts_compress (internal),
	FUNCTION	4	sys.gbt_decompress (internal),
	FUNCTION	5	sys.gbt_ts_penalty (internal, internal, internal),
	FUNCTION	6	sys.gbt_ts_picksplit (internal, internal),
	FUNCTION	7	sys.gbt_ts_same (sys.gbtreekey16, sys.gbtreekey16, internal),
	STORAGE 	sys.gbtreekey16;

ALTER OPERATOR FAMILY gist_oradate_ops USING gist ADD
	OPERATOR	6	<> (sys.oradate, sys.oradate) ,
	OPERATOR	15	<-> (sys.oradate, sys.oradate) FOR ORDER BY pg_catalog.interval_ops ,
	FUNCTION	8 (sys.oradate, sys.oradate) sys.gbt_ts_distance (internal, sys.oradate, int2, oid, internal) ,
	FUNCTION	9 (sys.oradate, sys.oradate) sys.gbt_ts_fetch (internal) ;

--
--
--
-- yminterval ops
--
--
--
CREATE FUNCTION gbt_ymintv_consistent(internal, sys.yminterval, int2, oid, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_distance(internal, sys.yminterval, int2, oid, internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_decompress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_fetch(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_penalty(internal, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_union(internal, internal)
RETURNS sys.gbtreekey32
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_ymintv_same(sys.gbtreekey32, sys.gbtreekey32, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

-- Create the operator class
CREATE OPERATOR CLASS gist_yminterval_ops
DEFAULT FOR TYPE yminterval USING gist
AS
	OPERATOR	1	< ,
	OPERATOR	2	<= ,
	OPERATOR	3	= ,
	OPERATOR	4	>= ,
	OPERATOR	5	> ,
	FUNCTION	1	gbt_ymintv_consistent (internal, sys.yminterval, int2, oid, internal),
	FUNCTION	2	gbt_ymintv_union (internal, internal),
	FUNCTION	3	gbt_ymintv_compress (internal),
	FUNCTION	4	gbt_ymintv_decompress (internal),
	FUNCTION	5	gbt_ymintv_penalty (internal, internal, internal),
	FUNCTION	6	gbt_ymintv_picksplit (internal, internal),
	FUNCTION	7	gbt_ymintv_same (sys.gbtreekey32, sys.gbtreekey32, internal),
	STORAGE 	sys.gbtreekey32;

ALTER OPERATOR FAMILY gist_yminterval_ops USING gist ADD
	OPERATOR	6	<> (sys.yminterval, sys.yminterval) ,
	OPERATOR	15	<-> (sys.yminterval, sys.yminterval) FOR ORDER BY sys.yminterval_ops ,
	FUNCTION	8 (sys.yminterval, sys.yminterval) gbt_ymintv_distance (internal, sys.yminterval, int2, oid, internal) ,
	FUNCTION	9 (sys.yminterval, sys.yminterval) gbt_ymintv_fetch (internal) ;

--
--
--
-- dsinterval ops
--
--
--
CREATE FUNCTION gbt_dsintv_consistent(internal, sys.dsinterval, int2, oid, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_distance(internal, sys.dsinterval, int2, oid, internal)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_compress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_decompress(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_fetch(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_penalty(internal, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_picksplit(internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_union(internal, internal)
RETURNS sys.gbtreekey32
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION gbt_dsintv_same(sys.gbtreekey32, sys.gbtreekey32, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

-- Create the operator class
CREATE OPERATOR CLASS gist_dsinterval_ops
DEFAULT FOR TYPE dsinterval USING gist
AS
	OPERATOR	1	< ,
	OPERATOR	2	<= ,
	OPERATOR	3	= ,
	OPERATOR	4	>= ,
	OPERATOR	5	> ,
	FUNCTION	1	gbt_dsintv_consistent (internal, sys.dsinterval, int2, oid, internal),
	FUNCTION	2	gbt_dsintv_union (internal, internal),
	FUNCTION	3	gbt_dsintv_compress (internal),
	FUNCTION	4	gbt_dsintv_decompress (internal),
	FUNCTION	5	gbt_dsintv_penalty (internal, internal, internal),
	FUNCTION	6	gbt_dsintv_picksplit (internal, internal),
	FUNCTION	7	gbt_dsintv_same (sys.gbtreekey32, sys.gbtreekey32, internal),
	STORAGE 	sys.gbtreekey32;

ALTER OPERATOR FAMILY gist_dsinterval_ops USING gist ADD
	OPERATOR	6	<> (sys.dsinterval, sys.dsinterval) ,
	OPERATOR	15	<-> (sys.dsinterval, sys.dsinterval) FOR ORDER BY sys.dsinterval_ops ,
	FUNCTION	8 (sys.dsinterval, sys.dsinterval) gbt_dsintv_distance (internal, sys.dsinterval, int2, oid, internal) ,
	FUNCTION	9 (sys.dsinterval, sys.dsinterval) gbt_dsintv_fetch (internal) ;
