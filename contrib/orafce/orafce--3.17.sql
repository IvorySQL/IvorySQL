/* orafce--3.17.sql */

/* -- complain if script is sourced in psql, rather than via CREATE EXTENSION */
\echo Use "CREATE EXTENSION orafce" to load this file. \quit

CREATE FUNCTION pg_catalog.trunc(value date, fmt text)
RETURNS date
AS 'MODULE_PATHNAME','ora_date_trunc'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.trunc(date,text) IS 'truncate date according to the specified format';

CREATE FUNCTION pg_catalog.round(value date, fmt text)
RETURNS date
AS 'MODULE_PATHNAME','ora_date_round'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.round(date, text) IS 'round dates according to the specified format';

CREATE FUNCTION pg_catalog.next_day(value date, weekday text)
RETURNS date
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.next_day (date, text) IS 'returns the first weekday that is greater than a date value';

CREATE FUNCTION pg_catalog.next_day(value date, weekday integer)
RETURNS date
AS 'MODULE_PATHNAME', 'next_day_by_index'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.next_day (date, integer) IS 'returns the first weekday that is greater than a date value';

CREATE FUNCTION pg_catalog.last_day(value date)
RETURNS date
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.last_day(date) IS 'returns last day of the month based on a date value';

CREATE FUNCTION pg_catalog.months_between(date1 date, date2 date)
RETURNS numeric
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.months_between(date, date) IS 'returns the number of months between date1 and date2';

CREATE FUNCTION pg_catalog.add_months(day date, value int)
RETURNS date
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.add_months(date, int) IS 'returns date plus n months';

CREATE FUNCTION pg_catalog.trunc(value timestamp with time zone, fmt text)
RETURNS timestamp with time zone
AS 'MODULE_PATHNAME', 'ora_timestamptz_trunc'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.trunc(timestamp with time zone, text) IS 'truncate date according to the specified format';

CREATE FUNCTION pg_catalog.round(value timestamp with time zone, fmt text)
RETURNS timestamp with time zone
AS 'MODULE_PATHNAME','ora_timestamptz_round'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.round(timestamp with time zone, text) IS 'round dates according to the specified format';

