--
-- dbms_assert.sql
--
-- tests for the DBMS_ASSERT package:
--   ENQUOTE_NAME / ENQUOTE_LITERAL / NOOP / SIMPLE_SQL_NAME /
--   QUALIFIED_SQL_NAME / SCHEMA_NAME / SQL_OBJECT_NAME
--

--
-- SIMPLE_SQL_NAME: valid names pass through unchanged
--
select dbms_assert.simple_sql_name('employees') as plain;
select dbms_assert.simple_sql_name('"Mixed Case"') as quoted;
select dbms_assert.simple_sql_name('_dollar$9') as odd_chars;
select dbms_assert.simple_sql_name('emp#1') as hash_char;
select dbms_assert.simple_sql_name('  employees  ') as outer_space;
select dbms_assert.simple_sql_name('测试') as multibyte;

-- not simple names
select dbms_assert.simple_sql_name('a b') as has_space;
select dbms_assert.simple_sql_name('9abc') as leading_digit;
select dbms_assert.simple_sql_name('a;drop table x') as injection;
select dbms_assert.simple_sql_name('a;') as trailing_semi;
select dbms_assert.simple_sql_name('"unterminated') as unterminated;
select dbms_assert.simple_sql_name('') as empty;
-- with empty strings preserved (not folded to NULL), '' hits the
-- explicit empty-input validation instead
set ivorysql.enable_emptystring_to_NULL = off;
select dbms_assert.simple_sql_name('') as empty_preserved;
set ivorysql.enable_emptystring_to_NULL = on;
select dbms_assert.simple_sql_name('a.b') as dotted;

--
-- QUALIFIED_SQL_NAME: dot-separated chains pass
--
select dbms_assert.qualified_sql_name('schema.table') as two_part;
select dbms_assert.qualified_sql_name('db.schema.table') as three_part;
select dbms_assert.qualified_sql_name('"S"."T"') as quoted_parts;

-- not qualified names
select dbms_assert.qualified_sql_name('a..b') as empty_part;
select dbms_assert.qualified_sql_name('a b.c') as space_in_part;
select dbms_assert.qualified_sql_name('a;') as trailing_semi;
select dbms_assert.qualified_sql_name('   ') as whitespace_only;
select dbms_assert.qualified_sql_name('""') as empty_quoted;

--
-- ENQUOTE_NAME: adds quotes to unquoted input, preserves valid quoted input,
-- validates embedded quote pairs, and upper-cases unquoted input by default
--
select dbms_assert.enquote_name('employees') as quoted;
select dbms_assert.enquote_name('employees', true) as capitalized;
select dbms_assert.enquote_name('MixedCase', false) as case_preserved;
select dbms_assert.enquote_name('MixedCase', true) as case_upper;
select dbms_assert.enquote_name('"Already"') as already_quoted;
select dbms_assert.enquote_name('"a""b"') as paired_quote;
select dbms_assert.enquote_name('a"b') as unpaired_quote;
select dbms_assert.enquote_name('SCOTT."EMP"') as qualified_quoted;
select dbms_assert.enquote_name('"SCOTT.EMP"') as quoted_period;

--
-- ENQUOTE_LITERAL: requires paired internal quotes and preserves input that
-- is already enclosed in single quotes
--
select dbms_assert.enquote_literal('it''''s') as paired_literal;
select dbms_assert.enquote_literal('plain') as plain_literal;
select dbms_assert.enquote_literal('''already quoted''') as already_quoted_literal;
select dbms_assert.enquote_literal('it''s') as unpaired_literal;

--
-- NOOP: returns the input untouched
--
select dbms_assert.noop('anything; goes -- here') as noop_out;

--
-- SCHEMA_NAME: must exist and be usable
--
select dbms_assert.schema_name('public') as public_schema;

-- Run as a non-owner, non-superuser so object_aclcheck cannot bypass ACL_USAGE.
create role dbms_assert_acl_user nosuperuser;
create schema dbms_assert_acl_test;
revoke all on schema dbms_assert_acl_test from public;
set role dbms_assert_acl_user;
select has_schema_privilege(current_user, 'dbms_assert_acl_test', 'USAGE') as has_usage;
select dbms_assert.schema_name('dbms_assert_acl_test') as no_usage_schema;
reset role;
drop schema dbms_assert_acl_test;
drop role dbms_assert_acl_user;

select dbms_assert.schema_name('no_such_schema_777') as missing_schema;
select dbms_assert.schema_name('a.b') as dotted_schema;

--
-- SQL_OBJECT_NAME: must be an existing SQL object (relation, function, or type)
--
create table assert_objects(id int);
select dbms_assert.object_name('assert_objects') as existing_table;
select dbms_assert.sql_object_name('assert_objects') as existing_table_oracle_name;
select dbms_assert.sql_object_name('pg_catalog.abs') as existing_function;
select dbms_assert.sql_object_name('pg_catalog.int4') as existing_type;
select dbms_assert.object_name('no_such_table_777') as missing_table;
select dbms_assert.sql_object_name('no_such_function_777') as missing_function;
drop table assert_objects;

--
-- SQL_OBJECT_NAME: all object kinds, like Oracle's ALL_OBJECTS
--
create table assert_kinds_tbl(id int);
create index assert_kinds_idx on assert_kinds_tbl(id);
create type assert_kinds_ty as (a int);
create sequence assert_kinds_seq;
create function assert_kinds_fn() returns int language sql as 'select 1';
/
create package assert_kinds_pkg is x integer; end;
/
select dbms_assert.sql_object_name('assert_kinds_tbl') as kind_table;
select dbms_assert.sql_object_name('assert_kinds_idx') as kind_index;
select dbms_assert.sql_object_name('assert_kinds_ty') as kind_type;
select dbms_assert.sql_object_name('assert_kinds_seq') as kind_sequence;
select dbms_assert.sql_object_name('assert_kinds_fn') as kind_function;
select dbms_assert.sql_object_name('assert_kinds_pkg') as kind_package;
select dbms_assert.sql_object_name('sys.dbms_assert') as sys_package;
-- a qualified name resolves by its longest visible prefix: trailing
-- components (package members, table columns) are not validated
select dbms_assert.sql_object_name('sys.dbms_assert.sql_object_name') as package_member;
select dbms_assert.sql_object_name('assert_kinds_tbl.id') as table_component;
select dbms_assert.sql_object_name('no_such_obj_777.component') as missing_prefix;
drop package assert_kinds_pkg;
drop function assert_kinds_fn();
drop sequence assert_kinds_seq;
drop type assert_kinds_ty;
drop table assert_kinds_tbl;

--
-- SQL_OBJECT_NAME: visibility follows privileges (Oracle ALL_OBJECTS
-- semantics: the owner, or any caller holding a privilege on the object)
--
create role assert_vis_owner nosuperuser;
create role assert_vis_peer nosuperuser;
create schema assert_vis_oth;
grant usage, create on schema assert_vis_oth to assert_vis_owner;
set role assert_vis_owner;
create table assert_vis_oth.secure_tbl(id int);
reset role;
set role assert_vis_peer;
select dbms_assert.sql_object_name('assert_vis_oth.secure_tbl') as no_privilege;
reset role;
grant select on assert_vis_oth.secure_tbl to assert_vis_peer;
set role assert_vis_peer;
select dbms_assert.sql_object_name('assert_vis_oth.secure_tbl') as with_privilege;
reset role;
drop table assert_vis_oth.secure_tbl;
drop schema assert_vis_oth;
drop role assert_vis_peer;
drop role assert_vis_owner;
