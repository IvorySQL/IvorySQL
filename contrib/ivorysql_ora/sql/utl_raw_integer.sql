-- Fixed-width integer conversions, independent byte vectors before round trips.
\pset format unaligned
\pset tuples_only on
SELECT 'zero_1=' || encode(sys.ora_utl_raw_cast_from_binary_integer((0)::pg_catalog.int4, (1)::pg_catalog.int4), 'hex');
SELECT 'decode_zero_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('00000000', 'hex'), (1)::pg_catalog.int4) = (0)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'zero_2=' || encode(sys.ora_utl_raw_cast_from_binary_integer((0)::pg_catalog.int4, (2)::pg_catalog.int4), 'hex');
SELECT 'decode_zero_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('00000000', 'hex'), (2)::pg_catalog.int4) = (0)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'one_1=' || encode(sys.ora_utl_raw_cast_from_binary_integer((1)::pg_catalog.int4, (1)::pg_catalog.int4), 'hex');
SELECT 'decode_one_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('00000001', 'hex'), (1)::pg_catalog.int4) = (1)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'one_2=' || encode(sys.ora_utl_raw_cast_from_binary_integer((1)::pg_catalog.int4, (2)::pg_catalog.int4), 'hex');
SELECT 'decode_one_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('01000000', 'hex'), (2)::pg_catalog.int4) = (1)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'order_1=' || encode(sys.ora_utl_raw_cast_from_binary_integer((16909060)::pg_catalog.int4, (1)::pg_catalog.int4), 'hex');
SELECT 'decode_order_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('01020304', 'hex'), (1)::pg_catalog.int4) = (16909060)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'order_2=' || encode(sys.ora_utl_raw_cast_from_binary_integer((16909060)::pg_catalog.int4, (2)::pg_catalog.int4), 'hex');
SELECT 'decode_order_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('04030201', 'hex'), (2)::pg_catalog.int4) = (16909060)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'minus_one_1=' || encode(sys.ora_utl_raw_cast_from_binary_integer((-1)::pg_catalog.int4, (1)::pg_catalog.int4), 'hex');
SELECT 'decode_minus_one_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('ffffffff', 'hex'), (1)::pg_catalog.int4) = (-1)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'minus_one_2=' || encode(sys.ora_utl_raw_cast_from_binary_integer((-1)::pg_catalog.int4, (2)::pg_catalog.int4), 'hex');
SELECT 'decode_minus_one_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('ffffffff', 'hex'), (2)::pg_catalog.int4) = (-1)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'minimum_1=' || encode(sys.ora_utl_raw_cast_from_binary_integer((-2147483648)::pg_catalog.int4, (1)::pg_catalog.int4), 'hex');
SELECT 'decode_minimum_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('80000000', 'hex'), (1)::pg_catalog.int4) = (-2147483648)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'minimum_2=' || encode(sys.ora_utl_raw_cast_from_binary_integer((-2147483648)::pg_catalog.int4, (2)::pg_catalog.int4), 'hex');
SELECT 'decode_minimum_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('00000080', 'hex'), (2)::pg_catalog.int4) = (-2147483648)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'maximum_1=' || encode(sys.ora_utl_raw_cast_from_binary_integer((2147483647)::pg_catalog.int4, (1)::pg_catalog.int4), 'hex');
SELECT 'decode_maximum_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('7fffffff', 'hex'), (1)::pg_catalog.int4) = (2147483647)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'maximum_2=' || encode(sys.ora_utl_raw_cast_from_binary_integer((2147483647)::pg_catalog.int4, (2)::pg_catalog.int4), 'hex');
SELECT 'decode_maximum_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('ffffff7f', 'hex'), (2)::pg_catalog.int4) = (2147483647)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'native_order=' || CASE WHEN sys.ora_utl_raw_cast_from_binary_integer((16909060)::pg_catalog.int4, (3)::pg_catalog.int4) IN (decode('01020304', 'hex'), decode('04030201', 'hex')) THEN 'ok' ELSE 'FAIL' END;
SELECT 'native_round_trip=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(sys.ora_utl_raw_cast_from_binary_integer((-2147483648)::pg_catalog.int4, (3)::pg_catalog.int4), (3)::pg_catalog.int4) = (-2147483648)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'from_null=' || CASE WHEN sys.ora_utl_raw_cast_from_binary_integer(NULL::pg_catalog.int4, (1)::pg_catalog.int4) IS NULL THEN 'ok' ELSE 'FAIL' END;
SELECT 'to_null=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(NULL::pg_catalog.bytea, (1)::pg_catalog.int4) IS NULL THEN 'ok' ELSE 'FAIL' END;
SELECT 'null_data_before_order=' || CASE WHEN sys.ora_utl_raw_cast_from_binary_integer(NULL::pg_catalog.int4, (4)::pg_catalog.int4) IS NULL AND sys.ora_utl_raw_cast_to_binary_integer(NULL::pg_catalog.bytea, NULL::pg_catalog.int4) IS NULL THEN 'ok' ELSE 'FAIL' END;

