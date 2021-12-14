set datestyle to ISO,YMD;
set search_path to oracle, pg_catalog;
select length('3day 3 hour 3second');
select length(date'2021-12-09');
select length(timestamp'2021-12-09 10:10:11');
select length(timestamptz'2021-12-09 10:10:11+08');
select length(12);
select length(12.44);
select length(12.4::real);
select length(1244444.44666::float);
select length('adc');
select length('123abc'::text);
select length(12.455555555555::float);
select length('jmenuji se Pavel Stehule');
select length('今天是个好日子');
select length('あbb'::char(6));
select length(''::char(6));

reset search_path;
