--
-- Test that table-rewriting operations preserve ROWID sequence values.
--
-- ROWID is meant to be a stable row identifier (unlike ctid); rewriting a
-- table (VACUUM FULL, CLUSTER, ALTER TABLE, REPACK) must keep each row's
-- ROWID, so cached values continue to locate rows.
--
set ivorysql.compatible_mode to oracle;

-- VACUUM FULL (tuple copied as-is)
create table t_rw (id int, v text) with rowid;
insert into t_rw values (1, 'a'), (2, 'b'), (3, 'c');
select (rowid).rowno, id from t_rw order by id;

vacuum full t_rw;
select (rowid).rowno, id from t_rw order by id;

-- VACUUM FULL after dropping a column forces the tuples to be rebuilt
alter table t_rw drop column v;
vacuum full t_rw;
select (rowid).rowno, id from t_rw order by id;

-- Create a table with no dropped columns to keep the remaining steps
-- straightforward (t_rw above is left with one column).
create table t_rw2 (id int primary key, v text) with rowid;
insert into t_rw2 values (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd'), (5, 'e');
select (rowid).rowno, id from t_rw2 order by id;

-- CLUSTER
create index t_rw2_idx on t_rw2 (id);
cluster t_rw2 using t_rw2_idx;
select (rowid).rowno, id from t_rw2 order by id;

-- ALTER TABLE ... ALTER COLUMN TYPE (the heap is rebuilt row by row)
alter table t_rw2 alter column v type varchar(100);
select (rowid).rowno, id from t_rw2 order by id;

-- Cached ROWIDs must still locate the rows after the rewrites above
create temp table cached_rids as select rowid as rid from t_rw2 where id in (1, 3);
alter table t_rw2 alter column v type varchar(200);
select count(*) from t_rw2 where rowid in (select rid from cached_rids);

-- A fresh insert after a rewrite must get the *next* sequence value,
-- not collide with the preserved ones (rowid 3 in this case).
alter table t_rw2 add column extra text;
insert into t_rw2 values (6, 'f', 'x');
select (rowid).rowno, id from t_rw2 where id in (3, 6) order by id;

-- REPACK (non-concurrent) also preserves ROWIDs
repack t_rw2;
select (rowid).rowno, id from t_rw2 order by id;

drop table t_rw2;
drop table t_rw;