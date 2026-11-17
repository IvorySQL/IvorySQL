-- Oracle-mode SELECT ... INTO must raise NO_DATA_FOUND / TOO_MANY_ROWS
create table plisql_sio_t (id int);
insert into plisql_sio_t values (1), (2);

do $$
declare
  v int := -99;
begin
  begin
    select id into v from plisql_sio_t where id = 42;
    raise notice 'zero rows: no error, v=%', v;
  exception
    when no_data_found then
      raise notice 'zero rows: caught NO_DATA_FOUND';
  end;

  begin
    select id into v from plisql_sio_t order by id;
    raise notice 'many rows: no error, v=%', v;
  exception
    when too_many_rows then
      raise notice 'many rows: caught TOO_MANY_ROWS';
  end;

  select id into v from plisql_sio_t where id = 2;
  raise notice 'one row: v=%', v;
end
$$;

drop table plisql_sio_t;
