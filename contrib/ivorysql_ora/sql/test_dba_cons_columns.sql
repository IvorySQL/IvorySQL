-- 测试 DBA_CONS_COLUMNS 视图是否存在
SELECT count(*) > 0 AS view_exists
FROM information_schema.views 
WHERE table_schema = 'sys' AND table_name = 'dba_cons_columns';

-- 测试查询是否能返回数据（至少不报错）
SELECT * FROM sys.dba_cons_columns LIMIT 1;
