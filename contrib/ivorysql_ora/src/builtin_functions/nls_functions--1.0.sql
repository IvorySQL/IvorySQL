/***************************************************************
 *
 * NLS case conversion functions.
 *
 ***************************************************************/

CREATE FUNCTION sys.nls_upper(str text)
RETURNS text
AS 'MODULE_PATHNAME','ora_nls_upper'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

COMMENT ON FUNCTION sys.nls_upper(text) IS 'Convert every letter to uppercase; simple mapping, independent of the database locale';

CREATE FUNCTION sys.nls_upper(str text, nlsparam text)
RETURNS text
AS 'MODULE_PATHNAME','ora_nls_upper_param'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

COMMENT ON FUNCTION sys.nls_upper(text, text) IS 'Convert every letter to uppercase, applying the linguistic special cases of the requested NLS_SORT sequence';

CREATE FUNCTION sys.nls_lower(str text)
RETURNS text
AS 'MODULE_PATHNAME','ora_nls_lower'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

COMMENT ON FUNCTION sys.nls_lower(text) IS 'Convert every letter to lowercase; simple mapping, independent of the database locale';

CREATE FUNCTION sys.nls_lower(str text, nlsparam text)
RETURNS text
AS 'MODULE_PATHNAME','ora_nls_lower_param'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;

COMMENT ON FUNCTION sys.nls_lower(text, text) IS 'Convert every letter to lowercase, applying the linguistic special cases of the requested NLS_SORT sequence';
