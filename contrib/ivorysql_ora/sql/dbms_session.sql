--
-- dbms_session.sql
--
-- tests for DBMS_SESSION application context subset:
--   SET_CONTEXT / CLEAR_CONTEXT / CLEAR_ALL_CONTEXT / LIST_CONTEXT
-- and integration with SYS_CONTEXT (incl. row-level security).
--

--
-- SET_CONTEXT + SYS_CONTEXT read-back
--
call dbms_session.set_context('app_ctx', 'user_id', '42');
call dbms_session.set_context('app_ctx', 'role', 'manager');
select sys_context('app_ctx', 'user_id') as user_id,
       sys_context('app_ctx', 'role')    as role;

-- overwrite an existing attribute
call dbms_session.set_context('app_ctx', 'user_id', '99');
select sys_context('app_ctx', 'user_id') as user_id;

-- unknown attribute / namespace returns NULL
select sys_context('app_ctx', 'missing') is null as missing_is_null;
select sys_context('no_such_ns', 'x') is null as ns_is_null;

--
-- LIST_CONTEXT (order by for stable output)
--
call dbms_session.set_context('other_ns', 'k1', 'v1');
select * from sys.dbms_session_list_context() order by namespace, attribute;

--
-- CLEAR_CONTEXT: single attribute
--
call dbms_session.clear_context('app_ctx', 'role');
select sys_context('app_ctx', 'role') is null as role_cleared;
select sys_context('app_ctx', 'user_id') as user_id_still_there;

--
-- CLEAR_CONTEXT: whole namespace (attribute omitted)
--
call dbms_session.clear_context('app_ctx');
select sys_context('app_ctx', 'user_id') is null as app_ctx_cleared;
-- other_ns is untouched
select sys_context('other_ns', 'k1') as other_ns_value;

--
-- CLEAR_ALL_CONTEXT
--
call dbms_session.clear_all_context('other_ns');
select sys_context('other_ns', 'k1') is null as other_ns_cleared;
select count(*) as remaining from sys.dbms_session_list_context();

--
-- Row-level security driven by application context.
-- Queries run as a non-superuser role so RLS is actually enforced
-- (superusers and table owners bypass RLS).  SET ROLE keeps the same
-- backend session, so the context set above remains visible.
--
create table docs (id int, owner text, body text);
insert into docs values (1, 'alice', 'a-doc'), (2, 'bob', 'b-doc');
alter table docs enable row level security;
create policy p_owner on docs using (owner = sys_context('app', 'usr'));
create role dbms_sess_rls nosuperuser;
grant select on docs to dbms_sess_rls;

call dbms_session.set_context('app', 'usr', 'alice');
set role dbms_sess_rls;
select * from docs order by id;          -- only alice's row
reset role;

call dbms_session.set_context('app', 'usr', 'bob');
set role dbms_sess_rls;
select * from docs order by id;          -- only bob's row
reset role;

call dbms_session.clear_context('app');
set role dbms_sess_rls;
select * from docs order by id;          -- predicate NULL -> no rows
reset role;

--
-- DISCARD ALL clears session context (connection-pool safety)
--
call dbms_session.set_context('app', 'usr', 'carol');
select sys_context('app', 'usr') as before_discard;
discard all;
select sys_context('app', 'usr') is null as after_discard;

drop table docs;
drop role dbms_sess_rls;
