/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 *-------------------------------------------------------------------------
 *
 * utl_mail.c
 *
 * IvorySQL implementation of the Oracle UTL_MAIL package: high-level email
 * sending built on a compact, dependency-free SMTP client (RFC 5321) with
 * MIME assembly (RFC 2045 / RFC 2046 / RFC 2047) and base64 attachments.
 *
 * The network core was ported from the standalone feasibility prototype
 * contrib/ivorysql_ora/proto/smtp_client.c, which was validated end-to-end
 * against a local mock SMTP server (Chinese RFC 2047 subjects, UTF-8 bodies,
 * multipart/base64 attachments, 550 rejection, connect timeout).  Differences
 * from the prototype:
 *
 *   - main() became PG_FUNCTION_INFO_V1(ora_utl_mail_*); the printf/fatal
 *     plumbing became elog()/ereport() and palloc()-based StringInfo
 *   - the message body is always transport-safe: 7bit when the body is
 *     ASCII, base64 otherwise.  We therefore never depend on the server
 *     advertising 8BITMIME (all widely deployed MTAs accept base64)
 *   - every header value is sanitized against CR/LF header injection,
 *     and addresses are validated so a crafted argument cannot smuggle
 *     extra SMTP commands into the session
 *   - sockets are always closed on error via PG_TRY/PG_CATCH, and all
 *     blocking operations honour utl_mail.timeout
 *
 * Security model (see UTL_MAIL_IMPLEMENTATION.md, §3.2): UTL_MAIL is an
 * outbound-network primitive, so SSRF is the top risk.  Accordingly:
 *
 *   - utl_mail.smtp_out_server and utl_mail.smtp_out_whitelist can only be
 *     set by superusers (checked by the GUC check hooks below, mirroring
 *     the utl_file.umask precedent);
 *   - sending is refused unless the configured server host is explicitly
 *     listed in utl_mail.smtp_out_whitelist, which defaults to empty
 *     ("deny all outbound mail").
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_mail/utl_mail.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "common/string.h"
#include "access/xact.h"
#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/elog.h"
#include "utils/guc.h"
#include "utils/memutils.h"
#include "utils/timestamp.h"

PG_FUNCTION_INFO_V1(ora_utl_mail_send);
PG_FUNCTION_INFO_V1(ora_utl_mail_send_attach_raw);
PG_FUNCTION_INFO_V1(ora_utl_mail_send_attach_varchar2);

/*
 * GUC variables (registered by ivorysql_ora.c _PG_init).
 *
 * utl_mail.smtp_out_server     "host[:port]" of the outbound SMTP server.
 *                              Empty (the default) = UTL_MAIL is disabled and
 *                              every call raises an error.  Superuser-only.
 * utl_mail.smtp_out_domain     HELO/EHLO domain name.  Defaults to the
 *                              machine hostname when not set.
 * utl_mail.smtp_out_whitelist  Comma-separated list of host names / IPs /
 *                              domains allowed as SMTP targets.  Empty (the
 *                              default) = deny all outbound mail.  An entry
 *                              matches the server host if it equals it or is
 *                              one of its parent domains; "*" allows any
 *                              host (explicit opt-in).  Superuser-only.
 * utl_mail.timeout             Timeout in milliseconds for the connect and
 *                              every blocking socket operation.
 * utl_mail.client_id           Optional client identity sent in the EHLO
 *                              command instead of the HELO domain.
 */
char	   *utl_mail_smtp_out_server = NULL;
char	   *utl_mail_smtp_out_domain = NULL;
char	   *utl_mail_smtp_out_whitelist = NULL;
char	   *utl_mail_client_id = NULL;
int			utl_mail_timeout = 10000;	/* milliseconds */

/* GUC check hooks (forward decls exported to ivorysql_ora.c). */
bool		utl_mail_smtp_out_server_check_hook(char **newval, void **extra, GucSource source);
bool		utl_mail_smtp_out_whitelist_check_hook(char **newval, void **extra, GucSource source);
bool		utl_mail_timeout_check_hook(int *newval, void **extra, GucSource source);

/* ---- constants ---- */
#define UTL_MAIL_DEFAULT_PORT			"25"
#define UTL_MAIL_DEFAULT_MIME_TYPE		"text/plain; charset=us-ascii"
#define UTL_MAIL_DEFAULT_ATT_MIME_TYPE	"application/octet"

/*
 * Oracle UTL_MAIL package-level exceptions.  Like the other Oracle packages
 * in this extension (utl_file and friends), the C layer reports the problem
 * by raising a user-visible error whose message is the exception name (plus
 * an errdetail() with the concrete cause), using SQLSTATE P0001 so that a
 * PL/iSQL "WHEN OTHERS" handler can catch it.
 */
#define UTL_MAIL_EX_INVALID_MAILBOX		"UTL_MAIL.INVALID_MAILBOX"
#define UTL_MAIL_EX_EMAIL_SEND_FAILED	"UTL_MAIL.EMAIL_SEND_FAILED"

/* Raises one of the UTL_MAIL package exceptions with a detail line. */
#define UTL_MAIL_RAISE(exname, detail) \
	ereport(ERROR, \
			(errcode(ERRCODE_RAISE_EXCEPTION), \
			 errmsg("%s", (exname)), \
			 (detail) ? errdetail("%s", (detail)) : 0))

/* Forward declarations of static helpers. */
static bool valid_address(const char *addr, char *reason, size_t reasonsz);
static char *trimmed_copy(const char *s);
static char **split_recipient_list(const char *list, const char *what,
								   int *n, char *reason, size_t reasonsz);
static bool host_in_whitelist(const char *host);
static char *parse_server_spec(const char *spec, char *port, size_t portsz);
static char *db_to_utf8(const char *s, int len);
static char *sanitize_header_value(const char *s);
static char *force_utf8_charset(const char *mime_type);
static bool str_is_ascii(const char *s);
static void ensure_crlf(StringInfo msg);
static void append_date_header(StringInfo msg);
static void append_base64(StringInfo msg, const unsigned char *data, size_t len);
static void append_body_with_crlf(StringInfo msg, const char *body);
static void append_rfc2231_filename(StringInfo msg, const char *key,
									const char *filename);
static void build_message(StringInfo msg,
						  const char *sender, const char *recipients,
						  const char *cc, const char *replyto,
						  const char *subject, const char *body,
						  const char *mime_type, int priority,
						  const unsigned char *att_data, size_t att_len,
						  bool att_inline, const char *att_mime_type,
						  const char *att_filename);
static int	smtp_connect(const char *host, const char *port, int timeout_ms);
static void smtp_session(int fd, const char *helo_domain, const char *sender,
						 const char *recipients, const char *cc, const char *bcc,
						 const char *payload, size_t payload_len);
static void utl_mail_common(text *sender_t, text *recipients_t,
							text *cc_t, text *bcc_t,
							text *subject_t, text *message_t,
							text *mime_type_t, int32 priority,
							text *replyto_t,
							const unsigned char *att_data, size_t att_len,
							bool att_inline, text *att_mime_type_t,
							text *att_filename_t);

