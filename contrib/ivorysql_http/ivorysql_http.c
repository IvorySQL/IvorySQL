/*
 * Copyright 2026 IvorySQL Global Development Team
 * Licensed under the Apache License, Version 2.0. See LICENSE.
 * Bounded UTF-8 HTTP requests. libcurl owns connections only during perform;
 * PostgreSQL contexts own session request/response data.
 */
#include "postgres.h"

#include <curl/curl.h>
#if LIBCURL_VERSION_NUM < 0x075500
#error "ivorysql_http requires libcurl 7.85 or later"
#endif
#include "access/xact.h"
#include "catalog/pg_type_d.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

PG_MODULE_MAGIC;
#define HTTP_MAX_HANDLES 16
#define HTTP_MAX_BODY (1024 * 1024)
#define HTTP_MAX_HEADERS 128
#define HTTP_MAX_HEADER_BYTES (64 * 1024)

typedef struct HttpRequest
{
	struct HttpRequest *next;
	MemoryContext context;
	int			id;
	Oid			owner;
	Oid			session_owner;
	SubTransactionId creator;
	int			phase;			/* 0 = building, 1 = response, 2 = failed/in
								 * progress */
	char	   *url;
	char	   *host;
	int			port;
	char	   *method;
	bool		http10;
	int			timeout;
	int			request_headers;
	char	   *names[HTTP_MAX_HEADERS];
	char	   *values[HTTP_MAX_HEADERS];
	StringInfoData request_body;
	char	   *response_body;
	size_t		response_len;
	size_t		response_pos;
	char	   *raw_headers;
	size_t		raw_header_len;
	bool		overflow;
	bool		text_checked;
	int			response_headers;
	char	   *response_names[HTTP_MAX_HEADERS];
	char	   *response_values[HTTP_MAX_HEADERS];
	long		status;
	char	   *reason;
	char	   *response_version;
} HttpRequest;

static HttpRequest *requests = NULL;
static int	next_id = 1;
static int	transfer_timeout = 30;
static bool initialized = false;

PG_FUNCTION_INFO_V1(ora_http_begin);
PG_FUNCTION_INFO_V1(ora_http_header);
PG_FUNCTION_INFO_V1(ora_http_write);
PG_FUNCTION_INFO_V1(ora_http_response);
PG_FUNCTION_INFO_V1(ora_http_info);
PG_FUNCTION_INFO_V1(ora_http_header_count);
PG_FUNCTION_INFO_V1(ora_http_get_header);
PG_FUNCTION_INFO_V1(ora_http_read);
PG_FUNCTION_INFO_V1(ora_http_close);
PG_FUNCTION_INFO_V1(ora_http_timeout);

static void
http_destroy(HttpRequest *r)
{
	HttpRequest **link = &requests;

	while (*link != r)
		link = &(*link)->next;
	*link = r->next;
	MemoryContextDelete(r->context);
}

static void
http_xact(XactEvent event, void *arg)
{
	if (event == XACT_EVENT_ABORT || event == XACT_EVENT_PARALLEL_ABORT)
		while (requests != NULL)
			http_destroy(requests);
}

static void
http_subxact(SubXactEvent event, SubTransactionId id, SubTransactionId parent, void *arg)
{
	HttpRequest *r = requests;

	while (r != NULL)
	{
		HttpRequest *next = r->next;

		if (r->creator == id)
		{
			if (event == SUBXACT_EVENT_ABORT_SUB)
				http_destroy(r);
			else if (event == SUBXACT_EVENT_COMMIT_SUB)
				r->creator = parent;
		}
		r = next;
	}
}

static void
http_init(void)
{
	if (!initialized)
	{
		if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
			elog(ERROR, "could not initialize libcurl");
		RegisterXactCallback(http_xact, NULL);
		RegisterSubXactCallback(http_subxact, NULL);
		initialized = true;
	}
}

