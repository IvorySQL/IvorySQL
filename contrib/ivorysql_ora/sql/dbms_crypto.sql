--
-- DBMS_CRYPTO
--
-- Regression tests for Oracle-compatible DBMS_CRYPTO package:
--   - HASH (RAW and VARCHAR2 for MD5, SHA1, SHA256, SHA384, SHA512)
--   - MAC (HMAC-MD5, HMAC-SHA1, HMAC-SHA256, HMAC-SHA384, HMAC-SHA512)
--   - RANDOMBYTES
--   - RANDOMINTEGER
--   - Package algorithm constants
--

-- Package constants
SELECT dbms_crypto.hash_md4;
SELECT dbms_crypto.hash_md5;
SELECT dbms_crypto.hash_sh1;
SELECT dbms_crypto.hash_sh256;
SELECT dbms_crypto.hash_sh384;
SELECT dbms_crypto.hash_sh512;
SELECT dbms_crypto.hmac_md5;
SELECT dbms_crypto.hmac_sh1;
SELECT dbms_crypto.hmac_sh256;
SELECT dbms_crypto.hmac_sh384;
SELECT dbms_crypto.hmac_sh512;

-- HASH with VARCHAR2 input
-- MD5 of 'hello' is 5d41402abc4b2a76b9719d911017c592
SELECT dbms_crypto.hash('hello', dbms_crypto.hash_md5);

-- SHA-1 of 'hello' is aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
SELECT dbms_crypto.hash('hello', dbms_crypto.hash_sh1);

-- SHA-256 of 'hello' is 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
SELECT dbms_crypto.hash('hello', dbms_crypto.hash_sh256);

-- SHA-384 of 'hello'
SELECT length(dbms_crypto.hash('hello', dbms_crypto.hash_sh384));

-- SHA-512 of 'hello'
SELECT length(dbms_crypto.hash('hello', dbms_crypto.hash_sh512));

-- HASH with RAW input
SELECT dbms_crypto.hash(E'\\x68656c6c6f'::bytea, dbms_crypto.hash_md5);
SELECT dbms_crypto.hash(E'\\x68656c6c6f'::bytea, dbms_crypto.hash_sh256);

-- MAC (HMAC) calculations
SELECT dbms_crypto.mac('hello', dbms_crypto.hmac_md5, E'\\x6b6579'::bytea);
SELECT dbms_crypto.mac('hello', dbms_crypto.hmac_sh256, E'\\x6b6579'::bytea);
SELECT dbms_crypto.mac(E'\\x68656c6c6f'::bytea, dbms_crypto.hmac_sh256, E'\\x6b6579'::bytea);

-- RANDOMBYTES length and non-null assertion
SELECT length(dbms_crypto.randombytes(16));
SELECT length(dbms_crypto.randombytes(32));

-- RANDOMINTEGER returns non-null integer
SELECT dbms_crypto.randominteger() IS NOT NULL;

-- NULL input handling
SELECT dbms_crypto.hash(NULL::bytea, dbms_crypto.hash_sh256) IS NULL;
SELECT dbms_crypto.hash(NULL::varchar2, dbms_crypto.hash_sh256) IS NULL;
SELECT dbms_crypto.mac(NULL::bytea, dbms_crypto.hmac_sh256, E'\\x6b6579'::bytea) IS NULL;
SELECT dbms_crypto.randombytes(NULL) IS NULL;

-- Invalid algorithm error checking
SELECT dbms_crypto.hash('hello', 999);
SELECT dbms_crypto.mac('hello', 999, E'\\x6b6579'::bytea);
SELECT dbms_crypto.randombytes(-5);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_crypto_hash',
                     'dbms_crypto_mac',
                     'dbms_crypto_randombytes',
                     'dbms_crypto_randominteger')
 ORDER BY p.proname;