/*
 * ---------------------------------------------------------------------
 * GUC check hooks
 * ---------------------------------------------------------------------
 * The two network-facing knobs (server address and outbound whitelist) are
 * superuser-only, following the utl_file.umask precedent.  A regular user
 * could otherwise point the server at an internal host (SSRF) or disable
 * the whitelist protection.
 */

/*
 * Shared guard: refuse the change unless we are a superuser.  During
 * process startup / reload (IsNormalProcessingMode() false, or no
 * transaction), every GUC value is applied by the superuser-owned
 * configuration, so the superuser() probe is intentionally skipped then -
 * same reasoning as utl_file_umask_check_hook().
 */
static bool
utl_mail_check_superuser(const char *gucname)
{
	if (IsNormalProcessingMode() && IsTransactionState() && !superuser())
	{
		GUC_check_errcode(ERRCODE_INSUFFICIENT_PRIVILEGE);
		GUC_check_errmsg("permission denied to set parameter \"%s\"", gucname);
		GUC_check_errdetail("Only roles with superuser privileges may change UTL_MAIL network settings.");
		return false;
	}
	return true;
}

/*
 * Accept "host", "host:port", "host:service" or "[ipv6]:port".  The whole
 * spec must be printable ASCII without spaces (a defensive whitelist
 * against crafted values flowing into getaddrinfo()), the host part must be
 * non-empty and a bracketed IPv6 literal must be well formed.
 */
static bool
valid_host_spec(const char *s)
{
	const char *p;
	bool		have_port = false;

	if (s == NULL || s[0] == '\0')
		return false;

	/* whole spec must be printable, non-space ASCII */
	for (p = s; *p; p++)
	{
		unsigned char c = (unsigned char) *p;

		if (c <= 0x20 || c > 0x7e)
			return false;
	}

	if (s[0] == '[')
	{
		p = strchr(s, ']');
		if (p == NULL)
			return false;
		p++;
		if (*p == '\0')
			return true;		/* "[::1]" alone is fine */
		if (*p != ':')
			return false;
		have_port = true;
		p++;
	}
	else
	{
		/* optional trailing ":port" (last colon only: host has no colon) */
		p = strrchr(s, ':');
		if (p != NULL)
		{
			if (p == s)
				return false;	/* empty host */
			have_port = true;
			p++;
		}
		else
			p = s + strlen(s);
	}

	if (have_port && *p == '\0')
		return false;			/* "host:" with an empty port */
	return true;
}

bool
utl_mail_smtp_out_server_check_hook(char **newval, void **extra, GucSource source)
{
	/* empty = UTL_MAIL disabled: always acceptable (it is the default) */
	if (*newval != NULL && (*newval)[0] != '\0' && !valid_host_spec(*newval))
	{
		GUC_check_errcode(ERRCODE_INVALID_PARAMETER_VALUE);
		GUC_check_errmsg("invalid value for parameter \"utl_mail.smtp_out_server\"");
		GUC_check_errdetail("Expected \"host\", \"host:port\" or \"[ipv6]:port\" (or empty to disable UTL_MAIL).");
		return false;
	}
	return utl_mail_check_superuser("utl_mail.smtp_out_server");
}

bool
utl_mail_smtp_out_whitelist_check_hook(char **newval, void **extra, GucSource source)
{
	const char *p = *newval;

	if (p != NULL)
	{
		while (*p)
		{
			while (*p == ',' || *p == ' ' || *p == '\t')
				p++;
			if (*p == '\0')
				break;
			while (*p && *p != ',')
			{
				unsigned char c = (unsigned char) *p;

				if (c <= 0x20 || c > 0x7e)
				{
					GUC_check_errcode(ERRCODE_INVALID_PARAMETER_VALUE);
					GUC_check_errmsg("invalid value for parameter \"utl_mail.smtp_out_whitelist\"");
					GUC_check_errdetail("Expected a comma-separated list of host names, IP addresses or domains.");
					return false;
				}
				p++;
			}
		}
	}
	return utl_mail_check_superuser("utl_mail.smtp_out_whitelist");
}

bool
utl_mail_timeout_check_hook(int *newval, void **extra, GucSource source)
{
	if (*newval < 1 || *newval > 3600000)
	{
		GUC_check_errcode(ERRCODE_INVALID_PARAMETER_VALUE);
		GUC_check_errmsg("\"utl_mail.timeout\" must be between 1 and 3600000 milliseconds");
		return false;
	}
	return true;
}

/*
 * ---------------------------------------------------------------------
 * Address validation
 * ---------------------------------------------------------------------
 * UTL_MAIL takes plain "user@example.com" addresses (no display names).
 * The checks below are deliberately pragmatic rather than RFC-complete:
 * they reject mailboxes that could not work or that would let a caller
 * smuggle data (CR/LF, ",", "<", ">", "(", ")", whitespace, non-ASCII)
 * into SMTP commands or RFC 5322 headers.  When `reason` is non-NULL the
 * first failure description is written there.
 */
static bool
valid_address(const char *addr, char *reason, size_t reasonsz)
{
	const char *p;
	const char *at;
	size_t		local_len;
	size_t		domain_len;

	if (addr == NULL || addr[0] == '\0')
	{
		if (reason)
			snprintf(reason, reasonsz, "mailbox is empty");
		return false;
	}
	if (strlen(addr) > 254)		/* near the RFC 5321 256-byte path limit */
	{
		if (reason)
			snprintf(reason, reasonsz, "mailbox is too long");
		return false;
	}

	/* Exactly one '@' separating local part and domain. */
	at = strchr(addr, '@');
	if (at == NULL)
	{
		if (reason)
			snprintf(reason, reasonsz, "mailbox has no '@'");
		return false;
	}
	if (strchr(at + 1, '@') != NULL)
	{
		if (reason)
			snprintf(reason, reasonsz, "mailbox has more than one '@'");
		return false;
	}

	local_len = at - addr;
	domain_len = strlen(at + 1);
	if (local_len == 0)
	{
		if (reason)
			snprintf(reason, reasonsz, "mailbox has an empty local part");
		return false;
	}
	if (domain_len == 0)
	{
		if (reason)
			snprintf(reason, reasonsz, "mailbox has an empty domain");
		return false;
	}

	/* Reject characters that cannot appear in a bare mailbox. */
	for (p = addr; *p; p++)
	{
		unsigned char c = (unsigned char) *p;

		if (c <= 0x20 || c >= 0x7f ||	/* control / whitespace / non-ASCII */
			c == '<' || c == '>' || c == '(' || c == ')' ||
			c == ',' || c == ';' || c == ':' || c == '"' ||
			c == '\\' || c == '[' || c == ']')
		{
			if (reason)
				snprintf(reason, reasonsz,
						 "character 0x%02x is not allowed in a mailbox", c);
			return false;
		}
	}
	return true;
}

/* strdup-style copy with surrounding whitespace trimmed. */
static char *
trimmed_copy(const char *s)
{
	const char *start = s;
	const char *end;

	while (*start == ' ' || *start == '\t')
		start++;
	end = start + strlen(start);
	while (end > start && (end[-1] == ' ' || end[-1] == '\t'))
		end--;
	return pnstrdup(start, end - start);
}

