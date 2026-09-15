# DBMS_NETWORK_ACL_ADMIN

This implementation provides network ACL administration for issue #2053 and
integrates checks into both UTL_INADDR entry points. It implements seven legacy
Oracle-compatible interfaces: CREATE_ACL, ADD_PRIVILEGE, DELETE_PRIVILEGE,
DROP_ACL, ASSIGN_ACL, UNASSIGN_ACL, and CHECK_PRIVILEGE. Parameter names, defaults,
and grant/deny semantics follow the corresponding Oracle interfaces.
XS$ACE_TYPE interfaces, wallet ACLs, and CHECK_PRIVILEGE_ACLID are not included.
ACL names identify database objects and do not access filesystem paths.

## Privilege semantics

UTL_INADDR retains AUTHID CURRENT_USER and checks the effective invoker's resolve
privilege. The connect privilege can be stored and queried but does not grant
DNS resolution access. Missing authorization or an applicable denial raises
UTL_INADDR.NETWORK_ACCESS_DENIED (ORA-24247) before calling the system resolver.
Resolution failures after authorization still raise UNKNOWN_HOST (ORA-29257).
Omitted and NULL arguments check LOCALHOST, including local hostname retrieval
that does not perform DNS resolution. Direct calls to the underlying C functions
perform the same checks.

Host matching is case-insensitive and ignores one trailing dot. Supported targets
include exact names, *.example.com, *, IPv4, IPv6, IPv4 wildcard subnets, and
IPv4/IPv6 CIDR. IPv4-mapped IPv6 addresses match the corresponding IPv4 addresses.
Equivalent addresses and subnets share a normalized binding. Exact hosts take
precedence over subnets and domains, which use the longest matching prefix or
suffix. If no ACE applies, checking continues with broader bindings. An explicit
denial prevents fallback to a broader grant. Port-specific bindings do not
participate in resolve checks. Port ranges cannot overlap; assigning the same
target again replaces its binding.

The first applicable ACE determines access. Principals support users, inherited
roles, and PUBLIC, and match pg_roles.rolname exactly. Validity includes both
endpoints and uses the current statement timestamp; omitted endpoints are
unbounded. Adding privileges to an existing ACE preserves its position and
validity. CHECK_PRIVILEGE returns 1 for a grant, 0 for a denial, and NULL when no
rule applies. A NULL user argument selects the invoker.

Principal identities use regrole. Recreating a role with the same name does not
inherit the old role's grants. Regranting adds only the newly specified
privileges. Logical backups preserve role names for OID conversion on restore.

## Usage

Only the extension owner and superusers may execute the management package by
default. Administrators can explicitly delegate access:

```sql
GRANT EXECUTE ON PACKAGE dbms_network_acl_admin TO network_admin;

BEGIN
  dbms_network_acl_admin.create_acl(
    acl => 'app_dns.xml', description => 'Application DNS resolution',
    principal => 'app_user', is_grant => true, privilege => 'resolve');
  dbms_network_acl_admin.assign_acl('app_dns.xml', '*.example.com');
  dbms_network_acl_admin.assign_acl('app_dns.xml', 'localhost');
END;
/
COMMIT;
```

Revoke delegation with REVOKE EXECUTE ON PACKAGE dbms_network_acl_admin FROM
network_admin. Changes belong to the caller's transaction and can be rolled back.
Administrative writes are serialized to protect ACE ordering and port ranges.
Storage tables and functions are private. The public C management entry point
checks package EXECUTE privileges before accessing storage. SECURITY DEFINER
functions use a fixed search_path. Authorization decisions are not cached.

## Installation, migration, and rollback

The ivorysql_ora SQL merge list installs the new objects. Make and Meson both
include the new C source. This branch retains extension version 1.0. Replacing
the shared library does not install SQL objects in existing databases. New
clusters initialize the complete extension through the normal build,
installation, and initdb -C normal workflow.

Existing 1.0 clusters require logical migration. Preserve the old binaries, data
directory, and complete logical backup. Install into a separate prefix and
initialize a new cluster. Restore global roles before business databases, grant
the required resolve privileges, and validate applications before switching
connections. Pause writes during final synchronization. Do not load the new SQL
file directly into an existing extension: configuration tables must be registered
during extension installation. There is no in-place ALTER EXTENSION UPDATE path.

All three ACL tables are registered as extension configuration tables. This
branch also fixes pg_dump filtering of built-in extension configuration data.
Use this version of pg_dump to preserve ACLs, ACEs, and bindings. Create the
required roles before restoration so regrole values resolve to their target OIDs.
Remove stale ACEs for deleted roles before backing up to avoid invalid numeric
OIDs in the backup.

For rollback, switch back to the preserved database and binaries. Reconcile any
writes after cutover using the application's rollback procedure first. Individual
ACL changes can be reversed through transaction rollback or the package's deletion
and unassignment interfaces without restarting the database.

## Tests and references

sql/dbms_network_acl_admin.sql is included in ORA_REGRESS. It covers invoker
isolation, delegation, direct-call enforcement, forward/reverse and local lookups,
connect/resolve separation, host and subnet precedence, role revocation and
recreation, validity periods, ports, invalid arguments, rollback, and cleanup.
sql/utl_inaddr.sql establishes explicit ACLs for existing resolver tests.
src/bin/pg_dump/t/007_network_acl.pl verifies configuration backups, role OID
conversion, resolution after restoration, and exclusion filters.

The following Oracle 26 documentation was checked on 2026-09-15 using resolve,
connect, precedence, CREATE_ACL, ADD_PRIVILEGE, and ASSIGN_ACL as search terms:

- [UTL_INADDR](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/UTL_INADDR.html)
- [DBMS_NETWORK_ACL_ADMIN](https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_NETWORK_ACL_ADMIN.html)
- [Fine-grained network access control](https://docs.oracle.com/en/database/oracle/oracle-database/26/dbseg/managing-fine-grained-access-in-pl-sql-packages-and-types.html)

The UTL_INADDR overview mentions connect, while its local-host usage notes and
the CREATE_ACL privilege description explicitly specify resolve for resolution.
This implementation follows those specific resolve requirements. It has not
been tested against a running Oracle instance.
