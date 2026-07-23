\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS orafce;
DROP SCHEMA IF EXISTS migration CASCADE;
CREATE SCHEMA migration;
SET search_path TO migration, oracle, public, pg_catalog;
SET TIME ZONE 'UTC';
SET orafce.nls_date_format TO 'YYYY-MM-DD HH24:MI:SS';

CREATE TABLE migration.contract_results (
    case_id text PRIMARY KEY,
    actual jsonb,
    actual_type text NOT NULL
);

CREATE FUNCTION migration.record(case_name text, value anyelement)
RETURNS void
LANGUAGE sql
AS $function$
    INSERT INTO migration.contract_results(case_id, actual, actual_type)
    VALUES (case_name, to_jsonb(value), pg_typeof(value)::text)
$function$;

SELECT migration.record(
    'identity.plisql_language',
    EXISTS (SELECT FROM pg_language WHERE lanname = 'plisql')
);

CREATE TABLE migration.accounts (
    account_id bigint PRIMARY KEY,
    balance numeric(12,2),
    status text NOT NULL
);
INSERT INTO migration.accounts VALUES (101, NULL, 'OPEN');

CREATE PROCEDURE migration.apply_payment(p_account_id bigint, p_amount numeric)
LANGUAGE plisql
AS $procedure$
BEGIN
    UPDATE migration.accounts
       SET balance = oracle.nvl(balance, 0::numeric) + p_amount
     WHERE account_id = p_account_id;
END;
$procedure$;

CALL migration.apply_payment(101, 125.50);
SELECT migration.record(
    'plisql.orafce_nvl',
    (SELECT balance::text FROM migration.accounts WHERE account_id = 101)
);

SELECT migration.record(
    'date.add_months_eom',
    oracle.add_months(date '2024-01-31', 1)::date::text
);
SELECT migration.record(
    'date.last_day_leap',
    oracle.last_day(date '2024-02-10')::date::text
);
SELECT migration.record(
    'date.next_day_strict',
    oracle.next_day(date '2024-01-01', 'MONDAY')::date::text
);
SELECT migration.record(
    'date.months_between_eom',
    oracle.months_between(date '2024-02-29', date '2024-01-31') = 1
);
SELECT migration.record(
    'date.trunc_iso_week',
    oracle.trunc(date '2024-01-03', 'IW')::date::text
);
SELECT migration.record(
    'date.to_date_format',
    to_char(
        oracle.to_date('2024-05-19 17:23:53', 'YYYY-MM-DD HH24:MI:SS'),
        'YYYY-MM-DD HH24:MI:SS'
    )
);

SELECT migration.record('string.substr_negative', oracle.substr('abcdef'::text, -2, 2));
SELECT migration.record(
    'string.instr_occurrence',
    oracle.instr('CORPORATE FLOOR', 'OR', 1, 2)
);
SELECT migration.record('string.lpad_zero', oracle.lpad('7'::text, 5, '0'::text));
SELECT migration.record(
    'string.rtrim_character',
    oracle.rtrim('600.00'::text, '0'::text)
);
SELECT migration.record(
    'string.regexp_instr',
    oracle.regexp_instr('abc123def', '[0-9]+')
);
SELECT migration.record(
    'conversion.to_number',
    to_char(oracle.to_number('1234.50'), 'FM9999990.00')
);

SELECT migration.record('null.nvl', oracle.nvl(NULL::text, 'fallback'::text));
SELECT migration.record(
    'null.nvl2',
    oracle.nvl2('value'::text, 'present'::text, 'missing'::text)
);
SELECT migration.record(
    'null.decode',
    oracle.decode(2, 1, 'one'::text, 2, 'two'::text, 'other'::text)
);
SELECT migration.record('predicate.lnnvl_null', oracle.lnnvl(NULL::boolean));

SELECT migration.record('math.nanvl', oracle.nanvl('NaN'::numeric, 42::numeric)::text);
SELECT migration.record('math.bitand', oracle.bitand(6, 3));
SELECT migration.record('math.mod_zero', oracle.mod(10, 0));
SELECT migration.record(
    'aggregate.listagg',
    (SELECT oracle.listagg(value, ',' ORDER BY value)
       FROM (VALUES ('C'::text), ('A'::text), ('B'::text)) source(value))
);
SELECT migration.record(
    'aggregate.median',
    (SELECT oracle.median(value::double precision)::numeric(10,2)::text
       FROM (VALUES (1), (2), (3), (4)) source(value))
);