/*
 * Split a comma-separated recipient header ("a@x.com, b@y.com" and the
 * same for Cc/Bcc) into individually validated addresses.  The whole list
 * is rejected (INVALID_MAILBOX) if any member is empty or malformed, which
 * prevents a typo in one address from silently dropping all other
 * recipients.  On success *n is the number of addresses in a palloc'd
 * array; on failure NULL is returned and `reason` describes the problem.
 */
static char **
split_recipient_list(const char *list, const char *what,
					 int *n, char *reason, size_t reasonsz)
{
	const char *p = list;
	char	  **out;
	int			count = 0;
	int			cap = 8;

	out = palloc(sizeof(char *) * cap);

	/*
	 * Hand-rolled splitter on ',': unlike strtok_r(), consecutive
	 * delimiters are visible here, so an empty member (",,", a leading or
	 * trailing comma) is reported instead of being silently skipped.
	 */
	while (*p)
	{
		const char *start = p;
		const char *end;
		char	   *addr;
		char		tmp[256];

		/* find the end of this member */
		while (*p && *p != ',')
			p++;
		end = p;
		while (start < end && (*start == ' ' || *start == '\t'))
			start++;
		while (end > start && (end[-1] == ' ' || end[-1] == '\t'))
			end--;
		if (end == start)
		{
			snprintf(reason, reasonsz,
					 "%s contains an empty address between commas", what);
			*n = count;
			return NULL;
		}
		addr = pnstrdup(start, end - start);
		if (!valid_address(addr, tmp, sizeof(tmp)))
		{
			/* compose into the caller's buffer after validation (no aliasing) */
			snprintf(reason, reasonsz, "%s has an invalid address: %s",
					 what, tmp);
			*n = count;
			return NULL;
		}
		if (count == cap)
		{
			cap *= 2;
			out = repalloc(out, sizeof(char *) * cap);
		}
		out[count++] = addr;
		if (*p == ',')
			p++;				/* consume the separator */
	}
	*n = count;
	return out;
}

/*
 * ---------------------------------------------------------------------
 * Configuration helpers
 * ---------------------------------------------------------------------
 */

/*
 * Match the configured SMTP server host against the outbound whitelist.
 * An entry matches when it equals the host or is a parent domain of it
 * ("example.com" allows "smtp.example.com"); a leading dot is tolerated;
 * "*" matches every host.  Matching is case-insensitive.
 */
static bool
host_in_whitelist(const char *host)
{
	const char *wl = utl_mail_smtp_out_whitelist;
	char	   *copy;
	char	   *saveptr = NULL;
	char	   *tok;
	bool		ok = false;

	if (wl == NULL || wl[0] == '\0')
		return false;
	copy = pstrdup(wl);
	for (tok = strtok_r(copy, ",", &saveptr); tok != NULL;
		 tok = strtok_r(NULL, ",", &saveptr))
	{
		char	   *entry = trimmed_copy(tok);
		size_t		entry_len;

		if (entry[0] == '\0')
			continue;
		if (strcmp(entry, "*") == 0)
		{
			ok = true;
			break;
		}
		if (entry[0] == '.')
			entry++;			/* a leading dot is tolerated */
		if (pg_strcasecmp(host, entry) == 0)
		{
			ok = true;
			break;
		}
		/* parent-domain match: "a.b.example.com" vs entry "example.com" */
		entry_len = strlen(entry);
		if (strlen(host) > entry_len &&
			pg_strcasecmp(host + (strlen(host) - entry_len), entry) == 0 &&
			host[strlen(host) - entry_len - 1] == '.')
		{
			ok = true;
			break;
		}
	}
	pfree(copy);
	return ok;
}

/*
 * Parse "utl_mail.smtp_out_server" into host + port.  Accepted forms:
 *   "smtp.example.com"       -> port 25
 *   "smtp.example.com:587"   -> port 587 (or any service name)
 *   "[::1]:2525" / "[::1]"   -> IPv6 literal
 * Returns a palloc'd host string; `port` is filled with the port string.
 */
static char *
parse_server_spec(const char *spec, char *port, size_t portsz)
{
	const char *colon;
	const char *hostend;

	if (spec[0] == '[')
	{
		hostend = strchr(spec, ']');
		if (hostend == NULL)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("invalid value \"%s\" for parameter \"utl_mail.smtp_out_server\"",
							spec),
					 errdetail("IPv6 literal is missing its closing bracket.")));
		if (hostend[1] == '\0')
		{
			snprintf(port, portsz, "%s", UTL_MAIL_DEFAULT_PORT);
			return pnstrdup(spec + 1, hostend - (spec + 1));
		}
		if (hostend[1] != ':')
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("invalid value \"%s\" for parameter \"utl_mail.smtp_out_server\"",
							spec),
					 errdetail("Expected \"[ipv6]:port\".")));
		snprintf(port, portsz, "%s", hostend + 2);
		return pnstrdup(spec + 1, hostend - (spec + 1));
	}

	colon = strrchr(spec, ':');
	if (colon != NULL)
	{
		size_t		hostlen = colon - spec;

		if (hostlen == 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("invalid value \"%s\" for parameter \"utl_mail.smtp_out_server\"",
							spec),
					 errdetail("Host part is empty.")));
		snprintf(port, portsz, "%s", colon + 1);
		return pnstrdup(spec, hostlen);
	}

	snprintf(port, portsz, "%s", UTL_MAIL_DEFAULT_PORT);
	return pstrdup(spec);
}

/*
 * ---------------------------------------------------------------------
 * Text / encoding helpers
 * ---------------------------------------------------------------------
 */

/*
 * Convert a server-encoded string to UTF-8 (the encoding we send on the
 * wire, and which RFC 2047 / RFC 2231 encoding uses).  pg_do_encoding_
 * conversion() can return its input pointer unchanged when no conversion
 * was needed, so callers must treat the result as read-only.
 */
static char *
db_to_utf8(const char *s, int len)
{
	return (char *) pg_do_encoding_conversion((unsigned char *) s, len,
											  GetDatabaseEncoding(), PG_UTF8);
}

/* True when the string is pure 7-bit ASCII (safe for any MTA). */
static bool
str_is_ascii(const char *s)
{
	const unsigned char *p = (const unsigned char *) s;

	while (*p)
	{
		if (*p >= 0x80)
			return false;
		p++;
	}
	return true;
}

/*
 * Replace CR/LF with a space so a caller-supplied value that lands in a
 * message header (subject, reply-to, MIME type, attachment name...) cannot
 * inject additional headers or fake SMTP data.  Returns a palloc'd copy.
 */
static char *
sanitize_header_value(const char *s)
{
	char	   *out = pstrdup(s);
	char	   *p;

	for (p = out; *p; p++)
	{
		if (*p == '\r' || *p == '\n')
			*p = ' ';
	}
	return out;
}

