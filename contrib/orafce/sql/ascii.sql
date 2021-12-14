--Test For ascii
set search_path = oracle, public;
set datestyle to ISO,YMD;
SELECT ascii(20199) "ascii" FROM DUAL;
SELECT ascii(2019::int2) "ascii" FROM DUAL;
SELECT ascii(201912::int4) "ascii" FROM DUAL;
SELECT ascii(20191234::int8) "ascii" FROM DUAL;
SELECT ascii(201956.99980855) "ascii" FROM DUAL;
SELECT ascii(201956.999808::numeric) "ascii" FROM DUAL;

SELECT ascii('1230') "ascii" FROM DUAL;
SELECT ascii('I 8O lIKE AlPH: a b c') "ascii" FROM DUAL;
SELECT ascii('AB 8O lIKE AlPH: a b c'::char(100)) "ascii" FROM DUAL;
SELECT ascii('ab 8O lIKE AlPH: a b c'::varchar(100)) "ascii" FROM DUAL;
SELECT ascii('cd 8O lIKE AlPH: a b c'::varchar2(100)) "ascii" FROM DUAL;
SELECT ascii('i 8O lIKE AlPH: a b c'::nvarchar2(100)) "ascii" FROM DUAL;
SELECT ascii('CD 8O lIKE AlPH: a b c'::text) "ascii" FROM DUAL;
SELECT ascii(cast('合理adfad' as varchar(100))) "ascii" FROM DUAL;
SELECT ascii(cast('合理adfad' as char(100))) "ascii" FROM DUAL;

SELECT ascii('2019-12-12'::date) "ascii" FROM DUAL;
SELECT ascii('2019-12-12'::timestamp) "ascii" FROM DUAL;

SELECT ascii(null) FROM DUAL;
SELECT ascii('') FROM DUAL;
SELECT ascii(' ') FROM DUAL;
SELECT ascii(0::int) FROM DUAL;
SELECT ascii(-1::int) FROM DUAL;
reset search_path;
reset datestyle;