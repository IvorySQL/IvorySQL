/* Modify ACL storage only through the admin package. Unicode quotes preserve collation C. */
CREATE TABLE sys.network_acl (
  acl text COLLATE pg_catalog.U&"C" PRIMARY KEY,
  description text COLLATE pg_catalog.U&"C"
);
CREATE TABLE sys.network_acl_ace (
  acl text COLLATE pg_catalog.U&"C" NOT NULL REFERENCES sys.network_acl ON DELETE CASCADE,
  principal text COLLATE pg_catalog.U&"C" NOT NULL,
  principal_oid regrole NOT NULL,
  is_grant boolean NOT NULL,
  privileges text[] COLLATE pg_catalog.U&"C" NOT NULL,
  ace_order integer NOT NULL,
  start_date pg_catalog.timestamptz,
  end_date pg_catalog.timestamptz,
  PRIMARY KEY (acl, principal, is_grant),
  CHECK (start_date <= end_date)
);
CREATE TABLE sys.network_acl_host (
  host text COLLATE pg_catalog.U&"C" NOT NULL,
  lower_port integer NOT NULL DEFAULT 0,
  upper_port integer NOT NULL DEFAULT 0,
  acl text COLLATE pg_catalog.U&"C" NOT NULL REFERENCES sys.network_acl ON DELETE CASCADE,
  PRIMARY KEY (host, lower_port, upper_port),
  CHECK ((lower_port = 0 AND upper_port = 0) OR
         (lower_port BETWEEN 1 AND 65535 AND upper_port BETWEEN lower_port AND 65535))
);
REVOKE ALL ON sys.network_acl, sys.network_acl_ace, sys.network_acl_host FROM PUBLIC;
-- Oracle treats empty strings as NULL; use a nonempty filter for this STRICT function.
SELECT pg_catalog.pg_extension_config_dump('sys.network_acl', 'WHERE true');
SELECT pg_catalog.pg_extension_config_dump('sys.network_acl_ace', 'WHERE true');
SELECT pg_catalog.pg_extension_config_dump('sys.network_acl_host', 'WHERE true');