/*
 * When the body carries non-ASCII bytes we always send UTF-8, so the
 * Content-Type charset claim must be made to match: reuse the caller's
 * mime_type but replace any "charset=..." (or append if absent).
 * The default Oracle value "text/plain; charset=us-ascii" therefore
 * becomes "...charset=UTF-8" in that case instead of lying about it.
 */
static char *
force_utf8_charset(const char *mime_type)
{
	const char *cs = strstr(mime_type, "charset=");
	const char *end;

	if (cs == NULL)
		return psprintf("%s; charset=UTF-8", mime_type);
	end = strchr(cs, ';');
	if (end == NULL)
		end = cs + strlen(cs);
	return psprintf("%.*scharset=UTF-8%s",
					(int) (cs - mime_type), mime_type, end);
}

/*
 * RFC 5322 date/time header using GMT (a legal and locale-independent
 * representation that avoids DST and timezone-name parsing pitfalls).
 */
static void
append_date_header(StringInfo msg)
{
	static const char *const wday[] = {"Sun", "Mon", "Tue", "Wed",
	"Thu", "Fri", "Sat"};
	static const char *const mon[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
	pg_time_t	now = (pg_time_t) time(NULL);
	struct pg_tm *tm;

	tm = pg_gmtime(&now);
	appendStringInfo(msg, "Date: %s, %02d %s %04d %02d:%02d:%02d +0000\r\n",
					 wday[tm->tm_wday],
					 tm->tm_mday, mon[tm->tm_mon], tm->tm_year + 1900,
					 tm->tm_hour, tm->tm_min, tm->tm_sec);
}

/*
 * ---------------------------------------------------------------------
 * Base64 (RFC 2045) with wrapping at 76 columns
 * ---------------------------------------------------------------------
 */
static const char b64tab[] =
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void
append_base64(StringInfo msg, const unsigned char *src, size_t n)
{
	size_t		i = 0;
	size_t		col = 0;
	char		out[4];

	while (i + 3 <= n)
	{
		uint32		v = ((uint32) src[i] << 16) |
			((uint32) src[i + 1] << 8) | src[i + 2];

		out[0] = b64tab[(v >> 18) & 63];
		out[1] = b64tab[(v >> 12) & 63];
		out[2] = b64tab[(v >> 6) & 63];
		out[3] = b64tab[v & 63];
		appendBinaryStringInfo(msg, out, 4);
		col += 4;
		if (col == 76)
		{
			appendStringInfoString(msg, "\r\n");
			col = 0;
		}
		i += 3;
	}

	if (n - i == 1)
	{
		uint32		v = (uint32) src[i] << 16;

		out[0] = b64tab[(v >> 18) & 63];
		out[1] = b64tab[(v >> 12) & 63];
		out[2] = '=';
		out[3] = '=';
		appendBinaryStringInfo(msg, out, 4);
	}
	else if (n - i == 2)
	{
		uint32		v = ((uint32) src[i] << 16) | ((uint32) src[i + 1] << 8);

		out[0] = b64tab[(v >> 18) & 63];
		out[1] = b64tab[(v >> 12) & 63];
		out[2] = b64tab[(v >> 6) & 63];
		out[3] = '=';
		appendBinaryStringInfo(msg, out, 4);
	}
	/* The final line still needs its CRLF, added by the caller. */
}

/*
 * ---------------------------------------------------------------------
 * MIME assembly
 * ---------------------------------------------------------------------
 */

/*
 * Append user text as the message body, normalizing every line break to
 * CRLF (RFC 5321 requires CRLF between lines; a lone-LF body would
 * otherwise be silently folded together by a strict MTA).
 */
static void
append_body_with_crlf(StringInfo msg, const char *body)
{
	size_t		i = 0;

	while (body[i])
	{
		if (body[i] == '\r')
		{
			/* "\r\n" -> "\r\n"; a bare "\r" is also a line break */
			if (body[i + 1] == '\n')
				i += 2;
			else
				i += 1;
			appendStringInfoString(msg, "\r\n");
		}
		else if (body[i] == '\n')
		{
			appendStringInfoString(msg, "\r\n");
			i += 1;
		}
		else
		{
			appendStringInfoChar(msg, body[i]);
			i += 1;
		}
	}
}

/* Make sure the message buffer ends with a CRLF line terminator. */
static void
ensure_crlf(StringInfo msg)
{
	if (msg->len >= 2 &&
		msg->data[msg->len - 2] == '\r' && msg->data[msg->len - 1] == '\n')
		return;
	if (msg->len > 0 && msg->data[msg->len - 1] == '\n')
		appendStringInfoChar(msg, '\r');	/* plain "\n" -> "\r\n" */
	else
		appendStringInfoString(msg, "\r\n");
}

/*
 * RFC 2231 parameter continuation for non-ASCII attachment names:
 *   ; filename*=UTF-8''<percent-encoded UTF-8 bytes>
 * The parameter is always percent-encoded (RFC 5987 attr-char hygiene),
 * so no header injection is possible through it.  The leading "; " is
 * included so the caller can emit the line "Key: value" + this directly.
 */
static void
append_rfc2231_filename(StringInfo msg, const char *key, const char *filename)
{
	const unsigned char *p = (const unsigned char *) filename;

	appendStringInfo(msg, "; %s*=UTF-8''", key);
	for (; *p; p++)
	{
		unsigned char c = *p;

		/* attr-char from RFC 5987, minus "%" and control chars */
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') ||
			strchr("!#$&+-.^_`|~", c) != NULL)
			appendStringInfoChar(msg, c);
		else
			appendStringInfo(msg, "%%%02X", c);
	}
}

/*
 * Build the full RFC 5322 / MIME message (headers + body and, when
 * attachments are present, a multipart/mixed container with the body in
 * the first part and the base64 attachment in the second).
 *
 * Encoding strategy (transport-safety first, see file header):
 *   - subject: raw when pure ASCII, RFC 2047 "=?utf-8?B?...?=" otherwise
 *   - body:   7bit when pure ASCII, otherwise base64 with a UTF-8 charset
 *              claim so the bytes on the wire never lie about themselves
 *   - attachment: always base64
 * Everything emitted here is CRLF-terminated; dot-stuffing happens at DATA
 * time (smtp_session()).
 */
