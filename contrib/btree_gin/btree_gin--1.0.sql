/* contrib/btree_gin/btree_gin--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION btree_gin" to load this file. \quit

CREATE FUNCTION gin_btree_consistent(internal, int2, anyelement, int4, internal, internal)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_value_int2(int2, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_int2(int2, int2, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_int2(int2, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS int2_ops
DEFAULT FOR TYPE int2 USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btint2cmp(int2,int2),
    FUNCTION        2       gin_extract_value_int2(int2, internal),
    FUNCTION        3       gin_extract_query_int2(int2, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_int2(int2,int2,int2, internal),
STORAGE         int2;

CREATE FUNCTION gin_extract_value_int4(int4, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_int4(int4, int4, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_int4(int4, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS int4_ops
DEFAULT FOR TYPE int4 USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btint4cmp(int4,int4),
    FUNCTION        2       gin_extract_value_int4(int4, internal),
    FUNCTION        3       gin_extract_query_int4(int4, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_int4(int4,int4,int2, internal),
STORAGE         int4;

CREATE FUNCTION gin_extract_value_int8(int8, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_int8(int8, int8, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_int8(int8, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS int8_ops
DEFAULT FOR TYPE int8 USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btint8cmp(int8,int8),
    FUNCTION        2       gin_extract_value_int8(int8, internal),
    FUNCTION        3       gin_extract_query_int8(int8, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_int8(int8,int8,int2, internal),
STORAGE         int8;

CREATE FUNCTION gin_extract_value_float4(float4, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_float4(float4, float4, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_float4(float4, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS float4_ops
DEFAULT FOR TYPE float4 USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btfloat4cmp(float4,float4),
    FUNCTION        2       gin_extract_value_float4(float4, internal),
    FUNCTION        3       gin_extract_query_float4(float4, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_float4(float4,float4,int2, internal),
STORAGE         float4;

CREATE FUNCTION gin_extract_value_float8(float8, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_float8(float8, float8, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_float8(float8, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS float8_ops
DEFAULT FOR TYPE float8 USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btfloat8cmp(float8,float8),
    FUNCTION        2       gin_extract_value_float8(float8, internal),
    FUNCTION        3       gin_extract_query_float8(float8, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_float8(float8,float8,int2, internal),
STORAGE         float8;

CREATE FUNCTION gin_extract_value_money(money, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_money(money, money, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_money(money, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS money_ops
DEFAULT FOR TYPE money USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       cash_cmp(money,money),
    FUNCTION        2       gin_extract_value_money(money, internal),
    FUNCTION        3       gin_extract_query_money(money, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_money(money,money,int2, internal),
STORAGE         money;

CREATE FUNCTION gin_extract_value_oid(oid, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_oid(oid, oid, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_oid(oid, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS oid_ops
DEFAULT FOR TYPE oid USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btoidcmp(oid,oid),
    FUNCTION        2       gin_extract_value_oid(oid, internal),
    FUNCTION        3       gin_extract_query_oid(oid, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_oid(oid,oid,int2, internal),
STORAGE         oid;

CREATE FUNCTION gin_extract_value_timestamp(pg_catalog.timestamp, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_timestamp(pg_catalog.timestamp, pg_catalog.timestamp, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_timestamp(pg_catalog.timestamp, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS timestamp_ops
DEFAULT FOR TYPE pg_catalog.timestamp USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       timestamp_cmp(pg_catalog.timestamp,pg_catalog.timestamp),
    FUNCTION        2       gin_extract_value_timestamp(pg_catalog.timestamp, internal),
    FUNCTION        3       gin_extract_query_timestamp(pg_catalog.timestamp, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_timestamp(pg_catalog.timestamp,pg_catalog.timestamp,int2, internal),
STORAGE         pg_catalog.timestamp;

CREATE FUNCTION gin_extract_value_timestamptz(pg_catalog.timestamptz, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_timestamptz(pg_catalog.timestamptz, pg_catalog.timestamptz, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_timestamptz(pg_catalog.timestamptz, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS timestamptz_ops
DEFAULT FOR TYPE pg_catalog.timestamptz USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       timestamptz_cmp(pg_catalog.timestamptz,pg_catalog.timestamptz),
    FUNCTION        2       gin_extract_value_timestamptz(pg_catalog.timestamptz, internal),
    FUNCTION        3       gin_extract_query_timestamptz(pg_catalog.timestamptz, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_timestamptz(pg_catalog.timestamptz,pg_catalog.timestamptz,int2, internal),
STORAGE         pg_catalog.timestamptz;

CREATE FUNCTION gin_extract_value_time(pg_catalog.time, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_time(pg_catalog.time, pg_catalog.time, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_time(pg_catalog.time, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS time_ops
DEFAULT FOR TYPE pg_catalog.time USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       time_cmp(pg_catalog.time,pg_catalog.time),
    FUNCTION        2       gin_extract_value_time(pg_catalog.time, internal),
    FUNCTION        3       gin_extract_query_time(pg_catalog.time, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_time(pg_catalog.time,pg_catalog.time,int2, internal),
STORAGE         time;

CREATE FUNCTION gin_extract_value_timetz(pg_catalog.timetz, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_timetz(pg_catalog.timetz, pg_catalog.timetz, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_timetz(pg_catalog.timetz, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS timetz_ops
DEFAULT FOR TYPE pg_catalog.timetz USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       timetz_cmp(pg_catalog.timetz,pg_catalog.timetz),
    FUNCTION        2       gin_extract_value_timetz(pg_catalog.timetz, internal),
    FUNCTION        3       gin_extract_query_timetz(pg_catalog.timetz, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_timetz(pg_catalog.timetz,pg_catalog.timetz,int2, internal),
STORAGE         timetz;

CREATE FUNCTION gin_extract_value_date(pg_catalog.date, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_date(pg_catalog.date, pg_catalog.date, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_date(pg_catalog.date, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS date_ops
DEFAULT FOR TYPE pg_catalog.date USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       date_cmp(pg_catalog.date,pg_catalog.date),
    FUNCTION        2       gin_extract_value_date(pg_catalog.date, internal),
    FUNCTION        3       gin_extract_query_date(pg_catalog.date, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_date(pg_catalog.date,pg_catalog.date,int2, internal),
STORAGE         pg_catalog.date;

CREATE FUNCTION gin_extract_value_interval(pg_catalog.interval, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_interval(pg_catalog.interval, pg_catalog.interval, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_interval(pg_catalog.interval, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS interval_ops
DEFAULT FOR TYPE pg_catalog.interval USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       interval_cmp(pg_catalog.interval,pg_catalog.interval),
    FUNCTION        2       gin_extract_value_interval(pg_catalog.interval, internal),
    FUNCTION        3       gin_extract_query_interval(pg_catalog.interval, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_interval(pg_catalog.interval,pg_catalog.interval,int2, internal),
STORAGE         pg_catalog.interval;

CREATE FUNCTION gin_extract_value_macaddr(pg_catalog.macaddr, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_macaddr(pg_catalog.macaddr, pg_catalog.macaddr, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_macaddr(pg_catalog.macaddr, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS macaddr_ops
DEFAULT FOR TYPE pg_catalog.macaddr USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       macaddr_cmp(pg_catalog.macaddr,pg_catalog.macaddr),
    FUNCTION        2       gin_extract_value_macaddr(pg_catalog.macaddr, internal),
    FUNCTION        3       gin_extract_query_macaddr(pg_catalog.macaddr, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_macaddr(pg_catalog.macaddr,pg_catalog.macaddr,int2, internal),
STORAGE         pg_catalog.macaddr;

CREATE FUNCTION gin_extract_value_inet(inet, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_inet(inet, inet, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_inet(inet, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS inet_ops
DEFAULT FOR TYPE inet USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       network_cmp(inet,inet),
    FUNCTION        2       gin_extract_value_inet(inet, internal),
    FUNCTION        3       gin_extract_query_inet(inet, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_inet(inet,inet,int2, internal),
STORAGE         inet;

CREATE FUNCTION gin_extract_value_cidr(cidr, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_cidr(cidr, cidr, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_cidr(cidr, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS cidr_ops
DEFAULT FOR TYPE cidr USING gin
AS
    OPERATOR        1       <(inet,inet),
    OPERATOR        2       <=(inet,inet),
    OPERATOR        3       =(inet,inet),
    OPERATOR        4       >=(inet,inet),
    OPERATOR        5       >(inet,inet),
    FUNCTION        1       network_cmp(inet,inet),
    FUNCTION        2       gin_extract_value_cidr(cidr, internal),
    FUNCTION        3       gin_extract_query_cidr(cidr, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_cidr(cidr,cidr,int2, internal),
STORAGE         cidr;

CREATE FUNCTION gin_extract_value_text(pg_catalog.text, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_text(pg_catalog.text, pg_catalog.text, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_text(pg_catalog.text, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS text_ops
DEFAULT FOR TYPE pg_catalog.text USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       bttextcmp(pg_catalog.text,pg_catalog.text),
    FUNCTION        2       gin_extract_value_text(pg_catalog.text, internal),
    FUNCTION        3       gin_extract_query_text(pg_catalog.text, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_text(pg_catalog.text,pg_catalog.text,int2, internal),
STORAGE         text;

CREATE OPERATOR CLASS varchar_ops
DEFAULT FOR TYPE pg_catalog.varchar USING gin
AS
    OPERATOR        1       <(pg_catalog.text,pg_catalog.text),
    OPERATOR        2       <=(pg_catalog.text,pg_catalog.text),
    OPERATOR        3       =(pg_catalog.text,pg_catalog.text),
    OPERATOR        4       >=(pg_catalog.text,pg_catalog.text),
    OPERATOR        5       >(pg_catalog.text,pg_catalog.text),
    FUNCTION        1       bttextcmp(pg_catalog.text,pg_catalog.text),
    FUNCTION        2       gin_extract_value_text(pg_catalog.text, internal),
    FUNCTION        3       gin_extract_query_text(pg_catalog.text, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_text(pg_catalog.text,pg_catalog.text,int2, internal),
STORAGE         pg_catalog.varchar;

CREATE FUNCTION gin_extract_value_char(pg_catalog.char, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_char(pg_catalog.char, pg_catalog.char, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_char(pg_catalog.char, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS char_ops
DEFAULT FOR TYPE pg_catalog.char USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       btcharcmp(pg_catalog.char,pg_catalog.char),
    FUNCTION        2       gin_extract_value_char(pg_catalog.char, internal),
    FUNCTION        3       gin_extract_query_char(pg_catalog.char, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_char(pg_catalog.char,pg_catalog.char,int2, internal),
STORAGE         pg_catalog.char;

CREATE FUNCTION gin_extract_value_bytea(bytea, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_bytea(bytea, bytea, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_bytea(bytea, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS bytea_ops
DEFAULT FOR TYPE bytea USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       byteacmp(bytea,bytea),
    FUNCTION        2       gin_extract_value_bytea(bytea, internal),
    FUNCTION        3       gin_extract_query_bytea(bytea, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_bytea(bytea,bytea,int2, internal),
STORAGE         bytea;

CREATE FUNCTION gin_extract_value_bit(bit, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_bit(bit, bit, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_bit(bit, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS bit_ops
DEFAULT FOR TYPE bit USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       bitcmp(bit,bit),
    FUNCTION        2       gin_extract_value_bit(bit, internal),
    FUNCTION        3       gin_extract_query_bit(bit, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_bit(bit,bit,int2, internal),
STORAGE         bit;

CREATE FUNCTION gin_extract_value_varbit(varbit, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_varbit(varbit, varbit, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_varbit(varbit, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS varbit_ops
DEFAULT FOR TYPE varbit USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       varbitcmp(varbit,varbit),
    FUNCTION        2       gin_extract_value_varbit(varbit, internal),
    FUNCTION        3       gin_extract_query_varbit(varbit, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_varbit(varbit,varbit,int2, internal),
STORAGE         varbit;

CREATE FUNCTION gin_extract_value_numeric(numeric, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_compare_prefix_numeric(numeric, numeric, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_extract_query_numeric(numeric, internal, int2, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE FUNCTION gin_numeric_cmp(numeric, numeric)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR CLASS numeric_ops
DEFAULT FOR TYPE numeric USING gin
AS
    OPERATOR        1       <,
    OPERATOR        2       <=,
    OPERATOR        3       =,
    OPERATOR        4       >=,
    OPERATOR        5       >,
    FUNCTION        1       gin_numeric_cmp(numeric,numeric),
    FUNCTION        2       gin_extract_value_numeric(numeric, internal),
    FUNCTION        3       gin_extract_query_numeric(numeric, internal, int2, internal, internal),
    FUNCTION        4       gin_btree_consistent(internal, int2, anyelement, int4, internal, internal),
    FUNCTION        5       gin_compare_prefix_numeric(numeric,numeric,int2, internal),
STORAGE         numeric;