static char *
http_text(FunctionCallInfo fcinfo, int arg)
{
	text	   *v;

	if (PG_ARGISNULL(arg))
		ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED), errmsg("HTTP argument must not be null")));
	v = PG_GETARG_TEXT_PP(arg);
	if (memchr(VARDATA_ANY(v), '\0', VARSIZE_ANY_EXHDR(v)) != NULL)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("HTTP text must not contain NUL bytes")));
	return text_to_cstring(v);
}

static HttpRequest *
http_handle(FunctionCallInfo fcinfo, int phase)
{
	HttpRequest *r;

	if (PG_ARGISNULL(0))
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("HTTP handle must not be null")));
	for (r = requests; r != NULL; r = r->next)
		if (r->id == PG_GETARG_INT32(0))
			break;
	if (r == NULL)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("invalid or closed HTTP handle")));
	if (r->owner != GetUserId() || r->session_owner != GetSessionUserId())
		ereport(ERROR, (errcode(ERRCODE_INSUFFICIENT_PRIVILEGE), errmsg("HTTP handle belongs to another role")));
	if (phase >= 0 && r->phase != phase)
		ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE), errmsg("HTTP operation is not valid in this request state")));
	return r;
}

/* The fixed-path policy function reads only administrator-owned ACL data. */
static char *
http_policy(const char *host, int port)
{
	MemoryContext old = CurrentMemoryContext;
	Oid			types[3] = {TEXTOID, INT4OID, OIDOID};
	Datum		values[3] = {CStringGetTextDatum(host), Int32GetDatum(port), ObjectIdGetDatum(GetUserId())};
	Datum		value;
	bool		isnull;
	char	   *ca_file = NULL;

	SPI_connect();
	if (SPI_execute_with_args("SELECT sys.ora_utl_http_policy($1,$2,$3)", 3, types, values, NULL, true, 1) != SPI_OK_SELECT || SPI_processed != 1)
		elog(ERROR, "could not check HTTP host policy");
	value = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
	if (!isnull)
	{
		MemoryContextSwitchTo(old);
		ca_file = TextDatumGetCString(value);
	}
	SPI_finish();
	if (ca_file == NULL)
		ereport(ERROR, (errcode(ERRCODE_INSUFFICIENT_PRIVILEGE), errmsg("HTTP access to %s:%d is not granted", host, port)));
	return ca_file;
}

Datum
ora_http_begin(PG_FUNCTION_ARGS)
{
	char	   *url = http_text(fcinfo, 0);
	char	   *method = http_text(fcinfo, 1);
	char	   *version = http_text(fcinfo, 2);
	CURLU	   *u;
	char	   *host = NULL,
			   *port = NULL,
			   *scheme = NULL,
			   *user = NULL;
	char		hostbuf[1024];
	int			portnum = 0;
	bool		valid = false;
	HttpRequest *r;
	MemoryContext context;
	MemoryContext old;
	int			count = 0;

	http_init();
	if (GetDatabaseEncoding() != PG_UTF8)
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("UTL_HTTP requires a UTF8 database")));
	if (strlen(url) > 32767 || strpbrk(url, "\r\n") != NULL)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("invalid HTTP URL")));
	if (strcmp(method, "GET") && strcmp(method, "POST") && strcmp(method, "PUT") && strcmp(method, "PATCH") &&
		strcmp(method, "DELETE") && strcmp(method, "HEAD") && strcmp(method, "OPTIONS"))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("unsupported HTTP method")));
	if (strcmp(version, "HTTP/1.1") && strcmp(version, "HTTP/1.0"))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("unsupported HTTP version")));
	u = curl_url();
	if (u == NULL)
		ereport(ERROR, (errcode(ERRCODE_OUT_OF_MEMORY), errmsg("could not allocate HTTP URL parser")));
	if (curl_url_set(u, CURLUPART_URL, url, 0) == CURLUE_OK &&
		curl_url_get(u, CURLUPART_SCHEME, &scheme, 0) == CURLUE_OK &&
		(!strcmp(scheme, "http") || !strcmp(scheme, "https")) &&
		curl_url_get(u, CURLUPART_HOST, &host, 0) == CURLUE_OK && strlen(host) < sizeof(hostbuf) &&
		curl_url_get(u, CURLUPART_PORT, &port, CURLU_DEFAULT_PORT) == CURLUE_OK &&
		curl_url_get(u, CURLUPART_USER, &user, 0) == CURLUE_NO_USER)
	{
		strlcpy(hostbuf, host, sizeof(hostbuf));
		portnum = atoi(port);
		valid = portnum >= 1 && portnum <= 65535;
	}
	curl_free(host);
	curl_free(port);
	curl_free(scheme);
	curl_free(user);
	curl_url_cleanup(u);
	if (!valid)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("expected an HTTP(S) URL without user credentials")));
	pfree(http_policy(hostbuf, portnum));
	for (r = requests; r != NULL; r = r->next)
		count++;
	if (count >= HTTP_MAX_HANDLES || next_id == PG_INT32_MAX)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), errmsg("HTTP request handle limit reached")));
	context = AllocSetContextCreate(TopMemoryContext, "UTL_HTTP request", ALLOCSET_DEFAULT_SIZES);
	old = MemoryContextSwitchTo(context);
	PG_TRY();
	{
		r = palloc0_object(HttpRequest);
		r->context = context;
		r->id = next_id++;
		r->owner = GetUserId();
		r->session_owner = GetSessionUserId();
		r->creator = GetCurrentSubTransactionId();
		r->url = pstrdup(url);
		r->host = pstrdup(hostbuf);
		r->port = portnum;
		r->method = pstrdup(method);
		r->http10 = !strcmp(version, "HTTP/1.0");
		r->timeout = transfer_timeout;
		initStringInfo(&r->request_body);
		r->next = requests;
		requests = r;
	}
	PG_CATCH();
	{
		MemoryContextSwitchTo(old);
		MemoryContextDelete(context);
		PG_RE_THROW();
	}
	PG_END_TRY();
	MemoryContextSwitchTo(old);
	PG_RETURN_INT32(r->id);
}

