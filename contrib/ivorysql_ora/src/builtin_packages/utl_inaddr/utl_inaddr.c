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
 * Oracle UTL_INADDR 包的主机名与地址解析实现。
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
 * 读取本机主机名。GET_HOST_NAME 的 NULL 分支只返回短名称，因此该分支
 * 会去掉第一个点及其后的域名；地址解析仍使用完整名称。
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
 * 将主机名解析为数字形式的 IPv4 或 IPv6 地址。地址顺序遵循系统解析器，
 * 与 Oracle 对多网卡主机只返回一个地址的契约一致。
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
 * 对数字形式的 IPv4 或 IPv6 地址执行反向解析。AI_NUMERICHOST 禁止把
 * 任意文本再次当作主机名解析，NI_NAMEREQD 则确保没有 PTR/hosts 名称时
 * 返回 UNKNOWN_HOST，而不是把原地址原样返回。
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
 * UTL_INADDR.GET_HOST_ADDRESS：给定主机名时返回其一个数字地址；NULL
 * 表示先取得本机主机名再解析。解析失败返回 NULL，由 PL/iSQL 包转换为
 * UNKNOWN_HOST，以便保留公开异常契约。
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
 * UTL_INADDR.GET_HOST_NAME：给定数字地址时执行反向解析；NULL 直接返回
 * 不带域名的本机短名称。解析失败同样交由包包装层转换为 UNKNOWN_HOST。
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
