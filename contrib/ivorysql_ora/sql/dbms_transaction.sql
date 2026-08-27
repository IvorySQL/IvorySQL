--
-- dbms_transaction.sql
--
-- tests for DBMS_TRANSACTION:
--   COMMIT / ROLLBACK, SAVEPOINT / ROLLBACK_SAVEPOINT,
--   READ_ONLY / READ_WRITE, LOCAL_TRANSACTION_ID,
--   legacy no-ops, and the documented-unsupported distributed
--   transaction recovery subprograms.
--

create table dbms_tx_t (id int, val varchar2(100));

--
-- COMMIT / ROLLBACK: valid only when the package procedure is invoked as a
-- top-level CALL (non-atomic context) -- same restriction as a bare
-- COMMIT/ROLLBACK statement inside a PL/iSQL procedure.

-- AUTOCOMMIT is default ON in psql
\set AUTOCOMMIT off
insert into dbms_tx_t values (0, 'committed');
call dbms_transaction.commit();
\set AUTOCOMMIT on
COMMIT;

insert into dbms_tx_t values (1, 'committed');
call dbms_transaction.commit();
select * from dbms_tx_t order by id;

insert into dbms_tx_t values (2, 'rolled back');
call dbms_transaction.rollback();
select * from dbms_tx_t order by id;

BEGIN
    insert into dbms_tx_t values (3, 'committed');
    dbms_transaction.commit();
    insert into dbms_tx_t values (4, 'rolled back');
    dbms_transaction.rollback();
END;
/
select * from dbms_tx_t order by id;

--
-- SAVEPOINT / ROLLBACK_SAVEPOINT: unlike COMMIT/ROLLBACK, these require an
-- explicit transaction block, same as a bare SQL SAVEPOINT statement.
--
call dbms_transaction.savepoint('sp_outside');

-- PG starts transactions explicitly while Oracle starts transactions implicityly
BEGIN;
    insert into dbms_tx_t values (5, 'before sp1');
    call dbms_transaction.savepoint('sp1');
    insert into dbms_tx_t values (6, 'after sp1, will be rolled back');
    call dbms_transaction.rollback_savepoint('sp1');
    insert into dbms_tx_t values (7, 'after rollback to sp1');
COMMIT;
select * from dbms_tx_t order by id;

-- nested savepoints: rolling back to the outer one undoes both
BEGIN;
    call dbms_transaction.savepoint('a');
    insert into dbms_tx_t values (8, 'a');
    call dbms_transaction.savepoint('b');
    insert into dbms_tx_t values (9, 'b');
    call dbms_transaction.rollback_savepoint('a');
    insert into dbms_tx_t values (10, 'after rollback to a');
COMMIT;
select * from dbms_tx_t order by id;

-- rollback to a savepoint that does not exist

BEGIN;
    call dbms_transaction.savepoint('a');
    insert into dbms_tx_t values (8, 'a');
    call dbms_transaction.savepoint('b');
    insert into dbms_tx_t values (9, 'b');
    call dbms_transaction.rollback_savepoint('a');
    insert into dbms_tx_t values (10, 'after rollback to a');
    call dbms_transaction.rollback_savepoint('b');
COMMIT;
select * from dbms_tx_t order by id;

BEGIN;
    call dbms_transaction.rollback_savepoint('does_not_exist');
ROLLBACK;

-- SAVEPOINT/ROLLBACK_SAVEPOINT also accept Oracle's named-parameter call
-- syntax now that the parameter is named "savept" (matching Oracle's
-- documented signature) instead of the "sp" name used previously.
begin;
insert into dbms_tx_t values (11, 'before named-param savepoint');
call dbms_transaction.savepoint(savept => 'sp_named');
insert into dbms_tx_t values (12, 'after named-param savepoint, will be rolled back');
call dbms_transaction.rollback_savepoint(savept => 'sp_named');
insert into dbms_tx_t values (13, 'after named-param rollback_savepoint');
commit;
select * from dbms_tx_t where id between 11 and 13 order by id;

