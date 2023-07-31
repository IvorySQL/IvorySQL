--
-- BINARY_DOUBLE
--

set ivorysql.enable_emptystring_to_NULL = on;
set extra_float_digits = 0;

CREATE TABLE BINARY_DOUBLE_TBL(f1 binary_double);

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('    0.0   ');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('1004.30  ');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('   -34.84');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('1.2345678901234e+200');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('1.2345678901234e-200');

-- test for underflow and overflow handling
SELECT '10e400'::binary_double;
SELECT '-10e400'::binary_double;
SELECT '10e-400'::binary_double;
SELECT '-10e-400'::binary_double;

-- bad input
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('     ');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('xyz');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('5.0.0');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('5 . 0');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('5.   0');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('    - 3');
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('123           5');

-- special inputs
SELECT 'NaN'::binary_double;
SELECT 'nan'::binary_double;
SELECT '   NAN  '::binary_double;
SELECT 'infinity'::binary_double;
SELECT '          -INFINiTY   '::binary_double;
-- bad special inputs
SELECT 'N A N'::binary_double;
SELECT 'NaN x'::binary_double;
SELECT ' INFINITY    x'::binary_double;

SELECT 'Infinity'::binary_double + 100.0;
SELECT 'Infinity'::binary_double / 'Infinity'::binary_double;
SELECT 'nan'::binary_double / 'nan'::binary_double;
SELECT 'nan'::number::binary_double;

SELECT '' AS five, * FROM BINARY_DOUBLE_TBL;

SELECT '' AS four, f.* FROM BINARY_DOUBLE_TBL f WHERE f.f1 <> '1004.3';

SELECT '' AS one, f.* FROM BINARY_DOUBLE_TBL f WHERE f.f1 = '1004.3';

SELECT '' AS three, f.* FROM BINARY_DOUBLE_TBL f WHERE '1004.3' > f.f1;

SELECT '' AS three, f.* FROM BINARY_DOUBLE_TBL f WHERE  f.f1 < '1004.3';

SELECT '' AS four, f.* FROM BINARY_DOUBLE_TBL f WHERE '1004.3' >= f.f1;

SELECT '' AS four, f.* FROM BINARY_DOUBLE_TBL f WHERE  f.f1 <= '1004.3';

SELECT '' AS three, f.f1, f.f1 * '-10' AS x
   FROM BINARY_DOUBLE_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS three, f.f1, f.f1 + '-10' AS x
   FROM BINARY_DOUBLE_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS three, f.f1, f.f1 / '-10' AS x
   FROM BINARY_DOUBLE_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS three, f.f1, f.f1 - '-10' AS x
   FROM BINARY_DOUBLE_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS one, f.f1 ^ '2.0' AS square_f1
   FROM BINARY_DOUBLE_TBL f where f.f1 = '1004.3';

-- absolute value
SELECT '' AS five, f.f1, @f.f1 AS abs_f1
   FROM BINARY_DOUBLE_TBL f;

-- truncate
SELECT '' AS five, f.f1, trunc(f.f1) AS trunc_f1
   FROM BINARY_DOUBLE_TBL f;

-- round
SELECT '' AS five, f.f1, round(f.f1) AS round_f1
   FROM BINARY_DOUBLE_TBL f;

-- ceil / ceiling
select ceil(f1) as ceil_f1 from BINARY_DOUBLE_TBL f;
select ceiling(f1) as ceiling_f1 from BINARY_DOUBLE_TBL f;

-- floor
select floor(f1) as floor_f1 from BINARY_DOUBLE_TBL f;

-- sign
select sign(f1) as sign_f1 from BINARY_DOUBLE_TBL f;

-- square root
SELECT sqrt(binary_double '64') AS eight;

SELECT |/ binary_double '64' AS eight;

SELECT '' AS three, f.f1, |/f.f1 AS sqrt_f1
   FROM BINARY_DOUBLE_TBL f
   WHERE f.f1 > '0.0';

-- power
SELECT power(binary_double '144', binary_double '0.5');

-- take exp of ln(f.f1)
SELECT '' AS three, f.f1, exp(ln(f.f1)) AS exp_ln_f1
   FROM BINARY_DOUBLE_TBL f
   WHERE f.f1 > '0.0';

-- cube root
SELECT ||/ binary_double '27' AS three;

SELECT '' AS five, f.f1, ||/f.f1 AS cbrt_f1 FROM BINARY_DOUBLE_TBL f;


SELECT '' AS five, * FROM BINARY_DOUBLE_TBL;

UPDATE BINARY_DOUBLE_TBL
   SET f1 = BINARY_DOUBLE_TBL.f1 * '-1'
   WHERE BINARY_DOUBLE_TBL.f1 > '0.0';

SELECT '' AS bad, f.f1 * '1e200' from BINARY_DOUBLE_TBL f;

SELECT '' AS bad, f.f1 ^ '1e200' from BINARY_DOUBLE_TBL f;

SELECT 0 ^ 0 + 0 ^ 1 + 0 ^ 0.0 + 0 ^ 0.5;

SELECT '' AS bad, ln(f.f1) from BINARY_DOUBLE_TBL f where f.f1 = '0.0' ;

SELECT '' AS bad, ln(f.f1) from BINARY_DOUBLE_TBL f where f.f1 < '0.0' ;

SELECT '' AS bad, exp(f.f1) from BINARY_DOUBLE_TBL f;

SELECT '' AS bad, f.f1 / '0.0' from BINARY_DOUBLE_TBL f;

SELECT '' AS five, * FROM BINARY_DOUBLE_TBL;

-- test for over- and underflow
INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('10e400');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('-10e400');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('10e-400');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('-10e-400');

-- maintain external table consistency across platforms
-- delete all values and reinsert well-behaved ones

DELETE FROM BINARY_DOUBLE_TBL;

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('0.0');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('-34.84');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('-1004.30');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('-1.2345678901234e+200');

INSERT INTO BINARY_DOUBLE_TBL(f1) VALUES ('-1.2345678901234e-200');

SELECT '' AS five, * FROM BINARY_DOUBLE_TBL;

-- drop table 
DROP TABLE BINARY_DOUBLE_TBL;



