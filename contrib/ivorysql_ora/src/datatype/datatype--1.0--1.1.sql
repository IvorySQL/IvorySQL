/* Use NUMBER's default representation without fractional trailing zeros. */
CREATE OR REPLACE FUNCTION sys.number_out(sys.number)
RETURNS cstring
AS 'MODULE_PATHNAME', 'ora_number_out'
LANGUAGE C
PARALLEL SAFE
STRICT
IMMUTABLE;
