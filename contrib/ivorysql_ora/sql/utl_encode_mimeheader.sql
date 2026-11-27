-- MIMEHEADER_ENCODE / MIMEHEADER_DECODE round-trips in both encoding
-- schemes (base64 and quoted-printable), on a fresh extension install.
SET ivorysql.compatible_mode = oracle;

-- default encoding is quoted-printable
SELECT utl_encode.mimeheader_encode('héllo wörld') AS qp_default;

-- explicit base64
SELECT utl_encode.mimeheader_encode('héllo wörld', NULL, 1) AS b64_mode;

-- charset omitted: the database encoding is used
SELECT utl_encode.mimeheader_encode('héllo wörld', NULL, 2) AS db_charset;

-- round-trips
SELECT utl_encode.mimeheader_decode(utl_encode.mimeheader_encode('héllo wörld', NULL, 2)) AS qp_roundtrip;
SELECT utl_encode.mimeheader_decode(utl_encode.mimeheader_encode('héllo wörld', NULL, 1)) AS b64_roundtrip;

-- non-encoded input passes through unchanged
SELECT utl_encode.mimeheader_decode('plain text') AS passthrough;

-- TEXT_ENCODE / TEXT_DECODE base64 round-trip
SELECT utl_encode.text_decode(utl_encode.text_encode('abc', NULL, 1), NULL, 1) AS text_roundtrip;
