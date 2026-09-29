--
-- NLS_UPPER / NLS_LOWER
--
-- Oracle-compatible NLS case conversion.  Without an NLS parameter the
-- conversion is a simple per-character mapping that does not depend on the
-- database locale ('ss'+'ß' is not expanded on uppercasing).
--
SELECT nls_upper('abc');
SELECT nls_lower('ABC');
SELECT nls_upper('straße');
SELECT nls_lower('STRAßE');
SELECT nls_upper('') IS NULL AS empty_string_is_null;
SELECT nls_upper(NULL) IS NULL AS null_is_null;

-- a NULL nlsparam makes the whole call return NULL, like Oracle
SELECT nls_upper('abc', NULL) IS NULL AS null_nlsparam_is_null;

--
-- NLS_SORT parameter
--
-- the X-prefixed German and West-European sorts expand ß to SS on
-- uppercasing; the corresponding non-X sorts behave like BINARY
--
SELECT nls_upper('straße', 'NLS_SORT=BINARY');
SELECT nls_upper('straße', 'NLS_SORT=XGERMAN');
SELECT nls_upper('straße', 'NLS_SORT=XGERMAN_DIN');
SELECT nls_upper('straße', 'NLS_SORT=XWEST_EUROPEAN');
SELECT nls_upper('straße', 'NLS_SORT=GERMAN');
SELECT nls_upper('straße', 'NLS_SORT=GERMAN_DIN');
SELECT nls_upper('straße', 'NLS_SORT=WEST_EUROPEAN');
SELECT nls_upper('straße', 'NLS_SORT=XFRENCH');
SELECT nls_upper('straße', 'NLS_SORT=FRENCH');
SELECT nls_lower('STRAßE', 'NLS_SORT=XGERMAN');
SELECT nls_lower('STRASSE', 'NLS_SORT=XGERMAN');

-- parsing: case-insensitive, spaces tolerated around name and value,
-- case/accent-insensitive suffixes allowed
SELECT nls_upper('straße', 'NLS_SORT = XGERMAN');
SELECT nls_upper('straße', 'nls_sort=xgerman');
SELECT nls_upper('straße', 'NLS_SORT=xGerman');
SELECT nls_upper('straße', 'NLS_SORT= XGERMAN ');
SELECT nls_upper('straße', 'NLS_SORT=XGERMAN_CI');
SELECT nls_upper('straße', 'NLS_SORT=XGERMAN_AI');

-- a clause for another NLS parameter is accepted and ignored, like Oracle
SELECT nls_upper('abc', 'NLS_DATE_LANGUAGE=AMERICAN');

--
-- errors: Oracle reports ORA-12702 for all of these
--
SELECT nls_upper('straße', 'NLS_SORT=BOGUS');
SELECT nls_upper('abc', 'NLS_SORT=');
SELECT nls_upper('abc', 'garbage');
SELECT nls_upper('abc', 'NLS_DATE_LANGUAGE=AMERICAN,NLS_SORT=XGERMAN');
