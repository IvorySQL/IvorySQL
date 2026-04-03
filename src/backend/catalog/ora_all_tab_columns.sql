-- src/backend/catalog/ora_all_tab_columns.sql
-- Oracle兼容 ALL_TAB_COLUMNS 系统视图定义
CREATE OR REPLACE VIEW pg_catalog.ALL_TAB_COLUMNS
(
    OWNER,          -- 模式名（对应Oracle的所有者）
    TABLE_NAME,     -- 表/视图名
    COLUMN_NAME,    -- 列名
    COLUMN_ID,      -- 列序号
    DATA_TYPE,      -- 数据类型
    DATA_LENGTH,    -- 数据长度
    DATA_PRECISION, -- 数值精度
    DATA_SCALE,     -- 小数位
    NULLABLE,       -- 空值标识(Y/N)
    DATA_DEFAULT,   -- 默认值
    TABLE_TYPE,     -- 表类型(TABLE/VIEW)
    CHAR_LENGTH,    -- 字符长度
    CHAR_USED,      -- 字符使用方式(BYTE/CHAR)
    DBA_COLUMN_ID   -- 兼容Oracle的DBA级列ID
)
AS
SELECT
    n.nspname::varchar,
    c.relname::varchar,
    a.attname::varchar,
    a.attnum::numeric,
    CASE
        -- Oracle数据类型 → IvorySQL映射（关键兼容点）
        WHEN t.typname = 'int4' THEN 'NUMBER'
        WHEN t.typname = 'varchar' THEN 'VARCHAR2'
        WHEN t.typname = 'text' THEN 'CLOB'
        WHEN t.typname = 'timestamp' THEN 'DATE'
        ELSE t.typname::varchar
    END,
    -- 修正：保证DATA_LENGTH非负
    CASE WHEN a.atttypmod > 0 THEN GREATEST(a.atttypmod - 4, 0) ELSE NULL END::numeric,
    CASE WHEN t.typname IN ('numeric', 'decimal') THEN (a.atttypmod >> 16) & 65535 ELSE NULL END::numeric,
    CASE WHEN t.typname IN ('numeric', 'decimal') THEN a.atttypmod & 65535 ELSE NULL END::numeric,
    CASE WHEN a.attnotnull THEN 'N' ELSE 'Y' END::varchar,
    -- 修正：默认值NULL时显示空字符串，对齐Oracle
    COALESCE(pg_get_expr(ad.adbin, ad.adrelid)::varchar, '')::varchar,
    CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW' ELSE NULL END::varchar,
    -- 修正：保证CHAR_LENGTH非负
    CASE WHEN t.typname IN ('varchar', 'char') THEN GREATEST(a.atttypmod - 4, 0) ELSE NULL END::numeric,
    CASE WHEN t.typname IN ('varchar', 'char') THEN 'CHAR' ELSE 'BYTE' END::varchar,
    a.attnum::numeric
FROM
    pg_namespace n
    JOIN pg_class c ON n.oid = c.relnamespace
    JOIN pg_attribute a ON c.oid = a.attrelid
    JOIN pg_type t ON a.atttypid = t.oid
    LEFT JOIN pg_attrdef ad ON a.attrelid = ad.adrelid AND a.attnum = ad.adnum
WHERE
    c.relkind IN ('r', 'v')  -- 仅表和视图
    AND a.attnum > 0         -- 排除系统隐藏列
    AND NOT a.attisdropped;  -- 排除已删除列;

-- 授予所有用户查询权限（对齐Oracle的PUBLIC权限）
GRANT SELECT ON pg_catalog.ALL_TAB_COLUMNS TO PUBLIC;

-- 修正：IvorySQL兼容的PUBLIC同义词语法
CREATE OR REPLACE SYNONYM ALL_TAB_COLUMNS FOR pg_catalog.ALL_TAB_COLUMNS;