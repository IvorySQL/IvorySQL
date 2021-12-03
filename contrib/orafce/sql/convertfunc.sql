set datestyle = ISO ,YMD;
set timezone = 'Asia/Shanghai';
set intervalstyle = postgres;
set compatible_mode = 'oracle';

select oracle.to_date('50-11-28 17:04:55','RR-MM-dd hh24:mi:ss');
select oracle.to_date('50-11-28 17:04:55','YY-MM-dd hh24:mi:ss');
select oracle.to_date('50-11-28','rr-MM-dd ');
select oracle.to_date('50-11-28 ','YY-MM-dd hh24:mi:ss');
select oracle.to_date('50-11-28 ','RR-MM-dd hh24:mi:ss');
select oracle.to_date('50-11-28 ','RR-MM-dd ');
select oracle.to_date(2454336, 'J');
select oracle.to_date(2454336, 'j');
select oracle.to_date('2019/11/22', 'yyyy-mm-dd');
select oracle.to_date('20-11-28','YY-MM-dd hh24:mi:ss');
select oracle.to_date('20-11-28 10:14:22','YY-MM-dd hh24:mi:ss');
select oracle.to_date('2019/11/22');
select oracle.to_date('2019/11/27 10:14:22');
select oracle.to_date('120','rr');
select oracle.to_date('120','RR');
select oracle.to_date('2020','RR');
select oracle.to_date(NULL);
select oracle.to_date(NULL,NULL);
--test SYYYY date type
select oracle.to_date('07--4712-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS');
select oracle.to_date('07-2019-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS');
select oracle.to_date('9999-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS');
select oracle.to_date('-4712-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss');
select oracle.to_date('-1-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss');
select oracle.to_date('+2021-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss');
select oracle.to_date('07--2019-23', 'MM-SYYYY-DD');
select oracle.to_date('-2019', 'SYYYY');
select oracle.to_date('2019', 'syyyy');

create table test1(d oracle.date);
insert into test1 values (oracle.to_date('2009-12-2', 'syyyy-mm-dd'));
insert into test1 values (oracle.to_date('-1452-12-2', 'syyyy-mm-dd'));
select oracle.to_char(d, 'bcyyyy-mm-dd') from test1;
select * from test1;

--error
select oracle.to_date('-0-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS');
select oracle.to_date('-4713-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS');
select oracle.to_date('--2021-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS');
select oracle.to_date('10000-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS');
select oracle.to_date('-2021-07-23 14:31:23', 'YYYY-MM-DD HH24:MI:SS');
drop table test1;

select oracle.bin_to_num(1,0,1);
select oracle.bin_to_num('1.3'::text,'1.2'::name);
select oracle.bin_to_num('1'::bpchar);
select oracle.bin_to_num('3'::bpchar);
select oracle.bin_to_num(1.2::numeric);
select oracle.bin_to_num(1.2::float8);
select oracle.bin_to_num(1.2::real,2.3::numeric);
select oracle.bin_to_num(1.2::real,1.5::numeric);
select oracle.bin_to_num(1.2::float8,1.3::float4);
select oracle.bin_to_num(1.2::float8,1::int4);
select oracle.bin_to_num(3.2::float8,1::int4);
select oracle.bin_to_num(NULL);
select oracle.bin_to_num(NULL,NULL,NULL);

select oracle.to_multi_byte('abc'::text);
select oracle.to_multi_byte('1.2'::text) ;
select oracle.to_multi_byte(1.2::float);
select oracle.to_multi_byte(1::int);
select oracle.to_multi_byte(1.4::numeric);
select oracle.to_multi_byte('abc'::bpchar);
select oracle.to_multi_byte(6.4);
select oracle.to_multi_byte(NULL);

select oracle.to_single_byte('ａｂｃ');
select oracle.to_single_byte('１．２');
select oracle.to_single_byte(１．２);
select oracle.to_single_byte(3.4);
select oracle.to_single_byte(NULL);

select oracle.to_binary_double(2.5555::float8);
select oracle.to_binary_double(2.5555::real);
select oracle.to_binary_double('2'::oracle.varchar2);
select oracle.to_binary_double(oracle.to_char(2.55555));
select oracle.to_binary_double('1.2');
select oracle.to_binary_double('1.2'::text);
select oracle.to_binary_double('1.2'::name);
select oracle.to_binary_double(1.2::numeric);
select oracle.to_binary_double(123456789123456789.45566::numeric);
select oracle.to_binary_double(1.234567891e+200::numeric);
select oracle.to_binary_double(1.234567891e+500::float);
select oracle.to_binary_double(NULL);

select oracle.to_binary_float(2.5555::float8);
select oracle.to_binary_float(2.5555::real);
select oracle.to_binary_float('1'::oracle.varchar2);
select oracle.to_binary_float('123'::text);
select oracle.to_binary_float('1.2'::name);
select oracle.to_binary_float(1.2::numeric);
select oracle.to_binary_float(1.234567891e+200::numeric);
select oracle.to_binary_float(NULL);