Datum
ora_http_header(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 0);
	char	   *name = http_text(fcinfo, 1),
			   *value = http_text(fcinfo, 2);
	char	   *p;
	int			i;
	int			j;
	int			total = 0;
	char	   *new_name;
	char	   *new_value;

	if (*name == '\0')
		ereport(ERROR, (errmsg("empty HTTP header name")));
	for (p = name; *p; p++)
		if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || strchr("!#$%&'*+-.^_`|~", *p)))
			ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("invalid HTTP header name")));
	for (p = value; *p; p++)
		if ((unsigned char) *p < 32 || (unsigned char) *p == 127)
			ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("HTTP header values must not contain control characters")));
	if (!pg_strcasecmp(name, "Host") || !pg_strcasecmp(name, "Content-Length") || !pg_strcasecmp(name, "Transfer-Encoding") || !pg_strcasecmp(name, "Connection"))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("HTTP framing headers are managed by libcurl")));
	for (i = 0; i < r->request_headers; i++)
		if (!pg_strcasecmp(name, r->names[i]))
			break;
	if (i == HTTP_MAX_HEADERS)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), errmsg("too many HTTP request headers")));
	for (j = 0; j < r->request_headers; j++)
		if (j != i)
			total += strlen(r->names[j]) + strlen(r->values[j]) + 4;
	if ((size_t) total + strlen(name) + strlen(value) + 4 > HTTP_MAX_HEADER_BYTES)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), errmsg("HTTP request headers exceed the limit")));
	new_name = MemoryContextStrdup(r->context, name);
	new_value = MemoryContextStrdup(r->context, value);
	if (i == r->request_headers)
		r->request_headers++;
	else
	{
		pfree(r->names[i]);
		pfree(r->values[i]);
	}
	r->names[i] = new_name;
	r->values[i] = new_value;
	PG_RETURN_VOID();
}

Datum
ora_http_write(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 0);
	MemoryContext old;
	char	   *value;

	if (PG_ARGISNULL(1))
		PG_RETURN_VOID();
	value = http_text(fcinfo, 1);
	if (strlen(value) + (size_t) r->request_body.len > HTTP_MAX_BODY)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), errmsg("HTTP request body exceeds one MiB")));
	old = MemoryContextSwitchTo(r->context);
	appendStringInfoString(&r->request_body, value);
	MemoryContextSwitchTo(old);
	PG_RETURN_VOID();
}

