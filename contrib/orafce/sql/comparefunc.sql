set compatible_mode = oracle;

select greatest(4,5,7,10,2);
select greatest(4,5,7,-10,-2);
select greatest('a','b','A','B');
select greatest(',','.','/',';','!','@','?');
select greatest('瀚','高','数','据','库');
SELECT greatest('HARRY', 'HARRIOT', 'HARRA');
SELECT greatest('HARRY', 'HARRIOT', NULL);
SELECT greatest(1.1, 2.22, 3.33);
SELECT greatest(1, 2, 3);
SELECT greatest(1,' 2', '3' );
SELECT greatest(NULL, NULL, NULL);
SELECT greatest('A', 6, 7, 5000, 'E', 'F','G') A;

SELECT least('HARRY', 'HARRIOT', 'HARRA');
SELECT least('HARRY', 'HARRIOT', NULL);
SELECT least(1.1, 2.22, 3.33);
SELECT least(1, 2, 3);
SELECT least(1,' 2', '3' );
SELECT least(NULL, NULL, NULL);
SELECT least('A', 6, 7, 5000, 'E', 'F','G') A;
select least(1,3,5,10);
select least(-1,3,5,-10);
select least('a','A','b','B');
select least(',','.','/',';','!','@');
select least('瀚','高','据','库');

set compatible_mode to default;
