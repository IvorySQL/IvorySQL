-- 网络 ACL 管理、调用者身份及主机匹配回归；不使用外部 DNS。
SELECT extconfig @> ARRAY['sys.network_acl'::regclass::oid,
  'sys.network_acl_ace'::regclass::oid, 'sys.network_acl_host'::regclass::oid] AS backup_registered
FROM pg_extension WHERE extname = 'ivorysql_ora';
CREATE ROLE acl_allowed;
CREATE ROLE acl_denied;
CREATE ROLE acl_group;
GRANT acl_group TO acl_allowed;

BEGIN
  dbms_network_acl_admin.create_acl('test.xml', '解析权限', 'acl_allowed', true, 'resolve');
  dbms_network_acl_admin.assign_acl('test.xml', 'LOCALHOST.');
  dbms_network_acl_admin.assign_acl('test.xml', '127.0.0.1');
  dbms_network_acl_admin.assign_acl('test.xml', '0:0:0:0:0:0:0:1');
END;
/

SET ROLE acl_allowed;
DECLARE
  address VARCHAR2(4000);
BEGIN
  address := utl_inaddr.get_host_address('127.0.0.1');
  IF address != '127.0.0.1' THEN RAISE EXCEPTION 'unexpected address'; END IF;
  address := utl_inaddr.get_host_address('localhost');
  address := utl_inaddr.get_host_name('127.0.0.1');
  address := utl_inaddr.get_host_address('::1');
  address := utl_inaddr.get_host_name();
  RAISE INFO '授权调用者正向、反向及本机查询通过';
END;
/
RESET ROLE;

SET ROLE acl_denied;
DECLARE
  denied EXCEPTION;
  PRAGMA EXCEPTION_INIT(denied, -24247);
  address VARCHAR2(4000);
BEGIN
  BEGIN
    address := utl_inaddr.get_host_address('127.0.0.1');
    RAISE EXCEPTION 'missing forward denial';
  EXCEPTION WHEN denied THEN NULL;
  END;
  BEGIN
    address := utl_inaddr.get_host_name('127.0.0.1');
    RAISE EXCEPTION 'missing reverse denial';
  EXCEPTION WHEN denied THEN NULL;
  END;
  BEGIN
    address := utl_inaddr.get_host_address();
    RAISE EXCEPTION 'missing local address denial';
  EXCEPTION WHEN denied THEN NULL;
  END;
  BEGIN
    address := utl_inaddr.get_host_name();
    RAISE EXCEPTION 'missing local name denial';
  EXCEPTION WHEN denied THEN NULL;
  END;
  BEGIN
    address := utl_inaddr.get_host_address('never-resolve.invalid');
    RAISE EXCEPTION 'missing pre-DNS denial';
  EXCEPTION WHEN denied THEN NULL;
  END;
  RAISE INFO '未授权调用者各入口均返回 ORA-24247';
END;
/
-- 普通用户不能修改 ACL，也不能通过私有函数或数据表绕过管理权限。
BEGIN
  dbms_network_acl_admin.drop_acl('test.xml');
END;
/
SELECT sys.network_acl_admin('drop', 'test.xml');
SELECT sys.network_acl_check('localhost', 'acl_allowed'::regrole::oid);
SELECT sys.network_acl_admin_impl('drop', 'test.xml');
SELECT sys.utl_inaddr_get_host_address('localhost');
DELETE FROM sys.network_acl;
RESET ROLE;

-- 显式委派包执行权即可管理 ACL，撤销后立即失效。
GRANT EXECUTE ON PACKAGE dbms_network_acl_admin TO acl_allowed;
SET ROLE acl_allowed;
BEGIN
  dbms_network_acl_admin.create_acl('delegated.xml', '委派管理', 'acl_allowed', true, 'resolve');
END;
/
SELECT dbms_network_acl_admin.check_privilege('delegated.xml', NULL, 'resolve') AS invoking_user;
BEGIN
  dbms_network_acl_admin.drop_acl('delegated.xml');