CREATE FUNCTION pg_catalog.round(value timestamp with time zone)
RETURNS timestamp with time zone
AS $$ SELECT pg_catalog.round($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.round(timestamp with time zone) IS 'will round dates according to the specified format';

CREATE FUNCTION pg_catalog.round(value date)
RETURNS date
AS $$ SELECT $1; $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.round(value date)IS 'will round dates according to the specified format';

CREATE FUNCTION pg_catalog.trunc(value timestamp with time zone)
RETURNS timestamp with time zone
AS $$ SELECT pg_catalog.trunc($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.trunc(timestamp with time zone) IS 'truncate date according to the specified format';

CREATE FUNCTION pg_catalog.trunc(value date)
RETURNS date
AS $$ SELECT $1; $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.trunc(date) IS 'truncate date according to the specified format';

CREATE FUNCTION pg_catalog.nlssort(text, text)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_nlssort'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION pg_catalog.nlssort(text, text) IS '';

CREATE FUNCTION pg_catalog.nlssort(text)
RETURNS bytea
AS $$ SELECT pg_catalog.nlssort($1, null); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.nlssort(text)IS '';

CREATE FUNCTION pg_catalog.set_nls_sort(text)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_set_nls_sort'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.set_nls_sort(text) IS '';

CREATE FUNCTION pg_catalog.instr(str text, patt text, start int, nth int)
RETURNS int
AS 'MODULE_PATHNAME','plvstr_instr4'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.instr(text, text, int, int) IS 'Search pattern in string';

CREATE FUNCTION pg_catalog.instr(str text, patt text, start int)
RETURNS int
AS 'MODULE_PATHNAME','plvstr_instr3'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.instr(text, text, int) IS 'Search pattern in string';

CREATE FUNCTION pg_catalog.instr(str text, patt text)
RETURNS int
AS 'MODULE_PATHNAME','plvstr_instr2'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.instr(text, text) IS 'Search pattern in string';

CREATE FUNCTION pg_catalog.to_char(num smallint)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_char_int4'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_char(smallint) IS 'Convert number to string';

CREATE FUNCTION pg_catalog.to_char(num int)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_char_int4'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_char(int) IS 'Convert number to string';

CREATE FUNCTION pg_catalog.to_char(num bigint)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_char_int8'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_char(bigint) IS 'Convert number to string';

CREATE FUNCTION pg_catalog.to_char(num real)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_char_float4'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_char(real) IS 'Convert number to string';

CREATE FUNCTION pg_catalog.to_char(num double precision)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_char_float8'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_char(double precision) IS 'Convert number to string';

CREATE FUNCTION pg_catalog.to_char(num numeric)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_char_numeric'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_char(numeric) IS 'Convert number to string';

CREATE FUNCTION pg_catalog.to_number(str text)
RETURNS numeric
AS 'MODULE_PATHNAME','orafce_to_number'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_number(text) IS 'Convert string to number';

CREATE OR REPLACE FUNCTION pg_catalog.to_number(numeric)
RETURNS numeric AS $$
SELECT pg_catalog.to_number($1::text);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION pg_catalog.to_number(numeric,numeric)
RETURNS numeric AS $$
SELECT pg_catalog.to_number($1::text,$2::text);
$$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION pg_catalog.to_date(str text)
RETURNS timestamp
AS 'MODULE_PATHNAME','ora_to_date'
LANGUAGE C STABLE STRICT;
COMMENT ON FUNCTION pg_catalog.to_date(text) IS 'Convert string to timestamp';

CREATE FUNCTION bitand(bigint, bigint)
RETURNS bigint
AS $$ SELECT $1 & $2; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION sinh(float8)
RETURNS float8 AS
$$ SELECT (exp($1) - exp(-$1)) / 2; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION cosh(float8)
RETURNS float8 AS
$$ SELECT (exp($1) + exp(-$1)) / 2; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION tanh(float8)
RETURNS float8 AS
$$ SELECT sinh($1) / cosh($1); $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION dump("any")
RETURNS varchar
AS 'MODULE_PATHNAME', 'orafce_dump'
LANGUAGE C;

CREATE FUNCTION dump("any", integer)
RETURNS varchar
AS 'MODULE_PATHNAME', 'orafce_dump'
LANGUAGE C;

CREATE SCHEMA plvstr;

CREATE FUNCTION plvstr.rvrs(str text, start int, _end int)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_rvrs'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvstr.rvrs(text, int, int) IS 'Reverse string or part of string';

CREATE FUNCTION plvstr.rvrs(str text, start int)
RETURNS text
AS $$ SELECT plvstr.rvrs($1,$2,NULL);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rvrs(text, int) IS 'Reverse string or part of string';

CREATE FUNCTION plvstr.rvrs(str text)
RETURNS text
AS $$ SELECT plvstr.rvrs($1,1,NULL);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rvrs(text) IS 'Reverse string or part of string';

CREATE FUNCTION pg_catalog.lnnvl(bool)
RETURNS bool
AS 'MODULE_PATHNAME','ora_lnnvl'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION pg_catalog.lnnvl(bool) IS '';

/* -- can't overwrite PostgreSQL functions!!!! */

CREATE SCHEMA oracle;

CREATE FUNCTION oracle.nanvl(float4, float4)
RETURNS float4 AS
$$ SELECT CASE WHEN $1 = 'NaN' THEN $2 ELSE $1 END; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION oracle.nanvl(float8, float8)
RETURNS float8 AS
$$ SELECT CASE WHEN $1 = 'NaN' THEN $2 ELSE $1 END; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION oracle.nanvl(numeric, numeric)
RETURNS numeric AS
$$ SELECT CASE WHEN $1 = 'NaN' THEN $2 ELSE $1 END; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION oracle.nanvl(float4, varchar)
RETURNS float4 AS
$$ SELECT CASE WHEN $1 = 'NaN' THEN $2::float4 ELSE $1 END; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION oracle.nanvl(float8, varchar)
RETURNS float8 AS
$$ SELECT CASE WHEN $1 = 'NaN' THEN $2::float8 ELSE $1 END; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION oracle.nanvl(numeric, varchar)
RETURNS numeric AS
$$ SELECT CASE WHEN $1 = 'NaN' THEN $2::numeric ELSE $1 END; $$
LANGUAGE sql IMMUTABLE STRICT;

CREATE FUNCTION oracle.substr(str text, start int)
RETURNS text
AS 'MODULE_PATHNAME','oracle_substr2'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.substr(text, int) IS 'Returns substring started on start_in to end';

CREATE FUNCTION oracle.substr(str text, start int, len int)
RETURNS text
AS 'MODULE_PATHNAME','oracle_substr3'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.substr(text, int, int) IS 'Returns substring started on start_in len chars';

CREATE OR REPLACE FUNCTION oracle.substr(numeric,numeric)
RETURNS text AS $$
SELECT oracle.substr($1::text,trunc($2)::int);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.substr(numeric,numeric,numeric)
RETURNS text AS $$
SELECT oracle.substr($1::text,trunc($2)::int,trunc($3)::int);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.substr(varchar,numeric)
RETURNS text AS $$
SELECT oracle.substr($1,trunc($2)::int);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.substr(varchar,numeric,numeric)
RETURNS text AS $$
SELECT oracle.substr($1,trunc($2)::int,trunc($3)::int);
$$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.to_multi_byte(str text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_multi_byte'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.to_multi_byte(text) IS 'Convert all single-byte characters to their corresponding multibyte characters';

CREATE FUNCTION oracle.to_single_byte(str text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_single_byte'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.to_single_byte(text) IS 'Convert characters to their corresponding single-byte characters if possible';

CREATE FUNCTION oracle.to_char("any")
RETURNS TEXT
AS 'MODULE_PATHNAME','orafce_to_varchar'
LANGUAGE C STABLE STRICT;
COMMENT ON FUNCTION oracle.to_char("any") IS 'Convert text type to string';

/* to deal to_char(unknown) */
CREATE FUNCTION oracle.to_char(text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_to_varchar'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.to_char(text) IS 'Convert text to string';

CREATE FUNCTION oracle.bin_to_num(VARIADIC "any")
RETURNS int8 
AS 'MODULE_PATHNAME','orafce_bin_to_num'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION oracle.bin_to_num("any") IS 'Converts a bit vector to its equivalent number.';

CREATE FUNCTION oracle.to_binary_double(VARIADIC "any")
RETURNS float8
AS 'MODULE_PATHNAME','orafce_to_binary_double'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.to_binary_double("any") IS 'double precision';

CREATE FUNCTION oracle.to_binary_float(VARIADIC "any")
RETURNS float4
AS 'MODULE_PATHNAME','orafce_to_binary_float'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.to_binary_float("any") IS 'signle precision';

CREATE OR REPLACE FUNCTION oracle.hex_to_decimal(text)
RETURNS int8
AS 'MODULE_PATHNAME','orafce_hex_to_decimal'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.to_number(float)
RETURNS numeric AS $$
SELECT pg_catalog.to_number($1::text);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.to_timestamp(text ,text)
RETURNS TIMESTAMP WITHOUT TIME ZONE
AS $$ SELECT pg_catalog.to_timestamp($1,$2)::TIMESTAMP WITHOUT TIME ZONE; $$
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.to_timestamp(double precision)
RETURNS TIMESTAMP WITHOUT TIME ZONE
AS $$ SELECT pg_catalog.to_timestamp($1)::TIMESTAMP WITHOUT TIME ZONE; $$
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.to_timestamp_tz(text ,text)
RETURNS TIMESTAMP WITH TIME ZONE
AS $$ SELECT pg_catalog.to_timestamp($1,$2); $$
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.to_timestamp_tz(text)
RETURNS timestamp with time zone
AS 'MODULE_PATHNAME','orafce_to_timestamp_tz'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION oracle.interval_to_seconds(value interval) 
RETURNS float8
AS 'MODULE_PATHNAME','orafce_interval_to_seconds'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION oracle.interval_to_seconds(interval) IS 'transfer interval format to seconds';

CREATE FUNCTION oracle.to_yminterval(text)
 RETURNS interval
AS 'MODULE_PATHNAME','orafce_to_yminterval'
 LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION oracle.to_yminterval(text) IS 'converts a interval datatype to an INTERVAL YEAR TO MONTH type';

CREATE FUNCTION oracle.to_dsinterval(text)
 RETURNS interval
AS 'MODULE_PATHNAME','orafce_to_dsinterval'
 LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION oracle.to_dsinterval(text) IS 'converts a interval datatype to an INTERVAL DAY TO SECOND type';

/* compatible oracle's date */
CREATE OR REPLACE FUNCTION oracle.ora_date_in(cstring)
RETURNS oracle.date
AS 'MODULE_PATHNAME','ora_date_in'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION oracle.ora_date_out(oracle.date)
RETURNS cstring
AS 'MODULE_PATHNAME','ora_date_out'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION oracle.ora_date_recv(internal)
RETURNS oracle.date
AS 'MODULE_PATHNAME','ora_date_recv'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION oracle.ora_date_send(oracle.date)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_date_send'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

create type oracle.date(
input = oracle.ora_date_in,
output = oracle.ora_date_out,
receive = oracle.ora_date_recv,
send = oracle.ora_date_send,
alignment = 'double',
storage = 'plain',
like = 'timestamp',
category = 'D',
preferred = false
);

/* oracle date's cast */
CREATE CAST(timestamp as oracle.date) WITH INOUT AS IMPLICIT; 
create cast(oracle.date as timestamp) WITH INOUT AS IMPLICIT; 

CREATE FUNCTION oracle.ora2pgdate(oracle.date)
RETURNS pg_catalog.date
AS 'select pg_catalog.date($1::timestamp)::pg_catalog.date'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.oradate2timestamptz(oracle.date)
RETURNS timestamp with time zone
AS 'select pg_catalog.timestamptz($1::timestamp)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.oradate2time(oracle.date)
RETURNS time without time zone 
AS 'select pg_catalog.time($1::timestamp)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.pg2oradate(pg_catalog.date)
RETURNS oracle.date 
AS 'select pg_catalog.timestamp($1::timestamp)::oracle.date'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.timestamptz2oradate(timestamptz)
RETURNS oracle.date 
AS 'select pg_catalog.timestamp($1::timestamp)::oracle.date'
LANGUAGE SQL IMMUTABLE;


create cast(pg_catalog.date as oracle.date) with function oracle.pg2oradate(pg_catalog.date) as implicit; 
create cast(oracle.date as pg_catalog.date) with function oracle.ora2pgdate(oracle.date) as assignment; 
create cast(oracle.date as timestamp with time zone) with function oracle.oradate2timestamptz(oracle.date) as implicit; 
create cast(oracle.date as time without time zone) with function oracle.oradate2time(oracle.date) as assignment;
create cast(timestamp with time zone as oracle.date) with function oracle.timestamptz2oradate(timestamptz) as assignment; 

/* oracle date's operator */
----------<=--------------
--date_le_oradate(pg_catalog.date, oracle.date)
CREATE FUNCTION oracle.date_le_oradate(pg_catalog.date, oracle.date)
RETURNS bool
AS 'select pg_catalog.date_le_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<= (procedure = oracle.date_le_oradate, leftarg = pg_catalog.date , rightarg = oracle.date);

--oradate_le_timestamptz(oracle.date,timestamptz)
CREATE FUNCTION oracle.oradate_le_timestamptz(oracle.date, timestamptz)
RETURNS bool
AS 'select pg_catalog.timestamp_le_timestamptz($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<= (procedure = oracle.oradate_le_timestamptz, leftarg = oracle.date , rightarg = timestamptz);

--oradate_le_date(oracle.date, pg_catalog.date)
CREATE FUNCTION oracle.oradate_le_date(oracle.date, pg_catalog.date)
RETURNS bool
AS 'select pg_catalog.timestamp_le_date($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<= (procedure = oracle.oradate_le_date, leftarg = oracle.date , rightarg = pg_catalog.date);

--timestamptz_le_oradate(timestamptz,oracle.date)
CREATE FUNCTION oracle.timestamptz_le_oradate(timestamptz, oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamptz_le_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<= (procedure = oracle.timestamptz_le_oradate, leftarg = timestamptz , rightarg = oracle.date);

--oradate_le(oracle.date, oracle.date)
CREATE FUNCTION oracle.oradate_le(oracle.date, oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamp_le($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<= (procedure = oracle.oradate_le, leftarg = oracle.date , rightarg = oracle.date);

----------<> --------------
--timestamptz_ne_oradate(timestamptz, oracle.date)
CREATE FUNCTION oracle.timestamptz_ne_oradate(timestamptz,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamptz_ne_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<> (procedure = oracle.timestamptz_ne_oradate, leftarg = timestamptz , rightarg = oracle.date);

--oradate_ne(oracle.date,oracle.date)
CREATE FUNCTION oracle.oradate_ne(oracle.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamp_ne($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<> (procedure = oracle.oradate_ne, leftarg = oracle.date , rightarg = oracle.date);

--pgdate_ne_oradate(pg_catalog.date, oracle.date)
CREATE FUNCTION oracle.pgdate_ne_oradate(pg_catalog.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.date_ne_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<> (procedure = oracle.pgdate_ne_oradate, leftarg = pg_catalog.date , rightarg = oracle.date);

--oradate_ne_date(oracle.date, pg_catalog.date)
CREATE FUNCTION oracle.oradate_ne_date(oracle.date,pg_catalog.date)
RETURNS bool
AS 'select pg_catalog.timestamp_ne_date($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<> (procedure = oracle.oradate_ne_date, leftarg = oracle.date , rightarg = pg_catalog.date);

--oradate_ne_timestamptz(oracle.date, timestamptz)
CREATE FUNCTION oracle.oradate_ne_timestamptz(oracle.date, timestamptz)
RETURNS bool
AS 'select pg_catalog.timestamp_ne_timestamptz($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.<> (procedure = oracle.oradate_ne_timestamptz, leftarg = oracle.date , rightarg = timestamptz);

----------=----------------
--oradate_eq_timestamptz(oracle.date, timestamptz)
CREATE FUNCTION oracle.oradate_eq_timestamptz(oracle.date, timestamptz)
RETURNS bool
AS 'select pg_catalog.timestamp_eq_timestamptz($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.oradate_eq_timestamptz, leftarg = oracle.date , rightarg = timestamptz);

--timestamptz_eq_oradate(timestamptz, oracle.date)
CREATE FUNCTION oracle.timestamptz_eq_oradate(timestamptz, oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamptz_eq_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.timestamptz_eq_oradate, leftarg = timestamptz, rightarg = oracle.date);

--oradate_eq(oracle.date, oracle.date)
CREATE FUNCTION oracle.oradate_eq(oracle.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamp_eq($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.oradate_eq, leftarg = oracle.date, rightarg = oracle.date);

CREATE FUNCTION oracle.timestamp_eq_oradate(timestamp,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamp_eq($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.timestamp_eq_oradate, leftarg = timestamp, rightarg = oracle.date);

CREATE FUNCTION oracle.oradate_eq_timestamp(oracle.date,timestamp)
RETURNS bool
AS 'select pg_catalog.timestamp_eq($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.oradate_eq_timestamp, leftarg = oracle.date, rightarg = timestamp);

--pgdate_eq_oradate(pg_catalog.date,oracle.date)
CREATE FUNCTION oracle.pgdate_eq_oradate(pg_catalog.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.date_eq_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.pgdate_eq_oradate, leftarg = pg_catalog.date, rightarg = oracle.date);

--oradate_eq_date(oracle.date, pg_catalog.date) 
CREATE FUNCTION oracle.oradate_eq_date(oracle.date,pg_catalog.date)
RETURNS bool
AS 'select pg_catalog.timestamp_eq_date($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.= (procedure = oracle.oradate_eq_date, leftarg = oracle.date, rightarg = pg_catalog.date);
 
---------->----------------
--oradate_gt(oracle.date, oracle.date)
CREATE FUNCTION oracle.oradate_gt(oracle.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamp_gt($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.> (procedure = oracle.oradate_gt, leftarg = oracle.date, rightarg = oracle.date);

--timestamptz_gt_oradate(timestamptz,oracle.date)
CREATE FUNCTION oracle.timestamptz_gt_oradate(timestamptz,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamptz_gt_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.> (procedure = oracle.timestamptz_gt_oradate, leftarg = timestamptz, rightarg = oracle.date);

--oradate_gt_timestamptz(oracle.date, timestamptz)
CREATE FUNCTION oracle.oradate_gt_timestamptz(oracle.date, timestamptz)
RETURNS bool
AS 'select pg_catalog.timestamp_gt_timestamptz($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.> (procedure = oracle.oradate_gt_timestamptz, leftarg = oracle.date, rightarg = timestamptz);

--oradate_gt_pgdate(oracle.date, pg_catalog.date)
CREATE FUNCTION oracle.oradate_gt_pgdate(oracle.date,pg_catalog.date)
RETURNS bool
AS 'select pg_catalog.timestamp_gt_date($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.> (procedure = oracle.oradate_gt_pgdate, leftarg = oracle.date, rightarg = pg_catalog.date);

--pgdate_gt_oradate(pg_catalog.date, oracle.date)
CREATE FUNCTION oracle.pgdate_gt_oradate(pg_catalog.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.date_gt_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.> (procedure = oracle.pgdate_gt_oradate, leftarg = pg_catalog.date, rightarg = oracle.date);

---------->=----------------
--pgdate_ge_oradate(pg_catalog.date, oracle.date)
CREATE FUNCTION oracle.pgdate_ge_oradate(pg_catalog.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.date_ge_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.>= (procedure = oracle.pgdate_ge_oradate, leftarg = pg_catalog.date, rightarg = oracle.date);

--oradate_ge
CREATE FUNCTION oracle.oradate_ge(oracle.date,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamp_ge($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.>= (procedure = oracle.oradate_ge, leftarg = oracle.date, rightarg = oracle.date);

--oradate_ge_pgdate
CREATE FUNCTION oracle.oradate_ge_pgdate(oracle.date,pg_catalog.date)
RETURNS bool
AS 'select pg_catalog.timestamp_ge_date($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.>= (procedure = oracle.oradate_ge_pgdate, leftarg = oracle.date, rightarg = pg_catalog.date);

--oradate_ge_timestamptz
CREATE FUNCTION oracle.oradate_ge_timestamptz(oracle.date,timestamptz)
RETURNS bool
AS 'select pg_catalog.timestamp_ge_timestamptz($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.>= (procedure = oracle.oradate_ge_timestamptz, leftarg = oracle.date, rightarg = timestamptz);

--timestamptz_ge_oradate
CREATE FUNCTION oracle.timestamptz_ge_oradate(timestamptz,oracle.date)
RETURNS bool
AS 'select pg_catalog.timestamptz_ge_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE;
CREATE OPERATOR oracle.>= (procedure = oracle.timestamptz_ge_oradate, leftarg = timestamptz, rightarg = oracle.date);


--+   oracle.date + interval
CREATE OR REPLACE FUNCTION oracle.oradate_pl_interval(oracle.date, interval)
RETURNS oracle.date
AS 'SELECT pg_catalog.timestamp_pl_interval($1::timestamp, $2)::oracle.date'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.date,
  RIGHTARG  = interval,
  PROCEDURE = oracle.oradate_pl_interval
);

--+    interval + oracle.date
CREATE OR REPLACE FUNCTION oracle.interval_pl_oradate(interval, oracle.date)
RETURNS oracle.date AS $$ 
	select $2 operator(oracle.+) $1;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.+ (
  LEFTARG   = interval,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.interval_pl_oradate
);

--+   oracle.date + real
CREATE OR REPLACE FUNCTION oracle.oradate_pl_float4(oracle.date, real)
RETURNS oracle.date
AS $$ SELECT $1 operator(oracle.+) interval '1 day' * $2 $$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.date,
  RIGHTARG  = real,
  PROCEDURE = oracle.oradate_pl_float4
);

--+     real  +  oracle.date
CREATE OR REPLACE FUNCTION oracle.float4_pl_oradate(real, t oracle.date)
RETURNS oracle.date
AS 'SELECT $2 operator(oracle.+)  $1'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
CREATE OPERATOR oracle.+ (
  LEFTARG   = real,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.float4_pl_oradate
);

--+  oracle.date + double precision
CREATE OR REPLACE FUNCTION oracle.oradate_pl_float8(oracle.date, double precision)
RETURNS oracle.date
AS $$ SELECT $1 + interval '1 day' * $2 $$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.date,
  RIGHTARG  = double precision,
  PROCEDURE = oracle.oradate_pl_float8
);

--+  double precision + oracle.date
CREATE OR REPLACE FUNCTION oracle.float8_pl_oradate(double precision, oracle.date)
RETURNS oracle.date
AS 'SELECT $2 operator(oracle.+) $1'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.+ (
  LEFTARG   = double precision,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.float8_pl_oradate
);

--+   oracle.date + numeric
CREATE OR REPLACE FUNCTION oracle.oradate_add_numeric(oracle.date, numeric)
RETURNS oracle.date
AS $$
	SELECT $1 operator(oracle.+) interval '1 day' * $2;
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.date,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.oradate_add_numeric
);

--+   numeric + oracle.date
CREATE OR REPLACE FUNCTION oracle.numeric_add_oradate(numeric, oracle.date)
RETURNS oracle.date AS  $$
	SELECT $2 operator(oracle.+) $1;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.numeric_add_oradate
);

--+   text + oracle.date
CREATE OR REPLACE FUNCTION oracle.oradate_add_text(oracle.date, text)
RETURNS oracle.date
AS $$
	SELECT $1 operator(oracle.+) $2::interval;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.date,
  RIGHTARG  = text,
  PROCEDURE = oracle.oradate_add_text
);

CREATE OR REPLACE FUNCTION oracle.text_add_oradate(text, oracle.date)
RETURNS oracle.date
AS $$
	SELECT $2 operator(oracle.+) $1::interval;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = text,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.text_add_oradate
);

--+
CREATE OR REPLACE FUNCTION oracle.oradate_add_integer(oracle.date, integer)
RETURNS timestamp AS $$
SELECT $1 + interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.date,
  RIGHTARG  = integer,
  PROCEDURE = oracle.oradate_add_integer
);

CREATE OR REPLACE FUNCTION oracle.integer_add_oradate(integer, oracle.date)
RETURNS timestamp AS $$
SELECT $2 + interval '1 day' * $1;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = integer,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.integer_add_oradate
);

-- -    oracle.date - interval
CREATE OR REPLACE FUNCTION oracle.oradate_mi_interval(oracle.date, interval)
RETURNS oracle.date 
AS 'select pg_catalog.timestamp_mi_interval($1::timestamp, $2)::oracle.date'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = interval,
  PROCEDURE = oracle.oradate_mi_interval
);

CREATE OR REPLACE FUNCTION oracle.oradatesubtract(oracle.date,oracle.date)
RETURNS double precision AS $$
SELECT date_part('epoch', ($1::timestamp - $2::timestamp)/3600/24);
$$ LANGUAGE SQL IMMUTABLE;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.oradatesubtract
);

-- -	oracle.date - oracle.date
CREATE OR REPLACE FUNCTION oracle.oradate_mi(oracle.date, oracle.date)
RETURNS interval 
AS 	'select  pg_catalog.timestamp_mi($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR pg_catalog.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.oradate_mi
);

-- -    oracle.date - numeric
CREATE OR REPLACE FUNCTION oracle.oradate_mi_numeric(oracle.date, numeric)
RETURNS oracle.date AS $$
	SELECT $1 OPERATOR(oracle.-) interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.oradate_mi_numeric
);

-- -     oracle.date - double precision
CREATE OR REPLACE FUNCTION oracle.oradatedate_mi_float8(oracle.date, double precision)
RETURNS oracle.date AS
	$$SELECT $1 OPERATOR(oracle.-) interval '1 day' * $2$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = double precision,
  PROCEDURE = oracle.oradatedate_mi_float8
);

-- -     oracle.date - real
CREATE OR REPLACE FUNCTION oracle.oradate_mi_float4(oracle.date, real)
RETURNS oracle.date AS
	$$SELECT $1 OPERATOR(oracle.-) interval '1 day' * $2$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = real,
  PROCEDURE = oracle.oradate_mi_float4
);

-- -
CREATE OR REPLACE FUNCTION oracle.oradate_mi_integer(oracle.date, integer)
RETURNS timestamp AS $$
SELECT $1 OPERATOR(oracle.-) interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.date,
  RIGHTARG  = integer,
  PROCEDURE = oracle.oradate_mi_integer
);

-- <     timestamp with time zone + oracle.date
CREATE OR REPLACE FUNCTION oracle.timestamptz_lt_oradate(timestamp with time zone, oracle.date)
RETURNS boolean
AS 'select pg_catalog.timestamptz_lt_timestamp($1, $2::timestamp)'
LANGUAGE SQL STABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.< (
  LEFTARG   = timestamptz,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.timestamptz_lt_oradate
);

-- <      pg_catalog.date < oracle.date
CREATE OR REPLACE FUNCTION oracle.pgdate_lt_oradate(pg_catalog.date, oracle.date)
RETURNS boolean
AS 'select pg_catalog.date_lt_timestamp($1, $2::timestamp)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.< (
  LEFTARG   = pg_catalog.date,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.pgdate_lt_oradate
);

-- <      oracle.date < oracle.date
CREATE OR REPLACE FUNCTION oracle.oradate_lt(oracle.date, oracle.date)
RETURNS boolean
AS 'select pg_catalog.timestamp_lt($1::timestamp, $2::timestamp)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.date,
  RIGHTARG  = oracle.date,
  PROCEDURE = oracle.oradate_lt
);

-- <       oracle.date < pg_catalog.date
CREATE OR REPLACE FUNCTION oracle.oradate_lt_pgdate(oracle.date, pg_catalog.date)
RETURNS boolean
AS 'select pg_catalog.timestamp_lt_date($1::timestamp, $2)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.date,
  RIGHTARG  = pg_catalog.date,
  PROCEDURE = oracle.oradate_lt_pgdate
);

-- <       oracle.date < timestamp with time zone
CREATE OR REPLACE FUNCTION oracle.oradate_lt_timestamptz(oracle.date, timestamp with time zone)
RETURNS boolean
AS 'select pg_catalog.timestamp_lt_timestamptz($1::timestamp, $2)'
LANGUAGE SQL STABLE PARALLEL SAFE STRICT;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.date,
  RIGHTARG  = timestamptz,
  PROCEDURE = oracle.oradate_lt_timestamptz
);

-- operator class
CREATE OPERATOR CLASS oradateops DEFAULT FOR TYPE oracle.date USING hash AS OPERATOR 1 oracle.=;

CREATE FUNCTION oracle.ora_dateoperator(oracle.date,oracle.date) RETURNS int  AS $$
BEGIN 
	IF($1<$2) THEN
		RETURN -1;
	ELSIF($1>$2) THEN
		RETURN 1;
	END IF;
		RETURN 0;
END;
$$
language 'plpgsql' immutable;

CREATE OPERATOR CLASS ora_dateops DEFAULT FOR TYPE oracle.date USING btree AS
OPERATOR 1 oracle.<,
OPERATOR 2 oracle.<=,
OPERATOR 3 oracle.=,
OPERATOR 4 oracle.>=,
OPERATOR 5 oracle.>,
FUNCTION 1 oracle.ora_dateoperator(oracle.date, oracle.date);

CREATE FUNCTION oracle.to_char(oracle.date)
RETURNS TEXT
AS 'select oracle.to_char($1::timestamp)'
LANGUAGE SQL IMMUTABLE;

/* support to_char(oracle.date,text) */
CREATE OR REPLACE FUNCTION oracle.to_char(oracle.date, text)
		RETURNS text
		LANGUAGE internal
		STABLE PARALLEL SAFE STRICT
		AS $function$timestamptz_to_char$function$;

-- oracle.date_trunc
CREATE OR REPLACE FUNCTION oracle.date_trunc(text, oracle.date)
RETURNS oracle.date AS
	'SELECT pg_catalog.date_trunc($1, $2::timestamp)::oracle.date'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION oracle.add_months(TIMESTAMP WITH TIME ZONE,INTEGER)
RETURNS TIMESTAMP
AS $$ SELECT (pg_catalog.add_months($1::pg_catalog.date, $2) + $1::time)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.last_day(TIMESTAMPTZ)
RETURNS TIMESTAMP
AS $$ SELECT (pg_catalog.date_trunc('MONTH', $1) + INTERVAL '1 MONTH' - INTERVAL '1 day' + $1::time)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION oracle.months_between(TIMESTAMP WITH TIME ZONE,TIMESTAMP WITH TIME ZONE)
RETURNS NUMERIC
AS 'MODULE_PATHNAME','months_betweentimestamptz'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.months_between(TIMESTAMP WITH TIME ZONE,TIMESTAMP WITH TIME ZONE) IS 'The months difference between the two timestamp values';

CREATE FUNCTION oracle.next_day(TIMESTAMP WITH TIME ZONE,INTEGER)
RETURNS TIMESTAMP
AS $$ SELECT (pg_catalog.next_day($1::pg_catalog.date,$2) + $1::time)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION oracle.next_day(TIMESTAMP WITH TIME ZONE,TEXT)
RETURNS TIMESTAMP
AS $$ SELECT (pg_catalog.next_day($1::pg_catalog.date,$2) + $1::time)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION oracle.to_date(TEXT)
RETURNS oracle.date
AS $$ SELECT pg_catalog.to_date($1)::oracle.date; $$
LANGUAGE SQL STABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.to_date(TEXT,TEXT)
RETURNS oracle.date
AS $$ SELECT TO_TIMESTAMP($1,$2)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.to_date(bigint, text)
RETURNS oracle.date
AS $$ SELECT pg_catalog.TO_TIMESTAMP($1::text,$2)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.to_date(timestamp, text)
RETURNS oracle.date
AS $$ SELECT pg_catalog.TO_TIMESTAMP($1::text,$2)::oracle.date; $$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION oracle.to_char(timestamp)
RETURNS TEXT
AS 'MODULE_PATHNAME','orafce_to_char_timestamp'
LANGUAGE C STABLE STRICT;
COMMENT ON FUNCTION oracle.to_char(timestamp) IS 'Convert timestamp to string';

CREATE FUNCTION oracle.sysdate()
RETURNS oracle.date
AS 'MODULE_PATHNAME','orafce_sysdate'
LANGUAGE C STABLE STRICT;
COMMENT ON FUNCTION oracle.sysdate() IS 'Ruturns statement timestamp at server time zone';

CREATE FUNCTION oracle.sessiontimezone()
RETURNS text
AS 'MODULE_PATHNAME','orafce_sessiontimezone'
LANGUAGE C STABLE STRICT;
COMMENT ON FUNCTION oracle.sessiontimezone() IS 'Ruturns session time zone';

CREATE FUNCTION oracle.dbtimezone()
RETURNS text
AS 'MODULE_PATHNAME','orafce_sessiontimezone'
LANGUAGE C STABLE STRICT;
COMMENT ON FUNCTION oracle.dbtimezone() IS 'Ruturns server time zone (orafce.timezone)';

-- emulation of dual table
CREATE VIEW public.dual AS SELECT 'X'::varchar AS dummy;
REVOKE ALL ON public.dual FROM PUBLIC;
GRANT SELECT, REFERENCES ON public.dual TO PUBLIC;

-- this packege is emulation of dbms_output Oracle packege
--

CREATE SCHEMA dbms_output;

CREATE FUNCTION dbms_output.enable(IN buffer_size int4)
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_enable'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_output.enable(IN int4) IS 'Enable package functionality';

CREATE FUNCTION dbms_output.enable()
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_enable_default'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.enable() IS 'Enable package functionality';

CREATE FUNCTION dbms_output.disable()
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_disable'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.disable() IS 'Disable package functionality';

CREATE FUNCTION dbms_output.serveroutput(IN bool)
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_serveroutput'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.serveroutput(IN bool) IS 'Set drowing output';

CREATE FUNCTION dbms_output.put(IN a text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_put'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.put(IN text) IS 'Put some text to output';

CREATE FUNCTION dbms_output.put_line(IN a text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_put_line'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.put_line(IN text) IS 'Put line to output';

CREATE FUNCTION dbms_output.new_line()
RETURNS void
AS 'MODULE_PATHNAME','dbms_output_new_line'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.new_line() IS 'Put new line char to output';

CREATE FUNCTION dbms_output.get_line(OUT line text, OUT status int4)
AS 'MODULE_PATHNAME','dbms_output_get_line'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.get_line(OUT text, OUT int4) IS 'Get line from output buffer';


CREATE FUNCTION dbms_output.get_lines(OUT lines text[], INOUT numlines int4)
AS 'MODULE_PATHNAME','dbms_output_get_lines'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_output.get_lines(OUT text[], INOUT int4) IS 'Get lines from output buffer';


-- others functions

CREATE FUNCTION nvl(anyelement, anyelement)
RETURNS anyelement
AS 'MODULE_PATHNAME','ora_nvl'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION nvl2(anyelement, anyelement, anyelement)
RETURNS anyelement
AS 'MODULE_PATHNAME','ora_nvl2'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION nvl2(anyelement, anyelement, anyelement) IS '';

CREATE FUNCTION public.decode(anyelement, anyelement, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, text, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, text, anyelement, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, text, anyelement, text, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, text, anyelement, text, anyelement, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, text, anyelement, text, anyelement, text, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bpchar)
RETURNS bpchar
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bpchar, bpchar)
RETURNS bpchar
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bpchar, anyelement, bpchar)
RETURNS bpchar
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bpchar, anyelement, bpchar, bpchar)
RETURNS bpchar
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bpchar, anyelement, bpchar, anyelement, bpchar)
RETURNS bpchar
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bpchar, anyelement, bpchar, anyelement, bpchar, bpchar)
RETURNS bpchar
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, integer, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, integer, anyelement, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, integer, anyelement, integer, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, integer, anyelement, integer, anyelement, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, integer, anyelement, integer, anyelement, integer, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bigint, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bigint, anyelement, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bigint, anyelement, bigint, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bigint, anyelement, bigint, anyelement, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, bigint, anyelement, bigint, anyelement, bigint, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, numeric)
RETURNS numeric
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, numeric, numeric)
RETURNS numeric
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, numeric, anyelement, numeric)
RETURNS numeric
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, numeric, anyelement, numeric, numeric)
RETURNS numeric
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, numeric, anyelement, numeric, anyelement, numeric)
RETURNS numeric
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, numeric, anyelement, numeric, anyelement, numeric, numeric)
RETURNS numeric
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, date)
RETURNS date
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, date, date)
RETURNS date
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, date, anyelement, date)
RETURNS date
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, date, anyelement, date, date)
RETURNS date
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, date, anyelement, date, anyelement, date)
RETURNS date
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, date, anyelement, date, anyelement, date, date)
RETURNS date
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, time)
RETURNS time
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, time, time)
RETURNS time
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, time, anyelement, time)
RETURNS time
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, time, anyelement, time, time)
RETURNS time
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, time, anyelement, time, anyelement, time)
RETURNS time
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, time, anyelement, time, anyelement, time, time)
RETURNS time
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamp)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamp, timestamp)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamp, anyelement, timestamp)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamp, anyelement, timestamp, timestamp)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamp, anyelement, timestamp, anyelement, timestamp)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamp, anyelement, timestamp, anyelement, timestamp, timestamp)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamptz, timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamptz, anyelement, timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamptz, anyelement, timestamptz, timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamptz, anyelement, timestamptz, anyelement, timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION public.decode(anyelement, anyelement, timestamptz, anyelement, timestamptz, anyelement, timestamptz, timestamptz)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'ora_decode'
LANGUAGE C IMMUTABLE;