/* No PostgreSQL allocations or errors while inside libcurl callbacks. */
static size_t
http_body_cb(char *data, size_t size, size_t n, void *arg)
{
	HttpRequest *r = arg;
	size_t		len = size * n;

	if (len > HTTP_MAX_BODY - r->response_len)
	{
		r->overflow = true;
		return 0;
	}
	memcpy(r->response_body + r->response_len, data, len);
	r->response_len += len;
	return len;
}

static size_t
http_header_cb(char *data, size_t size, size_t n, void *arg)
{
	HttpRequest *r = arg;
	size_t		len = size * n;

	if (len >= 5 && !memcmp(data, "HTTP/", 5))
		r->raw_header_len = 0;
	if (len > HTTP_MAX_HEADER_BYTES - r->raw_header_len)
	{
		r->overflow = true;
		return 0;
	}
	memcpy(r->raw_headers + r->raw_header_len, data, len);
	r->raw_header_len += len;
	return len;
}

static int
http_progress(void *arg, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow)
{
	return InterruptPending ? 1 : 0;
}

static void
http_parse_headers(HttpRequest *r)
{
	char	   *line = r->raw_headers;
	char	   *end = strstr(line, "\r\n");
	char	   *reason = strchr(line, ' ');

	if (end == NULL)
		ereport(ERROR, (errmsg("invalid HTTP status line")));
	*end = '\0';
	if (reason == NULL)
		ereport(ERROR, (errmsg("invalid HTTP status line")));
	r->response_version = pnstrdup(line, reason - line);
	if (reason != NULL)
		reason = strchr(reason + 1, ' ');
	r->reason = pstrdup(reason == NULL ? "" : reason + 1);
	line = end + 2;
	while (*line)
	{
		char	   *colon;
		char	   *value;

		end = strstr(line, "\r\n");
		if (end == NULL)
			break;
		*end = '\0';
		colon = strchr(line, ':');
		if (colon != NULL)
		{
			int			i = r->response_headers++;

			if (i == HTTP_MAX_HEADERS)
				ereport(ERROR, (errmsg("too many HTTP response headers")));
			*colon = '\0';
			value = colon + 1;
			while (*value == ' ' || *value == '\t')
				value++;
			r->response_names[i] = pstrdup(line);
			r->response_values[i] = pstrdup(value);
		}
		line = end + 2;
	}
}

Datum
ora_http_response(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 0);
	CURL	   *curl;
	struct curl_slist *volatile headers = NULL;
	CURLcode	result = CURLE_OK;
	char		error[CURL_ERROR_SIZE] = {0};
	char	   *ca_file = http_policy(r->host, r->port);
	MemoryContext old;
	int			i;

	r->phase = 2;
	old = MemoryContextSwitchTo(r->context);
	r->response_body = palloc(HTTP_MAX_BODY + 1);
	r->raw_headers = palloc(HTTP_MAX_HEADER_BYTES + 1);
	MemoryContextSwitchTo(old);
	curl = curl_easy_init();
	if (curl == NULL)
		ereport(ERROR, (errmsg("could not allocate HTTP transfer")));
