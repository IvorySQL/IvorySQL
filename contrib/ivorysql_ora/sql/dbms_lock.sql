--
-- dbms_lock.sql
--
-- tests for DBMS_LOCK
--
call dbms_lock.sleep(1);
create table handle(h text);
--
-- test DBMS_LOCK.S
--
begin;
declare
 v_lockname varchar2(10) = 'LOCKS';
 v_handle text;
 v_rc int;
begin
 dbms_lock.allocate_unique(v_lockname, v_handle);
 v_rc := dbms_lock.request(v_handle, dbms_lock.s_mode, 0);  
 raise notice 'request rc=%', v_rc;
 assert v_rc = 0, format('DBMS_LOCK.request failed: rc=%s', v_rc);
 insert into handle values(v_handle);
end;
/
do
$$
declare
 v_lockmode text;
begin
 select mode into v_lockmode from pg_locks where pid = pg_backend_pid() and locktype ='advisory' and mode = 'ShareLock';
  if not found then
  v_lockmode := 'not found';
 end if;
 raise notice 'mode=%', v_lockmode;
end
$$;
--
declare
 v_rc int;
 v_handle text;
begin
 select h into v_handle from handle;
 v_rc := dbms_lock.release(v_handle); 
 raise notice 'release rc=%', v_rc;
 assert v_rc = 0, format('DBMS_LOCK.release failed: rc=%s', v_rc);
 delete from handle;
end;
/
do
$$
declare
 v_lockmode text;
begin
 select mode into v_lockmode from pg_locks where pid = pg_backend_pid() and locktype ='advisory' and mode = 'ShareLock';
 if not found then
  v_lockmode := 'not found';
 end if;
 raise notice 'mode=%', v_lockmode;
end
$$;
--
commit;
--
-- test DBMS_LOCK.X
--
begin;
declare
 v_lockname varchar2(10) = 'LOCKX';
 v_handle text;
 v_rc int;
begin
 dbms_lock.allocate_unique(v_lockname, v_handle);
 v_rc := dbms_lock.request(v_handle, dbms_lock.x_mode, 0);  
 raise notice 'request rc=%', v_rc;
 assert v_rc = 0, format('DBMS_LOCK.request failed: rc=%s', v_rc);
 insert into handle values(v_handle);
end;
/
do
$$
declare
 v_lockmode text;
begin
 select mode into v_lockmode from pg_locks where pid = pg_backend_pid() and locktype='advisory' and mode = 'ExclusiveLock';
 if not found then
  v_lockmode := 'not found';
 end if;
 raise notice 'mode=%', v_lockmode;
end
$$;
--
declare
 v_rc int;
 v_handle text;
begin
 select h into v_handle from handle;
 v_rc := dbms_lock.release(v_handle); 
 raise notice 'release rc=%', v_rc;
 assert v_rc = 0, format('DBMS_LOCK.release failed: rc=%s', v_rc);
 delete from handle;
end;
/
do
$$
declare
 v_lockmode text ;
begin
 select mode into v_lockmode from pg_locks where pid = pg_backend_pid() and locktype = 'advisory' and mode = 'ExclusiveLock';
 if not found then
  v_lockmode := 'not found';
 end if;
 raise notice 'mode=%', v_lockmode;
end
$$;
commit;
--
-- test DBMS_LOCK.REQUEST invalid lock modes return parameter_error (3)
--
select dbms_lock.request('invalid-mode-test-2604', 99, 0);
begin;
declare
 v_lockname varchar2(30) = 'LOCK_INVALID';
 v_handle text;
 v_rc int;
begin
 dbms_lock.allocate_unique(v_lockname, v_handle);
 v_rc := dbms_lock.request(v_handle, 99, 0);
 raise notice 'invalid mode 99 rc=%', v_rc;
 assert v_rc = dbms_lock.parameter_error, format('expected parameter_error (3), got rc=%s', v_rc);
 v_rc := dbms_lock.request(v_handle, 0, 0);
 raise notice 'invalid mode 0 rc=%', v_rc;
 assert v_rc = dbms_lock.parameter_error, format('expected parameter_error (3), got rc=%s', v_rc);
 v_rc := dbms_lock.request(v_handle, -1, 0);
 raise notice 'invalid mode -1 rc=%', v_rc;
 assert v_rc = dbms_lock.parameter_error, format('expected parameter_error (3), got rc=%s', v_rc);
 v_rc := dbms_lock.request(v_handle, 7, 0);
 raise notice 'invalid mode 7 rc=%', v_rc;
 assert v_rc = dbms_lock.parameter_error, format('expected parameter_error (3), got rc=%s', v_rc);
 v_rc := dbms_lock.request(v_handle, dbms_lock.s_mode, -1);
 raise notice 'negative timeout rc=%', v_rc;
 assert v_rc = dbms_lock.parameter_error, format('expected parameter_error (3), got rc=%s', v_rc);
 v_rc := dbms_lock.request(v_handle, 99, -1);
 raise notice 'invalid mode and negative timeout rc=%', v_rc;
 assert v_rc = dbms_lock.parameter_error, format('expected parameter_error (3), got rc=%s', v_rc);
 raise notice 'plisql block continued after invalid modes';
end;
/
do
$$
declare
 v_cnt int;
begin
 select count(*) into v_cnt from pg_locks where pid = pg_backend_pid() and locktype = 'advisory';
 raise notice 'advisory lock count after invalid modes=%', v_cnt;
end
$$;
declare
 v_lockname varchar2(30) = 'LOCK_INVALID';
 v_handle text;
 v_rc int;
begin
 dbms_lock.allocate_unique(v_lockname, v_handle);
 v_rc := dbms_lock.request(v_handle, dbms_lock.s_mode, 0);
 raise notice 'valid S after invalid rc=%', v_rc;
 assert v_rc = dbms_lock.success, format('expected success (0), got rc=%s', v_rc);
 v_rc := dbms_lock.release(v_handle);
 raise notice 'release S after invalid rc=%', v_rc;
 assert v_rc = dbms_lock.success, format('expected success (0), got rc=%s', v_rc);
 v_rc := dbms_lock.request(v_handle, dbms_lock.x_mode, 0);
 raise notice 'valid X after invalid rc=%', v_rc;
 assert v_rc = dbms_lock.success, format('expected success (0), got rc=%s', v_rc);
 v_rc := dbms_lock.release(v_handle);
 raise notice 'release X after invalid rc=%', v_rc;
 assert v_rc = dbms_lock.success, format('expected success (0), got rc=%s', v_rc);
end;
/
do
$$
declare
 v_cnt int;
begin
 select count(*) into v_cnt from pg_locks where pid = pg_backend_pid() and locktype = 'advisory';
 raise notice 'advisory lock count after release=%', v_cnt;
end
$$;
commit;