static void
build_message(StringInfo msg,
			  const char *sender, const char *recipients,
			  const char *cc, const char *replyto,
			  const char *subject, const char *body,
			  const char *mime_type, int priority,
			  const unsigned char *att_data, size_t att_len,
			  bool att_inline, const char *att_mime_type,
			  const char *att_filename)
{
	bool		has_att = (att_data != NULL);
	bool		body_ascii = str_is_ascii(body);
	const char *body_ct;
	char		boundary[64];

	/* Content-Type for the body part: UTF-8 claim iff the body needs it. */
	if (body_ascii)
		body_ct = mime_type;
	else
		body_ct = force_utf8_charset(mime_type);

	/* ---- header block ---- */
	appendStringInfo(msg, "From: %s\r\n", sender);
	appendStringInfo(msg, "To: %s\r\n", recipients);
	if (cc != NULL && cc[0] != '\0')
		appendStringInfo(msg, "Cc: %s\r\n", cc);
	if (replyto != NULL && replyto[0] != '\0')
		appendStringInfo(msg, "Reply-To: %s\r\n", replyto);

	if (subject[0] != '\0')
	{
		if (str_is_ascii(subject))
			appendStringInfo(msg, "Subject: %s\r\n", subject);
		else
		{
			/* RFC 2047 encoded-word with the "B" (base64) encoding */
			appendStringInfoString(msg, "Subject: =?utf-8?B?");
			append_base64(msg, (const unsigned char *) subject, strlen(subject));
			appendStringInfoString(msg, "?=\r\n");
		}
	}
	else
		appendStringInfoString(msg, "Subject: \r\n");

	append_date_header(msg);
	appendStringInfo(msg, "X-Priority: %d\r\n", priority);
	appendStringInfoString(msg, "MIME-Version: 1.0\r\n");

	if (has_att)
	{
		snprintf(boundary, sizeof(boundary), "----=_ivorysql_%06d",
				 (int) getpid());
		appendStringInfo(msg, "Content-Type: multipart/mixed; boundary=\"%s\"\r\n",
						 boundary);
	}
	else
	{
		appendStringInfo(msg, "Content-Type: %s\r\n", body_ct);
		appendStringInfo(msg, "Content-Transfer-Encoding: %s\r\n",
						 body_ascii ? "7bit" : "base64");
	}
	appendStringInfoString(msg, "\r\n");	/* end of headers */

	/* ---- body part ---- */
	if (has_att)
	{
		appendStringInfo(msg, "--%s\r\n", boundary);
		appendStringInfo(msg, "Content-Type: %s\r\n", body_ct);
		appendStringInfo(msg, "Content-Transfer-Encoding: %s\r\n",
						 body_ascii ? "7bit" : "base64");
		appendStringInfoString(msg, "\r\n");
		if (body_ascii)
			append_body_with_crlf(msg, body);
		else
			append_base64(msg, (const unsigned char *) body, strlen(body));
		ensure_crlf(msg);

		/* ---- attachment part ---- */
		appendStringInfo(msg, "--%s\r\n", boundary);
		appendStringInfo(msg, "Content-Type: %s", att_mime_type);
		if (att_filename != NULL && att_filename[0] != '\0')
		{
			if (str_is_ascii(att_filename) && strchr(att_filename, '"') == NULL)
				appendStringInfo(msg, "; name=\"%s\"", att_filename);
			else
				append_rfc2231_filename(msg, "name", att_filename);
		}
		appendStringInfoString(msg, "\r\n");
		appendStringInfo(msg, "Content-Disposition: %s",
						 att_inline ? "inline" : "attachment");
		if (att_filename != NULL && att_filename[0] != '\0')
		{
			if (str_is_ascii(att_filename) && strchr(att_filename, '"') == NULL)
				appendStringInfo(msg, "; filename=\"%s\"", att_filename);
			else
				append_rfc2231_filename(msg, "filename", att_filename);
		}
		appendStringInfoString(msg, "\r\n");
		appendStringInfoString(msg, "Content-Transfer-Encoding: base64\r\n\r\n");
		append_base64(msg, att_data, att_len);
		ensure_crlf(msg);
		appendStringInfo(msg, "--%s--\r\n", boundary);
	}
	else
	{
		if (body_ascii)
			append_body_with_crlf(msg, body);
		else
			append_base64(msg, (const unsigned char *) body, strlen(body));
		ensure_crlf(msg);
	}
}

/*
 * ---------------------------------------------------------------------
 * SMTP client (RFC 5321), ported from proto/smtp_client.c
 * ---------------------------------------------------------------------
 */

/* Opaque reader state for the (blocking, timeout-bound) socket. */
typedef struct
{
	int			fd;
	char		buf[4096];
	size_t		len;
	size_t		pos;
} SockReader;

/* Fill the reader's buffer; 0 on success, -1 on EOF, -2 on timeout. */
static int
read_some(SockReader *r)
{
	ssize_t		n;

	CHECK_FOR_INTERRUPTS();
	n = recv(r->fd, r->buf + r->len, sizeof(r->buf) - r->len, 0);
	if (n == 0)
		return -1;				/* connection closed */
	if (n < 0)
	{
		if (errno == EINTR)
			return 0;
		if (errno == EAGAIN || errno == EWOULDBLOCK)
			return -2;			/* SO_RCVTIMEO expired */
		{
			int			saved_errno = errno;

			/* save errno: ereport() is allowed to clobber it */
			ereport(ERROR,
					(errcode(ERRCODE_IO_ERROR),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("Network read error: %s", strerror(saved_errno))));
		}
	}
	r->len += (size_t) n;
	return 0;
}

/*
 * Read one CRLF-terminated line (CRLF stripped).  Returns 0 on success,
 * -1 on EOF, -2 on timeout.
 */
static int
read_line(SockReader *r, char *out, size_t outsz)
{
	size_t		i;

	while (1)
	{
		for (i = r->pos; i < r->len; i++)
		{
			if (r->buf[i] == '\n')
			{
				size_t		n = i - r->pos;

				if (n > 0 && r->buf[i - 1] == '\r')
					n--;
				if (n >= outsz)
					n = outsz - 1;
				memcpy(out, r->buf + r->pos, n);
				out[n] = '\0';
				r->pos = i + 1;
				if (r->pos == r->len)
					r->pos = r->len = 0;	/* compact the buffer */
				return 0;
			}
		}
		r->pos = r->len;
		{
			int			rc = read_some(r);

			if (rc != 0)
				return rc;
		}
	}
}

/* Send all n bytes, honouring the socket send timeout. */
static void
send_all(int fd, const char *s, size_t n)
{
	while (n > 0)
	{
		ssize_t		w;

		CHECK_FOR_INTERRUPTS();
		w = send(fd, s, n, 0);
		if (w < 0)
		{
			if (errno == EINTR)
				continue;
			if (errno == EAGAIN || errno == EWOULDBLOCK)
				ereport(ERROR,
						(errcode(ERRCODE_IO_ERROR),
						 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
						 errdetail("Timed out writing to the SMTP server")));
			{
				int			saved_errno = errno;

				/* save errno: ereport() is allowed to clobber it */
				ereport(ERROR,
						(errcode(ERRCODE_IO_ERROR),
						 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
						 errdetail("Network write error: %s", strerror(saved_errno))));
			}
		}
		s += w;
		n -= (size_t) w;
	}
}

/* Send one SMTP command line (CRLF appended). */
static void
send_cmd(int fd, const char *fmt,...)
	__attribute__((format(printf, 2, 3)));

static void
send_cmd(int fd, const char *fmt,...)
{
	char		buf[2048];
	int			n;
	va_list		ap;

	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	if (n < 0 || (size_t) n >= sizeof(buf))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("SMTP command too long.")));

	elog(DEBUG1, "UTL_MAIL: C: %s", buf);
	send_all(fd, buf, (size_t) n);
	send_all(fd, "\r\n", 2);
}

