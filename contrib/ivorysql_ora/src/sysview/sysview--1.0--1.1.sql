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
