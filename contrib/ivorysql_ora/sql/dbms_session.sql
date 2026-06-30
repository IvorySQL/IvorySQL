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
-- Case-insensitivity: Oracle folds namespace/attribute to upper case, so a
-- value set with one case is readable in any case, an overwrite in a different
-- case hits the same entry, and CLEAR matches regardless of case.
--
call dbms_session.set_context('app_ctx', 'mixedAttr', 'mval');
select sys_context('APP_CTX', 'MIXEDATTR') as upper_read,
       sys_context('app_ctx', 'mixedattr') as lower_read,
       sys_context('App_Ctx', 'MixedAttr') as mixed_read;
-- overwrite through a different case reaches the same entry
call dbms_session.set_context('APP_CTX', 'MIXEDATTR', 'mval2');
select sys_context('app_ctx', 'mixedattr') as overwritten;
-- clear single attribute using a different case
call dbms_session.clear_context('app_ctx', 'MIXEDATTR');
select sys_context('app_ctx', 'mixedattr') is null as attr_cleared;
-- clear whole namespace using a different case
call dbms_session.set_context('Ns2', 'a', '1');
call dbms_session.clear_context('NS2');
select sys_context('ns2', 'a') is null as ns2_cleared;

-- read path: an over-long name (>= 256 bytes) cannot match any stored key,
-- so SYS_CONTEXT returns NULL instead of raising an error (usable in predicates)
select sys_context(repeat('x', 300), 'attr') is null as overlong_ns_is_null;
select sys_context('app_ctx', repeat('y', 300)) is null as overlong_attr_is_null;

--
-- LIST_CONTEXT (order by for stable output).
-- Note: stored names are folded to upper case, matching Oracle.
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

--
-- RESET_PACKAGE: resets all PL/iSQL package state in the session
--
-- Smoke test: call with no user-defined package state initialized
call dbms_session.reset_package();

-- Create a package with mutable state to verify the reset
CREATE OR REPLACE PACKAGE rp_pkg IS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END rp_pkg;
/

CREATE OR REPLACE PACKAGE BODY rp_pkg IS
    FUNCTION get_n RETURN NUMBER AS
    BEGIN
        RETURN g_n;
    END;
    FUNCTION set_n(n NUMBER) RETURN NUMBER AS
    BEGIN
        g_n := n;
        RETURN n;
    END;
END rp_pkg;
/

-- Mutate package state
SELECT rp_pkg.set_n(42);
SELECT rp_pkg.get_n;

-- RESET_PACKAGE marks every package uninitialized; next access re-runs package init
call dbms_session.reset_package();
SELECT rp_pkg.get_n;

-- reset_package must not touch application-context values (non-package session state)
call dbms_session.set_context('rp_ns', 'key', 'preserved');
call dbms_session.reset_package();
select sys_context('rp_ns', 'key') as ctx_after_reset;

DROP PACKAGE rp_pkg;
