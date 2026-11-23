# DBMS_METADATA 实现任务说明(handoff)

> 目标:在 IvorySQL `contrib/ivorysql_ora` 实现 Oracle `DBMS_METADATA`(对象 DDL 提取)。
> 仓库现状:**无 issue、无 PR,完全空白**;EDB EPAS 已实现(参考其文档行为)。
> 价值:Oracle 迁移/备份工具链刚需——GET_DDL 是数据迁移脚本生成的核心。

## 1. Oracle 官方 API(重点:GET_DDL)

```sql
FUNCTION DBMS_METADATA.GET_DDL (
    object_type  IN VARCHAR2,        -- 'TABLE','VIEW','INDEX','SEQUENCE',...
    name         IN VARCHAR2,
    schema       IN VARCHAR2 DEFAULT NULL,   -- 默认当前 schema
    version      IN VARCHAR2 DEFAULT 'COMPATIBLE',
    model        IN VARCHAR2 DEFAULT 'ORACLE',
    transform    IN VARCHAR2 DEFAULT 'DDL')
    RETURN CLOB;

-- 次要(二期):GET_XML / SET_XML / PARSE_XML、OPEN/FETCH_CLOB/CLOSE(游标多对象)、
-- ADD_TRANSFORM/SET_TRANSFORM_PARAM/SET_REMAP_PARAM/DELETE_TRANSFORM
```

Oracle 行为要点:
- 对象不存在 → 抛异常(ORA-31603 object "X" of type Y does not exist)
- 输出到 CLOB,含完整 CREATE 语句(列、约束、注释、分区等)
- TABLE 默认还带出 COMMENT、约束、授权(EDB/IvorySQL 可裁剪为"CREATE TABLE + 约束")

## 2. 实现思路(IIvorySQL 侧)

### 2.1 组装方式
首选:纯 SQL/PL 用 **PG 自带 DDL 辅助函数**拼装各对象类型的 CREATE 语句:

| object_type | 拼装素材(PG 现成函数/目录) |
|---|---|
| TABLE | pg_get_constraintdef、format_type、attnotnull/attdef、pg_attribute/pg_constraint/pg_class(**列+NOT NULL+默认+主外键/唯一/检查**),参考 pg_dump 的表格 schema 输出逻辑 |
| VIEW | pg_get_viewdef + 列? |
| SEQUENCE | pg_sequences / pg_get_serial_sequence(INCREMENT/START/MIN/MAX/CACHE/CYCLE 语法) |
| INDEX | pg_get_indexdef |
| FUNCTION/PROCEDURE | pg_get_functiondef(+参数、返回类型、VOLATILE/STRICT 子句) |
| TRIGGER | pg_get_triggerdef |
| MATERIALIZED VIEW(可选) | pg_get_viewdef + REFRESH 子句 |
| SYNONYM(若 ivorysql 有)/ PACKAGE(PL/iSQL 已支持) | 视能力补充 |

- 输出要**兼容 Oracle 风格**:对象名按 oracle 模式的大小写/引号规则(schema 限定、大写未引号标识符);
  摸清现有 `sys.*` 内置函数与 `SYS.ORA_CASE_TRANS` 等先例做一致性处理。
- 更稳的备选(若拼装太碎):内部封装 `pg_dump --schema-only` 的部分逻辑(仅做参考,不引进程)。

### 2.2 错误语义
- 对象不存在 / 类型不支持 → 抛 PL/iSQL 异常,消息对齐 Oracle 的 "object ... does not exist"(先查现有异常消息先例)。

### 2.3 模块布局
```
src/builtin_packages/dbms_metadata/
    dbms_metadata.c         # C:TYPE 输出大字符串(必要时);或全 PL/iSQL
    dbms_metadata--1.0.sql  # sys.ora_dbms_metadata_get_ddl(...) + CREATE PACKAGE DBMS_METADATA
```
按现有包惯例(C + SQL 转发 + PL/iSQL PACKAGE),`GET_DDL(object_type,name,schema)` 三个参数主入口,MVP 先支持 6–8 个常用类型。

## 3. 接线清单(4 处,照旧)
- Makefile:OBJS + ORA_REGRESS += dbms_metadata
- meson.build:sources
- ivorysql_ora_merge_sqls:加 `src/builtin_packages/dbms_metadata/dbms_metadata`
- (无 GUC,若需要可加,本期不需要)

## 4. 回归测试计划(~25 用例)

写入 `sql/dbms_metadata.sql` + expected:

1. 基本:TABLE(建表:列类型 xx→varchar2/number/date 映射、NOT NULL、默认值)
2. TABLE 带主键/外键/唯一/检查约束(pg_get_constraintdef 拼接)
3. TABLE 带索引(单独 INDEX 类型)
4. VIEW(pg_get_viewdef,列注释可选)
5. SEQUENCE(INCREMENT/START/MIN/MAX/CACHE/CYCLE 全子句)
6. FUNCTION / PROCEDURE(签名+返回+volatile 子句)
7. TRIGGER
8. 多 schema:指定 schema 参数;默认当前会话 schema
9. 不存在对象 → 兼容错误消息(断言错误文本)
10. 不支持的类型 → 明确报错(如 'PACKAGE BODY' 未实现)
11. 巨大对象(100+ 列表)→ 不截断、性能可接受
12. 特殊字符标识符(小写列名/引号)→ oracle 模式大小写规则
13. COMMENT ON(可选扩展)连带
14. 参数 NULL 语义:name/schema NULL
15. 幂等性:GET_DDL 连续调用输出一致;输出可回灌(建出来的 DDL 再 CREATE 成功,roundtrip 测试(除 SEQUENCE CACHE 等易变项))
16. 空表/零列边界(不允许,但验证不崩)
17. 与 pg 模式交互(compatible_mode=postgres 下 GET_DDL 仍可用,行为一致)
18. 类型映射表覆盖:varchar2/number/numeric/date/timestamp/boolean/array
19. 继承表/分区表(若 oracle 语法拼装支持)
20. 权限:无权限用户能拿自己 schema;拿别人 schema → 错误或降级(按 Oracle 语义)
21–25. 组合:多约束多索引大表、嵌套注释、视图依赖函数、序列与串行列对照、触发器多个

验收:installcheck 全绿;每类型 golden 输出人工核对;roundtrip 测试至少覆盖 TABLE/VIEW/SEQUENCE/FUNCTION。

## 5. 工作量估算

| 项 | 人日 |
|---|---|
| TABLE 组装(列/约束/默认,最重要最费) | 2–3 |
| VIEW/SEQUENCE/INDEX/TRIGGER/FUNCTION | 1–2 |
| oracle 模式大小写/引号/schema 规则 | 1 |
| 错误语义 + 接线 | 0.5 |
| 回归(~25 用例)+ 文档/评审 | 1–1.5 |
| **MVP 合计** | **≈ 6–8 人日** |

二期:GET_XML/SET_XML、OPEN/FETCH_CLOB 游标多对象、REMAP、SYNONYM/PACKAGE/MVIEW 扩展 ≈ +5 人日。

## 6. 验收清单
- [ ] 构建通过(Makefile + meson)
- [ ] 6–8 常见类型 GET_DDL 输出与 Oracle 语义一致(自建对象对照)
- [ ] roundtrip:输出 DDL 能重新 CREATE 成功
- [ ] 不存在/不支持类型错误消息正确
- [ ] 回归 + 模式交互全绿