END;
/
RESET ROLE;
REVOKE EXECUTE ON PACKAGE dbms_network_acl_admin FROM acl_allowed;
SET ROLE acl_allowed;
SELECT sys.network_acl_admin('drop', 'test.xml');
RESET ROLE;

-- 提权函数的有效身份也必须检查，不能错误地使用外层管理员会话身份。
CREATE FUNCTION public.acl_definer_admin() RETURNS pg_catalog.int4
LANGUAGE sql SECURITY DEFINER AS $$ SELECT sys.network_acl_admin('drop', 'test.xml') $$;
/
ALTER FUNCTION public.acl_definer_admin() OWNER TO acl_denied;
SELECT public.acl_definer_admin();
DROP FUNCTION public.acl_definer_admin();

-- connect 不代替 resolve；端口 ACL 不参与解析权限判定。
BEGIN
  dbms_network_acl_admin.create_acl('connect.xml', '连接权限', 'acl_denied', true, 'connect');
  dbms_network_acl_admin.assign_acl('connect.xml', '127.0.0.2');
  dbms_network_acl_admin.assign_acl('test.xml', '127.0.0.3', 80);
END;
/
SELECT sys.network_acl_check('127.0.0.2', 'acl_denied'::regrole::oid) AS connect_only,
       sys.network_acl_check('127.0.0.3', 'acl_allowed'::regrole::oid) AS port_only;
SET ROLE acl_denied;
DECLARE
  denied EXCEPTION;
  PRAGMA EXCEPTION_INIT(denied, -24247);
  address VARCHAR2(4000);
BEGIN
  address := utl_inaddr.get_host_address('127.0.0.2');
  RAISE EXCEPTION 'connect incorrectly permitted resolution';
EXCEPTION WHEN denied THEN
  RAISE INFO 'connect 不授予 DNS 解析权限';
END;
/
RESET ROLE;

-- 更具体的主机优先，显式拒绝不能被通配授权覆盖。
BEGIN
  dbms_network_acl_admin.create_acl('group.xml', '角色权限', 'acl_group', true, 'resolve');
  dbms_network_acl_admin.create_acl('deny.xml', '显式拒绝', 'acl_allowed', false, 'resolve');
  dbms_network_acl_admin.assign_acl('group.xml', '*.example.com');
  dbms_network_acl_admin.assign_acl('deny.xml', '*.private.example.com');
  dbms_network_acl_admin.assign_acl('test.xml', 'ok.private.example.com');
  dbms_network_acl_admin.assign_acl('group.xml', '192.168.*');
  dbms_network_acl_admin.assign_acl('deny.xml', '192.168.1.*');
  dbms_network_acl_admin.assign_acl('test.xml', '192.168.1.2');
END;
/
SELECT host, sys.network_acl_check(host, 'acl_allowed'::regrole::oid) AS allowed
FROM (VALUES ('x.example.com'), ('X.EXAMPLE.COM.'), ('example.com'),
  ('badexample.com'), ('x.private.example.com'), ('ok.private.example.com'),
  ('192.168.2.1'), ('192.168.1.1'), ('192.168.1.2'), ('192.1680.1.2')) AS hosts(host);

-- CIDR、IPv6 子网和 IPv4 映射 IPv6 统一比较，并选取最长前缀。
BEGIN
  dbms_network_acl_admin.assign_acl('group.xml', '2001:db8::/32');
  dbms_network_acl_admin.assign_acl('deny.xml', '2001:db8:1::/48');
  dbms_network_acl_admin.assign_acl('test.xml', '2001:db8:1::1/128');
  dbms_network_acl_admin.assign_acl('group.xml', '10.0.0.0/8');
  dbms_network_acl_admin.assign_acl('deny.xml', '10.1.0.0/16');