/*
 * Read a full SMTP reply, possibly multi-line ("250-..." / "250 ...").
 * Returns the numeric code; on EOF/timeout raises EMAIL_SEND_FAILED with
 * the operation name in the detail.
 */
static int
expect_reply(SockReader *r, const char *what)
{
	char		line[512];
	int			code = -1;

	while (1)
	{
		int			rc = read_line(r, line, sizeof(line));

		if (rc == -1)
			ereport(ERROR,
					(errcode(ERRCODE_PROTOCOL_VIOLATION),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("Connection closed while %s", what)));
		if (rc == -2)
			ereport(ERROR,
					(errcode(ERRCODE_PROTOCOL_VIOLATION),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("Timed out waiting for the SMTP server while %s",
							   what)));

		if (line[0] < '0' || line[0] > '9')
			ereport(ERROR,
					(errcode(ERRCODE_PROTOCOL_VIOLATION),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("SMTP garbage from server while %s: \"%s\"",
							   what, line)));
		if (code < 0)
			code = atoi(line);
		elog(DEBUG1, "UTL_MAIL: S: %s", line);
		if (strlen(line) < 4 || line[3] != '-')
			break;				/* last line of a multi-line reply */
	}
	return code;
}

/* 2xx (and 3xx) are acceptable in the SMTP state machine we run. */
static inline bool
smtp_ok(int code)
{
	return code >= 200 && code <= 399;
}

/*
 * Non-blocking connect with a poll() timeout.  Returns the connected fd.
 * The socket is put back in blocking mode with SO_RCVTIMEO/SO_SNDTIMEO so
 * every later read/write is bounded by the same timeout GUC.
 */
static int
smtp_connect(const char *host, const char *port, int timeout_ms)
{
	struct addrinfo hints;
	struct addrinfo *res = NULL;
	struct addrinfo *ai;
	int			fd = -1;

	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;

	/*
	 * NOTE: getaddrinfo() itself can block on the system resolver; the
	 * timeout only covers the TCP connect.  This matches the prototype
	 * and is a documented v1 limitation.
	 */
	if (getaddrinfo(host, port, &hints, &res) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("Could not resolve SMTP server \"%s:%s\".", host, port)));

	for (ai = res; ai; ai = ai->ai_next)
	{
		int			flags;
		int			crc;
		int			soerr = 0;
		socklen_t	slen = sizeof(soerr);
		struct timeval tv;

		fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
		if (fd < 0)
			continue;

		/* Start the connect non-blocking so we can bound it with poll(). */
		flags = fcntl(fd, F_GETFL, 0);
		if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
		{
			close(fd);
			fd = -1;
			continue;
		}
		crc = connect(fd, ai->ai_addr, ai->ai_addrlen);
		if (crc < 0 && errno != EINPROGRESS)
		{
			close(fd);
			fd = -1;
			continue;
		}
		if (crc < 0)			/* EINPROGRESS: wait for writability */
		{
			struct pollfd pfd;

			pfd.fd = fd;
			pfd.events = POLLOUT;
			pfd.revents = 0;
			do
			{
				CHECK_FOR_INTERRUPTS();
				crc = poll(&pfd, 1, timeout_ms);
			} while (crc < 0 && errno == EINTR);
			if (crc <= 0)
			{
				close(fd);
				fd = -1;
				continue;
			}
		}

		fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);	/* back to blocking */
		if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen) < 0 || soerr != 0)
		{
			close(fd);
			fd = -1;
			continue;
		}

		/* Bound every later blocking read/write by the timeout GUC. */
		tv.tv_sec = timeout_ms / 1000;
		tv.tv_usec = (timeout_ms % 1000) * 1000;
		setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
		setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
		break;
	}
	freeaddrinfo(res);
	if (fd < 0)
		ereport(ERROR,
				(errcode(ERRCODE_CONNECTION_FAILURE),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("Could not connect to SMTP server \"%s:%s\" within %d ms.",
						   host, port, timeout_ms)));
	return fd;
}

/*
 * Run the SMTP dialogue.  All EOF/timeout/4xx/5xx conditions surface as
 * UTL_MAIL.EMAIL_SEND_FAILED with a detail describing the exact failing
 * step (essential for operators chasing flaky outbound mail).
 */
