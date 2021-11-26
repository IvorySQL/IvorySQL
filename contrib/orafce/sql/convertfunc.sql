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
set compatible_mode to default;
