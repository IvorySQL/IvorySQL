/* Use NUMBER's default representation without fractional trailing zeros. */
CREATE OR REPLACE FUNCTION sys.number_out(sys.number)
RETURNS cstring
AS 'MODULE_PATHNAME', 'ora_number_out'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;

/*
 * Oracle LIKE relabels CHAR operands to the binary-compatible PG bpchar type.
 * Preserve pattern and escape padding instead of invoking bpchar's trimming
 * cast to text.  The shared C implementations accept either varlena layout.
 */
CREATE FUNCTION sys.like_escape(pg_catalog.bpchar)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_like_escape_noescape'
LANGUAGE C PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.like_escape(pg_catalog.bpchar, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_like_escape'
LANGUAGE C PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.like_escape(text, pg_catalog.bpchar)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_like_escape'
LANGUAGE C PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.like_escape(pg_catalog.bpchar, pg_catalog.bpchar)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_like_escape'
LANGUAGE C PARALLEL SAFE STRICT IMMUTABLE;

/* Keep default TO_CHAR on the binary floating-point formatting path. */
CREATE FUNCTION sys.to_char(sys.binary_float)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME', 'binary_float_to_char'
LANGUAGE C PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.to_char(sys.binary_double)
RETURNS sys.oravarcharchar
AS 'MODULE_PATHNAME', 'binary_double_to_char'
LANGUAGE C PARALLEL SAFE STRICT IMMUTABLE;

/*
 * BINARY_DOUBLE is a preferred numeric type.  Keep existing native numeric
 * calls on their original NUMBER conversion path instead of widening them
 * to a binary floating-point argument during overload resolution.
 */
CREATE FUNCTION sys.to_char(pg_catalog.int2)
RETURNS sys.oravarcharchar
AS 'SELECT sys.to_char($1::sys.number)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.to_char(pg_catalog.int4)
RETURNS sys.oravarcharchar
AS 'SELECT sys.to_char($1::sys.number)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.to_char(pg_catalog.int8)
RETURNS sys.oravarcharchar
AS 'SELECT sys.to_char($1::sys.number)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.to_char(pg_catalog.float4)
RETURNS sys.oravarcharchar
AS 'SELECT sys.to_char($1::sys.number)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.to_char(pg_catalog.float8)
RETURNS sys.oravarcharchar
AS 'SELECT sys.to_char($1::sys.number)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.to_char(pg_catalog.numeric)
RETURNS sys.oravarcharchar
AS 'SELECT sys.to_char($1::sys.number)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

/* These integer calls previously widened to the preferred BINARY_DOUBLE. */
CREATE FUNCTION sys.length(pg_catalog.int2)
RETURNS pg_catalog.int4
AS 'SELECT sys.length($1::pg_catalog.text)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;

CREATE FUNCTION sys.length(pg_catalog.int8)
RETURNS pg_catalog.int4
AS 'SELECT sys.length($1::pg_catalog.text)'
LANGUAGE SQL PARALLEL SAFE STRICT IMMUTABLE;
