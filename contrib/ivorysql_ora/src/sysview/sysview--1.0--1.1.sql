DO $$
DECLARE
	flag_type text;
BEGIN
	/* The existing flag columns use the VARCHAR2 type selected at install time. */
	SELECT pg_catalog.format('%I.%I', n.nspname, t.typname) INTO STRICT flag_type
	FROM pg_catalog.pg_attribute a
	JOIN pg_catalog.pg_type t ON t.oid = a.atttypid
	JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
	WHERE a.attrelid = 'sys.all_sequences'::pg_catalog.regclass
	  AND a.attname = 'scale_flag';

	EXECUTE pg_catalog.format($view$
CREATE OR REPLACE VIEW sys.all_sequences WITH (security_barrier = true) AS
SELECT
	c.relowner::regrole AS sequence_owner,
	c.relname AS sequence_name,
	s.seqmin AS min_value,
	s.seqmax AS max_value,
	s.seqincrement AS increment_by,
	s.seqcycle AS cycle_flag,
	NULL AS order_flag,
	s.seqcache AS cache_size,
	CASE
		WHEN pg_catalog.has_sequence_privilege(c.oid, 'SELECT,USAGE'::text)
			THEN pg_catalog.pg_sequence_last_value(c.oid::regclass)
		ELSE NULL::bigint
	END AS last_number,
	(CASE WHEN sys.bitand(s.flags, 16) = 16 THEN 'Y' ELSE 'N' END)::%1$s AS scale_flag,
	(CASE WHEN sys.bitand(s.flags, 2048) = 2048 THEN 'Y' ELSE 'N' END)::%1$s AS extend_flag,
	NULL AS shared_flag,
	(CASE WHEN sys.bitand(s.flags, 64) = 64 THEN 'Y' ELSE 'N' END)::%1$s AS session_flag,
	NULL AS keep_value
FROM pg_catalog.pg_sequence s
JOIN pg_catalog.pg_class c ON s.seqrelid = c.oid
WHERE pg_catalog.has_schema_privilege(c.relnamespace, 'USAGE')
  AND NOT pg_catalog.pg_is_other_temp_schema(c.relnamespace)
  AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
       OR pg_catalog.has_sequence_privilege(c.oid, 'SELECT,USAGE,UPDATE'::text))
	$view$, flag_type);
END
$$ LANGUAGE plpgsql;

GRANT SELECT ON sys.all_sequences TO PUBLIC;

DO $$
DECLARE
	varchar2_type text;
BEGIN
	/* Keep the view's existing VARCHAR2 byte or character semantics. */
	SELECT pg_catalog.format('%I.%I', n.nspname, t.typname) INTO STRICT varchar2_type
	FROM pg_catalog.pg_attribute a
	JOIN pg_catalog.pg_type t ON t.oid = a.atttypid
	JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
	WHERE a.attrelid = 'sys.all_source'::pg_catalog.regclass
	  AND a.attname = 'name';

	/* Preserve the original DBA_SOURCE.TEXT collation inherited from prosrc. */
	EXECUTE pg_catalog.format($view$
CREATE OR REPLACE VIEW sys.dba_source AS
SELECT
	sys.ora_case_trans(pg_catalog.pg_get_userbyid(p.proowner)::%1$s)::%1$s(128) AS owner,
	sys.ora_case_trans(p.proname::%1$s)::%1$s(128) AS name,
	(CASE WHEN p.prokind = 'f' THEN 'FUNCTION' ELSE 'PROCEDURE' END)::%1$s(12) AS type,
	l.line::sys.number AS line,
	l.text::%1$s(4000) COLLATE pg_catalog.U&"C" AS text,
	0::%1$s(256) AS origin_con_id
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_trigger t ON p.oid = t.tgfoid
CROSS JOIN LATERAL pg_catalog.string_to_table(
	pg_catalog.substring(pg_catalog.pg_get_functiondef(p.oid),
		pg_catalog.length('CREATE OR REPLACE ') + 1), pg_catalog.chr(10))
	WITH ORDINALITY AS l(text, line)
WHERE p.prokind IN ('p', 'f')
  AND t.oid IS NULL
  AND p.pronamespace NOT IN ('pg_catalog'::pg_catalog.regnamespace,
							 'pg_toast'::pg_catalog.regnamespace,
							 'information_schema'::pg_catalog.regnamespace)
	$view$, varchar2_type);

	EXECUTE pg_catalog.format($view$
CREATE OR REPLACE VIEW sys.all_source WITH (security_barrier = true) AS
SELECT
	sys.ora_case_trans(pg_catalog.pg_get_userbyid(p.proowner)::%1$s)::%1$s(128) AS owner,
	sys.ora_case_trans(p.proname::%1$s)::%1$s(128) AS name,
	(CASE WHEN p.prokind = 'f' THEN 'FUNCTION' ELSE 'PROCEDURE' END)::%1$s(12) AS type,
	pg_catalog.generate_series(1, sys._ora_src_count(p.oid))::sys.number AS line,
	pg_catalog.unnest(pg_catalog.string_to_array(
		pg_catalog.substring(pg_catalog.pg_get_functiondef(p.oid),
			pg_catalog.length('CREATE OR REPLACE ') + 1), pg_catalog.chr(10)))::%1$s(4000) AS text,
	0::%1$s(256) AS origin_con_id
FROM pg_catalog.pg_proc p
LEFT JOIN pg_catalog.pg_trigger t ON p.oid = t.tgfoid
WHERE p.prokind IN ('p', 'f')
  AND t.oid IS NULL
  AND p.pronamespace NOT IN ('pg_catalog'::pg_catalog.regnamespace,
							 'pg_toast'::pg_catalog.regnamespace,
							 'information_schema'::pg_catalog.regnamespace)
  AND pg_catalog.has_schema_privilege(p.pronamespace, 'USAGE')
  AND pg_catalog.has_function_privilege(p.oid, 'EXECUTE')
UNION ALL
SELECT
	sys.ora_case_trans(pg_catalog.pg_get_userbyid(p.pkgowner)::%1$s)::%1$s(128),
	p.pkgname::%1$s(128),
	s.type::%1$s(12),
	l.line::sys.number,
	l.text::%1$s(4000) COLLATE pg_catalog.default,
	0::%1$s(256)
FROM pg_catalog.pg_package p
LEFT JOIN pg_catalog.pg_package_body b
	ON b.pkgoid = p.oid AND pg_catalog.pg_has_role(p.pkgowner, 'USAGE')
/* Use catalog names and lowercase type labels for package lookups. */
CROSS JOIN LATERAL (VALUES ('package', p.pkgsrc), ('package body', b.bodysrc)) AS s(type, source)
CROSS JOIN LATERAL pg_catalog.string_to_table(s.source, pg_catalog.chr(10))
	WITH ORDINALITY AS l(text, line)
WHERE pg_catalog.has_schema_privilege(p.pkgnamespace, 'USAGE')
  AND pg_catalog.has_package_privilege(p.oid, 'EXECUTE')
  AND NOT pg_catalog.pg_is_other_temp_schema(p.pkgnamespace)
	$view$, varchar2_type);
END
$$ LANGUAGE plpgsql;