CREATE TABLE migration.oracle_types (
    code oracle.varchar2(4),
    label oracle.nvarchar2(2)
);
INSERT INTO migration.oracle_types VALUES ('éé', 'éé');

SELECT migration.record(
    'type.varchar2_name',
    (SELECT namespace.nspname || '.' || type.typname
       FROM pg_attribute attribute
       JOIN pg_class relation ON relation.oid = attribute.attrelid
       JOIN pg_namespace relation_namespace ON relation_namespace.oid = relation.relnamespace
       JOIN pg_type type ON type.oid = attribute.atttypid
       JOIN pg_namespace namespace ON namespace.oid = type.typnamespace
      WHERE relation_namespace.nspname = 'migration'
        AND relation.relname = 'oracle_types'
        AND attribute.attname = 'code')
);
SELECT migration.record(
    'type.varchar2_byte_semantics',
    (SELECT oracle.lengthb(code) FROM migration.oracle_types)
);
SELECT migration.record(
    'type.nvarchar2_name',
    (SELECT namespace.nspname || '.' || type.typname
       FROM pg_attribute attribute
       JOIN pg_class relation ON relation.oid = attribute.attrelid
       JOIN pg_namespace relation_namespace ON relation_namespace.oid = relation.relnamespace
       JOIN pg_type type ON type.oid = attribute.atttypid
       JOIN pg_namespace namespace ON namespace.oid = type.typnamespace
      WHERE relation_namespace.nspname = 'migration'
        AND relation.relname = 'oracle_types'
        AND attribute.attname = 'label')
);
SELECT migration.record(
    'type.nvarchar2_character_semantics',
    (SELECT char_length(label::text)::text || '/' || octet_length(label::text)::text
       FROM migration.oracle_types)
);

SELECT migration.record(
    'package.dbms_assert_literal',
    dbms_assert.enquote_literal('O''Reilly')::text
);
DO LANGUAGE plisql $block$
BEGIN
    PERFORM dbms_assert.simple_sql_name('unsafe;drop table accounts');
    PERFORM migration.record('package.dbms_assert_rejects_injection', false);
EXCEPTION
    WHEN OTHERS THEN
        PERFORM migration.record('package.dbms_assert_rejects_injection', true);
END;
$block$;

SELECT dbms_output.enable();
SELECT dbms_output.put_line('alpha');
SELECT dbms_output.put_line('beta');
SELECT migration.record(
    'package.dbms_output',
    (SELECT array_to_string(lines, '|') FROM dbms_output.get_lines(10))
);
SELECT migration.record(
    'package.dbms_random_range',
    value >= 10 AND value < 20
)
FROM (SELECT dbms_random.value(10, 20) AS value) sample;

SELECT migration.record('dictionary.dual', (SELECT count(*) FROM oracle.dual));
SELECT migration.record(
    'dictionary.user_tables',
    EXISTS (SELECT FROM oracle.user_tables WHERE table_name = 'accounts')
);
SELECT migration.record(
    'dictionary.user_tab_columns',
    (SELECT count(*) FROM oracle.user_tab_columns
      WHERE table_schema = 'migration' AND table_name = 'accounts')
);
SELECT migration.record(
    'dictionary.product_version',
    EXISTS (SELECT FROM oracle.product_component_version WHERE product = 'orafce')
);

CREATE TABLE migration.contacts (
    contact_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    display_name text
);
CREATE TRIGGER contacts_empty_string
BEFORE INSERT OR UPDATE ON migration.contacts
FOR EACH ROW EXECUTE FUNCTION oracle.replace_empty_strings();
INSERT INTO migration.contacts(display_name) VALUES ('');
SELECT migration.record(
    'semantics.empty_string_trigger',
    (SELECT display_name IS NULL FROM migration.contacts WHERE contact_id = 1)
);
