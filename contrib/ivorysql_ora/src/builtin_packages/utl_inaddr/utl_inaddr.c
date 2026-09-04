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
 * Oracle UTL_INADDR host name and address resolution.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_inaddr/utl_inaddr.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <netdb.h>
#include <sys/socket.h>

#include "common/ip.h"
#include "fmgr.h"
#include "port.h"
#include "utils/builtins.h"

PG_FUNCTION_INFO_V1(ivorysql_utl_inaddr_get_host_address);
PG_FUNCTION_INFO_V1(ivorysql_utl_inaddr_get_host_name);

static char *utl_inaddr_local_hostname(bool short_name);
static char *utl_inaddr_resolve_address(const char *host);
static char *utl_inaddr_resolve_name(const char *address);

/*
 * Read the local host name.  The NULL branch of GET_HOST_NAME returns only
 * the short name, so strip the first dot and the domain that follows it.
 * Address lookup continues to use the complete name.
 */
static char *
utl_inaddr_local_hostname(bool short_name)
{
	char		hostname[NI_MAXHOST];
	char	   *dot;

	if (gethostname(hostname, sizeof(hostname)) != 0)
		return NULL;

	hostname[sizeof(hostname) - 1] = '\0';
	if (hostname[0] == '\0')
		return NULL;

	if (short_name && (dot = strchr(hostname, '.')) != NULL)
		*dot = '\0';

	return pstrdup(hostname);
}

/*
 * Resolve a host name to a numeric IPv4 or IPv6 address.  Preserve the system
 * resolver's address order, matching Oracle's contract of returning one
 * address for a multihomed host.
 */
static char *
utl_inaddr_resolve_address(const char *host)
{
	struct addrinfo hints;
	struct addrinfo *addresses = NULL;
	struct addrinfo *address;
	char		numeric_host[NI_MAXHOST];
	char	   *result = NULL;
	int			ret;

	MemSet(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;

	ret = pg_getaddrinfo_all(host, NULL, &hints, &addresses);
	if (ret != 0 || addresses == NULL)
	{
		if (addresses != NULL)
			pg_freeaddrinfo_all(hints.ai_family, addresses);
		return NULL;
	}

	for (address = addresses; address != NULL; address = address->ai_next)
	{
		if (address->ai_family != AF_INET && address->ai_family != AF_INET6)
			continue;

		ret = pg_getnameinfo_all((const struct sockaddr_storage *) address->ai_addr,
							  address->ai_addrlen,
							  numeric_host, sizeof(numeric_host),
							  NULL, 0,
							  NI_NUMERICHOST);
		if (ret == 0)
		{
			result = pstrdup(numeric_host);
			break;
		}
	}

	pg_freeaddrinfo_all(hints.ai_family, addresses);
	return result;
}

/*
 * Reverse-resolve a numeric IPv4 or IPv6 address.  AI_NUMERICHOST prevents
 * arbitrary text from being resolved as a host name, while NI_NAMEREQD makes
 * an address without a PTR or hosts entry return UNKNOWN_HOST instead of the
 * original address.
 */
static char *
utl_inaddr_resolve_name(const char *address_text)
{
	struct addrinfo hints;
	struct addrinfo *addresses = NULL;
	struct addrinfo *address;
	char		hostname[NI_MAXHOST];
	char	   *result = NULL;
	int			ret;

	MemSet(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_NUMERICHOST;

	ret = pg_getaddrinfo_all(address_text, NULL, &hints, &addresses);
	if (ret != 0 || addresses == NULL)
	{
		if (addresses != NULL)
			pg_freeaddrinfo_all(hints.ai_family, addresses);
		return NULL;
	}

	for (address = addresses; address != NULL; address = address->ai_next)
	{
		if (address->ai_family != AF_INET && address->ai_family != AF_INET6)
			continue;

		ret = pg_getnameinfo_all((const struct sockaddr_storage *) address->ai_addr,
							  address->ai_addrlen,
							  hostname, sizeof(hostname),
							  NULL, 0,
							  NI_NAMEREQD);
		if (ret == 0)
		{
			result = pstrdup(hostname);
			break;
		}
	}

	pg_freeaddrinfo_all(hints.ai_family, addresses);
	return result;
}

/*
 * UTL_INADDR.GET_HOST_ADDRESS returns one numeric address for a host name.
 * NULL means to resolve the local host name.  Resolution failures return NULL
 * for the PL/iSQL package to convert to the public UNKNOWN_HOST exception.
 */
Datum
ivorysql_utl_inaddr_get_host_address(PG_FUNCTION_ARGS)
{
	char	   *host;
	char	   *address;

	if (PG_ARGISNULL(0))
		host = utl_inaddr_local_hostname(false);
	else
		host = text_to_cstring(PG_GETARG_TEXT_PP(0));

	if (host == NULL)
		PG_RETURN_NULL();

	address = utl_inaddr_resolve_address(host);
	pfree(host);

	if (address == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(address));
}

/*
 * UTL_INADDR.GET_HOST_NAME reverse-resolves a numeric address.  NULL returns
 * the local short name without its domain.  Resolution failures are likewise
 * converted to UNKNOWN_HOST by the package wrapper.
 */
Datum
ivorysql_utl_inaddr_get_host_name(PG_FUNCTION_ARGS)
{
	char	   *address;
	char	   *hostname;

	if (PG_ARGISNULL(0))
	{
		hostname = utl_inaddr_local_hostname(true);
		if (hostname == NULL)
			PG_RETURN_NULL();

		PG_RETURN_TEXT_P(cstring_to_text(hostname));
	}

	address = text_to_cstring(PG_GETARG_TEXT_PP(0));
	hostname = utl_inaddr_resolve_name(address);
	pfree(address);

	if (hostname == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(hostname));
}
