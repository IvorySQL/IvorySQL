-- Network ACL management, invoker identity, and host matching without external DNS.
SELECT extconfig @> ARRAY['sys.network_acl'::regclass::oid,
  'sys.network_acl_ace'::regclass::oid, 'sys.network_acl_host'::regclass::oid] AS backup_registered
FROM pg_extension WHERE extname = 'ivorysql_ora';
CREATE ROLE acl_allowed;
CREATE ROLE acl_denied;
CREATE ROLE acl_group;
GRANT acl_group TO acl_allowed;

BEGIN
  dbms_network_acl_admin.create_acl('test.xml', 'Resolution privileges', 'acl_allowed', true, 'resolve');
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
  RAISE INFO 'Authorized invoker forward, reverse, and local lookups: ok';
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
  RAISE INFO 'Unauthorized invoker receives ORA-24247 at every entry point';
END;
/
-- Ordinary users cannot bypass administration privileges through private functions or tables.
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

-- Package EXECUTE grants delegate administration and revocation takes effect immediately.
GRANT EXECUTE ON PACKAGE dbms_network_acl_admin TO acl_allowed;
SET ROLE acl_allowed;
BEGIN
  dbms_network_acl_admin.create_acl('delegated.xml', 'Delegated administration', 'acl_allowed', true, 'resolve');
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

-- Check the effective identity of definer functions, not the outer administrator session.
CREATE FUNCTION public.acl_definer_admin() RETURNS pg_catalog.int4
LANGUAGE sql SECURITY DEFINER AS $$ SELECT sys.network_acl_admin('drop', 'test.xml') $$;
/
ALTER FUNCTION public.acl_definer_admin() OWNER TO acl_denied;
SELECT public.acl_definer_admin();
DROP FUNCTION public.acl_definer_admin();

-- connect does not imply resolve; port-specific ACLs do not authorize resolution.
BEGIN
  dbms_network_acl_admin.create_acl('connect.xml', 'Connection privileges', 'acl_denied', true, 'connect');
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
  RAISE INFO 'connect does not grant DNS resolution privileges';
END;
/
RESET ROLE;

-- More specific hosts take precedence; wildcard grants cannot override explicit denials.
BEGIN
  dbms_network_acl_admin.create_acl('group.xml', 'Role privileges', 'acl_group', true, 'resolve');
  dbms_network_acl_admin.create_acl('deny.xml', 'Explicit denial', 'acl_allowed', false, 'resolve');
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

-- Match CIDR, IPv6 subnets, and IPv4-mapped IPv6 using the longest prefix.
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

-- Revoking role membership immediately removes inherited resolution privileges.
REVOKE acl_group FROM acl_allowed;
SELECT sys.network_acl_check('x.example.com', 'acl_allowed'::regrole::oid) AS revoked_role;
GRANT acl_group TO acl_allowed;

-- Fall back when a specific ACL has no applicable ACE; reassignment replaces the binding.
BEGIN
  dbms_network_acl_admin.assign_acl('connect.xml', 'fallback.example.com');
  dbms_network_acl_admin.assign_acl('deny.xml', 'replace.example.com');
  dbms_network_acl_admin.assign_acl('test.xml', 'replace.example.com');
END;
/
SELECT sys.network_acl_check('fallback.example.com', 'acl_allowed'::regrole::oid) AS fallback,
       sys.network_acl_check('replace.example.com', 'acl_allowed'::regrole::oid) AS replacement;

-- More specific denials override PUBLIC wildcard grants.
BEGIN
  dbms_network_acl_admin.create_acl('public.xml', 'Global grant', 'PUBLIC', true, 'resolve');
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

-- Recreating a role with the same name does not inherit grants for the old OID.
CREATE ROLE acl_recreated;
BEGIN
  dbms_network_acl_admin.create_acl('recreated.xml', 'Role lifecycle', 'acl_recreated', true, 'resolve');
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

-- The first matching ACE applies; adding privileges preserves its position and validity.
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

-- Expired and future ACEs do not grant access; validity uses database time.
BEGIN
  dbms_network_acl_admin.create_acl('expired.xml', 'Expired', 'acl_allowed', true, 'resolve',
    NULL, TIMESTAMP '2000-01-01 00:00:00');
  dbms_network_acl_admin.create_acl('future.xml', 'Future', 'acl_allowed', true, 'resolve',
    TIMESTAMP '2999-01-01 00:00:00');
  dbms_network_acl_admin.assign_acl('expired.xml', 'expired.invalid');
  dbms_network_acl_admin.assign_acl('future.xml', 'future.invalid');
END;
/
SELECT sys.network_acl_check('expired.invalid', 'acl_allowed'::regrole::oid) AS expired,
       sys.network_acl_check('future.invalid', 'acl_allowed'::regrole::oid) AS future;

-- Invalid input must not leave partial writes.
BEGIN
  dbms_network_acl_admin.create_acl('invalid.xml', 'Invalid privilege', 'acl_allowed', true, 'CONNECT');
END;
/
BEGIN
  dbms_network_acl_admin.create_acl('invalid.xml', 'Missing user', 'acl_missing', true, 'resolve');
END;
/
BEGIN
  dbms_network_acl_admin.create_acl('invalid.xml', 'Invalid dates', 'acl_allowed', true, 'resolve',
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

-- Transaction rollback undoes privilege changes.
BEGIN;
BEGIN
  dbms_network_acl_admin.delete_privilege('test.xml', 'acl_allowed');
END;
/
ROLLBACK;
SELECT sys.network_acl_check('localhost', 'acl_allowed'::regrole::oid) AS rollback_preserved;

-- Deleting one privilege preserves other privileges in the ACE.
BEGIN
  dbms_network_acl_admin.delete_privilege('test.xml', 'acl_allowed', true, 'connect');
END;
/
SELECT dbms_network_acl_admin.check_privilege('test.xml', 'acl_allowed', 'resolve') AS retained,
       dbms_network_acl_admin.check_privilege('test.xml', 'acl_allowed', 'connect') AS removed;

-- Unassignment preserves the ACL; dropping it removes its ACEs and host bindings.
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
