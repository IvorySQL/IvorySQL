/*
 * Match PostgreSQL's text signatures so the existing mode-specific search
 * path selects Oracle semantics for ordinary calls in Oracle mode.
 */
CREATE FUNCTION sys.regexp_like(text, text)
RETURNS bool
AS 'MODULE_PATHNAME', 'ora_regexp_like_no_flags'
LANGUAGE C
PARALLEL SAFE
STRICT
STABLE;

CREATE FUNCTION sys.regexp_like(text, text, text)
RETURNS bool
AS 'MODULE_PATHNAME', 'ora_regexp_like'
LANGUAGE C
PARALLEL SAFE
CALLED ON NULL INPUT
STABLE;

/*
 * The pre-existing VARCHAR2 signature depends on the length semantics used
 * when the extension was installed.  Preserve its identity while allowing a
 * NULL match_param to mean the default options.
 */
DO $$
DECLARE
    func regprocedure;
BEGIN
    FOR func IN
        SELECT p.oid::regprocedure
        FROM pg_catalog.pg_proc p
        WHERE p.pronamespace = 'sys'::regnamespace
          AND p.proname = 'regexp_like'
          AND p.pronargs = 3
          AND p.prosrc = 'ora_regexp_like'
          AND p.proisstrict
    LOOP
        EXECUTE pg_catalog.format('ALTER FUNCTION %s CALLED ON NULL INPUT', func);
    END LOOP;
END;
$$;

/* Resolve ordinary text calls to Oracle's NULL-aware replacement function. */
CREATE FUNCTION sys.replace(text, text, text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_replace'
LANGUAGE C
CALLED ON NULL INPUT
IMMUTABLE;
