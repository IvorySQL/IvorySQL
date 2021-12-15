--Test For vsize
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT vsize(20199) "vsize";
SELECT vsize(2019::int2) "vsize";
SELECT vsize(1::int4) "vsize";
SELECT vsize(10::int4) "vsize";
SELECT vsize(100::int4) "vsize";
SELECT vsize(1000::int4) "vsize";
SELECT vsize(10000::int4) "vsize";
SELECT vsize(30000::int4) "vsize";
SELECT vsize(40000::int8) "vsize";
SELECT vsize(20191234::int8) "vsize";
SELECT vsize(201956.99980855) "vsize";
SELECT vsize(201956.999808::numeric) "vsize";
SELECT vsize(201956.9998::float4) "vsize";
SELECT vsize(201956.9998089::float8) "vsize";

SELECT vsize('120') "vsize";
SELECT vsize('I 8O lIKE AlPH: a b c') "vsize";
SELECT vsize('I 8O lIKE AlPH: a b c'::char(100)) "vsize";
SELECT vsize('I 8O lIKE AlPH: a b c'::varchar(100)) "vsize";
SELECT vsize('I 8O lIKE AlPH: a b c'::varchar2(100)) "vsize";
SELECT vsize('I 8O lIKE AlPH: a b c'::nvarchar2(100)) "vsize";
SELECT vsize('I 8O lIKE AlPH: a b c'::text) "vsize";
SELECT vsize(cast('合理adfad' as varchar(100))) "vsize";
SELECT vsize(cast('合理adfad' as char(100))) "vsize";

SELECT vsize('2019-12-12'::date) "vsize";
SELECT vsize('2019-12-12'::timestamp) "vsize";
SELECT vsize('2019-12-12'::timestamptz) "vsize";
SELECT vsize('P-1Y-2M3DT-4H-5M-6S'::interval) "vsize";

SELECT vsize(null);
SELECT vsize('');
SELECT vsize(' ');
SELECT vsize(0::int);
SELECT vsize(-2::int);
SELECT vsize(-2.39::numeric);

reset search_path;
