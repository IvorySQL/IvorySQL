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

CREATE OR REPLACE PACKAGE utl_inaddr AUTHID CURRENT_USER IS
  -- No Oracle network ACL equivalent exists yet; retain the public exception.
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
