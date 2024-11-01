--
-- BINARY_FLOAT
--

set ivorysql.enable_emptystring_to_NULL = on;
set extra_float_digits = 0;

CREATE TABLE BINARY_FLOAT_TBL (f1 binary_float);

INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('    0.0');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('1004.30   ');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('     -34.84    ');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('1.2345678901234e+20');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('1.2345678901234e-20');

-- test for over and under flow
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('10e70');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('-10e70');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('10e-70');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('-10e-70');

-- bad input
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('       ');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('xyz');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('5.0.0');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('5 . 0');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('5.   0');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('     - 3.0');
INSERT INTO BINARY_FLOAT_TBL(f1) VALUES ('123            5');

-- special inputs
SELECT 'NaN'::binary_float;
SELECT 'nan'::binary_float;
SELECT '   NAN  '::binary_float;
SELECT 'infinity'::binary_float;
SELECT '          -INFINiTY   '::binary_float;

-- bad special inputs
SELECT 'N A N'::binary_float;
SELECT 'NaN x'::binary_float;
SELECT ' INFINITY    x'::binary_float;

SELECT 'Infinity'::binary_float + 100.0;
SELECT 'Infinity'::binary_float / 'Infinity'::binary_float;
SELECT 'nan'::binary_float / 'nan'::binary_float;
SELECT 'nan'::number::binary_float;

SELECT '' AS five, * FROM BINARY_FLOAT_TBL;

SELECT '' AS four, f.* FROM BINARY_FLOAT_TBL f WHERE f.f1 <> '1004.3';

SELECT '' AS one, f.* FROM BINARY_FLOAT_TBL f WHERE f.f1 = '1004.3';

SELECT '' AS three, f.* FROM BINARY_FLOAT_TBL f WHERE '1004.3' > f.f1;

SELECT '' AS three, f.* FROM BINARY_FLOAT_TBL f WHERE  f.f1 < '1004.3';

SELECT '' AS four, f.* FROM BINARY_FLOAT_TBL f WHERE '1004.3' >= f.f1;

SELECT '' AS four, f.* FROM BINARY_FLOAT_TBL f WHERE  f.f1 <= '1004.3';

SELECT '' AS three, f.f1, f.f1 * '-10' AS x FROM BINARY_FLOAT_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS three, f.f1, f.f1 + '-10' AS x FROM BINARY_FLOAT_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS three, f.f1, f.f1 / '-10' AS x FROM BINARY_FLOAT_TBL f
   WHERE f.f1 > '0.0';

SELECT '' AS three, f.f1, f.f1 - '-10' AS x FROM BINARY_FLOAT_TBL f
   WHERE f.f1 > '0.0';

-- test divide by zero
SELECT '' AS bad, f.f1 / '0.0' from BINARY_FLOAT_TBL f;

SELECT '' AS five, * FROM BINARY_FLOAT_TBL;

-- test the unary abs operator
SELECT '' AS five, f.f1, @f.f1 AS abs_f1 FROM BINARY_FLOAT_TBL f;

UPDATE BINARY_FLOAT_TBL
   SET f1 = BINARY_FLOAT_TBL.f1 * '-1'
   WHERE BINARY_FLOAT_TBL.f1 > '0.0';

SELECT '' AS five, * FROM BINARY_FLOAT_TBL;

-- drop table
DROP TABLE BINARY_FLOAT_TBL;


--SIMPLE_FLOAT
CREATE TABLE SIMPLE_FLOAT_TBL (f1 binary_float);

INSERT INTO SIMPLE_FLOAT_TBL(f1) VALUES ('    0.0');
INSERT INTO SIMPLE_FLOAT_TBL(f1) VALUES ('1004.30   ');
INSERT INTO SIMPLE_FLOAT_TBL(f1) VALUES ('     -34.84    ');
INSERT INTO SIMPLE_FLOAT_TBL(f1) VALUES ('1.2345678901234e+20');
INSERT INTO SIMPLE_FLOAT_TBL(f1) VALUES ('1.2345678901234e-20');
SELECT * FROM SIMPLE_FLOAT_TBL;
DROP TABLE SIMPLE_FLOAT_TBL;

--SIMPLE_DOUBLE
CREATE TABLE SIMPLE_DOUBLE_TBL(f1 binary_double);

INSERT INTO SIMPLE_DOUBLE_TBL(f1) VALUES ('    0.0   ');
INSERT INTO SIMPLE_DOUBLE_TBL(f1) VALUES ('1004.30  ');
INSERT INTO SIMPLE_DOUBLE_TBL(f1) VALUES ('   -34.84');
INSERT INTO SIMPLE_DOUBLE_TBL(f1) VALUES ('1.2345678901234e+200');
INSERT INTO SIMPLE_DOUBLE_TBL(f1) VALUES ('1.2345678901234e-200');
SELECT * FROM SIMPLE_DOUBLE_TBL;
DROP TABLE SIMPLE_DOUBLE_TBL;


create table test_bf(a binary_float);
insert into test_bf values(3.40282E+38F);	-- ok
insert into test_bf values(-3.40282E+38F);	-- ok
insert into test_bf values(3.40282E+39F);	-- overflow
insert into test_bf values(-3.40282E+39F);	-- overflow
insert into test_bf values(3.40282E+39);	-- inf
insert into test_bf values(-3.40282E+39);	-- -inf
insert into test_bf values('3.40282E+39');	-- inf
insert into test_bf values('-3.40282E+39');-- -inf
select * from test_bf;

delete from test_bf;
insert into test_bf values(1.17549E-38F);	-- ok
insert into test_bf values(-1.17549E-38F);	-- ok
insert into test_bf values(1.17549E-39F);	-- ok
insert into test_bf values(-1.17549E-39F);	-- ok
insert into test_bf values(1.17549E-70F);	-- overflow
insert into test_bf values(-1.17549E-70F); -- overflow
insert into test_bf values(1.17549E-70);	-- 0
insert into test_bf values(-1.17549E-70);	-- 0
insert into test_bf values('1.17549E-70');	-- 0
insert into test_bf values('-1.17549E-70'); -- 0
select * from test_bf;
drop table test_bf;

create table float_point_conditions(a binary_float);
insert into float_point_conditions values(1.17549E-38F);
insert into float_point_conditions values(-1.17549E-38F);
insert into float_point_conditions values('inf');
insert into float_point_conditions values('+inf');
insert into float_point_conditions values('-inf');
insert into float_point_conditions values('+nan');
insert into float_point_conditions values('-nan');
select * from float_point_conditions where a is nan;
select * from float_point_conditions where a is not nan;
select * from float_point_conditions where a is infinite;
select * from float_point_conditions where a is not infinite;
drop table float_point_conditions;



create table binaryf_tb(binaryf_clo binary_float);
insert into binaryf_tb values (BINARY_FLOAT_NAN);
insert into binaryf_tb values (binary_float_nan);
insert into binaryf_tb values (Binary_Float_Nan);
insert into binaryf_tb values (BINARY_FLOAT_INFINITY);
insert into binaryf_tb values (binary_float_infinity);
insert into binaryf_tb values (Binary_Float_Infinity);
select * from binaryf_tb;
drop table binaryf_tb;



create table binaryf_tbtidb002145521(a binary_float, b binary_double);
insert into binaryf_tbtidb002145521 values(-3.40282e39, -3.40282e666);
insert into binaryf_tbtidb002145521 values(-3.40283e38, -3.40282e666);
select * from binaryf_tbtidb002145521;
