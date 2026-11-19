-- Test the UTL_ENCODE quoted-printable and text conversion functions

SET ivorysql.compatible_mode = oracle;
SELECT pg_catalog.encode(sys.utl_encode_quoted_printable_encode(pg_catalog.decode('616263','hex')), 'hex');
SELECT pg_catalog.encode(sys.utl_encode_quoted_printable_encode(pg_catalog.decode('00ff20','hex')), 'hex');
SELECT sys.utl_encode_quoted_printable_decode(sys.utl_encode_quoted_printable_encode(pg_catalog.decode('aabbcc204120','hex'))) = pg_catalog.decode('aabbcc204120','hex') AS round_trip;
SELECT pg_catalog.encode(sys.utl_encode_quoted_printable_encode(pg_catalog.convert_to(pg_catalog.repeat('a', 73), 'UTF8')), 'hex') IS NOT NULL AS long_line;
SELECT sys.utl_encode_text_decode(sys.utl_encode_text_encode('你好', 'UTF8'), 'UTF8');
SELECT sys.utl_encode_text_decode(sys.utl_encode_text_encode('hello', 'UTF8', 1), 'UTF8', 1);
SELECT sys.utl_encode_text_decode(sys.utl_encode_text_encode('hello', 'UTF8', 2), 'UTF8', 2);