select oracle.hex_to_decimal('11');
select oracle.hex_to_decimal('0xffff');
select oracle.hex_to_decimal('0xFFff');
select oracle.hex_to_decimal('0x7fffffffffffffff');
select oracle.hex_to_decimal('0x8fffffffffffffff');
select oracle.hex_to_decimal(NULL);

select oracle.to_timestamp_tz('2020-01-15');
select oracle.to_timestamp_tz('2020-01-15'::text);
select oracle.to_timestamp_tz('2019','yyyy');
select oracle.to_timestamp_tz('2019-11','yyyy-mm');
select oracle.to_timestamp_tz('2003/12/13 10:13:18 -8:00');
select oracle.to_timestamp_tz('2003/12/13 10:13:18 +1:00');
select oracle.to_timestamp_tz('2003/12/13 10:13:18 +7:00');
select oracle.to_timestamp_tz('2019-11-25'::text,'yyyy-mm-dd HH24:MI:SS OF');
select oracle.to_timestamp_tz('2019-11-25 13:38:00'::text,'yyyy-mm-dd HH24:MI:SS');
select oracle.to_timestamp_tz('2019-11-29 14:17:00','YYYY-MM-DD HH24:MI:SS TZH:TZM');
select oracle.to_timestamp_tz('2003/12/13 10:13:18 -8:00', 'YYYY/MM/DD HH:MI:SS TZH:TZM');
select oracle.to_timestamp_tz('2019/12/13 10:13:18 -2:00', 'YYYY/MM/DD HH:MI:SS TZH:TZM');
select oracle.to_timestamp_tz('2019/12/13 10:13:18 +5:00', 'YYYY/MM/DD HH:MI:SS TZH:TZM');
select oracle.to_timestamp_tz(NULL);

select oracle.to_timestamp(-12124579);
select oracle.to_timestamp(-1212457999999999999999999);
select oracle.to_timestamp(12121212.55::float);
select oracle.to_timestamp(1212121212.55);
select oracle.to_timestamp(1212121212.55::real);
select oracle.to_timestamp(NULL);
select oracle.to_timestamp(1212121212.55::numeric);
select oracle.to_timestamp('2019-11-29 14:17:00','YYYY-MM-DD HH24:MI:SS TZH:TZM');
select oracle.to_timestamp('2020/03/03 10:13:18 -8:00', 'YYYY/MM/DD HH:MI:SS TZH:TZM');
select oracle.to_timestamp('2020/03/03 10:13:18 -2:00', 'YYYY/MM/DD HH:MI:SS TZH:TZM');
select oracle.to_timestamp('2020/03/03 10:13:18 +5:00', 'YYYY/MM/DD HH:MI:SS TZH:TZM');
select oracle.to_timestamp(NULL,NULL);
select oracle.to_timestamp(1212457898999999999999);

select oracle.interval_to_seconds('3day');
select oracle.interval_to_seconds('3hours');
select oracle.interval_to_seconds('3day 3 hour 3second ');
select oracle.interval_to_seconds(NULL);
select oracle.interval_to_seconds('P1Y');
select oracle.interval_to_seconds('P1Y2M');

select oracle.to_yminterval('01-02');
select oracle.to_yminterval('P1Y2M2D');
select oracle.to_yminterval('P1Y');
select oracle.to_yminterval('-P1Y2M');
select oracle.to_yminterval('+P1Y1M');
select oracle.to_yminterval('P1Y-2M2D');
select oracle.to_yminterval(' 01 -  02');
select oracle.to_yminterval(NULL);
select oracle.to_yminterval('-01-02');
select oracle.to_yminterval('+01-02');
select oracle.to_yminterval('-01-02-03');

select oracle.to_dsinterval('P1Y1M2D');
select oracle.to_dsinterval('100 00:02:00');
select oracle.to_dsinterval('100 00 :02 :00');
select oracle.to_dsinterval('+100 00:02:00');
select oracle.to_dsinterval(NULL);
select oracle.to_dsinterval('100 -10:02:00');
select oracle.to_dsinterval('100 +10:10:10');
select oracle.to_dsinterval('P100DT5H');
select oracle.to_dsinterval('+P100DT5H');
select oracle.to_dsinterval('-100 10:00:00');
select oracle.to_dsinterval('-P100DT5H');
select oracle.to_dsinterval('-P100DT');
select oracle.to_dsinterval('-P100D');
select oracle.to_dsinterval('-P100DT20H');
select oracle.to_dsinterval('-P100DT20S');
select oracle.to_dsinterval('-P100DT20');
select oracle.to_dsinterval('-P100DT20H2');

set compatible_mode to default;