CREATE FUNCTION sys.network_acl_name(value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF value IS NULL OR value = '' OR value ~ '(^|/)\.\.?(/|$)' THEN
    RAISE EXCEPTION 'invalid ACL name' USING ERRCODE = '22023';
  END IF;
  IF left(value, 1) = '/' THEN RETURN value; END IF;
  RETURN '/sys/acls/' || value;
END
$$;

/* Normalize IP addresses with inet; do not resolve names while checking privileges. */
CREATE FUNCTION sys.network_acl_host_name(value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  result text := lower(value);
  address inet;
BEGIN
  IF result IS NULL OR result = '' OR result ~ '[[:space:]%]' THEN
    RAISE EXCEPTION 'invalid network host' USING ERRCODE = '22023';
  END IF;
  IF right(result, 1) = '.' THEN result := left(result, -1); END IF;
  IF result ~ '[:/]' OR result ~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' THEN
    address := result::inet;
    IF family(address) = 6 AND address <<= '::ffff:0.0.0.0/96'::inet THEN
      address := set_masklen('0.0.0.0'::inet + (address - '::ffff:0.0.0.0'::inet), masklen(address) - 96);
    END IF;
    IF position('/' IN result) > 0 AND
       masklen(address) < (CASE WHEN family(address) = 4 THEN 32 ELSE 128 END) THEN
      RETURN network(address)::text;
    END IF;
    RETURN host(address);
  END IF;
  IF result = '*' OR result ~ '^([0-9]{1,3}\.){1,3}\*$' THEN
    IF result != '*' THEN
      address := (replace(result, '*', '0') || repeat('.0', 4 - array_length(string_to_array(result, '.'), 1)))::inet;
      RETURN network(set_masklen(address, (array_length(string_to_array(result, '.'), 1) - 1) * 8))::text;
    END IF;
    RETURN result;
  END IF;
  IF result !~ '^(\*\.)?[a-z0-9_][a-z0-9_.-]*$' OR result ~ '\.\.' THEN
    RAISE EXCEPTION 'invalid network host' USING ERRCODE = '22023';
  END IF;
  RETURN result;
END
$$;

/* Return match specificity; compare IPv4 and IPv4-mapped IPv6 in the same address space. */
CREATE FUNCTION sys.network_acl_host_match(target text, pattern text) RETURNS integer
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  address inet;
  subnet inet;
BEGIN
  IF pattern = target THEN RETURN 10000; END IF;
  IF pattern = '*' THEN RETURN 0; END IF;
  IF left(pattern, 2) = '*.' AND
     right(target, length(pattern) - 1) = substring(pattern FROM 2) THEN
    RETURN length(pattern);
  END IF;
  IF position('/' IN pattern) > 0 OR pattern ~ '^[0-9].*\*$' THEN
    BEGIN
      address := target::inet;
    EXCEPTION WHEN invalid_text_representation THEN RETURN NULL;
    END;
    IF right(pattern, 1) = '*' THEN
      subnet := (replace(pattern, '*', '0') ||
        repeat('.0', 4 - array_length(string_to_array(pattern, '.'), 1)))::inet;
      subnet := set_masklen(subnet, (array_length(string_to_array(pattern, '.'), 1) - 1) * 8);
    ELSE
      subnet := pattern::inet;
    END IF;
    IF family(address) = 4 THEN
      address := '::ffff:0.0.0.0'::inet + (address - '0.0.0.0'::inet);
    END IF;
    IF family(subnet) = 4 THEN
      subnet := set_masklen('::ffff:0.0.0.0'::inet + (subnet - '0.0.0.0'::inet), masklen(subnet) + 96);
    END IF;
    IF address <<= subnet THEN RETURN 100 + masklen(subnet); END IF;
  END IF;
  RETURN NULL;
END
$$;

/* Use the first matching valid ACE and the privileges actually inherited by the invoker. */
CREATE FUNCTION sys.network_acl_privilege(acl_name text, who oid, privilege_name text)
RETURNS integer LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN a.is_grant THEN 1 ELSE 0 END
  FROM sys.network_acl_ace a
  WHERE a.acl = acl_name AND privilege_name = ANY(a.privileges)
    AND (a.start_date IS NULL OR statement_timestamp() >= a.start_date)
    AND (a.end_date IS NULL OR statement_timestamp() <= a.end_date)
    AND (a.principal = 'PUBLIC' OR EXISTS (
      SELECT FROM pg_catalog.pg_roles r
      WHERE r.oid = a.principal_oid AND r.rolname = a.principal
        AND pg_catalog.pg_has_role(who, r.oid, 'USAGE')))
  ORDER BY a.ace_order LIMIT 1
$$;

/* The C caller supplies GetUserId(); users cannot substitute the identity being checked. */
CREATE FUNCTION sys.network_acl_check(host_name text, who oid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  target text;
  binding record;
  decision integer;
BEGIN
  BEGIN
    target := sys.network_acl_host_name(host_name);
  EXCEPTION WHEN invalid_parameter_value OR invalid_text_representation THEN
    target := lower(host_name);
  END;
  FOR binding IN
    SELECT h.acl FROM sys.network_acl_host h
    WHERE h.lower_port = 0 AND sys.network_acl_host_match(target, h.host) IS NOT NULL
    ORDER BY sys.network_acl_host_match(target, h.host) DESC, h.host
  LOOP
    decision := sys.network_acl_privilege(binding.acl, who, 'resolve');
    IF decision IS NOT NULL THEN RETURN decision = 1; END IF;
  END LOOP;
  RETURN false;
END
$$;

/* Serialize administrative writes to preserve ACE ordering and nonoverlapping port ranges. */
CREATE FUNCTION sys.network_acl_admin_impl(action text, acl_name text,
  principal_name text DEFAULT NULL, grant_value boolean DEFAULT NULL,
  privilege_name text DEFAULT NULL, position_value integer DEFAULT NULL,
  start_value pg_catalog.timestamptz DEFAULT NULL,
  end_value pg_catalog.timestamptz DEFAULT NULL,
  host_name text DEFAULT NULL, low_port integer DEFAULT NULL,
  high_port integer DEFAULT NULL, description_value text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  name text;
  target text;
  who oid;
  ace_position integer;
  last_position integer;
  lo integer := coalesce(low_port, 0);
  hi integer := coalesce(high_port, low_port, 0);
BEGIN
  IF action NOT IN ('create', 'add', 'delete', 'drop', 'assign', 'unassign', 'check')
     OR action IS NULL THEN
    RAISE EXCEPTION 'invalid ACL operation' USING ERRCODE = '22023';
  END IF;
  IF action != 'check' THEN
    LOCK TABLE sys.network_acl IN SHARE ROW EXCLUSIVE MODE;
  END IF;
  IF acl_name IS NOT NULL OR action != 'unassign' THEN
    name := sys.network_acl_name(acl_name);
  END IF;
  IF action != 'create' AND name IS NOT NULL AND
     NOT EXISTS (SELECT FROM sys.network_acl a WHERE a.acl = name) THEN
    RAISE EXCEPTION 'ACL does not exist: %', name USING ERRCODE = '42704';
  END IF;
  IF action IN ('create', 'add', 'delete', 'check') THEN
    IF principal_name = 'PUBLIC' THEN who := 0;
    ELSE
      SELECT r.oid INTO who FROM pg_catalog.pg_roles r WHERE r.rolname = principal_name;
      IF principal_name IS NULL OR (who IS NULL AND action != 'delete') THEN
        RAISE EXCEPTION 'unresolved principal: %', principal_name USING ERRCODE = '42704';
      END IF;
    END IF;
    IF (privilege_name IS NULL AND action != 'delete') OR
       privilege_name NOT IN ('connect', 'resolve') THEN
      RAISE EXCEPTION 'invalid network privilege' USING ERRCODE = '22023';
    END IF;
  END IF;
  IF action = 'check' THEN
    RETURN sys.network_acl_privilege(name, who, privilege_name);
  ELSIF action IN ('create', 'add') THEN
    IF grant_value IS NULL THEN
      RAISE EXCEPTION 'is_grant cannot be null' USING ERRCODE = '22023';
    END IF;
    IF action = 'create' THEN
      INSERT INTO sys.network_acl VALUES (name, description_value);
    END IF;
    -- Regranting to a recreated role must not revive other privileges of the old role.
    DELETE FROM sys.network_acl_ace a WHERE a.acl = name
      AND a.principal = principal_name AND a.principal_oid != who;
    SELECT a.ace_order INTO ace_position FROM sys.network_acl_ace a
      WHERE a.acl = name AND a.principal = principal_name AND a.is_grant = grant_value;
    IF ace_position IS NOT NULL THEN
      IF position_value IS NOT NULL THEN
        RAISE EXCEPTION 'ACE already exists' USING ERRCODE = '42710';
      END IF;
      UPDATE sys.network_acl_ace a SET privileges = array_append(a.privileges, privilege_name)
        WHERE a.acl = name AND a.principal = principal_name AND a.is_grant = grant_value
          AND NOT privilege_name = ANY(a.privileges);
    ELSE
      IF start_value > end_value THEN
        RAISE EXCEPTION 'invalid ACE date range' USING ERRCODE = '22023';
      END IF;
      SELECT coalesce(max(a.ace_order), 0) INTO last_position
        FROM sys.network_acl_ace a WHERE a.acl = name;
      ace_position := coalesce(position_value, last_position + 1);
      IF ace_position < 1 OR ace_position > last_position + 1 THEN
        RAISE EXCEPTION 'invalid ACE position' USING ERRCODE = '22023';
      END IF;
      UPDATE sys.network_acl_ace a SET ace_order = a.ace_order + 1
        WHERE a.acl = name AND a.ace_order >= ace_position;
      INSERT INTO sys.network_acl_ace VALUES
        (name, principal_name, who, grant_value, ARRAY[privilege_name],
         ace_position, start_value, end_value);
    END IF;
  ELSIF action = 'delete' THEN
    UPDATE sys.network_acl_ace a SET privileges =
      CASE WHEN privilege_name IS NULL THEN ARRAY[]::text[]
           ELSE array_remove(a.privileges, privilege_name) END
      WHERE a.acl = name AND a.principal = principal_name
        AND (grant_value IS NULL OR a.is_grant = grant_value);
    DELETE FROM sys.network_acl_ace a WHERE a.acl = name AND cardinality(a.privileges) = 0;
    WITH positions AS (
      SELECT a.principal, a.is_grant, row_number() OVER (ORDER BY a.ace_order) AS pos
      FROM sys.network_acl_ace a WHERE a.acl = name)
    UPDATE sys.network_acl_ace a SET ace_order = p.pos FROM positions p
      WHERE a.acl = name AND a.principal = p.principal AND a.is_grant = p.is_grant;
  ELSIF action = 'drop' THEN
    DELETE FROM sys.network_acl a WHERE a.acl = name;
  ELSE
    IF host_name IS NOT NULL OR action = 'assign' THEN
      target := sys.network_acl_host_name(host_name);
    END IF;
    IF (low_port IS NULL AND high_port IS NOT NULL) OR
       (low_port IS NOT NULL AND (lo < 1 OR hi < lo OR hi > 65535)) THEN
      RAISE EXCEPTION 'invalid port range' USING ERRCODE = '22023';
    END IF;
    IF action = 'assign' THEN
      IF lo > 0 AND EXISTS (SELECT FROM sys.network_acl_host h
        WHERE h.host = target AND h.lower_port > 0
          AND lo <= h.upper_port AND hi >= h.lower_port
          AND (lo != h.lower_port OR hi != h.upper_port)) THEN
        RAISE EXCEPTION 'overlapping port range' USING ERRCODE = '22023';
      END IF;
      INSERT INTO sys.network_acl_host VALUES (target, lo, hi, name)
        ON CONFLICT (host, lower_port, upper_port) DO UPDATE SET acl = excluded.acl;
    ELSE
      DELETE FROM sys.network_acl_host h
        WHERE (name IS NULL OR h.acl = name)
          AND (target IS NULL OR (h.host = target AND h.lower_port = lo AND h.upper_port = hi));
    END IF;
  END IF;
  RETURN NULL;
END
$$;

REVOKE ALL ON FUNCTION sys.network_acl_name(text), sys.network_acl_host_name(text),
  sys.network_acl_host_match(text, text),
  sys.network_acl_privilege(text, oid, text), sys.network_acl_check(text, oid),
  sys.network_acl_admin_impl(text, text, text, boolean, text, integer,
    pg_catalog.timestamptz, pg_catalog.timestamptz, text, integer, integer, text) FROM PUBLIC;

-- Share the package permission check; C authorizes access to the private storage implementation.
CREATE FUNCTION sys.network_acl_admin(action text, acl_name text,
  principal_name text DEFAULT NULL, grant_value boolean DEFAULT NULL,
  privilege_name text DEFAULT NULL, position_value integer DEFAULT NULL,
  start_value pg_catalog.timestamptz DEFAULT NULL,
  end_value pg_catalog.timestamptz DEFAULT NULL,
  host_name text DEFAULT NULL, low_port integer DEFAULT NULL,
  high_port integer DEFAULT NULL, description_value text DEFAULT NULL)
RETURNS integer AS 'MODULE_PATHNAME', 'ivorysql_network_acl_admin'
LANGUAGE C VOLATILE PARALLEL UNSAFE;

/* Only administrators may execute this package unless EXECUTE is explicitly granted. */
CREATE PACKAGE dbms_network_acl_admin AUTHID CURRENT_USER AS
  PROCEDURE create_acl(acl VARCHAR2, description VARCHAR2, principal VARCHAR2,
    is_grant BOOLEAN, privilege VARCHAR2,
    start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL, end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL);
  PROCEDURE add_privilege(acl VARCHAR2, principal VARCHAR2, is_grant BOOLEAN,
    privilege VARCHAR2, position INTEGER DEFAULT NULL,
    start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL, end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL);
  PROCEDURE delete_privilege(acl VARCHAR2, principal VARCHAR2,
    is_grant BOOLEAN DEFAULT NULL, privilege VARCHAR2 DEFAULT NULL);
  PROCEDURE drop_acl(acl VARCHAR2);
  PROCEDURE assign_acl(acl VARCHAR2, host VARCHAR2,
    lower_port INTEGER DEFAULT NULL, upper_port INTEGER DEFAULT NULL);
  PROCEDURE unassign_acl(acl VARCHAR2 DEFAULT NULL, host VARCHAR2 DEFAULT NULL,
    lower_port INTEGER DEFAULT NULL, upper_port INTEGER DEFAULT NULL);
  FUNCTION check_privilege(acl VARCHAR2, "user" VARCHAR2, privilege VARCHAR2) RETURN NUMBER;
END;

CREATE PACKAGE BODY dbms_network_acl_admin AS
  PROCEDURE create_acl(acl VARCHAR2, description VARCHAR2, principal VARCHAR2,
    is_grant BOOLEAN, privilege VARCHAR2,
    start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL, end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL) IS
  BEGIN
    PERFORM sys.network_acl_admin('create', acl::text, principal::text, is_grant, privilege::text,
      NULL, start_date::pg_catalog.timestamptz, end_date::pg_catalog.timestamptz,
      description_value => description::text);
  END;
  PROCEDURE add_privilege(acl VARCHAR2, principal VARCHAR2, is_grant BOOLEAN,
    privilege VARCHAR2, position INTEGER DEFAULT NULL,
    start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL, end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL) IS
  BEGIN
    PERFORM sys.network_acl_admin('add', acl::text, principal::text, is_grant, privilege::text,
      position::pg_catalog.int4, start_date::pg_catalog.timestamptz, end_date::pg_catalog.timestamptz);
  END;
  PROCEDURE delete_privilege(acl VARCHAR2, principal VARCHAR2,
    is_grant BOOLEAN DEFAULT NULL, privilege VARCHAR2 DEFAULT NULL) IS
  BEGIN
    PERFORM sys.network_acl_admin('delete', acl::text, principal::text, is_grant, privilege::text);
  END;
  PROCEDURE drop_acl(acl VARCHAR2) IS
  BEGIN
    PERFORM sys.network_acl_admin('drop', acl::text);
  END;
  PROCEDURE assign_acl(acl VARCHAR2, host VARCHAR2,
    lower_port INTEGER DEFAULT NULL, upper_port INTEGER DEFAULT NULL) IS
  BEGIN
    PERFORM sys.network_acl_admin('assign', acl::text, host_name => host::text,
      low_port => lower_port::pg_catalog.int4, high_port => upper_port::pg_catalog.int4);
  END;
  PROCEDURE unassign_acl(acl VARCHAR2 DEFAULT NULL, host VARCHAR2 DEFAULT NULL,
    lower_port INTEGER DEFAULT NULL, upper_port INTEGER DEFAULT NULL) IS
  BEGIN
    PERFORM sys.network_acl_admin('unassign', acl::text, host_name => host::text,
      low_port => lower_port::pg_catalog.int4, high_port => upper_port::pg_catalog.int4);
  END;
  FUNCTION check_privilege(acl VARCHAR2, "user" VARCHAR2, privilege VARCHAR2) RETURN NUMBER IS
  BEGIN
    RETURN sys.network_acl_admin('check', acl::text, coalesce("user"::text, current_user::text),
      privilege_name => privilege::text);
  END;
END;