--
-- READ_ONLY / READ_WRITE
--
BEGIN;
    call dbms_transaction.read_only();
    insert into dbms_tx_t values (14, 'blocked by read only');
ROLLBACK;

-- READ_WRITE as the first statement of a transaction is a no-op that must
-- not block subsequent writes.  (Switching a transaction back from read-only
-- to read-write after another statement has already run is a PostgreSQL
-- restriction -- "transaction read-write mode must be set before any
-- query" -- so that sequence is intentionally not exercised here.)
BEGIN;
    call dbms_transaction.read_write();
    insert into dbms_tx_t values (15, 'allowed with read_write');
COMMIT;
select * from dbms_tx_t where id = 15;

-- LOCAL_TRANSACTION_ID
select dbms_transaction.local_transaction_id() is null as no_xid_without_create from dual;
BEGIN;
    select dbms_transaction.local_transaction_id(true) is not null as xid_created from dual;
    select dbms_transaction.local_transaction_id() is not null as xid_now_visible from dual;
    -- calling again with create_transaction=true on an already-assigned
    -- transaction just returns the existing id, it does not assign a new one
    select dbms_transaction.local_transaction_id(true) = dbms_transaction.local_transaction_id() as xid_stable from dual;
COMMIT;

-- the transaction (and its id) ends with the commit above -- a fresh
-- transaction has no id again until something assigns one
select dbms_transaction.local_transaction_id() is null as no_xid_in_new_transaction from dual;

--
-- SAVEPOINT / ROLLBACK_SAVEPOINT: additional boundary conditions
--

-- NULL savepoint name is rejected explicitly by the C bridge, for both
-- SAVEPOINT and ROLLBACK_SAVEPOINT.
begin;
call dbms_transaction.savepoint(NULL);
rollback;
begin;
call dbms_transaction.rollback_savepoint(NULL);
rollback;

-- savepoint name length boundary: 255 bytes is accepted, 256 is rejected
-- (DBMS_TRANSACTION_SAVEPOINT_NAME_LEN in dbms_transaction.c is 256, so the
-- longest accepted name is 255 bytes).
begin;
call dbms_transaction.savepoint(repeat('x', 255));
call dbms_transaction.rollback_savepoint(repeat('x', 255));
rollback;
begin;
call dbms_transaction.savepoint(repeat('x', 256));
rollback;

-- an empty-string savepoint name hits the same "must not be NULL" error as
-- an explicit NULL: VARCHAR2 treats '' as NULL, and savept is declared
-- VARCHAR2, so the C bridge never sees a non-NULL empty string here.
begin;
call dbms_transaction.savepoint('');
rollback;

-- redefining the same savepoint name rolls back to the most recently
-- defined one, matching plain SQL SAVEPOINT semantics -- the first
-- definition's row is unaffected, only the row inserted after the second
-- "a" is undone.
begin;
insert into dbms_tx_t values (20, 'before first a');
call dbms_transaction.savepoint('a');
insert into dbms_tx_t values (21, 'after first a');
call dbms_transaction.savepoint('a');
insert into dbms_tx_t values (22, 'after second a, will be rolled back');
call dbms_transaction.rollback_savepoint('a');
commit;
select * from dbms_tx_t where id between 20 and 22 order by id;

-- rolling back to the same savepoint repeatedly is allowed each time --
-- ROLLBACK_SAVEPOINT does not release/consume the savepoint, so it can be
-- targeted again.
begin;
call dbms_transaction.savepoint('rep');
insert into dbms_tx_t values (23, 'first attempt, will be rolled back');
call dbms_transaction.rollback_savepoint('rep');
insert into dbms_tx_t values (23, 'second attempt, will also be rolled back');
call dbms_transaction.rollback_savepoint('rep');
commit;
select * from dbms_tx_t where id = 23;

-- ROLLBACK_SAVEPOINT called entirely outside a transaction block (no
-- enclosing BEGIN at all, unlike the "does_not_exist" case above which was
-- inside an explicit BEGIN) must raise the same kind of ordinary error as
-- ROLLBACK TO SAVEPOINT would, not crash the backend.
call dbms_transaction.rollback_savepoint('never_defined');

-- savepoint names are opaque text, not SQL identifiers -- whitespace is
-- accepted without quoting games.
begin;
call dbms_transaction.savepoint('sp with space');
insert into dbms_tx_t values (24, 'will be rolled back');
call dbms_transaction.rollback_savepoint('sp with space');
commit;
select * from dbms_tx_t where id = 24;

--
-- READ_ONLY / READ_WRITE: switching modes within one transaction
--

-- switching from read-only back to read-write in the same transaction hits
-- PostgreSQL's "must be set before any query" restriction, because
-- READ_ONLY's own SET TRANSACTION READ ONLY already counts as a query.
begin;
call dbms_transaction.read_only();
call dbms_transaction.read_write();
rollback;

-- the reverse direction -- read-write down to read-only -- is always
-- allowed, since it only narrows what the transaction can do.
begin;
call dbms_transaction.read_write();
call dbms_transaction.read_only();
select current_setting('transaction_read_only');
rollback;

--
-- COMMIT/ROLLBACK: atomic context (nested inside another procedure's CALL)
--

-- COMMIT/ROLLBACK are only valid as the top-level CALL; invoking them from
-- inside a procedure that is itself being CALLed (so the whole thing runs
-- atomically) must raise an error instead of silently no-op'ing.
create or replace procedure dbms_tx_wrapper_commit() as
begin
    dbms_transaction.commit();
end;
/
begin;
call dbms_tx_wrapper_commit();
rollback;
drop procedure dbms_tx_wrapper_commit();

-- SAVEPOINT/ROLLBACK_SAVEPOINT: the nested-call guard must not be bypassable
-- by setting plisql.inside_autonomous_transaction directly.  That GUC is
-- PGC_USERSET (dblink's own connection has to be able to set it), so an
-- ordinary session can set it to "on" without ever going through the
-- autonomous-transaction machinery -- the guard must still reject a nested
-- SAVEPOINT/ROLLBACK_SAVEPOINT call in that case, not fall through to
-- DefineSavepoint()/RollbackToSavepoint().
create or replace procedure dbms_tx_wrapper_savepoint() as
begin
    dbms_transaction.savepoint('should_not_be_reached');
end;
/
set plisql.inside_autonomous_transaction = true;
begin;
call dbms_tx_wrapper_savepoint();
rollback;
reset plisql.inside_autonomous_transaction;
drop procedure dbms_tx_wrapper_savepoint();

--
-- Skip the autonomous-transaction section entirely if dblink isn't even
-- installable in this environment, instead of letting CREATE EXTENSION
-- error out and cascade into a wall of unrelated failures below.
--
SELECT count(*) > 0 AS have_dblink
FROM pg_available_extensions WHERE name = 'dblink' \gset

\if :have_dblink
    --
    -- The autonomous-transaction tests below run PRAGMA AUTONOMOUS_TRANSACTION
    -- procedures via dblink.  dblink's connection string (built in
    -- pl_autonomous.c) has no explicit "user=", so libpq falls back to
    -- whatever OS user the postgres server process itself is running as --
    -- if no role of that name exists, every autonomous-transaction test below
    -- would fail with an unrelated connection error instead of testing what
    -- it's meant to.  Probe the same loopback connection here and create the
    -- missing role up front if that's the problem.
    --
    CREATE EXTENSION IF NOT EXISTS dblink;

    DO $$
    DECLARE
        missing_role text;
        probe_connstr text;
        err_detail    text;
    BEGIN
        -- mirror pl_autonomous.c's own connection string exactly: dbname + port,
        -- no user=
        probe_connstr := 'dbname=' || current_database()
                        || ' port=' || current_setting('port');
                        
        PERFORM dblink_connect('dbms_tx_probe', probe_connstr);
        PERFORM dblink_disconnect('dbms_tx_probe');
    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS err_detail = PG_EXCEPTION_DETAIL;
            missing_role := substring(err_detail FROM 'role "([^"]+)" does not exist');
            IF missing_role IS NOT NULL THEN
                EXECUTE format('CREATE ROLE %I LOGIN SUPERUSER', missing_role);
                -- record it so the cleanup block below knows to drop it again
                PERFORM set_config('dbms_tx_test.created_role', missing_role, false);
            ELSE
                RAISE;  -- some other, unrelated connection problem -- don't hide it
            END IF;
    END;    
    $$;

    -- LOCAL_TRANSACTION_ID: an autonomous transaction gets its own transaction
    -- id, distinct from (and independent of) the calling transaction's id --
    -- and the autonomous insert is visible immediately, before the outer
    -- transaction commits.
    create table dbms_tx_autonomous (which text, xid text);

    create or replace procedure dbms_tx_autonomous_xid() as
    pragma autonomous_transaction;
    begin
        insert into dbms_tx_autonomous values ('inner', dbms_transaction.local_transaction_id(true));
    end;
    /

    begin;
    insert into dbms_tx_autonomous values ('outer', dbms_transaction.local_transaction_id(true));
    call dbms_tx_autonomous_xid();
    select which, xid is not null as has_xid from dbms_tx_autonomous order by which;
    commit;
    select count(distinct xid) = 2 as outer_and_inner_xids_differ from dbms_tx_autonomous;

    -- the autonomous insert survives even though the calling transaction rolls
    -- back -- COMMIT/ROLLBACK of the outer transaction have no effect on it.
    truncate dbms_tx_autonomous;
    begin;
    insert into dbms_tx_autonomous values ('outer_rolled_back', dbms_transaction.local_transaction_id(true));
    call dbms_tx_autonomous_xid();
    rollback;
    select which from dbms_tx_autonomous order by which;

    drop procedure dbms_tx_autonomous_xid();
    drop table dbms_tx_autonomous;

    --
    -- SAVEPOINT / ROLLBACK_SAVEPOINT / COMMIT / ROLLBACK inside an autonomous
    -- transaction: the dblink call that executes the autonomous procedure is a
    -- single bare "CALL proc();" with no surrounding BEGIN, so from that
    -- session's point of view there is no explicit transaction block --
    -- SAVEPOINT/ROLLBACK_SAVEPOINT there fail the same way a bare top-level
    -- SAVEPOINT statement would (see "call dbms_transaction.savepoint('sp_outside')"
    -- above).  COMMIT/ROLLBACK are still invoked from within the autonomous
    -- procedure's own body (a nested CALL to dbms_transaction.commit()/rollback()),
    -- so they hit the same "invalid transaction termination" restriction as any
    -- other nested CALL -- PRAGMA AUTONOMOUS_TRANSACTION does not change either
    -- restriction.
    --
    create or replace procedure dbms_tx_autonomous_savepoint() as
    pragma autonomous_transaction;
    begin
        dbms_transaction.savepoint('autosp');
    end;
    /
    call dbms_tx_autonomous_savepoint();
    drop procedure dbms_tx_autonomous_savepoint();

    create or replace procedure dbms_tx_autonomous_rbsp() as
    pragma autonomous_transaction;
    begin
        dbms_transaction.rollback_savepoint('autosp');
    end;
    /
    call dbms_tx_autonomous_rbsp();
    drop procedure dbms_tx_autonomous_rbsp();

    create or replace procedure dbms_tx_autonomous_commit() as
    pragma autonomous_transaction;
    begin
        insert into dbms_tx_t values (900, 'should not be committed');
        dbms_transaction.commit();
    end;
    /
    call dbms_tx_autonomous_commit();
    select * from dbms_tx_t where id = 900;
    drop procedure dbms_tx_autonomous_commit();

    create or replace procedure dbms_tx_autonomous_rollback() as
    pragma autonomous_transaction;
    begin
        insert into dbms_tx_t values (901, 'should error before rollback runs');
        dbms_transaction.rollback();
    end;
    /
    call dbms_tx_autonomous_rollback();
    select * from dbms_tx_t where id = 901;
    drop procedure dbms_tx_autonomous_rollback();

    --
    -- READ_ONLY / READ_WRITE inside an autonomous transaction: these are plain
    -- SET TRANSACTION statements and do not need an explicit transaction block,
    -- so (unlike SAVEPOINT/COMMIT above) they work the same as at the top level.
    --
    create or replace procedure dbms_tx_autonomous_readonly() as
    pragma autonomous_transaction;
    begin
        dbms_transaction.read_only();
        insert into dbms_tx_t values (902, 'blocked by autonomous read_only');
    end;
    /
    call dbms_tx_autonomous_readonly();
    select * from dbms_tx_t where id = 902;
    drop procedure dbms_tx_autonomous_readonly();

    create or replace procedure dbms_tx_autonomous_readwrite() as
    pragma autonomous_transaction;
    begin
        dbms_transaction.read_write();
        insert into dbms_tx_t values (903, 'allowed by autonomous read_write, autocommitted');
    end;
    /
    call dbms_tx_autonomous_readwrite();
    select * from dbms_tx_t where id = 903;
    drop procedure dbms_tx_autonomous_readwrite();


    --
    -- Clean up: drop the role again, but only if this script is the one that
    -- created it -- never drop a role that already existed before we got here.
    -- Note: no "<> ''" check alongside IS NOT NULL -- Oracle-compat mode's
    -- empty-string-is-NULL semantics turns such a comparison into NULL, which
    -- IF treats as not-satisfied, silently skipping the DROP.
    --
    DO $$
    DECLARE
        r text := current_setting('dbms_tx_test.created_role', true);
    BEGIN 
        IF r IS NOT NULL THEN
            EXECUTE format('DROP ROLE %I', r);
        END IF;
    END;
    $$;
\else
    \echo 'dblink is not available in this environment, skipping DBMS_TRANSACTION autonomous-transaction tests'
\endif
--
-- Cross-user execution: the package must be callable by any role, not just
-- the owner/superuser that ran CREATE EXTENSION, and it must run with the
-- caller's own privileges (AUTHID CURRENT_USER) rather than the package
-- owner's -- this is what Oracle's own documentation for DBMS_TRANSACTION
-- promises ("all subprograms ... run with the privileges of the calling
-- user, rather than the package owner SYS").
--
create role regress_dbms_tx_other_user login;
create table regress_dbms_tx_other_user_t (id int);
grant all on regress_dbms_tx_other_user_t to regress_dbms_tx_other_user;

set session authorization regress_dbms_tx_other_user;
select current_user;

-- no explicit GRANT needed: EXECUTE on the package is granted to PUBLIC
-- when dbms_transaction is installed
select dbms_transaction.local_transaction_id() is null as no_xid_without_create;

begin;
select dbms_transaction.local_transaction_id(true) is not null as xid_created;
call dbms_transaction.savepoint('other_user_sp');
call dbms_transaction.rollback_savepoint('other_user_sp');
commit;

-- COMMIT/ROLLBACK also work for a non-owner role, same as for the owner
insert into regress_dbms_tx_other_user_t values (1);
call dbms_transaction.commit();
insert into regress_dbms_tx_other_user_t values (2);
call dbms_transaction.rollback();
select * from regress_dbms_tx_other_user_t order by id;

-- READ_ONLY/READ_WRITE also work for a non-owner role
begin;
call dbms_transaction.read_only();
insert into regress_dbms_tx_other_user_t values (3);
rollback;

begin;
call dbms_transaction.read_write();
insert into regress_dbms_tx_other_user_t values (4);
commit;
select * from regress_dbms_tx_other_user_t order by id;

reset session authorization;
drop table regress_dbms_tx_other_user_t;
drop role regress_dbms_tx_other_user;

drop table dbms_tx_t;
