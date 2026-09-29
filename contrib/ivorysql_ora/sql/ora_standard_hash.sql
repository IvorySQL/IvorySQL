--
-- STANDARD_HASH
--
-- Oracle-compatible message digest function returning RAW.
--

-- known test vectors for 'abc' across all five algorithms
SELECT standard_hash('abc', 'MD5');
SELECT standard_hash('abc', 'SHA1');
SELECT standard_hash('abc', 'SHA256');
SELECT standard_hash('abc', 'SHA384');
SELECT standard_hash('abc', 'SHA512');

-- the method argument defaults to SHA1, like in Oracle
SELECT standard_hash('abc') = standard_hash('abc', 'SHA1') AS default_is_sha1;

-- digest lengths: 16/20/32/48/64 bytes
SELECT octet_length(standard_hash('abc', 'MD5')) AS md5_len,
       octet_length(standard_hash('abc', 'SHA1')) AS sha1_len,
       octet_length(standard_hash('abc', 'SHA256')) AS sha256_len,
       octet_length(standard_hash('abc', 'SHA384')) AS sha384_len,
       octet_length(standard_hash('abc', 'SHA512')) AS sha512_len;

-- multibyte input digests its UTF-8 bytes, like Oracle in an AL32UTF8 database
SELECT standard_hash('中', 'MD5');
SELECT standard_hash('中文', 'SHA256');

-- a NULL input digests the empty string, like Oracle 23ai
SELECT standard_hash(NULL::text, 'MD5');
SELECT standard_hash(''::varchar, 'MD5');
SELECT standard_hash(NULL::text, 'MD5') = standard_hash('', 'MD5') AS null_is_empty_digest;
SELECT standard_hash('', 'SHA1');

-- long input
SELECT octet_length(standard_hash(repeat('x', 3000), 'SHA256'));

-- raw result interoperates with bytea functions
SELECT get_byte(standard_hash('abc', 'MD5'), 0);

-- the method name is matched case-sensitively; anything but the exact
-- spelling raises Oracle's ORA-03052
SELECT standard_hash('abc', 'md5');
SELECT standard_hash('abc', 'Sha256');
SELECT standard_hash('abc', 'MD4');
SELECT standard_hash('abc', 'MD5 ');
SELECT standard_hash('abc', NULL);