CREATE SCHEMA dbms_pipe;

CREATE FUNCTION dbms_pipe.pack_message(text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_text'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(text) IS 'Add text field to message';

CREATE FUNCTION dbms_pipe.unpack_message_text()
RETURNS text
AS 'MODULE_PATHNAME','dbms_pipe_unpack_message_text'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.unpack_message_text() IS 'Get text fiedl from message';

CREATE FUNCTION dbms_pipe.receive_message(text, int)
RETURNS int
AS 'MODULE_PATHNAME','dbms_pipe_receive_message'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.receive_message(text, int) IS 'Receive message from pipe';

CREATE FUNCTION dbms_pipe.receive_message(text)
RETURNS int
AS $$SELECT dbms_pipe.receive_message($1,NULL::int);$$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION dbms_pipe.receive_message(text) IS 'Receive message from pipe';

CREATE FUNCTION dbms_pipe.send_message(text, int, int)
RETURNS int
AS 'MODULE_PATHNAME','dbms_pipe_send_message'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.send_message(text, int, int) IS 'Send message to pipe';

CREATE FUNCTION dbms_pipe.send_message(text, int)
RETURNS int
AS $$SELECT dbms_pipe.send_message($1,$2,NULL);$$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION dbms_pipe.send_message(text, int) IS 'Send message to pipe';

CREATE FUNCTION dbms_pipe.send_message(text)
RETURNS int
AS $$SELECT dbms_pipe.send_message($1,NULL,NULL);$$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION dbms_pipe.send_message(text) IS 'Send message to pipe';

CREATE FUNCTION dbms_pipe.unique_session_name()
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_pipe_unique_session_name'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.unique_session_name() IS 'Returns unique session name';

CREATE FUNCTION dbms_pipe.__list_pipes()
RETURNS SETOF RECORD
AS 'MODULE_PATHNAME','dbms_pipe_list_pipes'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.__list_pipes() IS '';

CREATE VIEW dbms_pipe.db_pipes
AS SELECT * FROM dbms_pipe.__list_pipes() AS (Name varchar, Items int, Size int, "limit" int, "private" bool, "owner" varchar);

CREATE FUNCTION dbms_pipe.next_item_type()
RETURNS int
AS 'MODULE_PATHNAME','dbms_pipe_next_item_type'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.next_item_type() IS 'Returns type of next field in message';

CREATE FUNCTION dbms_pipe.create_pipe(text, int, bool)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_create_pipe'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.create_pipe(text, int, bool) IS 'Create named pipe';

CREATE FUNCTION dbms_pipe.create_pipe(text, int)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_create_pipe_2'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.create_pipe(text, int) IS 'Create named pipe';

CREATE FUNCTION dbms_pipe.create_pipe(text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_create_pipe_1'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.create_pipe(text) IS 'Create named pipe';

CREATE FUNCTION dbms_pipe.reset_buffer()
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_reset_buffer'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_pipe.reset_buffer() IS 'Clean input buffer';

CREATE FUNCTION dbms_pipe.purge(text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_purge'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.purge(text) IS 'Clean pipe';

CREATE FUNCTION dbms_pipe.remove_pipe(text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_remove_pipe'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.remove_pipe(text) IS 'Destroy pipe';

CREATE FUNCTION dbms_pipe.pack_message(date)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_date'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(date) IS 'Add date field to message';

CREATE FUNCTION dbms_pipe.unpack_message_date()
RETURNS date
AS 'MODULE_PATHNAME','dbms_pipe_unpack_message_date'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.unpack_message_date() IS 'Get date field from message';

CREATE FUNCTION dbms_pipe.pack_message(timestamp with time zone)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_timestamp'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(timestamp with time zone) IS 'Add timestamp field to message';

CREATE FUNCTION dbms_pipe.unpack_message_timestamp()
RETURNS timestamp with time zone
AS 'MODULE_PATHNAME','dbms_pipe_unpack_message_timestamp'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.unpack_message_timestamp() IS 'Get timestamp field from message';

CREATE FUNCTION dbms_pipe.pack_message(numeric)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_number'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(numeric) IS 'Add numeric field to message';

CREATE FUNCTION dbms_pipe.unpack_message_number()
RETURNS numeric
AS 'MODULE_PATHNAME','dbms_pipe_unpack_message_number'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.unpack_message_number() IS 'Get numeric field from message';

CREATE FUNCTION dbms_pipe.pack_message(integer)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_integer'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(integer) IS 'Add numeric field to message';

CREATE FUNCTION dbms_pipe.pack_message(bigint)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_bigint'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(bigint) IS 'Add numeric field to message';

CREATE FUNCTION dbms_pipe.pack_message(bytea)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_bytea'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(bytea) IS 'Add bytea field to message';

CREATE FUNCTION dbms_pipe.unpack_message_bytea()
RETURNS bytea
AS 'MODULE_PATHNAME','dbms_pipe_unpack_message_bytea'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.unpack_message_bytea() IS 'Get bytea field from message';

CREATE FUNCTION dbms_pipe.pack_message(record)
RETURNS void
AS 'MODULE_PATHNAME','dbms_pipe_pack_message_record'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.pack_message(record) IS 'Add record field to message';

CREATE FUNCTION dbms_pipe.unpack_message_record()
RETURNS record
AS 'MODULE_PATHNAME','dbms_pipe_unpack_message_record'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_pipe.unpack_message_record() IS 'Get record field from message';



-- follow package PLVdate emulation

CREATE SCHEMA plvdate;

CREATE FUNCTION plvdate.add_bizdays(date, int)
RETURNS date
AS 'MODULE_PATHNAME','plvdate_add_bizdays'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvdate.add_bizdays(date, int) IS 'Get the date created by adding <n> business days to a date';

CREATE FUNCTION plvdate.nearest_bizday(date)
RETURNS date
AS 'MODULE_PATHNAME','plvdate_nearest_bizday'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvdate.nearest_bizday(date) IS 'Get the nearest business date to a given date, user defined';

CREATE FUNCTION plvdate.next_bizday(date)
RETURNS date
AS 'MODULE_PATHNAME','plvdate_next_bizday'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvdate.next_bizday(date) IS 'Get the next business date from a given date, user defined';

CREATE FUNCTION plvdate.bizdays_between(date, date)
RETURNS int
AS 'MODULE_PATHNAME','plvdate_bizdays_between'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvdate.bizdays_between(date, date) IS 'Get the number of business days between two dates';

CREATE FUNCTION plvdate.prev_bizday(date)
RETURNS date
AS 'MODULE_PATHNAME','plvdate_prev_bizday'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvdate.prev_bizday(date) IS 'Get the previous business date from a given date';

CREATE FUNCTION plvdate.isbizday(date)
RETURNS bool
AS 'MODULE_PATHNAME','plvdate_isbizday'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvdate.isbizday(date) IS 'Call this function to determine if a date is a business day';

CREATE FUNCTION plvdate.set_nonbizday(text)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_set_nonbizday_dow'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.set_nonbizday(text) IS 'Set day of week as non bussines day';

CREATE FUNCTION plvdate.unset_nonbizday(text)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_unset_nonbizday_dow'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.unset_nonbizday(text) IS 'Unset day of week as non bussines day';

CREATE FUNCTION plvdate.set_nonbizday(date, bool)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_set_nonbizday_day'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.set_nonbizday(date, bool) IS 'Set day as non bussines day, if repeat is true, then day is nonbiz every year';

CREATE FUNCTION plvdate.unset_nonbizday(date, bool)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_unset_nonbizday_day'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.unset_nonbizday(date, bool) IS 'Unset day as non bussines day, if repeat is true, then day is nonbiz every year';

CREATE FUNCTION plvdate.set_nonbizday(date)
RETURNS bool
AS $$SELECT plvdate.set_nonbizday($1, false); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.set_nonbizday(date) IS 'Set day as non bussines day';

CREATE FUNCTION plvdate.unset_nonbizday(date)
RETURNS bool
AS $$SELECT plvdate.unset_nonbizday($1, false); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.unset_nonbizday(date) IS 'Unset day as non bussines day';

CREATE FUNCTION plvdate.use_easter(bool)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_use_easter'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.use_easter(bool) IS 'Easter Sunday and easter monday will be holiday';

CREATE FUNCTION plvdate.use_easter()
RETURNS bool
AS $$SELECT plvdate.use_easter(true); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.use_easter() IS 'Easter Sunday and easter monday will be holiday';

CREATE FUNCTION plvdate.unuse_easter()
RETURNS bool
AS $$SELECT plvdate.use_easter(false); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.unuse_easter() IS 'Easter Sunday and easter monday will not be holiday';

CREATE FUNCTION plvdate.using_easter()
RETURNS bool
AS 'MODULE_PATHNAME','plvdate_using_easter'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.using_easter() IS 'Use easter?';

CREATE FUNCTION plvdate.use_great_friday(bool)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_use_great_friday'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.use_great_friday(bool) IS 'Great Friday will be holiday';

CREATE FUNCTION plvdate.use_great_friday()
RETURNS bool
AS $$SELECT plvdate.use_great_friday(true); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.use_great_friday() IS 'Great Friday will be holiday';

CREATE FUNCTION plvdate.unuse_great_friday()
RETURNS bool
AS $$SELECT plvdate.use_great_friday(false); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.unuse_great_friday() IS 'Great Friday will not be holiday';

CREATE FUNCTION plvdate.using_great_friday()
RETURNS bool
AS 'MODULE_PATHNAME','plvdate_using_great_friday'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.using_great_friday() IS 'Use Great Friday?';

CREATE FUNCTION plvdate.include_start(bool)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_include_start'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.include_start(bool) IS 'Include starting date in bizdays_between calculation';

CREATE FUNCTION plvdate.include_start()
RETURNS bool
AS $$SELECT plvdate.include_start(true); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.include_start() IS '';

CREATE FUNCTION plvdate.noinclude_start()
RETURNS bool
AS $$SELECT plvdate.include_start(false); SELECT NULL::boolean;$$
LANGUAGE SQL VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.noinclude_start() IS '';

CREATE FUNCTION plvdate.including_start()
RETURNS bool
AS 'MODULE_PATHNAME','plvdate_including_start'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.including_start() IS '';

CREATE FUNCTION plvdate.version()
RETURNS cstring
AS 'MODULE_PATHNAME','plvdate_version'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.version() IS '';

CREATE FUNCTION plvdate.default_holidays(text)
RETURNS void
AS 'MODULE_PATHNAME','plvdate_default_holidays'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.default_holidays(text) IS 'Load calendar for some nations';

CREATE FUNCTION plvdate.days_inmonth(date)
RETURNS integer
AS 'MODULE_PATHNAME','plvdate_days_inmonth'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.days_inmonth(date) IS 'Returns number of days in month';

CREATE FUNCTION plvdate.isleapyear(date)
RETURNS bool
AS 'MODULE_PATHNAME','plvdate_isleapyear'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION plvdate.isleapyear(date) IS 'Is leap year';


-- PLVstr package


CREATE FUNCTION plvstr.normalize(str text)
RETURNS varchar
AS 'MODULE_PATHNAME','plvstr_normalize'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.normalize(text) IS 'Replace white chars by space, replace  spaces by space';

CREATE FUNCTION plvstr.is_prefix(str text, prefix text, cs bool)
RETURNS bool
AS 'MODULE_PATHNAME','plvstr_is_prefix_text'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.is_prefix(text, text, bool) IS 'Returns true, if prefix is prefix of str';

CREATE FUNCTION plvstr.is_prefix(str text, prefix text)
RETURNS bool
AS $$ SELECT plvstr.is_prefix($1,$2,true);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.is_prefix(text, text) IS 'Returns true, if prefix is prefix of str';

CREATE FUNCTION plvstr.is_prefix(str int, prefix int)
RETURNS bool
AS 'MODULE_PATHNAME','plvstr_is_prefix_int'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.is_prefix(int, int) IS 'Returns true, if prefix is prefix of str';

CREATE FUNCTION plvstr.is_prefix(str bigint, prefix bigint)
RETURNS bool
AS 'MODULE_PATHNAME','plvstr_is_prefix_int64'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.is_prefix(bigint, bigint) IS 'Returns true, if prefix is prefix of str';

CREATE FUNCTION plvstr.substr(str text, start int, len int)
RETURNS varchar
AS 'MODULE_PATHNAME','plvstr_substr3'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.substr(text, int, int) IS 'Returns substring started on start_in to end';

CREATE FUNCTION plvstr.substr(str text, start int)
RETURNS varchar
AS 'MODULE_PATHNAME','plvstr_substr2'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.substr(text, int) IS 'Returns substring started on start_in to end';

CREATE FUNCTION plvstr.instr(str text, patt text, start int, nth int)
RETURNS int
AS 'MODULE_PATHNAME','plvstr_instr4'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.instr(text, text, int, int) IS 'Search pattern in string';

CREATE FUNCTION plvstr.instr(str text, patt text, start int)
RETURNS int
AS 'MODULE_PATHNAME','plvstr_instr3'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.instr(text, text, int) IS 'Search pattern in string';

CREATE FUNCTION plvstr.instr(str text, patt text)
RETURNS int
AS 'MODULE_PATHNAME','plvstr_instr2'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.instr(text, text) IS 'Search pattern in string';

CREATE FUNCTION plvstr.lpart(str text, div text, start int, nth int, all_if_notfound bool)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_lpart'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.lpart(text, text, int, int, bool) IS 'Call this function to return the left part of a string';

CREATE FUNCTION plvstr.lpart(str text, div text, start int, nth int)
RETURNS text
AS $$ SELECT plvstr.lpart($1,$2, $3, $4, false); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.lpart(text, text, int, int) IS 'Call this function to return the left part of a string';

CREATE FUNCTION plvstr.lpart(str text, div text, start int)
RETURNS text
AS $$ SELECT plvstr.lpart($1,$2, $3, 1, false); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.lpart(text, text, int) IS 'Call this function to return the left part of a string';

CREATE FUNCTION plvstr.lpart(str text, div text)
RETURNS text
AS $$ SELECT plvstr.lpart($1,$2, 1, 1, false); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.lpart(text, text) IS 'Call this function to return the left part of a string';

CREATE FUNCTION plvstr.rpart(str text, div text, start int, nth int, all_if_notfound bool)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_rpart'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rpart(text, text, int, int, bool) IS 'Call this function to return the right part of a string';

CREATE FUNCTION plvstr.rpart(str text, div text, start int, nth int)
RETURNS text
AS $$ SELECT plvstr.rpart($1,$2, $3, $4, false); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rpart(text, text, int, int) IS 'Call this function to return the right part of a string';

CREATE FUNCTION plvstr.rpart(str text, div text, start int)
RETURNS text
AS $$ SELECT plvstr.rpart($1,$2, $3, 1, false); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rpart(text, text, int) IS 'Call this function to return the right part of a string';

CREATE FUNCTION plvstr.rpart(str text, div text)
RETURNS text
AS $$ SELECT plvstr.rpart($1,$2, 1, 1, false); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rpart(text, text) IS 'Call this function to return the right part of a string';

CREATE FUNCTION plvstr.lstrip(str text, substr text, num int)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_lstrip'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.lstrip(text, text, int) IS 'Call this function to remove characters from the beginning ';

CREATE FUNCTION plvstr.lstrip(str text, substr text)
RETURNS text
AS $$ SELECT plvstr.lstrip($1, $2, 1); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.lstrip(text, text) IS 'Call this function to remove characters from the beginning ';

CREATE FUNCTION plvstr.rstrip(str text, substr text, num int)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_rstrip'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rstrip(text, text, int) IS 'Call this function to remove characters from the end';

CREATE FUNCTION plvstr.rstrip(str text, substr text)
RETURNS text
AS $$ SELECT plvstr.rstrip($1, $2, 1); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.rstrip(text, text) IS 'Call this function to remove characters from the end';



CREATE FUNCTION plvstr.swap(str text, replace text, start int, length int)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_swap'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvstr.swap(text,text, int, int) IS 'Replace a substring in a string with a specified string';

CREATE FUNCTION plvstr.swap(str text, replace text)
RETURNS text
AS $$ SELECT plvstr.swap($1,$2,1, NULL);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.swap(text,text) IS 'Replace a substring in a string with a specified string';

CREATE FUNCTION plvstr.betwn(str text, start int, _end int, inclusive bool)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_betwn_i'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.betwn(text, int, int, bool) IS 'Find the Substring Between Start and End Locations';

CREATE FUNCTION plvstr.betwn(str text, start int, _end int)
RETURNS text
AS $$ SELECT plvstr.betwn($1,$2,$3,true);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.betwn(text, int, int) IS 'Find the Substring Between Start and End Locations';

CREATE FUNCTION plvstr.betwn(str text, start text, _end text, startnth int, endnth int, inclusive bool, gotoend bool)
RETURNS text
AS 'MODULE_PATHNAME','plvstr_betwn_c'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvstr.betwn(text, text, text, int, int, bool, bool) IS 'Find the Substring Between Start and End Locations';

CREATE FUNCTION plvstr.betwn(str text, start text, _end text)
RETURNS text
AS $$ SELECT plvstr.betwn($1,$2,$3,1,1,true,false);$$
LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION plvstr.betwn(text, text, text) IS 'Find the Substring Between Start and End Locations';

CREATE FUNCTION plvstr.betwn(str text, start text, _end text, startnth int, endnth int)
RETURNS text
AS $$ SELECT plvstr.betwn($1,$2,$3,$4,$5,true,false);$$
LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION plvstr.betwn(text, text, text, int, int) IS 'Find the Substring Between Start and End Locations';

CREATE SCHEMA plvchr;

CREATE FUNCTION plvchr.nth(str text, n int)
RETURNS text
AS 'MODULE_PATHNAME','plvchr_nth'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.nth(text, int) IS 'Call this function to return the Nth character in a string';

CREATE FUNCTION plvchr.first(str text)
RETURNS varchar
AS 'MODULE_PATHNAME','plvchr_first'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.first(text) IS 'Call this function to return the first character in a string';

CREATE FUNCTION plvchr.last(str text)
RETURNS varchar
AS 'MODULE_PATHNAME','plvchr_last'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.last(text) IS 'Call this function to return the last character in a string';

CREATE FUNCTION plvchr._is_kind(str text, kind int)
RETURNS bool
AS 'MODULE_PATHNAME','plvchr_is_kind_a'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr._is_kind(text, int) IS '';

CREATE FUNCTION plvchr._is_kind(c int, kind int)
RETURNS bool
AS 'MODULE_PATHNAME','plvchr_is_kind_i'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr._is_kind(int, int) IS '';

CREATE FUNCTION plvchr.is_blank(c int)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 1);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_blank(int) IS '';

CREATE FUNCTION plvchr.is_blank(c text)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 1);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_blank(text) IS '';

CREATE FUNCTION plvchr.is_digit(c int)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 2);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_digit(int) IS '';

CREATE FUNCTION plvchr.is_digit(c text)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 2);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_digit(text) IS '';

CREATE FUNCTION plvchr.is_quote(c int)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 3);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_quote(int) IS '';

CREATE FUNCTION plvchr.is_quote(c text)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 3);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_quote(text) IS '';

CREATE FUNCTION plvchr.is_other(c int)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 4);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_other(int) IS '';

CREATE FUNCTION plvchr.is_other(c text)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 4);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_other(text) IS '';

CREATE FUNCTION plvchr.is_letter(c int)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 5);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_letter(int) IS '';

CREATE FUNCTION plvchr.is_letter(c text)
RETURNS BOOL
AS $$ SELECT plvchr._is_kind($1, 5);$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.is_letter(text) IS '';

