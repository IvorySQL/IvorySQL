-- Test of index bulk load
SELECT setseed(1);
CREATE TABLE "gin_check"("Column1" int[]);
-- posting trees (frequently used entries)
INSERT INTO gin_check select array_agg(round(random()*255) ) from generate_series(1, 100000) as i group by i % 10000;
-- posting leaves (sparse entries)
INSERT INTO gin_check select array_agg(255 + round(random()*100)) from generate_series(1, 100) as i group by i % 100;
CREATE INDEX gin_check_idx on "gin_check" USING GIN("Column1");
SELECT gin_index_check('gin_check_idx');

-- cleanup
DROP TABLE gin_check;

-- Test index inserts
SELECT setseed(1);
CREATE TABLE "gin_check"("Column1" int[]);
CREATE INDEX gin_check_idx on "gin_check" USING GIN("Column1");
ALTER INDEX gin_check_idx SET (fastupdate = false);
-- posting trees
INSERT INTO gin_check select array_agg(round(random()*255) ) from generate_series(1, 100000) as i group by i % 10000;
-- posting leaves
INSERT INTO gin_check select array_agg(100 + round(random()*255)) from generate_series(1, 100) as i group by i % 100;

SELECT gin_index_check('gin_check_idx');

-- cleanup
DROP TABLE gin_check;

-- Test GIN over text array
SELECT setseed(1);
CREATE TABLE "gin_check_text_array"("Column1" text[]);
-- posting trees
INSERT INTO gin_check_text_array select array_agg(sha256(round(random()*300)::text::bytea)::text) from generate_series(1, 100000) as i group by i % 10000;
-- posting leaves
INSERT INTO gin_check_text_array select array_agg(sha256(round(random()*300 + 300)::text::bytea)::text) from generate_series(1, 10000) as i group by i % 100;
CREATE INDEX gin_check_text_array_idx on "gin_check_text_array" USING GIN("Column1");
SELECT gin_index_check('gin_check_text_array_idx');

-- cleanup
DROP TABLE gin_check_text_array;

-- Test GIN over jsonb
CREATE TABLE "gin_check_jsonb"("j" jsonb);
INSERT INTO gin_check_jsonb values ('{"a":[["b",{"x":1}],["b",{"x":2}]],"c":3}');
INSERT INTO gin_check_jsonb values ('[[14,2,3]]');
INSERT INTO gin_check_jsonb values ('[1,[14,2,3]]');
CREATE INDEX "gin_check_jsonb_idx" on gin_check_jsonb USING GIN("j" jsonb_path_ops);

SELECT gin_index_check('gin_check_jsonb_idx');

-- cleanup
DROP TABLE gin_check_jsonb;

-- Test GIN multicolumn index
CREATE TABLE "gin_check_multicolumn"(a text[], b text[]);
INSERT INTO gin_check_multicolumn (a,b) values ('{a,c,e}','{b,d,f}');
CREATE INDEX "gin_check_multicolumn_idx" on gin_check_multicolumn USING GIN(a,b);

SELECT gin_index_check('gin_check_multicolumn_idx');

-- cleanup
DROP TABLE gin_check_multicolumn;
