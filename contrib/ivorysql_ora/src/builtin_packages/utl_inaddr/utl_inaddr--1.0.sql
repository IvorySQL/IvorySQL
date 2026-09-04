/***************************************************************
 *
 * UTL_INADDR Package
 *
 * Oracle 兼容的主机名与 IP 地址解析函数。
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
  'UTL_INADDR.GET_HOST_ADDRESS 的内部实现';
COMMENT ON FUNCTION sys.utl_inaddr_get_host_name(text) IS
  'UTL_INADDR.GET_HOST_NAME 的内部实现';

CREATE OR REPLACE PACKAGE utl_inaddr AUTHID CURRENT_USER IS
  -- 当前尚无 Oracle 网络 ACL 的等价实现，仅保留公开异常以兼容接口。
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