END;
/
SELECT host, sys.network_acl_check(host, 'acl_allowed'::regrole::oid) AS allowed
FROM (VALUES ('2001:db8:2::1'), ('2001:db8:1::2'), ('2001:db8:1::1'),
  ('2001:db9::1'), ('10.2.0.1'), ('10.1.0.1'),
  ('::ffff:192.168.1.2'), ('::ffff:c0a8:101')) AS hosts(host);

-- 角色成员关系撤销后立即失去解析权限。
REVOKE acl_group FROM acl_allowed;
SELECT sys.network_acl_check('x.example.com', 'acl_allowed'::regrole::oid) AS revoked_role;
GRANT acl_group TO acl_allowed;

-- 更具体 ACL 无适用 ACE 时继续匹配父域，重新绑定替换原绑定。
BEGIN
  dbms_network_acl_admin.assign_acl('connect.xml', 'fallback.example.com');
  dbms_network_acl_admin.assign_acl('deny.xml', 'replace.example.com');
  dbms_network_acl_admin.assign_acl('test.xml', 'replace.example.com');
END;
/
SELECT sys.network_acl_check('fallback.example.com', 'acl_allowed'::regrole::oid) AS fallback,
       sys.network_acl_check('replace.example.com', 'acl_allowed'::regrole::oid) AS replacement;

-- PUBLIC 通配授权仍受更具体拒绝限制。
BEGIN
  dbms_network_acl_admin.create_acl('public.xml', '全局授权', 'PUBLIC', true, 'resolve');
  dbms_network_acl_admin.assign_acl('public.xml', '*');
END;
/
SELECT sys.network_acl_check('other.invalid', 'acl_denied'::regrole::oid) AS public_grant,
       sys.network_acl_check('x.private.example.com', 'acl_allowed'::regrole::oid) AS specific_deny;
BEGIN
  dbms_network_acl_admin.unassign_acl(host => '*');
  dbms_network_acl_admin.drop_acl('public.xml');
END;
/

-- 删除并重建同名角色不继承旧 OID 的授权。
CREATE ROLE acl_recreated;
BEGIN
  dbms_network_acl_admin.create_acl('recreated.xml', '角色生命周期', 'acl_recreated', true, 'resolve');
  dbms_network_acl_admin.assign_acl('recreated.xml', 'recreated.invalid');
END;
/
DROP ROLE acl_recreated;
CREATE ROLE acl_recreated;
SELECT sys.network_acl_check('recreated.invalid', 'acl_recreated'::regrole::oid) AS recreated_role;
BEGIN
  dbms_network_acl_admin.add_privilege('recreated.xml', 'acl_recreated', true, 'connect');
END;
/
SELECT dbms_network_acl_admin.check_privilege('recreated.xml', 'acl_recreated', 'resolve') AS old_privilege,
       dbms_network_acl_admin.check_privilege('recreated.xml', 'acl_recreated', 'connect') AS new_privilege;
DROP ROLE acl_recreated;
BEGIN
  dbms_network_acl_admin.delete_privilege('recreated.xml', 'acl_recreated');
END;
/
SELECT count(*) AS stale_aces FROM sys.network_acl_ace WHERE principal = 'acl_recreated';
BEGIN
  dbms_network_acl_admin.drop_acl('recreated.xml');
END;
/

-- 首个匹配 ACE 生效，新增同一 ACE 的权限保持原位置及有效期。
BEGIN
  dbms_network_acl_admin.add_privilege('test.xml', 'acl_allowed', false, 'resolve', 1);
END;
/
SELECT dbms_network_acl_admin.check_privilege('test.xml', 'acl_allowed', 'resolve') AS denied;
BEGIN
  dbms_network_acl_admin.delete_privilege('test.xml', 'acl_allowed', false, 'resolve');
  dbms_network_acl_admin.add_privilege('test.xml', 'acl_allowed', true, 'connect');
END;
/
SELECT dbms_network_acl_admin.check_privilege('/sys/acls/test.xml', 'acl_allowed', 'resolve') AS granted,
       dbms_network_acl_admin.check_privilege('test.xml', 'acl_allowed', 'connect') AS connect_granted,
       dbms_network_acl_admin.check_privilege('test.xml', 'acl_denied', 'resolve') AS unspecified;

