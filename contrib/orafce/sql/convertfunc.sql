set datestyle = ISO ,YMD;
set timezone = 'Asia/Shanghai';
set intervalstyle = postgres;
set compatible_mode = 'oracle';

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

set compatible_mode to default;
