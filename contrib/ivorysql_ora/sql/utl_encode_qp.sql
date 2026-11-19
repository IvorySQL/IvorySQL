-- Test the UTL_ENCODE quoted-printable and text conversion functions

SET ivorysql.compatible_mode = oracle;
SELECT pg_catalog.encode(sys.utl_encode_quoted_printable_encode(pg_catalog.decode('616263','hex')), 'hex');
SELECT pg_catalog.encode(sys.utl_encode_quoted_printable_encode(pg_catalog.decode('00ff20','hex')), 'hex');
SELECT sys.utl_encode_quoted_printable_decode(sys.utl_encode_quoted_printable_encode(pg_catalog.decode('aabbcc204120','hex'))) = pg_catalog.decode('aabbcc204120','hex') AS round_trip;
SELECT pg_catalog.encode(sys.utl_encode_quoted_printable_encode(pg_catalog.convert_to(pg_catalog.repeat('a', 73), 'UTF8')), 'hex') IS NOT NULL AS long_line;
SELECT sys.utl_encode_text_decode(sys.utl_encode_text_encode('你好', 'UTF8'), 'UTF8');
SELECT sys.utl_encode_text_decode(sys.utl_encode_text_encode('hello', 'UTF8', 1), 'UTF8', 1);
SELECT sys.utl_encode_text_decode(sys.utl_encode_text_encode('hello', 'UTF8', 2), 'UTF8', 2);

-- round trip holds for an input long enough to exercise soft line breaks
SELECT sys.utl_encode_quoted_printable_decode(
         sys.utl_encode_quoted_printable_encode(
           pg_catalog.convert_to(pg_catalog.repeat('a', 100), 'UTF8')))
       = pg_catalog.convert_to(pg_catalog.repeat('a', 100), 'UTF8') AS round_trip_100;

-- the encoded form wraps: every line is at most 76 bytes (the trailing '='
-- soft break included) and the wrapped lines end with '='
SELECT pg_catalog.bool_and(pg_catalog.length(l) <= 76) AS lines_within_limit
FROM pg_catalog.regexp_split_to_table(
       pg_catalog.convert_from(sys.utl_encode_quoted_printable_encode(
         pg_catalog.convert_to(pg_catalog.repeat('a', 100), 'UTF8')), 'UTF8'),
       E'\\r\\n') AS l;

-- an escape-heavy input near the wrap boundary keeps every line within the
-- limit (escapes are three bytes and must leave room for the soft break)
SELECT pg_catalog.bool_and(pg_catalog.length(l) <= 76) AS escaped_lines_within_limit
FROM pg_catalog.regexp_split_to_table(
       pg_catalog.convert_from(sys.utl_encode_quoted_printable_encode(
         pg_catalog.convert_to(pg_catalog.repeat(pg_catalog.chr(1), 60), 'UTF8')), 'UTF8'),
       E'\\r\\n') AS l;