-- 过期和未来 ACE 均不授权；有效期边界由数据库时间判断。
BEGIN
  dbms_network_acl_admin.create_acl('expired.xml', '过期', 'acl_allowed', true, 'resolve',
    NULL, TIMESTAMP '2000-01-01 00:00:00');
  dbms_network_acl_admin.create_acl('future.xml', '未来', 'acl_allowed', true, 'resolve',
    TIMESTAMP '2999-01-01 00:00:00');
  dbms_network_acl_admin.assign_acl('expired.xml', 'expired.invalid');
  dbms_network_acl_admin.assign_acl('future.xml', 'future.invalid');
END;
/
SELECT sys.network_acl_check('expired.invalid', 'acl_allowed'::regrole::oid) AS expired,
       sys.network_acl_check('future.invalid', 'acl_allowed'::regrole::oid) AS future;

-- 非法输入不留下部分写入。
BEGIN
  dbms_network_acl_admin.create_acl('invalid.xml', '错误权限', 'acl_allowed', true, 'CONNECT');
END;
/
BEGIN
  dbms_network_acl_admin.create_acl('invalid.xml', '不存在的用户', 'acl_missing', true, 'resolve');
END;
/
BEGIN
  dbms_network_acl_admin.create_acl('invalid.xml', '错误日期', 'acl_allowed', true, 'resolve',
    TIMESTAMP '2030-01-01 00:00:00', TIMESTAMP '2020-01-01 00:00:00');
END;
/
BEGIN
  dbms_network_acl_admin.assign_acl('test.xml', 'localhost', 100, 99);
END;
/
BEGIN
  dbms_network_acl_admin.assign_acl('test.xml', '127.0.0.3', 79, 81);
END;
/
BEGIN
  dbms_network_acl_admin.assign_acl('test.xml', 'bad.*.example.com');
END;
/
SELECT count(*) AS partial_writes FROM sys.network_acl WHERE acl = '/sys/acls/invalid.xml';

-- 事务回滚撤销权限变更。
BEGIN;
BEGIN
  dbms_network_acl_admin.delete_privilege('test.xml', 'acl_allowed');
END;
/
ROLLBACK;
SELECT sys.network_acl_check('localhost', 'acl_allowed'::regrole::oid) AS rollback_preserved;

-- 删除一项权限保留同一 ACE 的其它权限。
BEGIN
  dbms_network_acl_admin.delete_privilege('test.xml', 'acl_allowed', true, 'connect');
END;
/
SELECT dbms_network_acl_admin.check_privilege('test.xml', 'acl_allowed', 'resolve') AS retained,
       dbms_network_acl_admin.check_privilege('test.xml', 'acl_allowed', 'connect') AS removed;

-- 解绑保留 ACL；删除 ACL 同时删除 ACE 和主机绑定。
BEGIN
  dbms_network_acl_admin.unassign_acl('test.xml', '127.0.0.1');
END;
/
SELECT sys.network_acl_check('127.0.0.1', 'acl_allowed'::regrole::oid) AS unassigned;
BEGIN
  dbms_network_acl_admin.drop_acl('test.xml');
  dbms_network_acl_admin.drop_acl('connect.xml');
  dbms_network_acl_admin.drop_acl('group.xml');
  dbms_network_acl_admin.drop_acl('deny.xml');
  dbms_network_acl_admin.drop_acl('expired.xml');
  dbms_network_acl_admin.drop_acl('future.xml');
END;
/
SELECT (SELECT count(*) FROM sys.network_acl) AS acls,
       (SELECT count(*) FROM sys.network_acl_ace) AS aces,
       (SELECT count(*) FROM sys.network_acl_host) AS hosts;
DROP ROLE acl_allowed;
DROP ROLE acl_denied;
DROP ROLE acl_group;