#define HTTP_OPT(option,value) do { if (curl_easy_setopt(curl,option,value) != CURLE_OK) \
  ereport(ERROR,(errmsg("could not set HTTP transfer option"))); } while (0)
	PG_TRY();
	{
		for (i = 0; i < r->request_headers; i++)
		{
			char	   *line = psprintf("%s: %s", r->names[i], r->values[i]);
			struct curl_slist *next = curl_slist_append(headers, line);

			pfree(line);
			if (next == NULL)
				ereport(ERROR, (errmsg("could not allocate HTTP header list")));
			headers = next;
		}
		HTTP_OPT(CURLOPT_URL, r->url);
		HTTP_OPT(CURLOPT_PROTOCOLS_STR, "http,https");
		HTTP_OPT(CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
		HTTP_OPT(CURLOPT_FOLLOWLOCATION, 0L);
		HTTP_OPT(CURLOPT_PROXY, "");
		HTTP_OPT(CURLOPT_NOSIGNAL, 1L);
		HTTP_OPT(CURLOPT_SSL_VERIFYPEER, 1L);
		HTTP_OPT(CURLOPT_SSL_VERIFYHOST, 2L);
		if (*ca_file)
			HTTP_OPT(CURLOPT_CAINFO, ca_file);
		HTTP_OPT(CURLOPT_TIMEOUT, (long) r->timeout);
		HTTP_OPT(CURLOPT_CONNECTTIMEOUT, (long) r->timeout);
		HTTP_OPT(CURLOPT_HTTP_VERSION, r->http10 ? CURL_HTTP_VERSION_1_0 : CURL_HTTP_VERSION_1_1);
		HTTP_OPT(CURLOPT_CUSTOMREQUEST, r->method);
		HTTP_OPT(CURLOPT_HTTPHEADER, headers);
		if (!strcmp(r->method, "HEAD"))
			HTTP_OPT(CURLOPT_NOBODY, 1L);
		else if (r->request_body.len || !strcmp(r->method, "POST") || !strcmp(r->method, "PUT") || !strcmp(r->method, "PATCH"))
		{
			HTTP_OPT(CURLOPT_POSTFIELDS, r->request_body.data);
			HTTP_OPT(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t) r->request_body.len);
		}
		HTTP_OPT(CURLOPT_WRITEFUNCTION, http_body_cb);
		HTTP_OPT(CURLOPT_WRITEDATA, r);
		HTTP_OPT(CURLOPT_HEADERFUNCTION, http_header_cb);
		HTTP_OPT(CURLOPT_HEADERDATA, r);
		HTTP_OPT(CURLOPT_NOPROGRESS, 0L);
		HTTP_OPT(CURLOPT_XFERINFOFUNCTION, http_progress);
		HTTP_OPT(CURLOPT_ERRORBUFFER, error);
		result = curl_easy_perform(curl);
		curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &r->status);
	}
	PG_FINALLY();
	{
		curl_easy_cleanup(curl);
		curl_slist_free_all(headers);
	}
	PG_END_TRY();
#undef HTTP_OPT
	CHECK_FOR_INTERRUPTS();
	if (r->overflow)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), errmsg("HTTP response exceeds body/header limits")));
	if (result != CURLE_OK)
		ereport(ERROR, (errcode(ERRCODE_CONNECTION_FAILURE), errmsg("HTTP transfer failed: %s", error[0] ? error : curl_easy_strerror(result))));
	r->response_body[r->response_len] = '\0';
	r->raw_headers[r->raw_header_len] = '\0';
	if (memchr(r->raw_headers, '\0', r->raw_header_len) != NULL)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("HTTP headers contain NUL bytes")));
	old = MemoryContextSwitchTo(r->context);
	http_parse_headers(r);
	MemoryContextSwitchTo(old);
	r->phase = 1;
	PG_RETURN_VOID();
}

static ArrayType *
http_text_array(const char **strings, int n)
{
	Datum		values[3];
	int			i;

	for (i = 0; i < n; i++)
	{
		pg_verify_mbstr(PG_UTF8, strings[i], strlen(strings[i]), false);
		values[i] = CStringGetTextDatum(strings[i]);
	}
	return construct_array(values, n, TEXTOID, -1, false, TYPALIGN_INT);
}

Datum
ora_http_info(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 1);
	const char *values[3] = {psprintf("%ld", r->status), r->reason, r->response_version};

	PG_RETURN_ARRAYTYPE_P(http_text_array(values, 3));
}

Datum
ora_http_header_count(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 1);

	PG_RETURN_INT32(r->response_headers);
}

Datum
ora_http_get_header(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 1);
	int			n;
	const char *values[2];

	if (PG_ARGISNULL(1) || PG_GETARG_INT32(1) < 1 || PG_GETARG_INT32(1) > r->response_headers)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("invalid HTTP response header position")));
	n = PG_GETARG_INT32(1) - 1;
	values[0] = r->response_names[n];
	values[1] = r->response_values[n];
	PG_RETURN_ARRAYTYPE_P(http_text_array(values, 2));
}

