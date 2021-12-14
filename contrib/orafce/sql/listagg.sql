set search_path to oracle, pg_catalog;
select listagg(i::text) from generate_series(1,3) g(i);
select listagg(i::text, ',') from generate_series(1,3) g(i);
create table test(id text, pid int);
insert into test values('1',11), ('2',12), ('3',13), ('1',21), ('2',22);
select listagg(id, ',') from test;
select listagg(id, ',') from test group by id;
select listagg(pid, '/') from test group by id;
select listagg(pid::text, '/') from test group by id;
select listagg(id, '/')  over(partition by id) from test;
select listagg(id, '/')  over(partition by pid) from test;
select listagg(id, '/')  over(partition by id) from test group by id;
drop table test;

reset search_path;
