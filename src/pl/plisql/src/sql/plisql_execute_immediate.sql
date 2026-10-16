--
-- Tests for the Oracle-compatible EXECUTE IMMEDIATE statement
--

CREATE TABLE ei_test (id int, label text);

-- DDL through EXECUTE IMMEDIATE
do $$ begin
    execute immediate 'CREATE TABLE ei_ddl (id int)';
end $$;

select count(*) as ei_ddl_rows from ei_ddl;

-- DML with Oracle-style :n bind parameters
do $$ begin
    execute immediate 'INSERT INTO ei_test VALUES (:1, :2)' using 1, 'one';
    execute immediate 'INSERT INTO ei_test VALUES (:1, :2)' using 2, 'two';
end $$;

select id, label from ei_test order by id;

-- single-row query into a variable
do $$ declare
    n int;
begin
    execute immediate 'SELECT count(*) FROM ei_test' into n;
    raise notice 'count = %', n;
end $$;

-- INTO before USING (clauses in either order)
do $$ declare
    lbl text;
begin
    execute immediate 'SELECT label FROM ei_test WHERE id = :1'
        into lbl using 2;
    raise notice 'label = %', lbl;
end $$;

-- record target
do $$ declare
    r ei_test%ROWTYPE;
begin
    execute immediate 'SELECT * FROM ei_test WHERE id = :1' into r using 1;
    raise notice 'row = %, %', r.id, r.label;
end $$;

-- dynamic anonymous PL/iSQL block with a bind argument
do $$ begin
    execute immediate 'BEGIN INSERT INTO ei_test VALUES (:1, :2); END;'
        using 3, 'three';
end $$;

select count(*) as total from ei_test;

-- dynamic string built at runtime
do $$ declare
    v_sql text;
begin
    v_sql := 'UPDATE ei_test SET label = label || ''!'' WHERE id = ' || 2::text;
    execute immediate v_sql;
end $$;

select label from ei_test where id = 2;

-- NULL dynamic string
do $$ begin
    execute immediate null;
end $$;

-- plain EXECUTE keeps working and shares the same clauses
do $$ declare
    v int;
begin
    execute 'DELETE FROM ei_test WHERE id = 3';
    execute 'SELECT count(*) FROM ei_test' into v;
    raise notice 'after delete = %', v;
end $$;

DROP TABLE ei_test;
DROP TABLE ei_ddl;
