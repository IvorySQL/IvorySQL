# UTL_HTTP: bounded UTF-8 HTTP/HTTPS package

This optional extension provides Oracle-style request and response records and
the common text HTTP lifecycle. It requires an Oracle-mode IvorySQL cluster,
`ivorysql_ora`, and libcurl **7.85 or newer** with HTTPS support. Build/install
with the contrib build when pkg-config finds that dependency, or explicitly:

```sh
make -C contrib/ivorysql_http
make -C contrib/ivorysql_http install
# An installed server can instead use make USE_PGXS=1 PG_CONFIG=... .
```

`CURL_CFLAGS` and `CURL_LIBS` can override pkg-config for a custom dependency
location. Make skips the optional module when libcurl is unavailable; Meson
also detects the dependency. A separate Meson/Windows build is not claimed.
The TAP fixture additionally needs Python 3, the openssl command and fork.

Connect through the Oracle port/parser to install and use the public package:

```sql
CREATE EXTENSION ivorysql_http;
```

No network target is allowed initially. As the extension owner, authorize a
specific existing application role, hostname and port:

```sql
INSERT INTO sys.utl_http_host_acl(role_oid,host,port)
SELECT oid,'api.example.com',443 FROM pg_catalog.pg_roles WHERE rolname='app_role';
```

Only the extension owner can change the ACL unless an administrator explicitly
delegates table privileges. Hostnames are lowercase, exact matches, with no
wildcards. Role inheritance follows PostgreSQL USAGE membership. The C code
supplies the actual invoking role to a fixed-path policy function and checks
again before network transfer. There are no ambient proxy settings or automatic
redirects, so authorizing one target does not follow a redirect to another.
URL credentials, non-HTTP protocols and caller-supplied framing headers are
rejected. Header names are validated and values cannot contain controls/NUL.

HTTPS always validates the chain and hostname. NULL `ca_file` uses libcurl's
system certificate store. An administrator may set an ACL row's `ca_file` to a
server-readable PEM CA file for a private CA; application calls cannot disable
verification or choose their own CA path. Oracle Wallet/mutual TLS is not
implemented. The ACL table stores role OIDs: remove obsolete rows when dropping
roles; it is not an implementation of Oracle DBMS_NETWORK_ACL_ADMIN.

```sql
DECLARE
  rq utl_http.req;
  rs utl_http.resp;
  chunk VARCHAR2;
  http_eof EXCEPTION;
  PRAGMA EXCEPTION_INIT(http_eof,-29266);
BEGIN
  utl_http.set_transfer_timeout(10);
  rq:=utl_http.begin_request('https://api.example.com/endpoint','POST');
  utl_http.set_header(rq,'Content-Type','application/json; charset=UTF-8');
  utl_http.write_text(rq,'{"message":"IvorySQL"}');
  rs:=utl_http.get_response(rq);
  dbms_output.put_line(rs.status_code);
  BEGIN
    LOOP
      utl_http.read_text(rs,chunk,1024);
      dbms_output.put_line(chunk);
    END LOOP;
  EXCEPTION WHEN http_eof THEN NULL;
  END;
  utl_http.end_response(rs);
EXCEPTION WHEN OTHERS THEN
  utl_http.end_request(rq);
  RAISE;
END;
/
```

Current master does not parse `WHEN utl_http.end_of_body`; the local
EXCEPTION_INIT alias above catches the same -29266 error without changing the
PL/iSQL core. The package exposes END_OF_BODY for its own handlers. All three
identifier-case modes are tested for the public POST/header/read workflow.

Supported names: BEGIN_REQUEST, SET_HEADER, WRITE_TEXT, GET_RESPONSE,
GET_HEADER_COUNT, GET_HEADER, READ_TEXT, END_RESPONSE, END_REQUEST,
SET_TRANSFER_TIMEOUT, GET_TRANSFER_TIMEOUT and REQUEST. A repeated SET_HEADER
replaces its previous value case-insensitively. Response headers use 1-based
positions. HTTP status errors are returned as status codes, not automatically
raised. REQUEST is a convenience GET returning at most the first 2,000
characters; unsupported proxy/wallet/https_host arguments are rejected.

Resource and compatibility boundaries:

- UTF8 databases and text bodies only. Incoming UTF-8 is verified, US-ASCII
  declarations are checked, and other declared charsets are rejected. Absent
  charset defaults to UTF-8, unlike Oracle's ISO-8859-1 package default. WRITE_TEXT
  sends UTF-8 bytes; set the appropriate Content-Type yourself. Binary/RAW/LOB
  bodies and charset transcoding are outside this version.
- GET_RESPONSE completes and buffers the transfer before returning. READ_TEXT
  walks that buffer by Unicode characters, including across network chunks;
  this is not incremental network streaming. Bodies are capped at one MiB in
  each direction, headers at 64 KiB/128 entries, and open handles at sixteen per
  backend. Large downloads deliberately fail. HTTP/1.0 and HTTP/1.1 are exposed;
  no HTTP/2, decompression, cookie jar or persistent-connection API is claimed.
- The transfer deadline captured by BEGIN_REQUEST is 1–300 seconds (default
  30). Query cancellation is returned from libcurl callbacks before PostgreSQL
  raises the cancellation error. libcurl connections and header lists are
  cleaned on success/error; PostgreSQL contexts own all retained data.
- Handles belong to current/session-user identities and cannot be reused after
  close. Metadata/body buffers can survive commit. Top-level rollback closes
  outstanding handles; subtransaction abort closes handles created there.
  Other mutations of existing session state are not transactionally undone.
  Failed transfers leave a closeable failed handle; explicitly close it when
  catching an error. Closing an already closed/NULL handle is a cleanup no-op.
- Request/response public fields are informational; the private handle selects
  the actual request. Error codes and all Oracle subprograms/semantics are not
  claimed equivalent. No live Oracle comparison was performed.

`t/001_http.pl` uses loopback-only Python HTTP/HTTPS fixtures, including an
ephemeral certificate, so no external service is required by the tests.
