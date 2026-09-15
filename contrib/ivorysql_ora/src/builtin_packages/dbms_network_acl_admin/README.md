# DBMS_NETWORK_ACL_ADMIN

此实现为 issue #2053 提供网络 ACL 管理，并接入 `UTL_INADDR` 两个解析入口。
管理包提供 `CREATE_ACL`、`ADD_PRIVILEGE`、`DELETE_PRIVILEGE`、`DROP_ACL`、
`ASSIGN_ACL`、`UNASSIGN_ACL` 和 `CHECK_PRIVILEGE` 七个 Oracle 兼容接口。
它们的参数名、默认值和授权/拒绝语义对应 Oracle 的传统 ACL 接口。
不包含依赖 Oracle XML DB、Real Application Security 的 `XS$ACE_TYPE` 接口、
钱包 ACL 或 `CHECK_PRIVILEGE_ACLID`；ACL 名称为数据库内标识，不读写文件系统。

## 权限语义

`UTL_INADDR` 保留 `AUTHID CURRENT_USER`，使用实际有效用户的 `resolve` 权限。
`connect` 可以存储和查询，但不授予 DNS 解析权限。未找到有效授权或者匹配显式拒绝时，
在调用系统解析器前抛出 `UTL_INADDR.NETWORK_ACCESS_DENIED`（ORA-24247）。
权限检查通过后的解析失败仍抛出 `UNKNOWN_HOST`（ORA-29257）。
省略参数及 NULL 参数均检查 `LOCALHOST`，包括不执行 DNS 的本机名称查询。
底层 C 函数也执行同样检查，因此公开执行权不会绕过 ACL。

主机和域名不区分大小写，忽略末尾的一个点，支持完整域名、`*.example.com`、`*`、
IPv4、IPv6、IPv4 通配子网以及 IPv4/IPv6 CIDR。IPv4 映射 IPv6 地址与 IPv4
统一匹配；等价 IP 和子网规范化后共享绑定。
完整主机优先于子网/域名，子网按最长前缀匹配，域名按最长后缀匹配。
没有适用 ACE 时继续检查更宽泛的绑定；遇到显式拒绝后不再使用宽泛授权。
带端口范围的绑定只存储连接权限的适用范围，不参与 `resolve` 检查。
同一主机的端口范围不能重叠，重绑完全相同的目标会替换原绑定。

ACE 按位置顺序匹配，支持直接用户、继承角色及 `PUBLIC`。
principal 按 `pg_roles.rolname` 精确匹配，通常使用小写；引号创建的角色保留大小写。
有效期包含起止时刻，按当前语句时间判定；未指定边界表示无该侧限制。
为现有 ACE 添加权限保留其位置和有效期。`CHECK_PRIVILEGE` 返回 1、0 或 NULL，
分别表示授权、拒绝、无适用规则；user 为 NULL 时使用调用者。
角色标识使用 `regrole` 持久化，兼顾角色重建隔离和逻辑备份时的名称转换。
删除再创建同名角色不会继承旧授权；重新授权只添加新指定的权限。

## 使用方式

管理包默认仅扩展所有者及超级用户可执行。管理员可以显式委派：

```sql
GRANT EXECUTE ON PACKAGE dbms_network_acl_admin TO network_admin;

BEGIN
  dbms_network_acl_admin.create_acl(
    acl => 'app_dns.xml', description => '应用 DNS 解析',
    principal => 'app_user', is_grant => true, privilege => 'resolve');
  dbms_network_acl_admin.assign_acl('app_dns.xml', '*.example.com');
  dbms_network_acl_admin.assign_acl('app_dns.xml', 'localhost');
END;
/
COMMIT;
```

撤销委派执行 `REVOKE EXECUTE ON PACKAGE dbms_network_acl_admin FROM network_admin`。
管理写入属于调用者事务，可以回滚；并发管理操作串行化以保护 ACE 顺序与端口范围。
管理表及存储函数不向普通用户开放，公开的 C 管理入口会先检查管理包执行权限。
所有提升身份的存储函数固定 `search_path`，运行期每次检查 ACL，不缓存授权决定。

## 安装、迁移和回滚

新增对象由 `ivorysql_ora` 的 SQL 合并清单安装，Make 和 Meson 均包含新增 C 文件。
此分支沿用仓库的扩展版本 1.0；替换共享库不会自动为已有数据库安装新增 SQL 对象。
新集群使用正常构建、安装和 `initdb -C normal` 即可初始化完整扩展。

已有 1.0 集群应采用逻辑迁移：保留旧二进制、旧数据目录及完整逻辑备份，安装到独立
前缀并初始化新集群，先恢复全局角色，再恢复业务数据库，配置所需 `resolve` ACL，
验证应用后切换连接。在最终同步期间暂停业务写入，确保备份与切换点一致。
不要将新增 SQL 文件直接灌入旧扩展：配置表登记必须在扩展安装上下文内执行。
本功能没有提供原地 `ALTER EXTENSION UPDATE` 路径。

ACL 三张表已登记为扩展配置表，`pg_dump` 会保留 ACL、ACE 和绑定。
本分支同时修复 `pg_dump` 对内置扩展配置表的筛选；备份应使用此版本的工具。
恢复前应创建对应角色，以便 `regrole` 转换到目标集群的角色 OID。
清理已删除角色的旧 ACE 后再备份，避免备份中保留失效的数字 OID。
回滚时切回保留的旧数据库与旧二进制；切换后已有新写入时，必须先按业务方案回放差异。
撤销某项 ACL 变更可使用事务回滚或包的删除/解绑接口，无须重启数据库。

## 验证和依据

`sql/dbms_network_acl_admin.sql` 已加入 `ORA_REGRESS`，覆盖调用者隔离、管理委派、
直接调用防绕过、正反向及本机查询、connect/resolve 区分、主机/子网优先级、
角色撤销/重建、有效期、端口范围、非法参数、事务回滚及清理。
`sql/utl_inaddr.sql` 为原有解析测试建立和清理显式 ACL。
`src/bin/pg_dump/t/007_network_acl.pl` 验证内置扩展配置备份、角色 OID 转换、
恢复后的实际解析和备份排除条件。

文档核对日期：2026-09-15。检索关键词为 `resolve`、`connect`、`precedence`、
`CREATE_ACL`、`ADD_PRIVILEGE`、`ASSIGN_ACL`，采用以下 Oracle 26 官方资料：

- [UTL_INADDR](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/UTL_INADDR.html)
- [DBMS_NETWORK_ACL_ADMIN](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_NETWORK_ACL_ADMIN.html)
- [细粒度网络访问控制](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/managing-fine-grained-access-in-pl-sql-packages-and-types.html)

`UTL_INADDR` 概述写 `connect`，与其本机查询说明和 `CREATE_ACL` 的具体权限说明存在冲突。
此实现遵循后两者明确规定的 `resolve` 语义；没有声称已在 Oracle 实例上做双端对照测试。