-- Public package calls exercise PL/iSQL argument and return conversions.
SELECT 'package_default=' || encode(utl_raw.cast_from_binary_integer(16909060)::pg_catalog.bytea, 'hex');
SELECT 'package_little=' || encode(utl_raw.cast_from_binary_integer(16909060, 2)::pg_catalog.bytea, 'hex');
SELECT 'package_decode=' || CASE WHEN utl_raw.cast_to_binary_integer(hextoraw('80000000')) = -2147483648 THEN 'ok' ELSE 'FAIL' END;
SELECT 'package_negative=' || CASE WHEN utl_raw.cast_to_binary_integer(utl_raw.cast_from_binary_integer(-123456, 2), 2) = -123456 THEN 'ok' ELSE 'FAIL' END;
SELECT 'package_null=' || CASE WHEN utl_raw.cast_from_binary_integer(NULL) IS NULL AND utl_raw.cast_to_binary_integer(NULL) IS NULL THEN 'ok' ELSE 'FAIL' END;
SELECT 'package_short=' || CASE WHEN utl_raw.cast_to_binary_integer(hextoraw('010203'), 2) = 197121 THEN 'ok' ELSE 'FAIL' END;
SELECT 'package_null_endian=' || CASE WHEN utl_raw.cast_from_binary_integer(1, NULL) IS NULL AND utl_raw.cast_to_binary_integer(hextoraw('01020304'), NULL) IS NULL THEN 'ok' ELSE 'FAIL' END;
SELECT 'package_fraction=' || encode(utl_raw.cast_from_binary_integer(1.5)::pg_catalog.bytea, 'hex');
SELECT 'package_negative_fraction=' || encode(utl_raw.cast_from_binary_integer(-1.5)::pg_catalog.bytea, 'hex');
SELECT 'package_minimum=' || encode(utl_raw.cast_from_binary_integer(-2147483648)::pg_catalog.bytea, 'hex');
SELECT 'package_maximum=' || encode(utl_raw.cast_from_binary_integer(2147483647)::pg_catalog.bytea, 'hex');
SELECT 'catalog=' || CASE WHEN count(*) = 2
  AND bool_and(provolatile = 'i' AND proparallel = 's' AND NOT proisstrict)
  THEN 'ok' ELSE 'FAIL' END
FROM pg_catalog.pg_proc
WHERE pronamespace = 'sys'::regnamespace
  AND proname IN ('ora_utl_raw_cast_from_binary_integer',
                  'ora_utl_raw_cast_to_binary_integer');

-- Oracle reference probes: short RAWs and NULL selectors.
SELECT 'short_01_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('01', 'hex'), (1)::pg_catalog.int4) = (1)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'short_01_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('01', 'hex'), (2)::pg_catalog.int4) = (1)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'short_0102_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('0102', 'hex'), (1)::pg_catalog.int4) = (258)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'short_0102_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('0102', 'hex'), (2)::pg_catalog.int4) = (513)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'short_010203_1=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('010203', 'hex'), (1)::pg_catalog.int4) = (66051)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'short_010203_2=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('010203', 'hex'), (2)::pg_catalog.int4) = (197121)::pg_catalog.int4 THEN 'ok' ELSE 'FAIL' END;
SELECT 'null_endian_encode=' || CASE WHEN sys.ora_utl_raw_cast_from_binary_integer((1)::pg_catalog.int4, NULL::pg_catalog.int4) IS NULL THEN 'ok' ELSE 'FAIL' END;
SELECT 'null_endian_decode=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('01020304', 'hex'), NULL::pg_catalog.int4) IS NULL THEN 'ok' ELSE 'FAIL' END;
SELECT 'empty_raw=' || CASE WHEN sys.ora_utl_raw_cast_to_binary_integer(decode('', 'hex'), (1)::pg_catalog.int4) IS NULL THEN 'ok' ELSE 'FAIL' END;

-- Invalid selectors and values still raise errors; error codes are PostgreSQL-native.
SELECT sys.ora_utl_raw_cast_from_binary_integer((1)::pg_catalog.int4, (0)::pg_catalog.int4);
SELECT sys.ora_utl_raw_cast_from_binary_integer((1)::pg_catalog.int4, (4)::pg_catalog.int4);
SELECT sys.ora_utl_raw_cast_from_binary_integer((1)::pg_catalog.int4, (-1)::pg_catalog.int4);
SELECT sys.ora_utl_raw_cast_to_binary_integer(decode('0102030405', 'hex'), (1)::pg_catalog.int4);
SELECT sys.ora_utl_raw_cast_to_binary_integer(decode('010203040506', 'hex'), (1)::pg_catalog.int4);
SELECT sys.ora_utl_raw_cast_from_binary_integer((2147483648)::pg_catalog.int4, (1)::pg_catalog.int4);
SELECT sys.ora_utl_raw_cast_from_binary_integer((-2147483649)::pg_catalog.int4, (1)::pg_catalog.int4);
\pset tuples_only off
\pset format aligned