static void
smtp_session(int fd, const char *helo_domain, const char *sender,
			 const char *recipients, const char *cc, const char *bcc,
			 const char *payload, size_t payload_len)
{
	SockReader	rd;
	char		helo[256];
	int			code;
	int			i;
	char	  **to_list;
	char	  **cc_list = NULL;
	char	  **bcc_list = NULL;
	int			nto,
				ncc = 0,
				nbcc = 0;
	char		reason[256];

	/* Re-validate (cheap) and split the envelope recipient lists. */
	to_list = split_recipient_list(recipients, "recipients", &nto,
								   reason, sizeof(reason));
	Assert(to_list != NULL);
	if (cc != NULL && cc[0] != '\0')
		cc_list = split_recipient_list(cc, "cc recipients", &ncc,
									   reason, sizeof(reason));
	if (bcc != NULL && bcc[0] != '\0')
		bcc_list = split_recipient_list(bcc, "bcc recipients", &nbcc,
										reason, sizeof(reason));

	memset(&rd, 0, sizeof(rd));
	rd.fd = fd;

	/* ---- greeting ---- */
	code = expect_reply(&rd, "server greeting");
	if (!smtp_ok(code))
		ereport(ERROR,
				(errcode(ERRCODE_PROTOCOL_VIOLATION),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("SMTP server rejected the greeting: %d", code)));

	/* ---- EHLO (multi-line reply) ---- */
	code = -1;
	snprintf(helo, sizeof(helo), "EHLO %s\r\n", helo_domain);
	send_all(fd, helo, strlen(helo));
	while (1)
	{
		char		line[512];
		int			rc = read_line(&rd, line, sizeof(line));

		if (rc == -1)
			ereport(ERROR,
					(errcode(ERRCODE_PROTOCOL_VIOLATION),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("Connection closed while EHLO")));
		if (rc == -2)
			ereport(ERROR,
					(errcode(ERRCODE_PROTOCOL_VIOLATION),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("Timed out waiting for the SMTP server while EHLO")));
		if (code < 0)
			code = atoi(line);
		elog(DEBUG1, "UTL_MAIL: S: %s", line);
		if (strlen(line) < 4 || line[3] != '-')
			break;				/* last line of the multi-line reply */
	}
	if (code < 200 || code > 399)
		ereport(ERROR,
				(errcode(ERRCODE_PROTOCOL_VIOLATION),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("EHLO rejected: %d", code)));

	/* ---- MAIL FROM ---- */
	send_cmd(fd, "MAIL FROM:<%s>", sender);
	if (!smtp_ok(expect_reply(&rd, "MAIL FROM")))
		ereport(ERROR,
				(errcode(ERRCODE_PROTOCOL_VIOLATION),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("MAIL FROM:<%s> rejected by the SMTP server.", sender)));

	/* ---- RCPT TO (recipients + cc + bcc; bcc stays out of the headers) ---- */
	for (i = 0; i < nto; i++)
	{
		send_cmd(fd, "RCPT TO:<%s>", to_list[i]);
		if (!smtp_ok(expect_reply(&rd, "RCPT TO")))
			ereport(ERROR,
					(errcode(ERRCODE_PROTOCOL_VIOLATION),
					 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
					 errdetail("RCPT TO:<%s> rejected by the SMTP server.",
							   to_list[i])));
	}
	if (cc_list != NULL)
	{
		for (i = 0; i < ncc; i++)
		{
			send_cmd(fd, "RCPT TO:<%s>", cc_list[i]);
			if (!smtp_ok(expect_reply(&rd, "RCPT TO")))
				ereport(ERROR,
						(errcode(ERRCODE_PROTOCOL_VIOLATION),
						 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
						 errdetail("RCPT TO:<%s> rejected by the SMTP server.",
								   cc_list[i])));
		}
	}
	if (bcc_list != NULL)
	{
		for (i = 0; i < nbcc; i++)
		{
			send_cmd(fd, "RCPT TO:<%s>", bcc_list[i]);
			if (!smtp_ok(expect_reply(&rd, "RCPT TO")))
				ereport(ERROR,
						(errcode(ERRCODE_PROTOCOL_VIOLATION),
						 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
						 errdetail("RCPT TO:<%s> rejected by the SMTP server.",
								   bcc_list[i])));
		}
	}

	/* ---- DATA: send the dot-stuffed payload ---- */
	send_cmd(fd, "DATA");
	if (!smtp_ok(expect_reply(&rd, "DATA")))
		ereport(ERROR,
				(errcode(ERRCODE_PROTOCOL_VIOLATION),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("DATA command rejected by the SMTP server.")));

	/*
	 * RFC 5321 §4.5.2 transparency: a line whose first character is '.'
	 * must be doubled when transmitted, so the receiving MTA un-doubles
	 * it and the wire frame "." cannot be spoofed.  One linear scan over
	 * the payload (which we always emit with CRLF line endings) suffices.
	 */
	{
		size_t		start = 0;
		size_t		j;

		for (j = 0; j < payload_len; j++)
		{
			if (payload[j] == '\n')
			{
				if (payload[start] == '.')
					send_all(fd, ".", 1);
				send_all(fd, payload + start, j + 1 - start);
				start = j + 1;
			}
		}
		if (start < payload_len)
		{
			if (payload[start] == '.')
				send_all(fd, ".", 1);
			send_all(fd, payload + start, payload_len - start);
		}
	}
	send_all(fd, "\r\n.\r\n", 5);

	if (!smtp_ok(expect_reply(&rd, "message body")))
		ereport(ERROR,
				(errcode(ERRCODE_PROTOCOL_VIOLATION),
				 errmsg("UTL_MAIL.EMAIL_SEND_FAILED"),
				 errdetail("SMTP server rejected the message body.")));

	/* ---- QUIT (fire and forget: the outcome was reported above) ---- */
	send_cmd(fd, "QUIT");
	(void) expect_reply(&rd, "QUIT");

	elog(DEBUG1, "UTL_MAIL: message queued successfully");
}

/*
 * ---------------------------------------------------------------------
 * Shared implementation for SEND / SEND_ATTACH_RAW / SEND_ATTACH_VARCHAR2
 * ---------------------------------------------------------------------
 */
static void
utl_mail_common(text *sender_t, text *recipients_t,
				text *cc_t, text *bcc_t,
				text *subject_t, text *message_t,
				text *mime_type_t, int32 priority,
				text *replyto_t,
				const unsigned char *att_data, size_t att_len,
				bool att_inline, text *att_mime_type_t,
				text *att_filename_t)
{
	StringInfoData msg;
	char	   *sender;
	char	   *recipients;
	char	   *cc = NULL;
	char	   *bcc = NULL;
	char	   *subject;
	char	   *body;
	char	   *mime_type;
	char	   *replyto = NULL;
	char	   *att_mime_type;
	char	   *att_filename = NULL;
	char	   *server_host;
	char		server_port[64];
	char		helo_domain[256];
	int			fd = -1;

	/* ---- configuration gate ---- */
	if (utl_mail_smtp_out_server == NULL || utl_mail_smtp_out_server[0] == '\0')
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("UTL_MAIL is not configured"),
				 errdetail("Set \"utl_mail.smtp_out_server\" (and allow the server host "
						   "in \"utl_mail.smtp_out_whitelist\") to enable UTL_MAIL.")));

	server_host = parse_server_spec(utl_mail_smtp_out_server,
									server_port, sizeof(server_port));
	if (!host_in_whitelist(server_host))
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("outbound mail blocked by the SMTP whitelist"),
				 errdetail("SMTP server host \"%s\" is not allowed by "
						   "\"utl_mail.smtp_out_whitelist\".", server_host)));

	/* ---- basic argument validation ---- */
	if (sender_t == NULL)
		UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
					   "Sender address is NULL; UTL_MAIL requires a sender.");
	sender = sanitize_header_value(text_to_cstring(sender_t));
	{
		char		sreason[256];

		if (!valid_address(sender, sreason, sizeof(sreason)))
			UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
						   psprintf("Invalid sender address \"%s\": %s.",
									sender, sreason));
	}

	if (recipients_t == NULL)
		UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
					   "Recipient list is NULL; UTL_MAIL requires at least one recipient.");
	recipients = text_to_cstring(recipients_t);
	{
		int			dn = 0;
		char		dreason[256];

		if (split_recipient_list(recipients, "recipients", &dn,
								 dreason, sizeof(dreason)) == NULL)
			UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
						   psprintf("%s.", dreason));
		if (dn == 0)
			UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
						   "The recipient list is empty; provide at least one address.");
	}

	if (cc_t != NULL)
		cc = text_to_cstring(cc_t);
	if (bcc_t != NULL)
		bcc = text_to_cstring(bcc_t);
	if (cc != NULL && cc[0] != '\0')
	{
		int			dn = 0;
		char		dreason[256];

		if (split_recipient_list(cc, "cc recipients", &dn,
								 dreason, sizeof(dreason)) == NULL)
			UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
						   psprintf("%s.", dreason));
	}
	if (bcc != NULL && bcc[0] != '\0')
	{
		int			dn = 0;
		char		dreason[256];

		if (split_recipient_list(bcc, "bcc recipients", &dn,
								 dreason, sizeof(dreason)) == NULL)
			UTL_MAIL_RAISE(UTL_MAIL_EX_INVALID_MAILBOX,
						   psprintf("%s.", dreason));
	}

	if (priority < 1 || priority > 5)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_MAIL: priority must be between 1 and 5"),
				 errdetail("Got priority = %d.", priority)));

	/* ---- defaults ---- */
	subject = subject_t != NULL ? text_to_cstring(subject_t) : "";
	body = message_t != NULL ? text_to_cstring(message_t) : "";
	mime_type = mime_type_t != NULL ? text_to_cstring(mime_type_t)
		: UTL_MAIL_DEFAULT_MIME_TYPE;
	if (replyto_t != NULL)
		replyto = text_to_cstring(replyto_t);
	att_mime_type = att_mime_type_t != NULL ? text_to_cstring(att_mime_type_t)
		: UTL_MAIL_DEFAULT_ATT_MIME_TYPE;
	if (att_filename_t != NULL)
		att_filename = text_to_cstring(att_filename_t);

	/*
	 * Sanitize every caller string that lands in a message header.  The
	 * body is deliberately excluded: its CR/LF are the message's line
	 * structure (handled by CRLF normalization + DATA dot-stuffing), and
	 * they must round-trip.
	 */
	subject = sanitize_header_value(subject);
	mime_type = sanitize_header_value(mime_type);
	att_mime_type = sanitize_header_value(att_mime_type);
	if (replyto)
		replyto = sanitize_header_value(replyto);
	if (att_filename)
		att_filename = sanitize_header_value(att_filename);

	/* ---- convert to UTF-8 for the wire ---- */
	if (!str_is_ascii(subject))
		subject = db_to_utf8(subject, strlen(subject));
	if (!str_is_ascii(body))
		body = db_to_utf8(body, strlen(body));
	if (att_filename && !str_is_ascii(att_filename))
		att_filename = db_to_utf8(att_filename, strlen(att_filename));

	/* ---- MIME assembly (pure memory work, before any network I/O) ---- */
	initStringInfo(&msg);
	build_message(&msg, sender, recipients, cc, replyto,
				  subject, body, mime_type, priority,
				  att_data, att_len, att_inline, att_mime_type, att_filename);

	/* ---- HELO identity ---- */
	if (utl_mail_client_id != NULL && utl_mail_client_id[0] != '\0')
		snprintf(helo_domain, sizeof(helo_domain), "%s", utl_mail_client_id);
	else if (utl_mail_smtp_out_domain != NULL && utl_mail_smtp_out_domain[0] != '\0')
		snprintf(helo_domain, sizeof(helo_domain), "%s", utl_mail_smtp_out_domain);
	else
	{
		if (gethostname(helo_domain, sizeof(helo_domain) - 1) != 0)
			snprintf(helo_domain, sizeof(helo_domain), "localhost");
	}

	/*
	 * SMTP session.  The socket is closed even when the server misbehaves:
	 * every ereport(ERROR) below longjmps into the PG_CATCH handler.
	 */
	PG_TRY();
	{
		fd = smtp_connect(server_host, server_port, utl_mail_timeout);
		smtp_session(fd, helo_domain, sender, recipients, cc, bcc,
					 msg.data, msg.len);
		close(fd);
		fd = -1;
	}
	PG_CATCH();
	{
		if (fd >= 0)
			close(fd);
		PG_RE_THROW();
	}
	PG_END_TRY();
}

