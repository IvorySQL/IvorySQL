CREATE TABLE delete_test (
    id SERIAL PRIMARY KEY,
    a INT,
    b text
);

INSERT INTO delete_test (a) VALUES (10);
INSERT INTO delete_test (a, b) VALUES (50, repeat('x', 10000));
INSERT INTO delete_test (a) VALUES (100);

-- allow an alias to be specified for DELETE's target table
DELETE FROM delete_test AS dt WHERE dt.a > 75;

-- if an alias is specified, don't allow the original table name
-- to be referenced
DELETE FROM delete_test dt WHERE delete_test.a > 25;

SELECT id, a, char_length(b) FROM delete_test;

-- delete a row with a TOASTed value
DELETE FROM delete_test WHERE a > 25;

SELECT id, a, char_length(b) FROM delete_test;

DROP TABLE delete_test;

--ignore FROM keyword
create table tb_test4(id int, flg char(10));
insert into tb_test4 values(1, '2'), (3, '4'), (5, '6');
delete from tb_test4 where id = 1;
delete tb_test4 where id = 3;
table tb_test4;