-- Test UTL_RAW package

-- Basic CAST_TO_RAW: verify bytes are preserved
SELECT UTL_RAW.CAST_TO_RAW('hello');
SELECT UTL_RAW.CAST_TO_RAW('ABC');

-- NULL input returns NULL
SELECT UTL_RAW.CAST_TO_RAW(NULL) IS NULL;

-- Empty string
SELECT UTL_RAW.CAST_TO_RAW('');

-- Multi-byte characters (Chinese)
SELECT UTL_RAW.CAST_TO_RAW('你好');

-- Mixed Chinese and ASCII characters
SELECT UTL_RAW.CAST_TO_RAW('你好ABC世界');

-- Package constants
SELECT UTL_RAW.big_endian;

-- Special characters
SELECT UTL_RAW.CAST_TO_RAW('a b c');
SELECT UTL_RAW.CAST_TO_RAW('\n');