/* Parse parameters without confusing a quoted value's semicolon for a key. */
static bool
http_ascii_charset(const char *value)
{
	const char *p = value;
	bool		ascii = false;

	while (*p && *p != ';')
		p++;
	while (*p)
	{
		const char *key;
		const char *start;
		int			key_len;
		char		quote = 0;
		char	   *charset;
		bool		escaped = false;

		p++;
		while (*p == ' ' || *p == '\t')
			p++;
		key = p;
		while (*p && *p != '=' && *p != ';' && *p != ' ' && *p != '\t')
			p++;
		key_len = p - key;
		while (*p == ' ' || *p == '\t')
			p++;
		if (*p != '=')
		{
			while (*p && *p != ';')
				p++;
			continue;
		}
		p++;
		while (*p == ' ' || *p == '\t')
			p++;
		if (*p == '"' || *p == '\'')
			quote = *p++;
		start = p;
		while (*p && (quote ? *p != quote : (*p != ';' && *p != ' ' && *p != '\t')))
		{
			if (quote && *p == '\\' && p[1])
			{
				escaped = true;
				p++;
			}
			p++;
		}
		if (key_len == 7 && !pg_strncasecmp(key, "charset", 7))
		{
			charset = pnstrdup(start, p - start);
			if (escaped || (pg_strcasecmp(charset, "utf-8") && pg_strcasecmp(charset, "utf8") && pg_strcasecmp(charset, "us-ascii")))
				ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("HTTP text response charset is not UTF-8 or US-ASCII")));
			ascii = ascii || !pg_strcasecmp(charset, "us-ascii");
			pfree(charset);
		}
		if (quote && *p)
			p++;
		while (*p && *p != ';')
			p++;
	}
	return ascii;
}

Datum
ora_http_read(PG_FUNCTION_ARGS)
{
	HttpRequest *r = http_handle(fcinfo, 1);
	int			len;
	int			bytes;
	text	   *value;

	if (PG_ARGISNULL(1) || PG_GETARG_INT32(1) < 1 || PG_GETARG_INT32(1) > 32767)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("HTTP text read length must be 1..32767 characters")));
	if (!r->text_checked)
	{
		int			i;

		for (i = 0; i < r->response_headers; i++)
			if (!pg_strcasecmp(r->response_names[i], "Content-Type"))
			{
				if (http_ascii_charset(r->response_values[i]))
				{
					size_t		n;

					for (n = 0; n < r->response_len; n++)
						if ((unsigned char) r->response_body[n] > 127)
							ereport(ERROR, (errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE), errmsg("non-ASCII HTTP response body")));
				}
			}
		pg_verify_mbstr(PG_UTF8, r->response_body, r->response_len, false);
		r->text_checked = true;
	}
	if (r->response_pos == r->response_len)
		PG_RETURN_NULL();
	len = PG_GETARG_INT32(1);
	bytes = pg_mbcharcliplen(r->response_body + r->response_pos, r->response_len - r->response_pos, len);
	value = cstring_to_text_with_len(r->response_body + r->response_pos, bytes);
	r->response_pos += bytes;
	PG_RETURN_TEXT_P(value);
}

Datum
ora_http_close(PG_FUNCTION_ARGS)
{
	HttpRequest *r;

	if (PG_ARGISNULL(0))
		PG_RETURN_VOID();
	for (r = requests; r != NULL; r = r->next)
		if (r->id == PG_GETARG_INT32(0))
			break;
	if (r == NULL)
		PG_RETURN_VOID();
	r = http_handle(fcinfo, -1);
	http_destroy(r);
	PG_RETURN_VOID();
}

Datum
ora_http_timeout(PG_FUNCTION_ARGS)
{
	if (!PG_ARGISNULL(0))
	{
		int			n = PG_GETARG_INT32(0);

		if (n < 1 || n > 300)
			ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("HTTP transfer timeout must be 1..300 seconds")));
		transfer_timeout = n;
	}
	PG_RETURN_INT32(transfer_timeout);
}
