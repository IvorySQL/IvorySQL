/***************************************************************
 *
 * UTL_INADDR Package
 *
 * Oracle-compatible host name and IP address resolution functions.
 *
 ***************************************************************/

CREATE FUNCTION sys.utl_inaddr_get_host_address(host text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_inaddr_get_host_address'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.utl_inaddr_get_host_name(ip text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_inaddr_get_host_name'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

COMMENT ON FUNCTION sys.utl_inaddr_get_host_address(text) IS
  'Internal implementation of UTL_INADDR.GET_HOST_ADDRESS';
COMMENT ON FUNCTION sys.utl_inaddr_get_host_name(text) IS
  'Internal implementation of UTL_INADDR.GET_HOST_NAME';

-- AUTHID CURRENT_USER 包需要调用权限；直接调用也在 C 层强制检查同一 ACL。
GRANT EXECUTE ON FUNCTION sys.utl_inaddr_get_host_address(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION sys.utl_inaddr_get_host_name(text) TO PUBLIC;

CREATE OR REPLACE PACKAGE utl_inaddr AUTHID CURRENT_USER IS
  -- C 层在解析前检查调用者的 resolve 权限，拒绝时使用相同异常码。
  NETWORK_ACCESS_DENIED EXCEPTION;
  PRAGMA EXCEPTION_INIT(NETWORK_ACCESS_DENIED, -24247);

  UNKNOWN_HOST EXCEPTION;
  PRAGMA EXCEPTION_INIT(UNKNOWN_HOST, -29257);

  FUNCTION GET_HOST_ADDRESS(host IN VARCHAR2 DEFAULT NULL)
    RETURN VARCHAR2;

  FUNCTION GET_HOST_NAME(ip IN VARCHAR2 DEFAULT NULL)
    RETURN VARCHAR2;
END utl_inaddr;

CREATE OR REPLACE PACKAGE BODY utl_inaddr IS
  FUNCTION GET_HOST_ADDRESS(host IN VARCHAR2 DEFAULT NULL)
    RETURN VARCHAR2 IS
    v_address VARCHAR2(4000);
  BEGIN
    v_address := sys.utl_inaddr_get_host_address(host);
    IF v_address IS NULL THEN
      RAISE UNKNOWN_HOST;
    END IF;
    RETURN v_address;
  END GET_HOST_ADDRESS;

  FUNCTION GET_HOST_NAME(ip IN VARCHAR2 DEFAULT NULL)
    RETURN VARCHAR2 IS
    v_hostname VARCHAR2(4000);
  BEGIN
    v_hostname := sys.utl_inaddr_get_host_name(ip);
    IF v_hostname IS NULL THEN
      RAISE UNKNOWN_HOST;
    END IF;
    RETURN v_hostname;
  END GET_HOST_NAME;
END utl_inaddr;

-- Packages default to no PUBLIC privileges at all (unlike plain FUNCTION/
-- PROCEDURE, which grant EXECUTE to PUBLIC by default) -- without this,
-- only the role that ran CREATE EXTENSION could call any subprogram here.
GRANT EXECUTE ON PACKAGE utl_inaddr TO PUBLIC;
