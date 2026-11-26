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

/* HEXTORAW returns bytea, which is also the base type of RAW and BLOB. */
CREATE FUNCTION sys.to_blob(pg_catalog.bytea)
RETURNS sys.blob
AS $$ SELECT $1::sys.blob; $$
LANGUAGE SQL
PARALLEL SAFE
STRICT
IMMUTABLE;

/* SUBSTR uses character positions; SUBSTRB below uses byte positions. */
CREATE FUNCTION sys.substr(text, pg_catalog.int4)
RETURNS text
AS 'MODULE_PATHNAME','ora_substr_no_length'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE FUNCTION sys.substr(text, pg_catalog.int4, pg_catalog.int4)
RETURNS text
AS 'MODULE_PATHNAME','ora_substr'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

/* Keep string literals as text when the position and length are fractional. */
CREATE FUNCTION sys.substr(pg_catalog.text, pg_catalog.float8, pg_catalog.float8)
RETURNS pg_catalog.text
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE
RETURN sys.substr($1, pg_catalog.trunc($2)::pg_catalog.int4,
                  pg_catalog.trunc($3)::pg_catalog.int4);

/* Float8-to-text conversion depends on extra_float_digits. */
CREATE FUNCTION sys.substr(pg_catalog.float8, pg_catalog.float8, pg_catalog.float8)
RETURNS pg_catalog.text
LANGUAGE SQL STABLE STRICT PARALLEL SAFE
RETURN sys.substr($1::pg_catalog.text, $2, $3);

CREATE FUNCTION sys.substr(pg_catalog.numeric, pg_catalog.float8, pg_catalog.float8)
RETURNS pg_catalog.text
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE
RETURN sys.substr($1::pg_catalog.text, $2, $3);

/* Preserve Oracle NUMBER precision instead of resolving it through float8. */
CREATE FUNCTION sys.substr(sys.number, pg_catalog.float8, pg_catalog.float8)
RETURNS pg_catalog.text
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE
RETURN sys.substr($1::pg_catalog.text, $2, $3);