/*
 * ---------------------------------------------------------------------
 * C SQL-callable entry points
 * ---------------------------------------------------------------------
 */

/*
 * UTL_MAIL.SEND(sender, recipients[, cc[, bcc[, subject[, message[,
 * mime_type[, priority[, replyto]]]]]]])
 */
Datum
ora_utl_mail_send(PG_FUNCTION_ARGS)
{
	utl_mail_common(
		PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0),
		PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1),
		PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2),
		PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3),
		PG_ARGISNULL(4) ? NULL : PG_GETARG_TEXT_PP(4),
		PG_ARGISNULL(5) ? NULL : PG_GETARG_TEXT_PP(5),
		PG_ARGISNULL(6) ? NULL : PG_GETARG_TEXT_PP(6),
		PG_ARGISNULL(7) ? -1 : PG_GETARG_INT32(7),
		PG_ARGISNULL(8) ? NULL : PG_GETARG_TEXT_PP(8),
		NULL, 0, false, NULL, NULL);
	PG_RETURN_VOID();
}

/*
 * UTL_MAIL.SEND_ATTACH_RAW(sender, recipients[, cc[, bcc[, subject[,
 * message[, mime_type[, priority[, attachment[, att_inline[,
 * att_mime_type[, att_filename]]]]]]]]])
 * The attachment is a RAW / bytea value; its bytes are base64-encoded
 * verbatim (a binary round-trip through the server).
 */
Datum
ora_utl_mail_send_attach_raw(PG_FUNCTION_ARGS)
{
	bytea	   *attach = PG_ARGISNULL(8) ? NULL : PG_GETARG_BYTEA_PP(8);

	utl_mail_common(
		PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0),
		PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1),
		PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2),
		PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3),
		PG_ARGISNULL(4) ? NULL : PG_GETARG_TEXT_PP(4),
		PG_ARGISNULL(5) ? NULL : PG_GETARG_TEXT_PP(5),
		PG_ARGISNULL(6) ? NULL : PG_GETARG_TEXT_PP(6),
		PG_ARGISNULL(7) ? -1 : PG_GETARG_INT32(7),
		NULL,					/* replyto: not part of SEND_ATTACH_* */
		attach ? (const unsigned char *) VARDATA_ANY(attach) : NULL,
		attach ? (size_t) VARSIZE_ANY_EXHDR(attach) : 0,
		PG_ARGISNULL(9) ? false : PG_GETARG_BOOL(9),
		PG_ARGISNULL(10) ? NULL : PG_GETARG_TEXT_PP(10),
		PG_ARGISNULL(11) ? NULL : PG_GETARG_TEXT_PP(11));
	PG_RETURN_VOID();
}

/*
 * UTL_MAIL.SEND_ATTACH_VARCHAR2(... same signature, attachment as text ...)
 * The text is converted from the database encoding to UTF-8 (like the
 * message body), so a Chinese .txt attachment round-trips byte-for-byte.
 */
Datum
ora_utl_mail_send_attach_varchar2(PG_FUNCTION_ARGS)
{
	char	   *attach_cstr = NULL;
	const unsigned char *att_bytes = NULL;
	size_t		att_len = 0;

	if (!PG_ARGISNULL(8))
	{
		attach_cstr = text_to_cstring(PG_GETARG_TEXT_PP(8));
		if (!str_is_ascii(attach_cstr))
			attach_cstr = db_to_utf8(attach_cstr, strlen(attach_cstr));
		att_bytes = (const unsigned char *) attach_cstr;
		att_len = strlen(attach_cstr);
	}

	utl_mail_common(
		PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0),
		PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1),
		PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2),
		PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3),
		PG_ARGISNULL(4) ? NULL : PG_GETARG_TEXT_PP(4),
		PG_ARGISNULL(5) ? NULL : PG_GETARG_TEXT_PP(5),
		PG_ARGISNULL(6) ? NULL : PG_GETARG_TEXT_PP(6),
		PG_ARGISNULL(7) ? -1 : PG_GETARG_INT32(7),
		NULL,					/* replyto: not part of SEND_ATTACH_* */
		att_bytes, att_len,
		PG_ARGISNULL(9) ? false : PG_GETARG_BOOL(9),
		PG_ARGISNULL(10) ? NULL : PG_GETARG_TEXT_PP(10),
		PG_ARGISNULL(11) ? NULL : PG_GETARG_TEXT_PP(11));
	PG_RETURN_VOID();
}