CREATE FUNCTION plvchr.char_name(c text)
RETURNS varchar
AS 'MODULE_PATHNAME','plvchr_char_name'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.char_name(text) IS '';

CREATE FUNCTION plvstr.left(str text, n int)
RETURNS varchar
AS 'MODULE_PATHNAME', 'plvstr_left'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.left(text, int) IS 'Returns firs num_in charaters. You can use negative num_in';

CREATE FUNCTION plvstr.right(str text, n int)
RETURNS varchar
AS 'MODULE_PATHNAME','plvstr_right'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvstr.right(text, int) IS 'Returns last num_in charaters. You can use negative num_ni';

CREATE FUNCTION plvchr.quoted1(str text)
RETURNS varchar
AS $$SELECT ''''||$1||'''';$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.quoted1(text) IS E'Quoted text between ''';

CREATE FUNCTION plvchr.quoted2(str text)
RETURNS varchar
AS $$SELECT '"'||$1||'"';$$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.quoted2(text) IS 'Quoted text between "';

CREATE FUNCTION plvchr.stripped(str text, char_in text)
RETURNS varchar
AS $$ SELECT TRANSLATE($1, 'A'||$2, 'A'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION plvchr.stripped(text, text) IS 'Strips a string of all instances of the specified characters';

-- dbms_alert

CREATE SCHEMA dbms_alert;

CREATE FUNCTION dbms_alert.register(name text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_alert_register'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_alert.register(text) IS 'Register session as recipient of alert name';

CREATE FUNCTION dbms_alert.remove(name text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_alert_remove'
LANGUAGE C VOLATILE STRICT;
COMMENT ON FUNCTION dbms_alert.remove(text) IS 'Remove session as recipient of alert name';

CREATE FUNCTION dbms_alert.removeall()
RETURNS void
AS 'MODULE_PATHNAME','dbms_alert_removeall'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_alert.removeall() IS 'Remove registration for all alerts';

CREATE FUNCTION dbms_alert._signal(name text, message text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_alert_signal'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_alert._signal(text, text) IS '';

CREATE FUNCTION dbms_alert.waitany(OUT name text, OUT message text, OUT status integer, timeout float8)
RETURNS record
AS 'MODULE_PATHNAME','dbms_alert_waitany'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_alert.waitany(OUT text, OUT text, OUT integer, float8) IS 'Wait for any signal';

CREATE FUNCTION dbms_alert.waitone(name text, OUT message text, OUT status integer, timeout float8)
RETURNS record
AS 'MODULE_PATHNAME','dbms_alert_waitone'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_alert.waitone(text, OUT text, OUT integer, float8) IS 'Wait for specific signal';

CREATE FUNCTION dbms_alert.set_defaults(sensitivity float8)
RETURNS void
AS 'MODULE_PATHNAME','dbms_alert_set_defaults'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_alert.set_defaults(float8) IS '';

CREATE FUNCTION dbms_alert.defered_signal()
RETURNS trigger
AS 'MODULE_PATHNAME','dbms_alert_defered_signal'
LANGUAGE C SECURITY DEFINER;
REVOKE ALL ON FUNCTION dbms_alert.defered_signal() FROM PUBLIC;

CREATE FUNCTION dbms_alert.signal(_event text, _message text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_alert_signal'
LANGUAGE C SECURITY DEFINER;
COMMENT ON FUNCTION dbms_alert.signal(text, text) IS 'Emit signal to all recipients';

CREATE SCHEMA plvsubst;

CREATE FUNCTION plvsubst.string(template_in text, values_in text[], subst text)
RETURNS text
AS 'MODULE_PATHNAME','plvsubst_string_array'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvsubst.string(text, text[], text) IS 'Scans a string for all instances of the substitution keyword and replace it with the next value in the substitution values list';

CREATE FUNCTION plvsubst.string(template_in text, values_in text[])
RETURNS text
AS $$SELECT plvsubst.string($1,$2, NULL);$$
LANGUAGE SQL STRICT VOLATILE;
COMMENT ON FUNCTION plvsubst.string(text, text[]) IS 'Scans a string for all instances of the substitution keyword and replace it with the next value in the substitution values list';

CREATE FUNCTION plvsubst.string(template_in text, vals_in text, delim_in text, subst_in text)
RETURNS text
AS 'MODULE_PATHNAME','plvsubst_string_string'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvsubst.string(text, text, text, text) IS 'Scans a string for all instances of the substitution keyword and replace it with the next value in the substitution values list';

CREATE FUNCTION plvsubst.string(template_in text, vals_in text)
RETURNS text
AS 'MODULE_PATHNAME','plvsubst_string_string'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvsubst.string(text, text) IS 'Scans a string for all instances of the substitution keyword and replace it with the next value in the substitution values list';

CREATE FUNCTION plvsubst.string(template_in text, vals_in text, delim_in text)
RETURNS text
AS 'MODULE_PATHNAME','plvsubst_string_string'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plvsubst.string(text, text, text) IS 'Scans a string for all instances of the substitution keyword and replace it with the next value in the substitution values list';

CREATE FUNCTION plvsubst.setsubst(str text)
RETURNS void
AS 'MODULE_PATHNAME','plvsubst_setsubst'
LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION plvsubst.setsubst(text) IS 'Change the substitution keyword';

CREATE FUNCTION plvsubst.setsubst()
RETURNS void
AS 'MODULE_PATHNAME','plvsubst_setsubst_default'
LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION plvsubst.setsubst() IS 'Change the substitution keyword to default %s';

CREATE FUNCTION plvsubst.subst()
RETURNS text
AS 'MODULE_PATHNAME','plvsubst_subst'
LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION plvsubst.subst() IS 'Retrieve the current substitution keyword';

CREATE SCHEMA dbms_utility;

CREATE FUNCTION dbms_utility.format_call_stack(text)
RETURNS text
AS 'MODULE_PATHNAME','dbms_utility_format_call_stack1'
LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION dbms_utility.format_call_stack(text) IS 'Return formated call stack';

CREATE FUNCTION dbms_utility.format_call_stack()
RETURNS text
AS 'MODULE_PATHNAME','dbms_utility_format_call_stack0'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_utility.format_call_stack() IS 'Return formated call stack';

CREATE FUNCTION dbms_utility.get_time()
RETURNS int
AS 'MODULE_PATHNAME','dbms_utility_get_time'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_utility.get_time() IS 'Returns the number of hundredths of seconds that have elapsed since point in time';

CREATE SCHEMA plvlex;

CREATE FUNCTION plvlex.tokens(IN str text, IN skip_spaces bool, IN qualified_names bool,
OUT pos int, OUT token text, OUT code int, OUT class text, OUT separator text, OUT mod text)
RETURNS SETOF RECORD
AS 'MODULE_PATHNAME','plvlex_tokens'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION plvlex.tokens(text,bool,bool) IS 'Parse SQL string';

CREATE SCHEMA utl_file;
CREATE DOMAIN utl_file.file_type integer;

CREATE FUNCTION utl_file.fopen(location text, filename text, open_mode text, max_linesize integer, encoding name)
RETURNS utl_file.file_type
AS 'MODULE_PATHNAME','utl_file_fopen'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fopen(text,text,text,integer,name) IS 'The FOPEN function open file and return file handle';

CREATE FUNCTION utl_file.fopen(location text, filename text, open_mode text, max_linesize integer)
RETURNS utl_file.file_type
AS 'MODULE_PATHNAME','utl_file_fopen'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fopen(text,text,text,integer) IS 'The FOPEN function open file and return file handle';

CREATE FUNCTION utl_file.fopen(location text, filename text, open_mode text)
RETURNS utl_file.file_type
AS $$SELECT utl_file.fopen($1, $2, $3, 1024); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.fopen(text,text,text,integer) IS 'The FOPEN function open file and return file handle';

CREATE FUNCTION utl_file.is_open(file utl_file.file_type)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_is_open'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.is_open(utl_file.file_type) IS 'Functions returns true if handle points to file that is open';

CREATE FUNCTION utl_file.get_line(file utl_file.file_type, OUT buffer text)
AS 'MODULE_PATHNAME','utl_file_get_line'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.get_line(utl_file.file_type) IS 'Returns one line from file';

CREATE FUNCTION utl_file.get_line(file utl_file.file_type, OUT buffer text, len integer)
AS 'MODULE_PATHNAME','utl_file_get_line'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.get_line(utl_file.file_type, len integer) IS 'Returns one line from file';

CREATE FUNCTION utl_file.get_nextline(file utl_file.file_type, OUT buffer text)
AS 'MODULE_PATHNAME','utl_file_get_nextline'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.get_nextline(utl_file.file_type) IS 'Returns one line from file or returns NULL';

CREATE FUNCTION utl_file.put(file utl_file.file_type, buffer text)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_put'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.put(utl_file.file_type, text) IS 'Puts data to specified file';

CREATE FUNCTION utl_file.put(file utl_file.file_type, buffer anyelement)
RETURNS bool
AS $$SELECT utl_file.put($1, $2::text); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.put(utl_file.file_type, anyelement) IS 'Puts data to specified file';

CREATE FUNCTION utl_file.new_line(file utl_file.file_type)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_new_line'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.new_line(file utl_file.file_type) IS 'Function inserts one ore more newline characters in specified file';

CREATE FUNCTION utl_file.new_line(file utl_file.file_type, lines int)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_new_line'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.new_line(file utl_file.file_type) IS 'Function inserts one ore more newline characters in specified file';

CREATE FUNCTION utl_file.put_line(file utl_file.file_type, buffer text)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_put_line'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.put_line(utl_file.file_type, text) IS 'Puts data to specified file and append newline character';

CREATE FUNCTION utl_file.put_line(file utl_file.file_type, buffer text, autoflush bool)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_put_line'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.put_line(utl_file.file_type, text, bool) IS 'Puts data to specified file and append newline character';

CREATE FUNCTION utl_file.putf(file utl_file.file_type, format text, arg1 text, arg2 text, arg3 text, arg4 text, arg5 text)
RETURNS bool
AS 'MODULE_PATHNAME','utl_file_putf'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.putf(utl_file.file_type, text, text, text, text, text, text) IS 'Puts formatted data to specified file';

CREATE FUNCTION utl_file.putf(file utl_file.file_type, format text, arg1 text, arg2 text, arg3 text, arg4 text)
RETURNS bool
AS $$SELECT utl_file.putf($1, $2, $3, $4, $5, $6, NULL); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.putf(utl_file.file_type, text, text, text, text, text) IS 'Puts formatted data to specified file';

CREATE FUNCTION utl_file.putf(file utl_file.file_type, format text, arg1 text, arg2 text, arg3 text)
RETURNS bool
AS $$SELECT utl_file.putf($1, $2, $3, $4, $5, NULL, NULL); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.putf(utl_file.file_type, text, text, text, text) IS 'Puts formatted data to specified file';

CREATE FUNCTION utl_file.putf(file utl_file.file_type, format text, arg1 text, arg2 text)
RETURNS bool
AS $$SELECT utl_file.putf($1, $2, $3, $4, NULL, NULL, NULL); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.putf(utl_file.file_type, text, text, text, text) IS 'Puts formatted data to specified file';

CREATE FUNCTION utl_file.putf(file utl_file.file_type, format text, arg1 text)
RETURNS bool
AS $$SELECT utl_file.putf($1, $2, $3, NULL, NULL, NULL, NULL); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.putf(utl_file.file_type, text, text) IS 'Puts formatted data to specified file';

CREATE FUNCTION utl_file.putf(file utl_file.file_type, format text)
RETURNS bool
AS $$SELECT utl_file.putf($1, $2, NULL, NULL, NULL, NULL, NULL); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.putf(utl_file.file_type, text) IS 'Puts formatted data to specified file';

CREATE FUNCTION utl_file.fflush(file utl_file.file_type)
RETURNS void
AS 'MODULE_PATHNAME','utl_file_fflush'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fflush(file utl_file.file_type) IS 'This procedure makes sure that all pending data for specified file is written physically out to a file';

CREATE FUNCTION utl_file.fclose(file utl_file.file_type)
RETURNS utl_file.file_type
AS 'MODULE_PATHNAME','utl_file_fclose'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fclose(utl_file.file_type) IS 'Close file';

CREATE FUNCTION utl_file.fclose_all()
RETURNS void
AS 'MODULE_PATHNAME','utl_file_fclose_all'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fclose_all() IS 'Close all open files.';

CREATE FUNCTION utl_file.fremove(location text, filename text)
RETURNS void
AS 'MODULE_PATHNAME','utl_file_fremove'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fremove(text, text) IS 'Remove file.';

CREATE FUNCTION utl_file.frename(location text, filename text, dest_dir text, dest_file text, overwrite boolean)
RETURNS void
AS 'MODULE_PATHNAME','utl_file_frename'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.frename(text, text, text, text, boolean) IS 'Rename file.';

CREATE FUNCTION utl_file.frename(location text, filename text, dest_dir text, dest_file text)
RETURNS void
AS $$SELECT utl_file.frename($1, $2, $3, $4, false);$$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.frename(text, text, text, text) IS 'Rename file.';

CREATE FUNCTION utl_file.fcopy(src_location text, src_filename text, dest_location text, dest_filename text)
RETURNS void
AS 'MODULE_PATHNAME','utl_file_fcopy'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fcopy(text, text, text, text) IS 'Copy a text file.';

CREATE FUNCTION utl_file.fcopy(src_location text, src_filename text, dest_location text, dest_filename text, start_line integer)
RETURNS void
AS 'MODULE_PATHNAME','utl_file_fcopy'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fcopy(text, text, text, text, integer) IS 'Copy a text file.';

CREATE FUNCTION utl_file.fcopy(src_location text, src_filename text, dest_location text, dest_filename text, start_line integer, end_line integer)
RETURNS void
AS 'MODULE_PATHNAME','utl_file_fcopy'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fcopy(text, text, text, text, integer, integer) IS 'Copy a text file.';

CREATE FUNCTION utl_file.fgetattr(location text, filename text, OUT fexists boolean, OUT file_length bigint, OUT blocksize integer)
AS 'MODULE_PATHNAME','utl_file_fgetattr'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.fgetattr(text, text) IS 'Get file attributes.';

CREATE FUNCTION utl_file.tmpdir()
RETURNS text
AS 'MODULE_PATHNAME','utl_file_tmpdir'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION utl_file.tmpdir() IS 'Get temp directory path.';

/* carry all safe directories */
CREATE TABLE utl_file.utl_file_dir(dir text, dirname text unique);
REVOKE ALL ON utl_file.utl_file_dir FROM PUBLIC;

/* allow only read on utl_file.utl_file_dir to unprivileged users */
GRANT SELECT ON TABLE utl_file.utl_file_dir TO PUBLIC;

-- dbms_assert

CREATE SCHEMA dbms_assert;

CREATE FUNCTION dbms_assert.enquote_literal(str varchar)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_enquote_literal'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_assert.enquote_literal(varchar) IS 'Add leading and trailing quotes, verify that all single quotes are paired with adjacent single quotes';

CREATE FUNCTION dbms_assert.enquote_name(str varchar, loweralize boolean)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_enquote_name'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_assert.enquote_name(varchar, boolean) IS 'Enclose name in double quotes';

CREATE FUNCTION dbms_assert.enquote_name(str varchar)
RETURNS varchar
AS 'SELECT dbms_assert.enquote_name($1, true)'
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_assert.enquote_name(varchar) IS 'Enclose name in double quotes';

CREATE FUNCTION dbms_assert.noop(str varchar)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_noop'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_assert.noop(varchar) IS 'Returns value without any checking.';

CREATE FUNCTION dbms_assert.schema_name(str varchar)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_schema_name'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION dbms_assert.schema_name(varchar) IS 'Verify input string is an existing schema name.';

CREATE FUNCTION dbms_assert.object_name(str varchar)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_object_name'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION dbms_assert.object_name(varchar) IS 'Verify input string is an existing object name.';

CREATE FUNCTION dbms_assert.simple_sql_name(str varchar)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_simple_sql_name'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION dbms_assert.object_name(varchar) IS 'Verify input string is an sql name.';

CREATE FUNCTION dbms_assert.qualified_sql_name(str varchar)
RETURNS varchar
AS 'MODULE_PATHNAME','dbms_assert_qualified_sql_name'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION dbms_assert.object_name(varchar) IS 'Verify input string is an qualified sql name.';

CREATE SCHEMA plunit;

CREATE FUNCTION plunit.assert_true(condition boolean)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_true'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_true(condition boolean) IS 'Asserts that the condition is true';

CREATE FUNCTION plunit.assert_true(condition boolean, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_true_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_true(condition boolean, message varchar) IS 'Asserts that the condition is true';

CREATE FUNCTION plunit.assert_false(condition boolean)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_false'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_false(condition boolean) IS 'Asserts that the condition is false';

CREATE FUNCTION plunit.assert_false(condition boolean, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_false_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_false(condition boolean, message varchar) IS 'Asserts that the condition is false';

CREATE FUNCTION plunit.assert_null(actual anyelement)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_null'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_null(actual anyelement) IS 'Asserts that the actual is null';

CREATE FUNCTION plunit.assert_null(actual anyelement, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_null_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_null(actual anyelement, message varchar) IS 'Asserts that the condition is null';

CREATE FUNCTION plunit.assert_not_null(actual anyelement)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_not_null'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_not_null(actual anyelement) IS 'Asserts that the actual is not null';

CREATE FUNCTION plunit.assert_not_null(actual anyelement, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_not_null_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_not_null(actual anyelement, message varchar) IS 'Asserts that the condition is not null';

CREATE FUNCTION plunit.assert_equals(expected anyelement, actual anyelement)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_equals'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_equals(expected anyelement, actual anyelement) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_equals(expected anyelement, actual anyelement, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_equals_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_equals(expected anyelement, actual anyelement, message varchar) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_equals(expected double precision, actual double precision, "range" double precision)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_equals_range'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_equals(expected double precision, actual double precision, "range" double precision) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_equals(expected double precision, actual double precision, "range" double precision, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_equals_range_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_equals(expected double precision, actual double precision, "range" double precision, message varchar) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_not_equals(expected anyelement, actual anyelement)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_not_equals'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_not_equals(expected anyelement, actual anyelement) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_not_equals(expected anyelement, actual anyelement, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_not_equals_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_not_equals(expected anyelement, actual anyelement, message varchar) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_not_equals(expected double precision, actual double precision, "range" double precision)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_not_equals_range'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_equals(expected double precision, actual double precision, "range" double precision) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.assert_not_equals(expected double precision, actual double precision, "range" double precision, message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_assert_not_equals_range_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.assert_not_equals(expected double precision, actual double precision, "range" double precision, message varchar) IS 'Asserts that expected and actual are equal';

CREATE FUNCTION plunit.fail()
RETURNS void
AS 'MODULE_PATHNAME','plunit_fail'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.fail() IS 'Immediately fail.';

CREATE FUNCTION plunit.fail(message varchar)
RETURNS void
AS 'MODULE_PATHNAME','plunit_fail_message'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION plunit.fail(message varchar) IS 'Immediately fail.';

-- dbms_random
CREATE SCHEMA dbms_random;

CREATE FUNCTION dbms_random.initialize(int)
RETURNS void
AS 'MODULE_PATHNAME','dbms_random_initialize'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_random.initialize(int) IS 'Initialize package with a seed value';

CREATE FUNCTION dbms_random.normal()
RETURNS double precision
AS 'MODULE_PATHNAME','dbms_random_normal'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_random.normal() IS 'Returns random numbers in a standard normal distribution';

CREATE FUNCTION dbms_random.random()
RETURNS integer
AS 'MODULE_PATHNAME','dbms_random_random'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_random.random() IS 'Generate Random Numeric Values';

CREATE FUNCTION dbms_random.seed(integer)
RETURNS void
AS 'MODULE_PATHNAME','dbms_random_seed_int'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_random.seed(int) IS 'Reset the seed value';

CREATE FUNCTION dbms_random.seed(text)
RETURNS void
AS 'MODULE_PATHNAME','dbms_random_seed_varchar'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION dbms_random.seed(text) IS 'Reset the seed value';

CREATE FUNCTION dbms_random.string(opt text, len int)
RETURNS text
AS 'MODULE_PATHNAME','dbms_random_string'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION dbms_random.string(text,int) IS 'Create Random Strings';

CREATE FUNCTION dbms_random.terminate()
RETURNS void
AS 'MODULE_PATHNAME','dbms_random_terminate'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION dbms_random.terminate() IS 'Terminate use of the Package';

CREATE FUNCTION dbms_random.value(low double precision, high double precision)
RETURNS double precision
AS 'MODULE_PATHNAME','dbms_random_value_range'
LANGUAGE C STRICT VOLATILE;
COMMENT ON FUNCTION dbms_random.value(double precision, double precision) IS 'Generate Random number x, where x is greater or equal to low and less then high';

CREATE FUNCTION dbms_random.value()
RETURNS double precision
AS 'MODULE_PATHNAME','dbms_random_value'
LANGUAGE C VOLATILE;
COMMENT ON FUNCTION dbms_random.value() IS 'Generate Random number x, where x is greater or equal to 0 and less then 1';

CREATE FUNCTION dump(text)
RETURNS varchar
AS 'MODULE_PATHNAME', 'orafce_dump'
LANGUAGE C;

CREATE FUNCTION dump(text, integer)
RETURNS varchar
AS 'MODULE_PATHNAME', 'orafce_dump'
LANGUAGE C;

CREATE FUNCTION utl_file.put_line(file utl_file.file_type, buffer anyelement)
RETURNS bool
AS $$SELECT utl_file.put_line($1, $2::text); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.put_line(utl_file.file_type, anyelement) IS 'Puts data to specified file and append newline character';

CREATE FUNCTION utl_file.put_line(file utl_file.file_type, buffer anyelement, autoflush bool)
RETURNS bool
AS $$SELECT utl_file.put_line($1, $2::text, true); $$
LANGUAGE SQL VOLATILE;
COMMENT ON FUNCTION utl_file.put_line(utl_file.file_type, anyelement, bool) IS 'Puts data to specified file and append newline character';

CREATE FUNCTION pg_catalog.listagg1_transfn(internal, text)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_listagg1_transfn'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION pg_catalog.wm_concat_transfn(internal, text)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_wm_concat_transfn'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION pg_catalog.listagg2_transfn(internal, text, text)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_listagg2_transfn'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION pg_catalog.listagg_finalfn(internal)
RETURNS text
AS 'MODULE_PATHNAME','orafce_listagg_finalfn'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE pg_catalog.listagg(text) (
  SFUNC=pg_catalog.listagg1_transfn,
  STYPE=internal,
  FINALFUNC=pg_catalog.listagg_finalfn
);

/*
 * Undocumented function wm_concat - removed from
 * Oracle 12c.
 */
CREATE AGGREGATE pg_catalog.wm_concat(text) (
  SFUNC=pg_catalog.wm_concat_transfn,
  STYPE=internal,
  FINALFUNC=pg_catalog.listagg_finalfn
);

CREATE AGGREGATE pg_catalog.listagg(text, text) (
  SFUNC=pg_catalog.listagg2_transfn,
  STYPE=internal,
  FINALFUNC=pg_catalog.listagg_finalfn
);

CREATE FUNCTION pg_catalog.median4_transfn(internal, real)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_median4_transfn'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION pg_catalog.median4_finalfn(internal)
RETURNS real
AS 'MODULE_PATHNAME','orafce_median4_finalfn'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION pg_catalog.median8_transfn(internal, double precision)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_median8_transfn'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION pg_catalog.median8_finalfn(internal)
RETURNS double precision
AS 'MODULE_PATHNAME','orafce_median8_finalfn'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE pg_catalog.median(real) (
  SFUNC=pg_catalog.median4_transfn,
  STYPE=internal,
  FINALFUNC=pg_catalog.median4_finalfn
);

CREATE AGGREGATE pg_catalog.median(double precision) (
  SFUNC=pg_catalog.median8_transfn,
  STYPE=internal,
  FINALFUNC=pg_catalog.median8_finalfn
);

-- oracle.varchar2 type support

CREATE FUNCTION oracle.varchar2in(cstring,oid,integer)
RETURNS oracle.varchar2
AS 'MODULE_PATHNAME','varchar2in'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.varchar2out(oracle.varchar2)
RETURNS CSTRING
AS 'MODULE_PATHNAME','varchar2out'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.varchar2_transform(internal)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_varchar_transform'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.varchar2recv(internal,oid,integer)
RETURNS oracle.varchar2
AS 'MODULE_PATHNAME','varchar2recv'
LANGUAGE C
STRICT
STABLE;

CREATE FUNCTION oracle.varchar2send(oracle.varchar2)
RETURNS bytea
AS 'varcharsend'
LANGUAGE internal
STRICT
STABLE;

CREATE FUNCTION oracle.varchar2typmodin(cstring[])
RETURNS integer
AS 'varchartypmodin'
LANGUAGE internal
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.varchar2typmodout(integer)
RETURNS CSTRING
AS 'varchartypmodout'
LANGUAGE internal
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.varchar2(oracle.varchar2,integer,boolean)
RETURNS oracle.varchar2
AS 'MODULE_PATHNAME','varchar2'
LANGUAGE C
STRICT
IMMUTABLE;

/* CREATE TYPE */
CREATE TYPE oracle.varchar2 (
internallength = VARIABLE,
input = oracle.varchar2in,
output = oracle.varchar2out,
receive = oracle.varchar2recv,
send = oracle.varchar2send,
category = 'S',
storage = 'extended',
typmod_in = oracle.varchar2typmodin,
typmod_out = oracle.varchar2typmodout,
collatable = true
);

CREATE FUNCTION oracle.orafce_concat2(oracle.varchar2, oracle.varchar2)
RETURNS oracle.varchar2
AS 'MODULE_PATHNAME','orafce_concat2'
LANGUAGE C STABLE;

/* CREATE CAST */
CREATE CAST (oracle.varchar2 AS text)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (text AS oracle.varchar2)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS char)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (char AS oracle.varchar2)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS varchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (varchar AS oracle.varchar2)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS oracle.varchar2)
WITH FUNCTION oracle.varchar2(oracle.varchar2,integer,boolean)
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS real)
WITH INOUT
AS IMPLICIT;

CREATE CAST (real AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS double precision)
WITH INOUT
AS IMPLICIT;

CREATE CAST (double precision AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS integer)
WITH INOUT
AS IMPLICIT;

CREATE CAST (integer AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS smallint)
WITH INOUT
AS IMPLICIT;

CREATE CAST (smallint AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS bigint)
WITH INOUT
AS IMPLICIT;

CREATE CAST (bigint AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS numeric)
WITH INOUT
AS IMPLICIT;

CREATE CAST (numeric AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS pg_catalog.date)
WITH INOUT
AS IMPLICIT;

CREATE CAST (pg_catalog.date AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS timestamp)
WITH INOUT
AS IMPLICIT;

CREATE CAST (timestamp AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.date AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS oracle.date)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS interval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (interval AS oracle.varchar2)
WITH INOUT
AS IMPLICIT;

/*
 * Note - a procedure keyword is depraceted from PostgreSQL 11, but it used
 * because older release doesn't know function.
 *
 */
CREATE FUNCTION oracle.orafce_concat2(numeric, numeric)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(numeric, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, numeric)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(float4, float4)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(float4, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, float4)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(float8, float8)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(float8, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, float8)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(pg_catalog.date, pg_catalog.date)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(pg_catalog.date, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, pg_catalog.date)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(timestamp, timestamp)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(timestamp, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, timestamp)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(timestamptz, timestamptz)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(timestamptz, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, timestamptz)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(interval, interval)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(interval, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, interval)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = numeric, rightarg = numeric);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = float4, rightarg = float4);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = float8, rightarg = float8);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = pg_catalog.date, rightarg = pg_catalog.date);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = timestamp, rightarg = timestamp);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = timestamptz, rightarg = timestamptz);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = interval, rightarg = interval);

CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = numeric, rightarg = text);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = float4, rightarg = text);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = float8, rightarg = text);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = pg_catalog.date, rightarg = text);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = timestamp, rightarg = text);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = timestamptz, rightarg = text);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = interval, rightarg = text);

CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = text, rightarg = numeric);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = text, rightarg = float4);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = text, rightarg = float8);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = text, rightarg = pg_catalog.date);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = text, rightarg = timestamp);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = text, rightarg = timestamptz);

/*-----------------------------------------------------------------
  * add operator, avoid implicit cast
  * begin
  *-----------------------------------------------------------------
  */
/* equal */
CREATE OR REPLACE FUNCTION oracle.varchar2_eq(oracle.varchar2, oracle.varchar2)
RETURNS bool AS $$
SELECT $1::text = $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.= (
	LEFTARG   = oracle.varchar2,
	RIGHTARG  = oracle.varchar2,
	PROCEDURE = oracle.varchar2_eq,
	COMMUTATOR = operator(oracle.=),
	NEGATOR = operator(oracle.<>)
);

/* ne */
CREATE OR REPLACE FUNCTION oracle.varchar2_ne(oracle.varchar2, oracle.varchar2)
RETURNS bool AS $$
SELECT $1::text != $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<> (
	LEFTARG   = oracle.varchar2,
	RIGHTARG  = oracle.varchar2,
	PROCEDURE = oracle.varchar2_ne,
	COMMUTATOR = operator(oracle.<>),
	NEGATOR = operator(oracle.=)
);

/* le and greate */
/* le */
CREATE OR REPLACE FUNCTION oracle.varchar2_le(oracle.varchar2, oracle.varchar2)
RETURNS bool AS $$
SELECT $1::text <= $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.varchar2_le,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

/* great */
CREATE OR REPLACE FUNCTION oracle.varchar2_gt(oracle.varchar2, oracle.varchar2)
RETURNS bool AS $$
SELECT $1::text > $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.varchar2_gt,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

/* ge and letter */
/* ge */
CREATE OR REPLACE FUNCTION oracle.varchar2_ge(oracle.varchar2, oracle.varchar2)
RETURNS bool AS $$
SELECT $1::text >= $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.varchar2_ge,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

/* letter */
CREATE OR REPLACE FUNCTION oracle.varchar2_lt(oracle.varchar2, oracle.varchar2)
RETURNS bool AS $$
SELECT $1::text < $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.varchar2_lt,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

/*-----------------------------------------------------------------
  * add operator, avoid implicit cast
  * end
  *-----------------------------------------------------------------
  */

do $$
BEGIN
  IF EXISTS(SELECT * FROM pg_settings WHERE name = 'server_version_num' AND setting::int >= 120000) THEN
    ALTER FUNCTION oracle.varchar2(oracle.varchar2, integer, boolean) SUPPORT oracle.varchar2_transform;
  ELSE
    UPDATE pg_proc SET protransform= 'varchar2_transform'::regproc::oid WHERE proname='varchar2';

    INSERT INTO pg_depend (classid, objid, objsubid,
                           refclassid, refobjid, refobjsubid, deptype)
       VALUES('pg_proc'::regclass::oid, 'varchar2'::regproc::oid, 0,
              'pg_proc'::regclass::oid, 'varchar2_transform'::regproc::oid, 0, 'n');
  END IF;
END
$$;

-- string functions for varchar2 type
-- these are 'byte' versions of corresponsing text/varchar functions

CREATE OR REPLACE FUNCTION pg_catalog.substrb(oracle.varchar2, integer, integer) RETURNS oracle.varchar2
AS 'bytea_substr'
LANGUAGE internal
STRICT IMMUTABLE;
COMMENT ON FUNCTION pg_catalog.substrb(oracle.varchar2, integer, integer) IS 'extracts specified number of bytes from the input varchar2 string starting at the specified byte position (1-based) and returns as a varchar2 string';

CREATE OR REPLACE FUNCTION pg_catalog.substrb(oracle.varchar2, integer) RETURNS oracle.varchar2
AS 'bytea_substr_no_len'
LANGUAGE internal
STRICT IMMUTABLE;
COMMENT ON FUNCTION pg_catalog.substrb(oracle.varchar2, integer) IS 'extracts specified number of bytes from the input varchar2 string starting at the specified byte position (1-based) and returns as a varchar2 string';

CREATE OR REPLACE FUNCTION pg_catalog.lengthb(oracle.varchar2) RETURNS integer
AS 'byteaoctetlen'
LANGUAGE internal
STRICT IMMUTABLE;
COMMENT ON FUNCTION pg_catalog.lengthb(oracle.varchar2) IS 'returns byte length of the input varchar2 string';

CREATE OR REPLACE FUNCTION pg_catalog.strposb(oracle.varchar2, oracle.varchar2) RETURNS integer
AS 'byteapos'
LANGUAGE internal
STRICT IMMUTABLE;
COMMENT ON FUNCTION pg_catalog.strposb(oracle.varchar2, oracle.varchar2) IS 'returns the byte position of a specified string in the input varchar2 string';

-- oracle.nvarchar2 type support

CREATE FUNCTION oracle.nvarchar2in(cstring,oid,integer)
RETURNS oracle.nvarchar2
AS 'MODULE_PATHNAME','nvarchar2in'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.nvarchar2out(oracle.nvarchar2)
RETURNS CSTRING
AS 'MODULE_PATHNAME','nvarchar2out'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.nvarchar2_transform(internal)
RETURNS internal
AS 'MODULE_PATHNAME','orafce_varchar_transform'
LANGUAGE C
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.nvarchar2recv(internal,oid,integer)
RETURNS oracle.nvarchar2
AS 'MODULE_PATHNAME','nvarchar2recv'
LANGUAGE C
STRICT
STABLE;

CREATE FUNCTION oracle.nvarchar2send(oracle.nvarchar2)
RETURNS bytea
AS 'varcharsend'
LANGUAGE internal
STRICT
STABLE;

CREATE FUNCTION oracle.nvarchar2typmodin(cstring[])
RETURNS integer
AS 'varchartypmodin'
LANGUAGE internal
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.nvarchar2typmodout(integer)
RETURNS CSTRING
AS 'varchartypmodout'
LANGUAGE internal
STRICT
IMMUTABLE;

CREATE FUNCTION oracle.nvarchar2(oracle.nvarchar2,integer,boolean)
RETURNS oracle.nvarchar2
AS 'MODULE_PATHNAME','nvarchar2'
LANGUAGE C
STRICT
IMMUTABLE;

/* CREATE TYPE */
CREATE TYPE oracle.nvarchar2 (
internallength = VARIABLE,
input = oracle.nvarchar2in,
output = oracle.nvarchar2out,
receive = oracle.nvarchar2recv,
send = oracle.nvarchar2send,
category = 'S',
storage = 'extended',
typmod_in = oracle.nvarchar2typmodin,
typmod_out = oracle.nvarchar2typmodout,
collatable = true
);

CREATE FUNCTION oracle.orafce_concat2(oracle.nvarchar2, oracle.nvarchar2)
RETURNS oracle.nvarchar2
AS 'MODULE_PATHNAME','orafce_concat2'
LANGUAGE C IMMUTABLE;

/* CREATE CAST */
CREATE CAST (oracle.nvarchar2 AS text)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (text AS oracle.nvarchar2)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS char)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (char AS oracle.nvarchar2)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS varchar)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (varchar AS oracle.nvarchar2)
WITHOUT FUNCTION
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS oracle.nvarchar2)
WITH FUNCTION oracle.nvarchar2(oracle.nvarchar2, integer, boolean)
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS real)
WITH INOUT
AS IMPLICIT;

CREATE CAST (real AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS double precision)
WITH INOUT
AS IMPLICIT;

CREATE CAST (double precision AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS integer)
WITH INOUT
AS IMPLICIT;

CREATE CAST (integer AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS smallint)
WITH INOUT
AS IMPLICIT;

CREATE CAST (smallint AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS bigint)
WITH INOUT
AS IMPLICIT;

CREATE CAST (bigint AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS numeric)
WITH INOUT
AS IMPLICIT;

CREATE CAST (numeric AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS date)
WITH INOUT
AS IMPLICIT;

CREATE CAST (date AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS timestamp)
WITH INOUT
AS IMPLICIT;

CREATE CAST (timestamp AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.nvarchar2 AS interval)
WITH INOUT
AS IMPLICIT;

CREATE CAST (interval AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

CREATE CAST (oracle.varchar2 AS oracle.nvarchar2)
WITH INOUT
AS IMPLICIT;

do $$
BEGIN
  IF EXISTS(SELECT * FROM pg_settings WHERE name = 'server_version_num' AND setting::int >= 120000) THEN
    ALTER FUNCTION oracle.nvarchar2(oracle.nvarchar2, integer, boolean) SUPPORT oracle.nvarchar2_transform;
  ELSE
    UPDATE pg_proc SET protransform= 'nvarchar2_transform'::regproc::oid WHERE proname='nvarchar2';

    INSERT INTO pg_depend (classid, objid, objsubid,
                           refclassid, refobjid, refobjsubid, deptype)
       VALUES('pg_proc'::regclass::oid, 'nvarchar2'::regproc::oid, 0,
              'pg_proc'::regclass::oid, 'nvarchar2_transform'::regproc::oid, 0, 'n');
  END IF;
END
$$;

/*
 * Note - a procedure keyword is depraceted from PostgreSQL 11, but it used
 * because older release doesn't know function.
 *
 */
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = oracle.varchar2, rightarg = oracle.varchar2);
CREATE OPERATOR oracle.|| (procedure = oracle.orafce_concat2, leftarg = oracle.nvarchar2, rightarg = oracle.nvarchar2);

/*-----------------------------------------------------------------
  * add operator, avoid implicit cast
  * begin
  *-----------------------------------------------------------------
  */
/* equal */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_eq(oracle.nvarchar2, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1::text = $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.= (
	LEFTARG   = oracle.nvarchar2,
	RIGHTARG  = oracle.nvarchar2,
	PROCEDURE = oracle.nvarchar2_eq,
	COMMUTATOR = operator(oracle.=),
	NEGATOR = operator(oracle.<>)
);

/* ne */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_ne(oracle.nvarchar2, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1::text != $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<> (
	LEFTARG   = oracle.nvarchar2,
	RIGHTARG  = oracle.nvarchar2,
	PROCEDURE = oracle.nvarchar2_ne,
	COMMUTATOR = operator(oracle.<>),
	NEGATOR = operator(oracle.=)
);

/* le and greate */
/* le */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_le(oracle.nvarchar2, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1::text <= $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.nvarchar2_le,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

/* great */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_gt(oracle.nvarchar2, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1::text > $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.nvarchar2_gt,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

/* ge and letter */
/* ge */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_ge(oracle.nvarchar2, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1::text >= $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.nvarchar2_ge,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

/* letter */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_lt(oracle.nvarchar2, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1::text < $2::text;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.nvarchar2_lt,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

/* -----------------------------------------------------------------
  * --compatible numeric/float/float8 op nvarchar2
  * --if you use implicit cast to implement this function.
  * --you should iport bug about ambiguity problem when select some function.
  * -----------------------------------------------------------------
  */
/* equal and unequal */
/* equal */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_eq_numeric(oracle.nvarchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric = $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_eq_nvarchar2(numeric, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 = $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_eq_float4(oracle.nvarchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 = $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_eq_nvarchar2(float4, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 = $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_eq_float8(oracle.nvarchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 = $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_eq_nvarchar2(float8, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 = $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_eq_numeric,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_eq_nvarchar2,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_eq_float4,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_eq_nvarchar2,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_eq_float8,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_eq_nvarchar2,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

/* ne */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_ne_numeric(oracle.nvarchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric != $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_ne_nvarchar2(numeric, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 != $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_ne_float4(oracle.nvarchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 != $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_ne_nvarchar2(float4, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 != $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_ne_float8(oracle.nvarchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 != $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_ne_nvarchar2(float8, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 != $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_ne_numeric,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_ne_nvarchar2,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_ne_float4,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_ne_nvarchar2,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_ne_float8,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_ne_nvarchar2,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

/* le and greate */
/* le */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_le_numeric(oracle.nvarchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric <= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_le_nvarchar2(numeric, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 <= $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_le_float4(oracle.nvarchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 <= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_le_nvarchar2(float4, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 <= $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_le_float8(oracle.nvarchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 <= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_le_nvarchar2(float8, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 <= $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_le_numeric,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_le_nvarchar2,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_le_float4,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_le_nvarchar2,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_le_float8,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_le_nvarchar2,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

/* great */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_gt_numeric(oracle.nvarchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric > $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_gt_nvarchar2(numeric, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 > $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_gt_float4(oracle.nvarchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 > $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_gt_nvarchar2(float4, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 > $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_gt_float8(oracle.nvarchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 > $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_gt_nvarchar2(float8, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 > $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_gt_numeric,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_gt_nvarchar2,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_gt_float4,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_gt_nvarchar2,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_gt_float8,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_gt_nvarchar2,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

/* ge and letter */
/* ge */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_ge_numeric(oracle.nvarchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric >= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_ge_nvarchar2(numeric, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 >= $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_ge_float4(oracle.nvarchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 >= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_ge_nvarchar2(float4, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 >= $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_ge_float8(oracle.nvarchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 >= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_ge_nvarchar2(float8, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 >= $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_ge_numeric,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_ge_nvarchar2,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_ge_float4,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_ge_nvarchar2,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_ge_float8,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_ge_nvarchar2,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

/* letter */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_lt_numeric(oracle.nvarchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric < $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_lt_nvarchar2(numeric, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 < $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_lt_float4(oracle.nvarchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 < $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_lt_nvarchar2(float4, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 < $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_lt_float8(oracle.nvarchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 < $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_lt_nvarchar2(float8, oracle.nvarchar2)
RETURNS bool AS $$
SELECT $1 < $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_lt_numeric,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_lt_nvarchar2,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_lt_float4,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_lt_nvarchar2,
   COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_lt_float8,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_lt_nvarchar2,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

/* add and subtract */
/* add */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_add_numeric(oracle.nvarchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric + $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_add_nvarchar2(numeric, oracle.nvarchar2)
RETURNS numeric AS $$
SELECT $1 + $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_add_float4(oracle.nvarchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 + $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_add_nvarchar2(float4, oracle.nvarchar2)
RETURNS float4 AS $$
SELECT $1 + $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_add_float8(oracle.nvarchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 + $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_add_nvarchar2(float8, oracle.nvarchar2)
RETURNS float8 AS $$
SELECT $1 + $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_add_numeric,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_add_nvarchar2,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_add_float4,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_add_nvarchar2,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_add_float8,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_add_nvarchar2,
  COMMUTATOR = operator(oracle.+)
);

/* sub */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_sub_numeric(oracle.nvarchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric - $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_sub_nvarchar2(numeric, oracle.nvarchar2)
RETURNS numeric AS $$
SELECT $1 - $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_sub_float4(oracle.nvarchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 - $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_sub_nvarchar2(float4, oracle.nvarchar2)
RETURNS float4 AS $$
SELECT $1 - $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_sub_float8(oracle.nvarchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 - $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_sub_nvarchar2(float8, oracle.nvarchar2)
RETURNS float8 AS $$
SELECT $1 - $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_sub_numeric
);

CREATE OPERATOR oracle.- (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_sub_nvarchar2
);

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_sub_float4
);

CREATE OPERATOR oracle.- (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_sub_nvarchar2
);

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_sub_float8
);

CREATE OPERATOR oracle.- (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_sub_nvarchar2
);

/* mul */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_mul_numeric(oracle.nvarchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_mul_nvarchar2(numeric, oracle.nvarchar2)
RETURNS numeric AS $$
SELECT $1 * $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_mul_float4(oracle.nvarchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_mul_nvarchar2(float4, oracle.nvarchar2)
RETURNS float4 AS $$
SELECT $1 * $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_mul_float8(oracle.nvarchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_mul_nvarchar2(float8, oracle.nvarchar2)
RETURNS float8 AS $$
SELECT $1 * $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.* (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_mul_numeric,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_mul_nvarchar2,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_mul_float4,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_mul_nvarchar2,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_mul_float8,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_mul_nvarchar2,
  COMMUTATOR = operator(oracle.*)
);

/* div */
CREATE OR REPLACE FUNCTION oracle.nvarchar2_div_numeric(oracle.nvarchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric / $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_div_nvarchar2(numeric, oracle.nvarchar2)
RETURNS numeric AS $$
SELECT $1 / $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_div_float4(oracle.nvarchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 / $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_div_nvarchar2(float4, oracle.nvarchar2)
RETURNS float4 AS $$
SELECT $1 / $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.nvarchar2_div_float8(oracle.nvarchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 / $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_div_nvarchar2(float8, oracle.nvarchar2)
RETURNS float8 AS $$
SELECT $1 / $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle./ (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.nvarchar2_div_numeric
);

CREATE OPERATOR oracle./ (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.numeric_div_nvarchar2
);

CREATE OPERATOR oracle./ (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.nvarchar2_div_float4
);

CREATE OPERATOR oracle./ (
  LEFTARG   = float4,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float4_div_nvarchar2
);

CREATE OPERATOR oracle./ (
  LEFTARG   = oracle.nvarchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.nvarchar2_div_float8
);

CREATE OPERATOR oracle./ (
  LEFTARG   = float8,
  RIGHTARG  = oracle.nvarchar2,
  PROCEDURE = oracle.float8_div_nvarchar2
);
/* end */

/* PAD */

/* LPAD family */

/* Incompatibility #1:
 *     pg_catalog.lpad removes trailing blanks of CHAR arguments
 *     because of implicit cast to text
 *
 * Incompatibility #2:
 *     pg_catalog.lpad considers character length, NOT display length
 *     so, add functions to use custom C implementation of lpad as defined
 *     in charpad.c
 */
CREATE FUNCTION oracle.lpad(char, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(char, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT  IMMUTABLE
;

CREATE FUNCTION oracle.lpad(char, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(char, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(char, integer)
RETURNS text
AS $$ SELECT oracle.lpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(text, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.varchar2, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.nvarchar2, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(text, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(text, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(text, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(text, integer)
RETURNS text
AS $$ SELECT oracle.lpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.varchar2, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.varchar2, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.varchar2, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.varchar2, integer)
RETURNS text
AS $$ SELECT oracle.lpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.nvarchar2, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.nvarchar2, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.nvarchar2, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_lpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.lpad(oracle.nvarchar2, integer)
RETURNS text
AS $$ SELECT oracle.lpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

/* -----------------------------------------------------------------
  * --compatible numeric/float/float8 op varchar2
  * --if you use implicit cast to implement this function.
  * --you should iport bug about ambiguity problem when select some function.
  * -----------------------------------------------------------------
  */
/* equal and unequal */
/* equal */
CREATE OR REPLACE FUNCTION oracle.varchar2_eq_numeric(oracle.varchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric = $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_eq_varchar2(numeric, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 = $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_eq_float4(oracle.varchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 = $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_eq_varchar2(float4, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 = $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_eq_float8(oracle.varchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 = $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_eq_varchar2(float8, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 = $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_eq_numeric,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_eq_varchar2,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_eq_float4,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_eq_varchar2,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_eq_float8,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

CREATE OPERATOR oracle.= (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_eq_varchar2,
  COMMUTATOR = operator(oracle.=),
  NEGATOR = operator(oracle.<>)
);

/* ne */
CREATE OR REPLACE FUNCTION oracle.varchar2_ne_numeric(oracle.varchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric != $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_ne_varchar2(numeric, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 != $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_ne_float4(oracle.varchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 != $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_ne_varchar2(float4, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 != $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_ne_float8(oracle.varchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 != $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_ne_varchar2(float8, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 != $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_ne_numeric,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_ne_varchar2,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_ne_float4,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_ne_varchar2,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_ne_float8,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

CREATE OPERATOR oracle.<> (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_ne_varchar2,
  COMMUTATOR = operator(oracle.<>),
  NEGATOR = operator(oracle.=)
);

/* le and greate */
/* le */
CREATE OR REPLACE FUNCTION oracle.varchar2_le_numeric(oracle.varchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric <= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_le_varchar2(numeric, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 <= $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_le_float4(oracle.varchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 <= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_le_varchar2(float4, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 <= $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_le_float8(oracle.varchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 <= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_le_varchar2(float8, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 <= $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_le_numeric,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_le_varchar2,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_le_float4,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_le_varchar2,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_le_float8,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

CREATE OPERATOR oracle.<= (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_le_varchar2,
  COMMUTATOR = operator(oracle.>=),
  NEGATOR = operator(oracle.>)
);

/* great */
CREATE OR REPLACE FUNCTION oracle.varchar2_gt_numeric(oracle.varchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric > $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_gt_varchar2(numeric, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 > $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_gt_float4(oracle.varchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 > $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_gt_varchar2(float4, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 > $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_gt_float8(oracle.varchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 > $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_gt_varchar2(float8, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 > $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_gt_numeric,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_gt_varchar2,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_gt_float4,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_gt_varchar2,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_gt_float8,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

CREATE OPERATOR oracle.> (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_gt_varchar2,
  COMMUTATOR = operator(oracle.<),
  NEGATOR = operator(oracle.<=)
);

/* ge and letter */
/* ge */
CREATE OR REPLACE FUNCTION oracle.varchar2_ge_numeric(oracle.varchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric >= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_ge_varchar2(numeric, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 >= $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_ge_float4(oracle.varchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 >= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_ge_varchar2(float4, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 >= $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_ge_float8(oracle.varchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 >= $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_ge_varchar2(float8, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 >= $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_ge_numeric,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_ge_varchar2,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_ge_float4,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_ge_varchar2,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_ge_float8,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

CREATE OPERATOR oracle.>= (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_ge_varchar2,
  COMMUTATOR = operator(oracle.<=),
  NEGATOR = operator(oracle.<)
);

/* letter */
CREATE OR REPLACE FUNCTION oracle.varchar2_lt_numeric(oracle.varchar2, numeric)
RETURNS bool AS $$
SELECT $1::numeric < $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_lt_varchar2(numeric, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 < $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_lt_float4(oracle.varchar2, float4)
RETURNS bool AS $$
SELECT $1::float4 < $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_lt_varchar2(float4, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 < $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_lt_float8(oracle.varchar2, float8)
RETURNS bool AS $$
SELECT $1::float8 < $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_lt_varchar2(float8, oracle.varchar2)
RETURNS bool AS $$
SELECT $1 < $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_lt_numeric,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_lt_varchar2,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_lt_float4,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_lt_varchar2,
   COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_lt_float8,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

CREATE OPERATOR oracle.< (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_lt_varchar2,
  COMMUTATOR = operator(oracle.>),
  NEGATOR = operator(oracle.>=)
);

/* add and subtract */
/* add */
CREATE OR REPLACE FUNCTION oracle.varchar2_add_numeric(oracle.varchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric + $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_add_varchar2(numeric, oracle.varchar2)
RETURNS numeric AS $$
SELECT $1 + $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_add_float4(oracle.varchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 + $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_add_varchar2(float4, oracle.varchar2)
RETURNS float4 AS $$
SELECT $1 + $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_add_float8(oracle.varchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 + $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_add_varchar2(float8, oracle.varchar2)
RETURNS float8 AS $$
SELECT $1 + $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_add_numeric,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_add_varchar2,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_add_float4,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_add_varchar2,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_add_float8,
  COMMUTATOR = operator(oracle.+)
);

CREATE OPERATOR oracle.+ (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_add_varchar2,
  COMMUTATOR = operator(oracle.+)
);

/* sub */
CREATE OR REPLACE FUNCTION oracle.varchar2_sub_numeric(oracle.varchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric - $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_sub_varchar2(numeric, oracle.varchar2)
RETURNS numeric AS $$
SELECT $1 - $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_sub_float4(oracle.varchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 - $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_sub_varchar2(float4, oracle.varchar2)
RETURNS float4 AS $$
SELECT $1 - $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_sub_float8(oracle.varchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 - $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_sub_varchar2(float8, oracle.varchar2)
RETURNS float8 AS $$
SELECT $1 - $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_sub_numeric
);

CREATE OPERATOR oracle.- (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_sub_varchar2
);

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_sub_float4
);

CREATE OPERATOR oracle.- (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_sub_varchar2
);

CREATE OPERATOR oracle.- (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_sub_float8
);

CREATE OPERATOR oracle.- (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_sub_varchar2
);

/* mul */
CREATE OR REPLACE FUNCTION oracle.varchar2_mul_numeric(oracle.varchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_mul_varchar2(numeric, oracle.varchar2)
RETURNS numeric AS $$
SELECT $1 * $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_mul_float4(oracle.varchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_mul_varchar2(float4, oracle.varchar2)
RETURNS float4 AS $$
SELECT $1 * $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_mul_float8(oracle.varchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_mul_varchar2(float8, oracle.varchar2)
RETURNS float8 AS $$
SELECT $1 * $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle.* (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_mul_numeric,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_mul_varchar2,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_mul_float4,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_mul_varchar2,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_mul_float8,
  COMMUTATOR = operator(oracle.*)
);

CREATE OPERATOR oracle.* (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_mul_varchar2,
  COMMUTATOR = operator(oracle.*)
);

/* div */
CREATE OR REPLACE FUNCTION oracle.varchar2_div_numeric(oracle.varchar2, numeric)
RETURNS numeric AS $$
SELECT $1::numeric / $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.numeric_div_varchar2(numeric, oracle.varchar2)
RETURNS numeric AS $$
SELECT $1 / $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_div_float4(oracle.varchar2, float4)
RETURNS float4 AS $$
SELECT $1::float4 / $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float4_div_varchar2(float4, oracle.varchar2)
RETURNS float4 AS $$
SELECT $1 / $2::float4;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.varchar2_div_float8(oracle.varchar2, float8)
RETURNS float8 AS $$
SELECT $1::float8 / $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.float8_div_varchar2(float8, oracle.varchar2)
RETURNS float8 AS $$
SELECT $1 / $2::float8;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OPERATOR oracle./ (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = numeric,
  PROCEDURE = oracle.varchar2_div_numeric
);

CREATE OPERATOR oracle./ (
  LEFTARG   = numeric,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.numeric_div_varchar2
);

CREATE OPERATOR oracle./ (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float4,
  PROCEDURE = oracle.varchar2_div_float4
);

CREATE OPERATOR oracle./ (
  LEFTARG   = float4,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float4_div_varchar2
);

CREATE OPERATOR oracle./ (
  LEFTARG   = oracle.varchar2,
  RIGHTARG  = float8,
  PROCEDURE = oracle.varchar2_div_float8
);

CREATE OPERATOR oracle./ (
  LEFTARG   = float8,
  RIGHTARG  = oracle.varchar2,
  PROCEDURE = oracle.float8_div_varchar2
);
/* end */

/* RPAD family */

/* Incompatibility #1:
 *     pg_catalog.rpad removes trailing blanks of CHAR arguments
 *     because of implicit cast to text
 *
 * Incompatibility #2:
 *     pg_catalog.rpad considers character length, NOT display length
 *     so, add functions to use custom C implementation of rpad as defined
 *     in charpad.c
 */
CREATE FUNCTION oracle.rpad(char, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(char, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(char, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(char, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(char, integer)
RETURNS text
AS $$ SELECT oracle.rpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(text, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.varchar2, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.nvarchar2, integer, char)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(text, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(text, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(text, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(text, integer)
RETURNS text
AS $$ SELECT oracle.rpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.varchar2, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.varchar2, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.varchar2, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.varchar2, integer)
RETURNS text
AS $$ SELECT oracle.rpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.nvarchar2, integer, text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.nvarchar2, integer, oracle.varchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.nvarchar2, integer, oracle.nvarchar2)
RETURNS text
AS 'MODULE_PATHNAME','orafce_rpad'
LANGUAGE 'c'
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rpad(oracle.nvarchar2, integer)
RETURNS text
AS $$ SELECT oracle.rpad($1, $2, ' '::text); $$
LANGUAGE SQL
STRICT IMMUTABLE
;

/* TRIM */

/* Incompatibility #1:
 *     pg_catalog.ltrim, pg_catalog.rtrim and pg_catalog.btrim remove
 *     trailing blanks of CHAR arguments because of implicit cast to
 *     text
 *
 *     Following re-definitions address this incompatbility so that
 *     trailing blanks of CHAR arguments are preserved and considered
 *     significant for the trimming process.
 */

/* LTRIM family */
CREATE FUNCTION oracle.ltrim(char, char)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(char, text)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(char, oracle.varchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(char, oracle.nvarchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(char)
RETURNS text
AS $$ SELECT oracle.ltrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(text, char)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(text, text)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(text, oracle.varchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(text, oracle.nvarchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(text)
RETURNS text
AS $$ SELECT oracle.ltrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.varchar2, char)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.varchar2, text)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.varchar2, oracle.varchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.varchar2, oracle.nvarchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.varchar2)
RETURNS text
AS $$ SELECT oracle.ltrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.nvarchar2, char)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.nvarchar2, text)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.nvarchar2, oracle.varchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.nvarchar2, oracle.nvarchar2)
RETURNS text
AS 'ltrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.ltrim(oracle.nvarchar2)
RETURNS text
AS $$ SELECT oracle.ltrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

/* RTRIM family */
CREATE FUNCTION oracle.rtrim(char, char)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(char, text)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(char, oracle.varchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(char, oracle.nvarchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(char)
RETURNS text
AS $$ SELECT oracle.rtrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(text, char)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(text, text)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(text, oracle.varchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(text, oracle.nvarchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(text)
RETURNS text
AS $$ SELECT oracle.rtrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.varchar2, char)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.varchar2, text)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.varchar2, oracle.varchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.varchar2, oracle.nvarchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.varchar2)
RETURNS text
AS $$ SELECT oracle.rtrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.nvarchar2, char)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.nvarchar2, text)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.nvarchar2, oracle.varchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.nvarchar2, oracle.nvarchar2)
RETURNS text
AS 'rtrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.rtrim(oracle.nvarchar2)
RETURNS text
AS $$ SELECT oracle.rtrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

/* BTRIM family */
CREATE FUNCTION oracle.btrim(char, char)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(char, text)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(char, oracle.varchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(char, oracle.nvarchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(char)
RETURNS text
AS $$ SELECT oracle.btrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(text, char)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(text, text)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(text, oracle.varchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(text, oracle.nvarchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(text)
RETURNS text
AS $$ SELECT oracle.btrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.varchar2, char)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.varchar2, text)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.varchar2, oracle.varchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.varchar2, oracle.nvarchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.varchar2)
RETURNS text
AS $$ SELECT oracle.btrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.nvarchar2, char)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.nvarchar2, text)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.nvarchar2, oracle.varchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.nvarchar2, oracle.nvarchar2)
RETURNS text
AS 'btrim'
LANGUAGE internal
STRICT IMMUTABLE
;

CREATE FUNCTION oracle.btrim(oracle.nvarchar2)
RETURNS text
AS $$ SELECT oracle.btrim($1, ' '::text) $$
LANGUAGE SQL
STRICT IMMUTABLE
;

/* LENGTH */
CREATE FUNCTION oracle.length(char)
RETURNS integer
AS 'MODULE_PATHNAME','orafce_bpcharlen'
LANGUAGE 'c'
STRICT IMMUTABLE
;

GRANT USAGE ON SCHEMA dbms_pipe TO PUBLIC;
GRANT USAGE ON SCHEMA dbms_alert TO PUBLIC;
GRANT USAGE ON SCHEMA plvdate TO PUBLIC;
GRANT USAGE ON SCHEMA plvstr TO PUBLIC;
GRANT USAGE ON SCHEMA plvchr TO PUBLIC;
GRANT USAGE ON SCHEMA dbms_output TO PUBLIC;
GRANT USAGE ON SCHEMA plvsubst TO PUBLIC;
GRANT SELECT ON dbms_pipe.db_pipes to PUBLIC;
GRANT USAGE ON SCHEMA dbms_utility TO PUBLIC;
GRANT USAGE ON SCHEMA plvlex TO PUBLIC;
GRANT USAGE ON SCHEMA utl_file TO PUBLIC;
GRANT USAGE ON SCHEMA dbms_assert TO PUBLIC;
GRANT USAGE ON SCHEMA dbms_random TO PUBLIC;
GRANT USAGE ON SCHEMA oracle TO PUBLIC;
GRANT USAGE ON SCHEMA plunit TO PUBLIC;

/* orafce 3.3. related changes */
ALTER FUNCTION dbms_assert.enquote_name ( character varying ) STRICT;
ALTER FUNCTION dbms_assert.enquote_name ( character varying, boolean ) STRICT;
ALTER FUNCTION dbms_assert.noop ( character varying ) STRICT;

CREATE FUNCTION pg_catalog.trunc(value timestamp without time zone, fmt text)
RETURNS timestamp without time zone
AS 'MODULE_PATHNAME', 'ora_timestamp_trunc'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.trunc(timestamp without time zone, text) IS 'truncate date according to the specified format';

CREATE FUNCTION pg_catalog.round(value timestamp without time zone, fmt text)
RETURNS timestamp without time zone
AS 'MODULE_PATHNAME','ora_timestamp_round'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.round(timestamp with time zone, text) IS 'round dates according to the specified format';

CREATE FUNCTION pg_catalog.round(value timestamp without time zone)
RETURNS timestamp without time zone
AS $$ SELECT pg_catalog.round($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.round(timestamp without time zone) IS 'will round dates according to the specified format';

CREATE FUNCTION pg_catalog.trunc(value timestamp without time zone)
RETURNS timestamp without time zone
AS $$ SELECT pg_catalog.trunc($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION pg_catalog.trunc(timestamp without time zone) IS 'truncate date according to the specified format';

CREATE OR REPLACE FUNCTION oracle.round(double precision, int)
RETURNS numeric
AS $$SELECT pg_catalog.round($1::numeric, $2)$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.trunc(double precision, int)
RETURNS numeric
AS $$SELECT pg_catalog.trunc($1::numeric, $2)$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.round(float4, int)
RETURNS numeric
AS $$SELECT pg_catalog.round($1::numeric, $2)$$
LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.trunc(float4, int)
RETURNS numeric
AS $$SELECT pg_catalog.trunc($1::numeric, $2)$$
LANGUAGE sql IMMUTABLE STRICT;


CREATE FUNCTION oracle.get_major_version()
RETURNS text
AS 'MODULE_PATHNAME','ora_get_major_version'
LANGUAGE 'c' STRICT IMMUTABLE;

CREATE FUNCTION oracle.get_major_version_num()
RETURNS text
AS 'MODULE_PATHNAME','ora_get_major_version_num'
LANGUAGE 'c' STRICT IMMUTABLE;

CREATE FUNCTION oracle.get_full_version_num()
RETURNS text
AS 'MODULE_PATHNAME','ora_get_full_version_num'
LANGUAGE 'c' STRICT IMMUTABLE;

CREATE FUNCTION oracle.get_platform()
RETURNS text
AS 'MODULE_PATHNAME','ora_get_platform'
LANGUAGE 'c' STRICT IMMUTABLE;

CREATE FUNCTION oracle.get_status()
RETURNS text
AS 'MODULE_PATHNAME','ora_get_status'
LANGUAGE 'c' STRICT IMMUTABLE;

-- Oracle system views
create view oracle.user_tab_columns as
    select table_name,
           column_name,
           data_type,
           coalesce(character_maximum_length, numeric_precision) AS data_length,
           numeric_precision AS data_precision,
           numeric_scale AS data_scale,
           is_nullable AS nullable,
           ordinal_position AS column_id,
           is_updatable AS data_upgraded,
           table_schema
    from information_schema.columns;

create view oracle.user_tables as
    select table_name
      from information_schema.tables
     where table_type = 'BASE TABLE';

create view oracle.user_cons_columns as
   select constraint_name, column_name, table_name
     from information_schema.constraint_column_usage ;

create view oracle.user_constraints as
    select conname as constraint_name,
           conindid::regclass as index_name,
           case contype when 'p' then 'P' when 'f' then 'R' end as constraint_type,
           conrelid::regclass as table_name,
           case contype when 'f' then (select conname
                                         from pg_constraint c2
                                        where contype = 'p' and c2.conindid = c1.conindid)
                                      end as r_constraint_name
      from pg_constraint c1, pg_class
     where conrelid = pg_class.oid;

create view oracle.product_component_version as
    select oracle.get_major_version() as product,
           oracle.get_full_version_num() as version,
           oracle.get_platform() || ' ' || oracle.get_status() as status
    union all
    select extname,
           case when extname = 'plpgsql' then oracle.get_full_version_num() else extversion end,
           oracle.get_platform() || ' ' || oracle.get_status()
      from pg_extension;

create view oracle.user_objects as
    select relname as object_name,
           null::text as subject_name,
           c.oid as object_id,
           case relkind when 'r' then 'TABLE'
                        when 'i' then 'INDEX'
                        when 'S' then 'SEQUENCE'
                        when 'v' then 'VIEW'
                        when 'm' then 'VIEW'
                        when 'f' then 'FOREIGN TABLE' end as object_type,
           null::timestamp(0) as created,
           null::timestamp(0) as last_ddl_time,
           case when relkind = 'i' then (select case when indisvalid then 'VALID' else 'INVALID' end
                                          from pg_index
                                         where indexrelid = c.oid)
                                   else case when relispopulated then 'VALID' else 'INVALID' end end as status,
           relnamespace as namespace
      from pg_class c join pg_namespace n on c.relnamespace = n.oid
     where relkind not in  ('t','c')
       and nspname not in ('pg_toast','pg_catalog','information_schema')
    union all
    select tgname, null, t.oid, 'TRIGGER',null, null,'VALID', relnamespace
      from pg_trigger t join pg_class c on t.tgrelid = c.oid
     where not tgisinternal
    union all
    select proname, null, p.oid, 'FUNCTION', null, null, 'VALID', pronamespace
      from pg_proc p join pg_namespace n on p.pronamespace = n.oid
     where nspname not in ('pg_toast','pg_catalog','information_schema') order by 1;

create view oracle.user_procedures as
    select proname as object_name
      from pg_proc p join pg_namespace n on p.pronamespace = n.oid
       and nspname <> 'pg_catalog';

create view oracle.user_source as
    select row_number() over (partition by oid) as line, *
      from ( select oid, unnest(string_to_array(prosrc, e'\n')) as text,
                    proname as name, 'FUNCTION'::text as type
               from pg_proc) s;

create view oracle.user_views
   as select c.relname as view_name,
  pg_catalog.pg_get_userbyid(c.relowner) as owner
from pg_catalog.pg_class c
     left join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('v','')
      and n.nspname <> 'pg_catalog'
      and n.nspname <> 'information_schema'
      and n.nspname !~ '^pg_toast'
  and pg_catalog.pg_table_is_visible(c.oid);

create view oracle.user_ind_columns as
    select attname as column_name, c1.relname as index_name, c2.relname as table_name
      from (select unnest(indkey) attno, indexrelid, indrelid from pg_index) s
           join pg_attribute on attno = attnum and attrelid = indrelid
           join pg_class c1 on indexrelid = c1.oid
           join pg_class c2 on indrelid = c2.oid
           join pg_namespace n on c2.relnamespace = n.oid
     where attno > 0 and nspname not in ('pg_catalog','information_schema');

CREATE VIEW oracle.dba_segments AS
SELECT
    pg_namespace.nspname AS owner,
    pg_class.relname AS segment_name,
    CASE
        WHEN pg_class.relkind = 'r' THEN CAST( 'TABLE' AS VARCHAR( 18 ) )
        WHEN pg_class.relkind = 'i' THEN CAST( 'INDEX' AS VARCHAR( 18 ) )
        WHEN pg_class.relkind = 'f' THEN CAST( 'FOREIGN TABLE' AS VARCHAR( 18 ) )
        WHEN pg_class.relkind = 'S' THEN CAST( 'SEQUENCE' AS VARCHAR( 18 ) )
        WHEN pg_class.relkind = 's' THEN CAST( 'SPECIAL' AS VARCHAR( 18 ) )
        WHEN pg_class.relkind = 't' THEN CAST( 'TOAST TABLE' AS VARCHAR( 18 ) )
        WHEN pg_class.relkind = 'v' THEN CAST( 'VIEW' AS VARCHAR( 18 ) )
        ELSE CAST( pg_class.relkind AS VARCHAR( 18 ) )
    END AS segment_type,
    spcname AS tablespace_name,
    relfilenode AS header_file,
    NULL::oid AS header_block,
    pg_relation_size( pg_class.oid ) AS bytes,
    relpages AS blocks
FROM
    pg_class
    INNER JOIN pg_namespace
     ON pg_class.relnamespace = pg_namespace.oid
    LEFT OUTER JOIN pg_tablespace
     ON pg_class.reltablespace = pg_tablespace.oid
WHERE
    pg_class.relkind not in ('f','S','v');

-- Oracle dirty functions
CREATE OR REPLACE FUNCTION oracle.lpad(int, int, int)
RETURNS text AS $$
SELECT pg_catalog.lpad($1::text,$2,$3::text)
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.lpad(bigint, int, int)
RETURNS text AS $$
SELECT pg_catalog.lpad($1::text,$2,$3::text)
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.lpad(smallint, int, int)
RETURNS text AS $$
SELECT pg_catalog.lpad($1::text,$2,$3::text)
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.lpad(numeric, int, int)
RETURNS text AS $$
SELECT pg_catalog.lpad($1::text,$2,$3::text)
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.nvl(bigint, int)
RETURNS bigint AS $$
SELECT coalesce($1, $2)
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.nvl(numeric, int)
RETURNS numeric AS $$
SELECT coalesce($1, $2)
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.nvl(int, int)
RETURNS int AS $$
SELECT coalesce($1, $2)
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION oracle.numtodsinterval(double precision, text)
RETURNS interval AS $$
  SELECT $1 * ('1' || $2)::interval
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.replace_empty_strings()
RETURNS TRIGGER
AS 'MODULE_PATHNAME','orafce_replace_empty_strings'
LANGUAGE 'c';

CREATE OR REPLACE FUNCTION oracle.replace_null_strings()
RETURNS TRIGGER
AS 'MODULE_PATHNAME','orafce_replace_null_strings'
LANGUAGE 'c';

CREATE OR REPLACE FUNCTION oracle.unistr(text)
RETURNS text
AS 'MODULE_PATHNAME','orafce_unistr'
LANGUAGE 'c';

-- Translate Oracle regexp modifier into PostgreSQl ones
-- Append the global modifier if $2 is true. Used internally
-- by regexp_*() functions bellow.
CREATE OR REPLACE FUNCTION oracle.translate_oracle_modifiers(text, bool)
RETURNS text
AS $$
DECLARE
  modifiers text := '';
BEGIN
  IF $1 IS NOT NULL THEN
    -- Check that we don't have modifier not supported by Oracle
    IF $1 ~ '[^icnsmx]' THEN
      -- Modifier 's' is not supported by Oracle but it is a synonym
      -- of 'n', we translate 'n' into 's' bellow. It is safe to allow it.
      RAISE EXCEPTION 'argument ''flags'' has unsupported modifier(s).';
    END IF;
    -- Oracle 'n' modifier correspond to 's' POSIX modifier
    -- Oracle 'm' modifier correspond to 'n' POSIX modifier
    modifiers := translate($1, 'nm', 'sn');
  END IF;
  IF $2 THEN
    modifiers := modifiers || 'g';
  END IF;
  RETURN modifiers;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_LIKE( string text, pattern text) -> boolean
-- If one of the param is NULL returns NULL, declared STRICT
CREATE OR REPLACE FUNCTION oracle.regexp_like(text, text)
RETURNS boolean
AS $$
  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  SELECT CASE WHEN (count(*) > 0) THEN true ELSE false END FROM regexp_matches($1, $2, 'p');
$$
LANGUAGE 'sql' STRICT;

-- REGEXP_LIKE( string text, pattern text, flags text ) -> boolean
CREATE OR REPLACE FUNCTION oracle.regexp_like(text, text, text)
RETURNS boolean
AS $$
DECLARE
  modifiers text;
BEGIN
  -- Only modifier can be NULL
  IF $1 IS NULL OR $2 IS NULL THEN
    RETURN NULL;
  END IF;
  modifiers := oracle.translate_oracle_modifiers($3, false);
  IF (regexp_matches($1, $2, modifiers))[1] IS NOT NULL THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_COUNT( string text, pattern text ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_count(text, text)
RETURNS integer
AS $$
  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  SELECT count(*)::integer FROM regexp_matches($1, $2, 'pg');
$$
LANGUAGE 'sql' STRICT;

-- REGEXP_COUNT( string text, pattern text, position int ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_count(text, text, integer)
RETURNS integer
AS $$
DECLARE
  v_cnt integer;
BEGIN
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_cnt :=  (SELECT count(*)::integer FROM regexp_matches(substr($1, $3), $2, 'pg'));
  RETURN v_cnt;
END;
$$
LANGUAGE plpgsql STRICT;

-- REGEXP_COUNT( string text, pattern text, position int, flags text ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_count(text, text, integer, text)
RETURNS integer
AS $$
DECLARE
  modifiers text;
  v_cnt   integer;
BEGIN
  -- Only modifier can be NULL
  IF $1 IS NULL OR $2 IS NULL OR $3 IS NULL THEN
    RETURN NULL;
  END IF;
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;

  modifiers := oracle.translate_oracle_modifiers($4, true);
  v_cnt := (SELECT count(*)::integer FROM regexp_matches(substr($1, $3), $2, modifiers));
  RETURN v_cnt;
END;
$$
LANGUAGE plpgsql;

--  REGEXP_INSTR( string text, pattern text ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_instr(text, text)
RETURNS integer
AS $$
DECLARE
  v_pos integer;
  v_pattern text;
BEGIN
  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_pos := (SELECT position((SELECT (regexp_matches($1, v_pattern, 'pg'))[1] OFFSET 0 LIMIT 1) IN $1));

  -- position() returns NULL when not found, we need to return 0 instead
  IF v_pos IS NOT NULL THEN
    RETURN v_pos;
  END IF;
  RETURN 0;
END;
$$
LANGUAGE plpgsql STRICT;

--  REGEXP_INSTR( string text, pattern text, position int ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_instr(text, text, integer)
RETURNS integer
AS $$
DECLARE
  v_pos integer;
  v_pattern text;
BEGIN
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_pos := (SELECT position((SELECT (regexp_matches(substr($1, $3), v_pattern, 'pg'))[1] OFFSET 0 LIMIT 1) IN $1));

  -- position() returns NULL when not found, we need to return 0 instead
  IF v_pos IS NOT NULL THEN
    RETURN v_pos;
  END IF;
  RETURN 0;
END;
$$
LANGUAGE plpgsql STRICT;

--  REGEXP_INSTR( string text, pattern text, position int, occurence int ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_instr(text, text, integer, integer)
RETURNS integer
AS $$
DECLARE
  v_pos integer;
  v_pattern text;
BEGIN
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;

  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_pos := (SELECT position((SELECT (regexp_matches(substr($1, $3), v_pattern, 'pg'))[1] OFFSET $4 - 1 LIMIT 1) IN $1));

  -- position() returns NULL when not found, we need to return 0 instead
  IF v_pos IS NOT NULL THEN
    RETURN v_pos;
  END IF;
  RETURN 0;
END;
$$
LANGUAGE plpgsql STRICT;

--  REGEXP_INSTR( string text, pattern text, position int, occurence int, return_opt int ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_instr(text, text, integer, integer, integer)
RETURNS integer
AS $$
DECLARE
  v_pos integer;
  v_len integer;
  v_pattern text;
BEGIN
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;
  IF $5 != 0 AND $5 != 1 THEN
    RAISE EXCEPTION 'argument ''return_opt'' must be 0 or 1';
  END IF;

  -- Without subexpression specified, assume 0 which mean that the first
  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_pos := (SELECT position((SELECT (regexp_matches(substr($1, $3), v_pattern, 'pg'))[1] OFFSET $4-1 LIMIT 1) IN $1));

  -- position() returns NULL when not found, we need to return 0 instead
  IF v_pos IS NOT NULL THEN
    IF $5 = 1 THEN
      v_len := (SELECT length((SELECT (regexp_matches(substr($1, $3), v_pattern, 'pg'))[1] OFFSET $4 - 1 LIMIT 1)));
      v_pos := v_pos + v_len;
    END IF;
    RETURN v_pos;
  END IF;
  RETURN 0;
END;
$$
LANGUAGE plpgsql STRICT;

--  REGEXP_INSTR( string text, pattern text, position int, occurence int, return_opt int, flags text ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_instr(text, text, integer, integer, integer, text)
RETURNS integer
AS $$
DECLARE
  v_pos integer;
  v_len integer;
  modifiers text;
  v_pattern text;
BEGIN
  -- Only modifier can be NULL
  IF $1 IS NULL OR $2 IS NULL OR $3 IS NULL OR $4 IS NULL OR $5 IS NULL THEN
    RETURN NULL;
  END IF;
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
      RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;
  IF $5 != 0 AND $5 != 1 THEN
    RAISE EXCEPTION 'argument ''return_opt'' must be 0 or 1';
  END IF;
  modifiers := oracle.translate_oracle_modifiers($6, true);

  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';
  v_pos := (SELECT position((SELECT (regexp_matches(substr($1, $3), v_pattern, modifiers))[1] OFFSET $4 - 1 LIMIT 1) IN $1));

  -- position() returns NULL when not found, we need to return 0 instead
  IF v_pos IS NOT NULL THEN
    IF $5 = 1 THEN
      v_len := (SELECT length((SELECT (regexp_matches(substr($1, $3), v_pattern, modifiers))[1] OFFSET $4-1 LIMIT 1)));
      v_pos := v_pos + v_len;
    END IF;
    RETURN v_pos;
  END IF;
  RETURN 0;
END;
$$
LANGUAGE plpgsql;

--  REGEXP_INSTR( string text, pattern text, position int, occurence int, return_opt int, flags text, group int ) -> integer
CREATE OR REPLACE FUNCTION oracle.regexp_instr(text, text, integer, integer, integer, text, integer)
RETURNS integer
AS $$
DECLARE
  v_pos integer := 0;
  v_pos_orig integer := $3;
  v_len integer := 0;
  modifiers text;
  occurrence integer := $4;
  idx integer := 1;
  v_curr_pos integer := 0;
  v_pattern text;
  v_subexpr integer := $7;
BEGIN
  -- Only modifier can be NULL
  IF $1 IS NULL OR $2 IS NULL OR $3 IS NULL OR $4 IS NULL OR $5 IS NULL OR $7 IS NULL THEN
    RETURN NULL;
  END IF;
  -- Check numeric arguments
  IF $3 < 1 THEN
      RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;
  IF $7 < 0 THEN
    RAISE EXCEPTION 'argument ''group'' must be a positive number';
  END IF;
  IF $5 != 0 AND $5 != 1 THEN
    RAISE EXCEPTION 'argument ''return_opt'' must be 0 or 1';
  END IF;

  -- Translate Oracle regexp modifier into PostgreSQl ones
  modifiers := oracle.translate_oracle_modifiers($6, true);

  -- If subexpression value is 0 we need to enclose the pattern between parentheses.
  IF v_subexpr = 0 THEN
     v_pattern := '(' || $2 || ')';
     v_subexpr := 1;
  ELSE
     v_pattern := $2;
  END IF;

  -- To get position of occurrence > 1 we need a more complex code
  LOOP
    v_curr_pos := v_curr_pos + v_len;
    v_pos := (SELECT position((SELECT (regexp_matches(substr($1, v_pos_orig), '('||$2||')', modifiers))[1] OFFSET 0 LIMIT 1) IN substr($1, v_pos_orig)));
    v_len := (SELECT length((SELECT (regexp_matches(substr($1, v_pos_orig), '('||$2||')', modifiers))[1] OFFSET 0 LIMIT 1)));

    EXIT WHEN v_len IS NULL;

    v_pos_orig := v_pos_orig + v_pos + v_len;
    v_curr_pos := v_curr_pos + v_pos;
    idx := idx + 1;

    EXIT WHEN idx > occurrence;
  END LOOP;

  v_pos := (SELECT position((SELECT (regexp_matches(substr($1, v_curr_pos), v_pattern, modifiers))[v_subexpr] OFFSET 0 LIMIT 1) IN substr($1, v_curr_pos)));
  IF v_pos IS NOT NULL THEN
    IF $5 = 1 THEN
      v_len := (SELECT length((SELECT (regexp_matches(substr($1, v_curr_pos), v_pattern, modifiers))[v_subexpr] OFFSET 0 LIMIT 1)));
      v_pos := v_pos + v_len;
    END IF;
    RETURN v_pos + v_curr_pos - 1;
  END IF;
  RETURN 0;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_SUBSTR( string text, pattern text ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_substr(text, text)
RETURNS text
AS $$
DECLARE
  v_substr text;
  v_pattern text;
BEGIN
  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_substr := (SELECT (regexp_matches($1, v_pattern, 'pg'))[1] OFFSET 0 LIMIT 1);
  RETURN v_substr;
END;
$$
LANGUAGE plpgsql STRICT;

-- REGEXP_SUBSTR( string text, pattern text, position int ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_substr(text, text, int)
RETURNS text
AS $$
DECLARE
  v_substr text;
  v_pattern text;
BEGIN
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;

  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_substr := (SELECT (regexp_matches(substr($1, $3), v_pattern, 'pg'))[1] OFFSET 0 LIMIT 1);
  RETURN v_substr;
END;
$$
LANGUAGE plpgsql STRICT;

-- REGEXP_SUBSTR( string text, pattern text, position int, occurence int ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_substr(text, text, integer, integer)
RETURNS text
AS $$
DECLARE
  v_substr text;
  v_pattern text;
BEGIN
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;

  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_substr := (SELECT (regexp_matches(substr($1, $3), v_pattern, 'pg'))[1] OFFSET $4 - 1 LIMIT 1);
  RETURN v_substr;
END;
$$
LANGUAGE plpgsql STRICT;

-- REGEXP_SUBSTR( string text, pattern text, position int, occurence int, flags text ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_substr(text, text, integer, integer, text)
RETURNS text
AS $$
DECLARE
  v_substr text;
  v_pattern text;
  modifiers text;
BEGIN
  -- Only modifier can be NULL
  IF $1 IS NULL OR $2 IS NULL OR $3 IS NULL OR $4 IS NULL THEN
    RETURN NULL;
  END IF;
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;

  modifiers := oracle.translate_oracle_modifiers($5, true);

  -- Without subexpression specified, assume 0 which mean that the first
  -- position for the substring matching the whole pattern is returned.
  -- We need to enclose the pattern between parentheses.
  v_pattern := '(' || $2 || ')';

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_substr := (SELECT (regexp_matches(substr($1, $3), v_pattern, modifiers))[1] OFFSET $4 - 1 LIMIT 1);
  RETURN v_substr;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_SUBSTR( string text, pattern text, position int, occurence int, flags text, group int ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_substr(text, text, integer, integer, text, int)
RETURNS text
AS $$
DECLARE
  v_substr text;
  v_pattern text;
  modifiers text;
  v_subexpr integer := $6;
  has_group integer;
BEGIN
  -- Only modifier can be NULL
  IF $1 IS NULL OR $2 IS NULL OR $3 IS NULL OR $4 IS NULL OR $6 IS NULL THEN
    RETURN NULL;
  END IF;
  -- Check numeric arguments
  IF $3 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''occurence'' must be a number greater than 0';
  END IF;
  IF v_subexpr < 0 THEN
    RAISE EXCEPTION 'argument ''group'' must be a positive number';
  END IF;

  -- Check that with v_subexpr = 1 we have a capture group otherwise return NULL
  has_group := (SELECT count(*) FROM regexp_matches($2, '(?:[^\\]|^)\(', 'g'));
  IF $6 = 1 AND has_group = 0 THEN
    RETURN NULL;
  END IF;

  modifiers := oracle.translate_oracle_modifiers($5, true);

  -- If subexpression value is 0 we need to enclose the pattern between parentheses.
  IF v_subexpr = 0 THEN
    v_pattern := '(' || $2 || ')';
    v_subexpr := 1;
  ELSE
    v_pattern := $2;
  END IF;

  -- Oracle default behavior is newline-sensitive,
  -- PostgreSQL not, so force 'p' modifier to affect
  -- newline-sensitivity but not ^ and $ search.
  v_substr := (SELECT (regexp_matches(substr($1, $3), v_pattern, modifiers))[v_subexpr] OFFSET $4 - 1 LIMIT 1);
  RETURN v_substr;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_REPLACE( string text, pattern text, replace_string text ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_replace(text, text, text)
RETURNS text
AS $$
DECLARE
  str text;
BEGIN
  IF $2 IS NULL AND $1 IS NOT NULL THEN
    RETURN $1;
  END IF;
  -- Oracle default behavior is to replace all occurence
  -- whereas PostgreSQL only replace the first occurrence
  -- so we need to add 'g' modifier.
  SELECT pg_catalog.regexp_replace($1, $2, $3, 'g') INTO str;
  RETURN str;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_REPLACE( string text, pattern text, replace_string text, position int ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_replace(text, text, text, integer)
RETURNS text
AS $$
DECLARE
  v_replaced_str text;
  v_before text;
BEGIN
  IF $1 IS NULL OR $3 IS NULL OR $4 IS NULL THEN
    RETURN NULL;
  END IF;
  IF $2 IS NULL THEN
    RETURN $1;
  END IF;
  -- Check numeric arguments
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;

  v_before = substr($1, 1, $4 - 1);

  -- Oracle default behavior is to replace all occurence
  -- whereas PostgreSQL only replace the first occurrence
  -- so we need to add 'g' modifier.
  v_replaced_str := v_before || pg_catalog.regexp_replace(substr($1, $4), $2, $3, 'g');
  RETURN v_replaced_str;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_REPLACE( string text, pattern text, replace_string text, position int, occurence int ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_replace(text, text, text, integer, integer)
RETURNS text
AS $$
DECLARE
  v_replaced_str text;
  v_pos integer := $4;
  v_before text := '';
  v_nummatch integer;
BEGIN
  IF $1 IS NULL OR $3 IS NULL OR $4 IS NULL OR $5 IS NULL THEN
    RETURN NULL;
  END IF;
  IF $2 IS NULL THEN
    RETURN $1;
  END IF;
  -- Check numeric arguments
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $5 < 0 THEN
    RAISE EXCEPTION 'argument ''occurrence'' must be a positive number';
  END IF;
  -- Check if the occurrence queried exceeds the number of occurrences
  IF $5 > 1 THEN
    v_nummatch := (SELECT count(*) FROM regexp_matches(substr($1, $4), $2, 'g'));
    IF $5 > v_nummatch THEN
      RETURN $1;
    END IF;
    -- Get the position of the occurrence we are looking for
    v_pos := oracle.regexp_instr($1, $2, $4, $5, 0, '', 1);
    IF v_pos = 0 THEN
      RETURN $1;
    END IF;
  END IF;
  -- Get the substring before this position we will need to restore it
  v_before := substr($1, 1, v_pos - 1);

  -- Replace all occurrences
  IF $5 = 0 THEN
    v_replaced_str := v_before || pg_catalog.regexp_replace(substr($1, v_pos), $2, $3, 'g');
  ELSE
    -- Replace the first occurrence
    v_replaced_str := v_before || pg_catalog.regexp_replace(substr($1, v_pos), $2, $3);
  END IF;

  RETURN v_replaced_str;
END;
$$
LANGUAGE plpgsql;

-- REGEXP_REPLACE( string text, pattern text, replace_string text, position int, occurence int, flags text ) -> text
CREATE OR REPLACE FUNCTION oracle.regexp_replace(text, text, text, integer, integer, text)
RETURNS text
AS $$
DECLARE
  v_replaced_str text;
  v_pos integer := $4;
  v_nummatch integer;
  v_before text := '';
  modifiers text := '';
BEGIN
  IF $1 IS NULL OR $3 IS NULL OR $4 IS NULL OR $5 IS NULL THEN
    RETURN NULL;
  END IF;
  IF $2 IS NULL THEN
    RETURN $1;
  END IF;
  -- Check numeric arguments
  IF $4 < 1 THEN
    RAISE EXCEPTION 'argument ''position'' must be a number greater than 0';
  END IF;
  IF $5 < 0 THEN
    RAISE EXCEPTION 'argument ''occurrence'' must be a positive number';
  END IF;
  -- Set the modifiers
  IF $5 = 0 THEN
    modifiers := oracle.translate_oracle_modifiers($6, true);
  ELSE
    modifiers := oracle.translate_oracle_modifiers($6, false);
  END IF;
  -- Check if the occurrence queried exceeds the number of occurrences
  IF $5 > 1 THEN
    v_nummatch := (SELECT count(*) FROM regexp_matches(substr($1, $4), $2, $6||'g'));
    IF $5 > v_nummatch THEN
      RETURN $1;
    END IF;
    -- Get the position of the occurrence we are looking for
    v_pos := oracle.regexp_instr($1, $2, $4, $5, 0, $6, 1);
    IF v_pos = 0 THEN
      RETURN $1;
    END IF;
  END IF;
  -- Get the substring before this position we will need to restore it
  v_before := substr($1, 1, v_pos - 1);
  -- Replace occurrence(s)
  v_replaced_str := v_before || pg_catalog.regexp_replace(substr($1, v_pos), $2, $3, modifiers);
  RETURN v_replaced_str;
END;
$$
LANGUAGE plpgsql;

--oracle compatible functions, from_tz function
CREATE FUNCTION oracle.from_tz(TIMESTAMP, TEXT)
RETURNS cstring                
AS 'MODULE_PATHNAME','ora_fromtz'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION oracle.from_tz(TIMESTAMP, TEXT) IS 'Convert timestamp value of specific time zone to a timestamp with a time zone value.';

--numtodsinterval function
CREATE OR REPLACE FUNCTION oracle.numtodsinterval(double precision, text)
RETURNS interval AS $$
  SELECT $1 * ('1' || $2)::interval
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.numtodsinterval(numeric, text)
RETURNS interval AS $$
  SELECT $1 * ('1' || $2)::interval
$$ LANGUAGE sql IMMUTABLE STRICT;

--numtoyminterval function
CREATE OR REPLACE FUNCTION oracle.numtoyminterval(double precision, text)
RETURNS interval AS $$
  SELECT $1 * ('1' || $2)::interval
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION oracle.numtoyminterval(numeric, text)
RETURNS interval AS $$
  SELECT $1 * ('1' || $2)::interval
$$ LANGUAGE sql IMMUTABLE STRICT;

--systimestamp function
CREATE FUNCTION oracle.systimestamp()
RETURNS timestamptz
AS 'MODULE_PATHNAME','ora_systimestamp'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.systimestamp() IS 'get the system timestamp';

--sys_extract_utc function
CREATE FUNCTION oracle.sys_extract_utc(tm timestamptz)
RETURNS timestamp              
AS 'MODULE_PATHNAME','ora_sys_extract_utc'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE; 
COMMENT ON FUNCTION  oracle.sys_extract_utc(timestamptz) IS 'extracts the UTC from a datetime value with time zone offset or time zone region name.';

--days_between function
CREATE FUNCTION oracle.days_between(TIMESTAMP, TIMESTAMP)
RETURNS numeric
AS 'MODULE_PATHNAME','ora_days_between'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.days_between(TIMESTAMP, TIMESTAMP) IS 'The days difference between the two timestamp values';

--days_between_tmtz function
CREATE FUNCTION oracle.days_between_tmtz(TIMESTAMPTZ, TIMESTAMPTZ)
RETURNS numeric
AS 'MODULE_PATHNAME','ora_days_between_tmtz'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.days_between_tmtz(TIMESTAMPTZ, TIMESTAMPTZ) IS 'The days difference between the two timestamptz values';

--add_days_to_timestamp function
CREATE OR REPLACE FUNCTION oracle.add_days_to_timestamp(timestamp, numeric)
RETURNS timestamp AS $$
SELECT $1 + interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.add_days_to_timestamp(text, text)
RETURNS timestamp AS $$
SELECT $1::timestamp + interval '1 day' * $2::numeric;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.add_days_to_timestamp(text, numeric)
RETURNS timestamp AS $$
SELECT $1::timestamp + interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.add_days_to_timestamp(oracle.date,integer)
RETURNS timestamp AS $$
SELECT $1 + interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE;

--subtract function
CREATE OR REPLACE FUNCTION oracle.subtract(timestamptz, numeric)
RETURNS timestamptz AS $$
SELECT $1 - interval '1 day' * $2;
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oracle.subtract(timestamptz, timestamptz)
RETURNS double precision AS $$
SELECT date_part('epoch', ($1 OPERATOR(pg_catalog.-) $2)/3600/24);
$$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

--new_time function
CREATE FUNCTION oracle.new_time(timestamptz, text, text)
RETURNS timestamp
AS 'MODULE_PATHNAME','new_time'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.new_time(timestamptz, text, text) IS 'returns the date and time in time zone timezone2 when date and time in time zone timezone1 are date.';

CREATE FUNCTION oracle.orafce_concat2(oracle.date, oracle.date)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(text, oracle.date)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION oracle.orafce_concat2(oracle.date, text)
RETURNS oracle.varchar2
AS 'select oracle.orafce_concat2($1::oracle.varchar2, $2::oracle.varchar2)'
LANGUAGE SQL IMMUTABLE;
 
CREATE OPERATOR oracle.|| (LEFTARG = oracle.date, RIGHTARG = oracle.date, PROCEDURE = oracle.orafce_concat2);
CREATE OPERATOR oracle.|| (LEFTARG = text, RIGHTARG = oracle.date, PROCEDURE = oracle.orafce_concat2);
CREATE OPERATOR oracle.|| (LEFTARG = oracle.date, RIGHTARG = text, PROCEDURE = oracle.orafce_concat2);

--months_between function
CREATE FUNCTION oracle.months_between(oracle.date,oracle.date)
RETURNS NUMERIC
AS 'MODULE_PATHNAME','oramonths_betweentimestamp'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION  oracle.months_between(oracle.date,oracle.date) IS 'The months difference between the two oracle.date values';

--add_months function
CREATE FUNCTION oracle.add_months(day oracle.date, value int)
RETURNS oracle.date
AS 'MODULE_PATHNAME', 'oraadd_months'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.add_months(day oracle.date, value int) IS 'returns oracle.date plus n months';

--trunc function
CREATE FUNCTION oracle.trunc(value timestamp with time zone, fmt text)
RETURNS timestamp with time zone
AS 'MODULE_PATHNAME', 'ora_timestamptz_trunc'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.trunc(timestamp with time zone, text) IS 'truncate date according to the specified format';

CREATE FUNCTION oracle.trunc(value timestamp with time zone)
RETURNS timestamp with time zone
AS $$ SELECT oracle.trunc($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.trunc(timestamp with time zone) IS 'truncate date according to the specified format';

CREATE FUNCTION oracle.trunc(value timestamp without time zone, fmt text)
RETURNS timestamp without time zone
AS 'MODULE_PATHNAME', 'ora_timestamp_trunc'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.trunc(timestamp without time zone, text) IS 'truncate date according to the specified format';

CREATE FUNCTION oracle.trunc(value timestamp without time zone)
RETURNS timestamp without time zone
AS $$ SELECT oracle.trunc($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.trunc(timestamp without time zone) IS 'truncate date according to the specified format';

CREATE FUNCTION oracle.trunc(value oracle.date, fmt text)
RETURNS oracle.date
AS 'MODULE_PATHNAME', 'ora_timestamp_trunc'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.trunc(value oracle.date, fmt text) IS 'truncate oracle.date according to the specified format';

CREATE FUNCTION oracle.trunc(value oracle.date)
RETURNS oracle.date
AS $$ SELECT oracle.trunc($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.trunc(value oracle.date) IS 'truncate oracle.date according to the specified format';

--round function
CREATE FUNCTION oracle.round(value timestamp with time zone, fmt text)
RETURNS timestamp with time zone
AS 'MODULE_PATHNAME','ora_timestamptz_round'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.round(timestamp with time zone, text) IS 'round dates according to the specified format';

CREATE FUNCTION oracle.round(value timestamp with time zone)
RETURNS timestamp with time zone
AS $$ SELECT oracle.round($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.round(timestamp with time zone) IS 'will round dates according to the specified format';

CREATE FUNCTION oracle.round(value timestamp without time zone, fmt text)
RETURNS timestamp without time zone
AS 'MODULE_PATHNAME','ora_timestamp_round'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.round(timestamp with time zone, text) IS 'round dates according to the specified format';

CREATE FUNCTION oracle.round(value timestamp without time zone)
RETURNS timestamp without time zone
AS $$ SELECT oracle.round($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.round(timestamp without time zone) IS 'will round dates according to the specified format';

CREATE FUNCTION oracle.round(value oracle.date, fmt text)
RETURNS oracle.date
AS 'MODULE_PATHNAME','ora_timestamp_round'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.round(value oracle.date, fmt text) IS 'round oracle.date according to the specified format';

CREATE FUNCTION oracle.round(value oracle.date)
RETURNS oracle.date
AS $$ SELECT oracle.round($1, 'DDD'); $$
LANGUAGE SQL IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.round(value oracle.date) IS 'will round oracle.date according to the specified format';

CREATE FUNCTION oracle.next_day(value oracle.date, weekday text)
RETURNS oracle.date
AS 'MODULE_PATHNAME','ora_next_day'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.next_day (value oracle.date, weekday text) IS 'returns the first weekday that is greater than a date value';

CREATE FUNCTION oracle.next_day(value oracle.date, weekday integer)
RETURNS oracle.date
AS 'MODULE_PATHNAME', 'oranext_day_by_index'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.next_day(value oracle.date, weekday integer) IS 'returns the first weekday that is greater than a date value';

CREATE FUNCTION oracle.last_day(oracle.date)
RETURNS oracle.date
AS 'MODULE_PATHNAME', 'ora_last_day'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION oracle.last_day(oracle.date) IS 'returns last day of the month based on a date value';

--ascii function
CREATE OR REPLACE FUNCTION oracle.ascii(oracle.varchar2)
RETURNS integer
AS 'ascii'
LANGUAGE internal
IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(oracle.varchar2) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(smallint)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(smallint) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(int)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(int) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(numeric)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(numeric) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(bigint)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(bigint) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(float4)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(float4) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(float8)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(float8) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(pg_catalog.date)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(pg_catalog.date) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(timestamp)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(timestamp) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(timestamptz)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(timestamptz) IS 'returns the decimal representation of the first character from string.';

CREATE OR REPLACE FUNCTION oracle.ascii(interval)
RETURNS integer
AS 'select ascii($1::text)'
LANGUAGE SQL IMMUTABLE PARALLEL SAFE STRICT;
COMMENT ON FUNCTION oracle.ascii(interval) IS 'returns the decimal representation of the first character from string.';