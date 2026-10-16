-- Test UTL_COMPRESS package

-- Empty input: LZ_COMPRESS(zero-length) produces a valid (non-empty) stream
-- that roundtrips back to zero length.  (Note: '' is NULL in Oracle mode,
-- so the regression uses the true zero-length bytea literal '\x'.)
SELECT length(UTL_COMPRESS.LZ_COMPRESS('\x'::bytea));
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS('\x'::bytea)) = '\x'::bytea;

-- Zero-length input to LZ_UNCOMPRESS raises LZ_UNCOMPRESS_EMPTY_FILE.
SELECT UTL_COMPRESS.LZ_UNCOMPRESS('\x'::bytea);

-- NULL input returns NULL (STRICT wrappers)
SELECT UTL_COMPRESS.LZ_COMPRESS(NULL) IS NULL;
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(NULL) IS NULL;
SELECT UTL_COMPRESS.LZ_COMPRESS(NULL, 9) IS NULL;

-- Single-byte roundtrip
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS('A'::bytea)) = 'A'::bytea;

-- Text roundtrip
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(convert_to('hello world', 'UTF8'))) = convert_to('hello world', 'UTF8');

-- Multi-byte (Chinese) roundtrip
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(convert_to('你好,IvorySQL 压缩测试', 'UTF8'))) = convert_to('你好,IvorySQL 压缩测试', 'UTF8');

-- Repetitive data actually compresses (output strictly shorter than input)
SELECT length(UTL_COMPRESS.LZ_COMPRESS(repeat('abcdefgh', 1000)::bytea)) < length(repeat('abcdefgh', 1000)::bytea);
SELECT length(UTL_COMPRESS.LZ_COMPRESS(repeat('x', 10000)::bytea));

-- Roundtrip of repetitive data with default quality 6
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(repeat('abcdefgh', 1000)::bytea)) = repeat('abcdefgh', 1000)::bytea;

-- quality 1 vs 9 roundtrip (both restore the original)
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(repeat('abc', 1000)::bytea, 1)) = repeat('abc', 1000)::bytea;
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(repeat('abc', 1000)::bytea, 9)) = repeat('abc', 1000)::bytea;

-- quality outside 1..9 raises LZ_INVALID_PARAMETER
SELECT UTL_COMPRESS.LZ_COMPRESS('hello'::bytea, 0);
SELECT UTL_COMPRESS.LZ_COMPRESS('hello'::bytea, 10);

-- Compressing already-compressed data: no crash, double roundtrip restores
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(
         UTL_COMPRESS.LZ_UNCOMPRESS(
           UTL_COMPRESS.LZ_COMPRESS(
             UTL_COMPRESS.LZ_COMPRESS('IvorySQL'::bytea)))) = 'IvorySQL'::bytea;

-- Corrupted / truncated input raises LZ_UNCOMPRESS_EXCEPTION, no crash
SELECT UTL_COMPRESS.LZ_UNCOMPRESS('\x12203040'::bytea);
SELECT UTL_COMPRESS.LZ_UNCOMPRESS('\x78da0102feff0001ffff02'::bytea);

-- Stream format is standard zlib: the zero-length stream is byte-for-byte
-- the well-known empty DEFLATE stream, and a stream produced by an
-- independent zlib implementation (Python's zlib module) decompresses
-- back to the original text, so roundtrips are not self-referential.
SELECT UTL_COMPRESS.LZ_COMPRESS('\x'::bytea) = '\x789c030000000001'::bytea;
SELECT UTL_COMPRESS.LZ_UNCOMPRESS('\x789ccb48cdc9c95728cf2fca4901001a0b045d'::bytea) = convert_to('hello world', 'UTF8');

-- The C wrapper and the package must agree on the same input
SELECT sys.ora_utl_compress_lz_compress('\x00112233445566778899aabbccddeeff'::bytea, 6) = UTL_COMPRESS.LZ_COMPRESS('\x00112233445566778899aabbccddeeff'::bytea);

-- RAW type roundtrip through the package (RAW in, RAW out)
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS('\x48656c6c6f20524157'::sys.raw)) = '\x48656c6c6f20524157'::sys.raw;

-- Highly compressible 100KB input: the compressed stream (a few hundred
-- bytes) is far smaller than the initial 8x decompression-buffer guess, so
-- this exercises the buffer-growth (doubling) path in lz_uncompress.
SELECT length(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('00', 100000), 'hex'))) < 1024;
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('00', 100000), 'hex'))) = decode(repeat('00', 100000), 'hex');

-- Truncating a *valid* compressed stream raises LZ_UNCOMPRESS_EXCEPTION
-- instead of hanging, crashing, or returning partial data.
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(substring(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('00', 100000), 'hex')), 1, 112));
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(substring(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('00', 100000), 'hex')), 1, 100));

-- Intermediate quality levels also roundtrip (1 and 9 covered above)
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('6162', 1000), 'hex'), 2)) = decode(repeat('6162', 1000), 'hex');
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('6162', 1000), 'hex'), 5)) = decode(repeat('6162', 1000), 'hex');
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(decode(repeat('6162', 1000), 'hex'), 8)) = decode(repeat('6162', 1000), 'hex');

-- Pseudo-random binary data roundtrip (deterministic via md5)
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(
    (SELECT decode(string_agg(md5(i::text), ''), 'hex')
       FROM generate_series(1, 128) i))) =
    (SELECT decode(string_agg(md5(i::text), ''), 'hex')
       FROM generate_series(1, 128) i);

-- Large-ish binary blob (64KB) roundtrip
SELECT UTL_COMPRESS.LZ_UNCOMPRESS(UTL_COMPRESS.LZ_COMPRESS(
    (SELECT decode(string_agg(md5(i::text), ''), 'hex')
       FROM generate_series(1, 4096) i))) =
    (SELECT decode(string_agg(md5(i::text), ''), 'hex')
       FROM generate_series(1, 4096) i);