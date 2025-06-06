/*-------------------------------------------------------------------------------
 *
 * File: ora_xml_functions.c
 *
 * Abstract:
 * 		This file implements the C functions that support the XML SQL functions
 *
 * Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/xml_functions/ora_xml_functions.c
 *
 *-------------------------------------------------------------------------------
 */
#include "postgres.h"

#include <ctype.h>
#include <math.h>
#include "fmgr.h"
#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "funcapi.h"
#include "libpq/pqformat.h"
#include "nodes/nodeFuncs.h"
#include "nodes/supportnodes.h"
#include "optimizer/optimizer.h"
#include "port/pg_bitutils.h"
#include "utils/array.h"
#include "utils/arrayaccess.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/fmgroids.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/selfuncs.h"
#include "utils/typcache.h"
#include "access/table.h"
#include "catalog/namespace.h"
#include "catalog/pg_class.h"
#include "commands/dbcommands.h"
#include "executor/spi.h"
#include "executor/tablefunc.h"
#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "nodes/execnodes.h"
#include "utils/date.h"
#include "utils/datetime.h"
#include "utils/rel.h"
#include "utils/syscache.h"
#include "utils/arrayaccess.h"
#include "utils/xml.h"

#include "../include/ivorysql_ora.h"

#ifdef USE_LIBXML
#include <libxml/chvalid.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/tree.h>
#include <libxml/uri.h>
#include <libxml/xmlerror.h>
#include <libxml/xmlversion.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#endif

/*
 * Local definitions
 */
#define IS_STR_XMLNS(str) ((str != NULL) && (str[0] == 'x') && \
	(str[1] == 'm') && (str[2] == 'l') && (str[3] == 'n') && \
	(str[4] == 's') && (str[5] == ':'))

#define NO_XML_SUPPORT() \
	ereport(ERROR, \
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED), \
			 errmsg("unsupported XML feature"), \
			 errdetail("This functionality requires the server to be built with libxml support."), \
			 errhint("You need to rebuild PostgreSQL using %s.", "--with-libxml")))

PgXmlErrorContext *ivy_xml_parser_init(PgXmlStrictness strictness);

#ifdef USE_LIBXML
typedef struct xpath_ws
{
	xmlDocPtr			doc;
	xmlXPathContextPtr 	xpathctx;
	xmlXPathCompExprPtr xpathcomp;
	xmlXPathObjectPtr 	xpathobj;
} xpath_ws;
#endif

/*
 * ----------------------------------------------------------------------------
 *	Helper Function declarations
 * ----------------------------------------------------------------------------
 */
#ifdef USE_LIBXML
static text *rv_newline(text *tv);
static char *left_trim(char *str);
static char *right_trim(char *str);
static char *ivy_trim(char *str);
static char *ivy_escape_xml(const char *str);
static xmltype *ivy_stringinfo_to_xmltype(StringInfo buf);
static void cleanup_ws(xpath_ws *ws);
static xmlXPathObjectPtr ivy_xml_xpath(xpath_ws *ws, text *xpath_expr_text, xmltype *data, char *namespace);
static xmlXPathObjectPtr ivy_xml_xpath2(xpath_ws *ws, text *xpath_expr_text, xmlDocPtr doc, char *namespace);
static void init_ws_doc(xpath_ws *ws, xmltype *data);
static void register_ns_from_csting(xmlXPathContextPtr xpathCtx, char* nsList);
static int ivy_xpathobjnode_nr(xmlXPathObjectPtr xpathobj);
static char *ivy_xmlnode_getcontent(xmlNodePtr cur);
static char *ivy_xml_xpathobjtostring(xmlXPathObjectPtr xpathobj);
static text *ivy_xml_xmlnode2xmltype(xmlNodePtr cur);
static xmltype *ivy_xml_xpathobjtoxmltype(xmlXPathObjectPtr xpathobj);
static void ivy_xml_setnodecontent(xmlXPathObjectPtr xpathobj, xmlChar *var);
static void ivy_xml_delenode(xmlXPathObjectPtr xpathobj);
static void ivy_xml_addchildnode(xmlXPathObjectPtr xpathobj, xmlNodePtr cnode);
static void ivy_xml_addprevsiblingnode(xmlXPathObjectPtr xpathobj, const xmlChar* new_node);
static void ivy_xml_addnextsiblingnode(xmlXPathObjectPtr xpathobj, const xmlChar* new_node);
static void ivy_xml_replacenode(xmlXPathObjectPtr xpathobj, const xmlChar* new_node);
static xmlChar *ivy_xmlCharStrndup(const char *str, size_t len);
#endif

#ifdef USE_LIBXML
/*
 * Initialize for xml parsing.
 *
 * As with the underlying pg_xml_init function, calls to this MUST be followed
 * by a PG_TRY block that guarantees that pg_xml_done is called.
 */
PgXmlErrorContext *
ivy_xml_parser_init(PgXmlStrictness strictness)
{
	PgXmlErrorContext *xmlerrcxt;

	/* Set up error handling (we share the core's error handler) */
	xmlerrcxt = pg_xml_init(strictness);

	/* Note: we're assuming an elog cannot be thrown by the following calls */

	/* Initialize libxml */
	xmlInitParser();

	xmlSubstituteEntitiesDefault(1);
	xmlLoadExtDtdDefaultValue = 1;

	return xmlerrcxt;
}

/*
 * cleanup_ws
 *	clean up after processing the result of using xpath
 */
static void
cleanup_ws(xpath_ws *ws)
{
	if (ws->xpathobj)
		xmlXPathFreeObject(ws->xpathobj);
	ws->xpathobj = NULL;
	if (ws->xpathcomp)
		xmlXPathFreeCompExpr(ws->xpathcomp);
	ws->xpathcomp = NULL;
	if (ws->xpathctx)
		xmlXPathFreeContext(ws->xpathctx);
	ws->xpathctx = NULL;
	if (ws->doc)
		xmlFreeDoc(ws->doc);
	ws->doc = NULL;
}

/*
 * ivy_xml_xpath
 *	build the xpath and return the xpath object
 */
static xmlXPathObjectPtr
ivy_xml_xpath(xpath_ws *ws, text *xpath_expr_text, xmltype *data, char *namespace)
{
	PgXmlErrorContext *xmlerrcxt;
	char	   *datastr;
	int32		len;
	int32		xpath_len;
	xmlChar    *string;
	xmlChar    *xpath_expr;

	ws->doc = NULL;
	ws->xpathcomp = NULL;
	ws->xpathctx = NULL;
	ws->xpathobj = NULL;

	datastr = VARDATA(data);
	len = VARSIZE(data) - VARHDRSZ;
	xpath_len = VARSIZE_ANY_EXHDR(xpath_expr_text);
	if (xpath_len == 0)
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				 errmsg("empty XPath expression")));

	string = ivy_xmlCharStrndup(datastr, len);
	xpath_expr = ivy_xmlCharStrndup(VARDATA_ANY(xpath_expr_text), xpath_len);

	xmlerrcxt = ivy_xml_parser_init(PG_XML_STRICTNESS_LEGACY);

	PG_TRY();
	{
		ws->doc = xmlReadMemory((const char *)string, len, NULL, NULL, XML_PARSE_NOBLANKS); /* Bug#Z202 */
		if (ws->doc != NULL)
		{
			ws->xpathctx = xmlXPathNewContext(ws->doc);
			if (ws->xpathctx == NULL)
				ereport(ERROR,(errcode(ERRCODE_OUT_OF_MEMORY),
						errmsg("could not allocate XPath context")));
			ws->xpathctx->node = (xmlNodePtr)ws->doc;

			/* register namespaces, if any */
			if (namespace)
				register_ns_from_csting(ws->xpathctx, namespace);

			ws->xpathcomp = xmlXPathCompile(xpath_expr);
			if (ws->xpathcomp == NULL)
				ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
						errmsg("invalid XPath expression")));

			ws->xpathobj = xmlXPathCompiledEval(ws->xpathcomp, ws->xpathctx);
			if (ws->xpathobj == NULL)
				ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
						errmsg("could not create XPath object")));
		}
		else
			ereport(ERROR,(errcode(ERRCODE_INVALID_XML_DOCUMENT),
					errmsg("could not parse XML document")));
	}
	PG_CATCH();
	{
		cleanup_ws(ws);
		pg_xml_done(xmlerrcxt, true);
		PG_RE_THROW();
	}
	PG_END_TRY();

	if (ws->xpathobj == NULL)
		cleanup_ws(ws);

	pg_xml_done(xmlerrcxt, false);

	return ws->xpathobj;
}

static void
init_ws_doc(xpath_ws *ws, xmltype *data)
{
	PgXmlErrorContext *xmlerrcxt;
	char	   *datastr;
	xmlChar    *string;
	int32		len;

	ws->doc = NULL;
	ws->xpathcomp = NULL;
	ws->xpathctx = NULL;
	ws->xpathobj = NULL;

	datastr = VARDATA(data);
	len = VARSIZE(data) - VARHDRSZ;
	string = ivy_xmlCharStrndup(datastr, len);

	xmlerrcxt = ivy_xml_parser_init(PG_XML_STRICTNESS_LEGACY);

	PG_TRY();
	{
		ws->doc = xmlReadMemory((const char *)string, len, NULL, NULL, XML_PARSE_NOBLANKS); /* Bug#Z202 */
		if (ws->doc == NULL)
			ereport(ERROR,(errcode(ERRCODE_INVALID_XML_DOCUMENT),
					errmsg("could not parse XML document")));
	}
	PG_CATCH();
	{
		cleanup_ws(ws);
		pg_xml_done(xmlerrcxt, true);
		PG_RE_THROW();
	}
	PG_END_TRY();

	pg_xml_done(xmlerrcxt, false);
}

static xmlXPathObjectPtr
ivy_xml_xpath2(xpath_ws *ws, text *xpath_expr_text, xmlDocPtr doc, char *namespace)
{
	PgXmlErrorContext *xmlerrcxt;
	int32		xpath_len;
	xmlChar    *xpath_expr = NULL;

	xpath_len = VARSIZE_ANY_EXHDR(xpath_expr_text);
	if (xpath_len == 0)
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				 errmsg("empty XPath expression")));
	xpath_expr = ivy_xmlCharStrndup(VARDATA_ANY(xpath_expr_text), xpath_len);

	xmlerrcxt = ivy_xml_parser_init(PG_XML_STRICTNESS_LEGACY);

	PG_TRY();
	{
		ws->xpathctx = xmlXPathNewContext(doc);
		if (ws->xpathctx == NULL)
			ereport(ERROR,(errcode(ERRCODE_OUT_OF_MEMORY),
					errmsg("could not allocate XPath context")));
		ws->xpathctx->node = (xmlNodePtr)doc;

		/* register namespaces, if any */
		if (namespace)
			register_ns_from_csting(ws->xpathctx, namespace);

		ws->xpathcomp = xmlXPathCompile(xpath_expr);
		if (ws->xpathcomp == NULL)
			ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
					errmsg("invalid XPath expression")));

		ws->xpathobj = xmlXPathCompiledEval(ws->xpathcomp, ws->xpathctx);
		if (ws->xpathobj == NULL)
			ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
					errmsg("could not create XPath object")));
	}
	PG_CATCH();
	{
		cleanup_ws(ws);
		pg_xml_done(xmlerrcxt, true);
		PG_RE_THROW();
	}
	PG_END_TRY();
	pg_xml_done(xmlerrcxt, false);

	return ws->xpathobj;
}
#endif

/*
 * ----------------------------------------------------------------------------
 *				Exported Function declarations
 * ----------------------------------------------------------------------------
 */
PG_FUNCTION_INFO_V1(ivy_xmltype_in);
PG_FUNCTION_INFO_V1(ivy_xmltype_out);

PG_FUNCTION_INFO_V1(ivy_existsnode);
PG_FUNCTION_INFO_V1(ivy_existsnode2);
PG_FUNCTION_INFO_V1(ivy_extractvalue);
PG_FUNCTION_INFO_V1(ivy_extractvalue2);
PG_FUNCTION_INFO_V1(ivy_extract);
PG_FUNCTION_INFO_V1(ivy_extract2);
PG_FUNCTION_INFO_V1(ivy_deletexml);
PG_FUNCTION_INFO_V1(ivy_deletexml2);
PG_FUNCTION_INFO_V1(ivy_appendchildxml);
PG_FUNCTION_INFO_V1(ivy_appendchildxml2);
PG_FUNCTION_INFO_V1(ivy_insertxmlbefore);
PG_FUNCTION_INFO_V1(ivy_insertxmlbefore2);
PG_FUNCTION_INFO_V1(ivy_insertxmlafter);
PG_FUNCTION_INFO_V1(ivy_insertxmlafter2);
PG_FUNCTION_INFO_V1(ivy_insertchildxml);
PG_FUNCTION_INFO_V1(ivy_insertchildxml2);
PG_FUNCTION_INFO_V1(ivy_insertchildxmlbefore);
PG_FUNCTION_INFO_V1(ivy_insertchildxmlbefore2);
PG_FUNCTION_INFO_V1(ivy_insertchildxmlafter);
PG_FUNCTION_INFO_V1(ivy_insertchildxmlafter2);
PG_FUNCTION_INFO_V1(ivy_xmlisvalid);
/*
 * ----------------------------------------------------------------------------
 *	Helper Function definition
 * ----------------------------------------------------------------------------
 */
#ifdef USE_LIBXML
/*
 * rv_newline
 *	Remove the final newline in XMLTYPE data.
 */
static text*
rv_newline(text *tv)
{
	char 	*tmp = NULL;
	int		 len = 0;
	text	*ret = NULL;

	if (!tv)
		return ret;

	tmp = text_to_cstring(tv);
	len = strlen(tmp);
	if (tmp[len-1] == '\n')
		tmp[len-1] = '\0';
	ret = cstring_to_text(tmp);

	return ret;
}

/*
 * left_trim
 * 	remove the spaces at the beginning of a string
 */
static char *
left_trim(char *str)
{
	char	*start = str;
	char	*tmp = str;

	while (isspace(*start)) start++;
	while ((*tmp++ = *start++));

	return str;
}

/*
 * right_trim
 *	remove the spaces at the end of a string
 */
static char *
right_trim(char *str)
{
	char	*end;
	size_t	len = strlen(str);

	if(len == 0)
		return str;

	end = str + strlen(str) - 1;
	while (isspace(*end)) end--;
	*(end + 1) = '\0';

	return str;
}

/*
 * ivy_trim
 * 	trim spaces at the beginning and end of a sring
 */
static char *
ivy_trim(char *str)
{
	str = left_trim(str);
	str = right_trim(str);

	return str;
}

/*
 * Escape characters in text that have special meanings in XML.
 *
 * Returns a palloc'd string.
 *
 * NB: this is intentionally not dependent on libxml.
 */
static char *
ivy_escape_xml(const char *str)
{
	StringInfoData buf;
	const char *p;

	initStringInfo(&buf);
	for (p = str; *p; p++)
	{
		switch (*p)
		{
		case '&':
			appendStringInfoString(&buf, "&amp;");
			break;
		case '<':
			appendStringInfoString(&buf, "&lt;");
			break;
		case '>':
			appendStringInfoString(&buf, "&gt;");
			break;
		case '\r':
			appendStringInfoString(&buf, "&#x0d;");
			break;
		default:
			appendStringInfoCharMacro(&buf, *p);
			break;
		}
	}
	return buf.data;
}

static xmltype *
ivy_stringinfo_to_xmltype(StringInfo buf)
{
	return (xmltype *) cstring_to_text_with_len(buf->data, buf->len);
}

static void
register_ns_from_csting(xmlXPathContextPtr xpathCtx, char* nsList)
{
	char	*nslist = NULL;
	char	*p1 = NULL;
	char	*sub = NULL;
	char	*start = NULL;
	char	*end = NULL;
	char	*f = NULL;
	int 	l1 = 0;

	StringInfoData tmp;
	StringInfoData prefix;
	StringInfoData url;

	initStringInfo(&tmp);
	initStringInfo(&prefix);
	initStringInfo(&url);

	/* process the original string, removing leading and trailing spaces */
	nslist = ivy_trim(nsList);

	f = strchr(nslist, (int)'=');
	while (f != NULL)
	{
		if ((*(f - 1) == ' ') || (*(f + 1) != '"') || (*(f + 2) == ' '))
			elog(ERROR, "Invalid namespace");
		f = strchr(f + 1, (int)'=');
	}

	sub = strtok(nslist, " ");
	while (sub != NULL)
	{
		if (!IS_STR_XMLNS(sub))
			elog(ERROR, "Invalid namespace");

		appendStringInfoString(&tmp, sub);
		appendStringInfoString(&prefix, "");
		appendStringInfoString(&url, "");

		/* get the prefix */
		start = strchr(tmp.data, (int)':');
		end = strchr(tmp.data, (int)'=');
		memcpy(prefix.data, start + 1, end - start);
		prefix.data[end - start -1] = '\0';

		/* get the url */
		p1 = strstr(tmp.data, "=");
		l1 = strlen(p1);
		memcpy(url.data, p1 + 2, l1 - 3);
		url.data[l1 - 3] = '\0';

		/* do register namespace */
		if (xmlXPathRegisterNs(xpathCtx, (xmlChar *)prefix.data, (xmlChar *)url.data) != 0)
			elog(ERROR, "unable to register NS with prefix=%s and url=%s", prefix.data, url.data);

		/* handle the next sub string */
		sub = strtok(NULL, " ");

		resetStringInfo(&tmp);
		resetStringInfo(&prefix);
		resetStringInfo(&url);
	}

	pfree(tmp.data);
	pfree(prefix.data);
	pfree(url.data);
}

static int
ivy_xpathobjnode_nr(xmlXPathObjectPtr xpathobj)
{
	int			result = 0;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
			result = xpathobj->nodesetval->nodeNr;
	}

	return result;
}

static char *
ivy_xmlnode_getcontent(xmlNodePtr cur)
{
	char    	*result = NULL;

	if (cur->type == XML_ELEMENT_NODE)
	{
		if (cur->children && cur->children->type == XML_TEXT_NODE)
			result = (char *)xmlNodeGetContent(cur->children);
	}

	return result;
}

static char *
ivy_xml_xpathobjtostring(xmlXPathObjectPtr xpathobj)
{
	int			num = 0;
	char	   *res = NULL;
	char	   *res_str = NULL;
	int			i;
	StringInfoData buf;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			initStringInfo(&buf);

			for (i = 0; i < num; i++)
			{
				res = ivy_xmlnode_getcontent(xpathobj->nodesetval->nodeTab[i]);
				if (res)
					appendStringInfoString(&buf, res);
				else
					appendStringInfoString(&buf, "");
			}
			res_str = buf.data;
		}
	}

	return res_str;
}

static text *
ivy_xml_xmlnode2xmltype(xmlNodePtr cur)
{
	xmltype    *result = NULL;

	if (cur->type != XML_ATTRIBUTE_NODE && cur->type != XML_TEXT_NODE)
	{
		void		(*volatile nodefree) (xmlNodePtr) = NULL;
		volatile xmlBufferPtr buf = NULL;
		volatile xmlNodePtr cur_copy = NULL;

		PG_TRY();
		{
			int			bytes;

			buf = xmlBufferCreate();
			if (buf == NULL)
				ereport(ERROR, (errcode(ERRCODE_OUT_OF_MEMORY),
						errmsg("could not allocate xmlBuffer")));

			cur_copy = xmlCopyNode(cur, 1);
			if (cur_copy == NULL)
				ereport(ERROR, (errcode(ERRCODE_OUT_OF_MEMORY),
						errmsg("could not copy node")));

			nodefree = (cur_copy->type == XML_DOCUMENT_NODE) ?
				(void (*) (xmlNodePtr)) xmlFreeDoc : xmlFreeNode;

			bytes = xmlNodeDump(buf, NULL, cur_copy, 0, 1); /* Bug#Z202 */
			if (bytes == -1)
				ereport(ERROR, (errcode(ERRCODE_OUT_OF_MEMORY),
						errmsg("could not dump node")));

			result = (xmltype *)cstring_to_text_with_len((const char *) xmlBufferContent(buf),
														 xmlBufferLength(buf));
		}
		PG_FINALLY();
		{
			if (nodefree)
				nodefree(cur_copy);
			if (buf)
				xmlBufferFree(buf);
		}
		PG_END_TRY();
	}
	else
	{
		xmlChar    *str;

		str = xmlXPathCastNodeToString(cur);
		PG_TRY();
		{
			/* Here we rely on XML having the same representation as TEXT */
			char	*escaped = ivy_escape_xml((char *) str);
			result = (xmltype *) cstring_to_text(escaped);
			pfree(escaped);
		}
		PG_FINALLY();
		{
			xmlFree(str);
		}
		PG_END_TRY();
	}

	return result;
}

static xmltype *
ivy_xml_xpathobjtoxmltype(xmlXPathObjectPtr xpathobj)
{
	xmlNodePtr	cur = NULL;
	char	   *str = NULL;
	int			num = 0;
	int			i;
	StringInfoData buf;

	initStringInfo(&buf);

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			for (i = 0; i < num; i++)
			{
				cur = xpathobj->nodesetval->nodeTab[i];
				if (cur->type == XML_TEXT_NODE)
				{
					str = (char *)xmlNodeGetContent(cur);
					appendStringInfoString(&buf, str);
				}
				else
				{
					str = text_to_cstring(ivy_xml_xmlnode2xmltype(cur));
					appendStringInfoString(&buf, str);
					appendStringInfoString(&buf, "\n");
					pfree(str);
				}
			}
		}
	}

	return ivy_stringinfo_to_xmltype(&buf);
}

static void
ivy_xml_setnodecontent(xmlXPathObjectPtr xpathobj, xmlChar *var)
{
	xmlNodePtr	cur = NULL;
	int			num = 0;
	int			i;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			for (i = 0; i < num; i++)
			{
				cur = xpathobj->nodesetval->nodeTab[i];
				if (strcmp((char *)var, "") == 0 && cur->type == XML_ELEMENT_NODE)
				{
					xmlUnlinkNode(cur->children);
					xmlFreeNode(cur->children);
				}
				else
				{
					if (cur->type == XML_TEXT_NODE)
						xmlNodeSetContent(cur, var);
				}
			}
		}
	}

}

static void
ivy_xml_delenode(xmlXPathObjectPtr xpathobj)
{
	int			num = 0;
	int			i;

	if (xpathobj->type == XPATH_NODESET)
	{
		num = xpathobj->nodesetval->nodeNr;
		for (i = 0; i < num; i++)
		{
			xmlUnlinkNode(xpathobj->nodesetval->nodeTab[i]);
			xmlFreeNode(xpathobj->nodesetval->nodeTab[i]);
		}
	}
}

static void
ivy_xml_addchildnode(xmlXPathObjectPtr xpathobj, xmlNodePtr cnode)
{
	int			num = 0;
	int			i;
	xmlNodePtr		cnode_copy = NULL;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			for (i = 0; i < num; i++)
			{
				cnode_copy = xmlCopyNode(cnode, 1);
				xmlAddChild(xpathobj->nodesetval->nodeTab[i], cnode_copy->children);
				cnode_copy->children = NULL;
				xmlFreeNode(cnode_copy);
			}
		}
	}
}

static void
ivy_xml_addprevsiblingnode(xmlXPathObjectPtr xpathobj, const xmlChar* new_node)
{
	int			num = 0;
	int			i;
	xmlDocPtr	n_node = NULL;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			for (i = 0; i < num; i++)
			{
				n_node = xmlParseDoc(new_node);
				if (n_node == NULL)
					ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
							 errmsg("could not parse XML new node")));
				xmlAddPrevSibling(xpathobj->nodesetval->nodeTab[i], (xmlNodePtr)n_node->children);
				xmlFreeDoc(n_node);
			}
		}
	}

}

static void
ivy_xml_addnextsiblingnode(xmlXPathObjectPtr xpathobj, const xmlChar* new_node)
{
	int			num = 0;
	int			i;
	xmlDocPtr	n_node = NULL;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			for (i = 0; i < num; i++)
			{
				n_node = xmlParseDoc(new_node);
				if (n_node == NULL)
					ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
							 errmsg("could not parse XML new node")));
				xmlAddNextSibling(xpathobj->nodesetval->nodeTab[i], (xmlNodePtr)n_node->children);
				xmlFreeDoc(n_node);
			}
		}
	}

}

static void
ivy_xml_replacenode(xmlXPathObjectPtr xpathobj, const xmlChar* new_node)
{
	int			num = 0;
	int			i;
	xmlDocPtr	n_node = NULL;
	xmlNodePtr	cur = NULL;

	if (xpathobj->type == XPATH_NODESET)
	{
		if (xpathobj->nodesetval != NULL)
		{
			num = xpathobj->nodesetval->nodeNr;
			for (i = 0; i < num; i++)
			{
				cur = xpathobj->nodesetval->nodeTab[i];
				if (strcmp((char *)new_node, "") == 0)
				{
						xmlUnlinkNode(cur->children);
						xmlFreeNode(cur->children);
				}
				else
				{
					n_node = xmlParseDoc(new_node);
					if (n_node == NULL)
						ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
								errmsg("could not parse XML new node")));
					xmlReplaceNode(cur, (xmlNodePtr)n_node->children);
					xmlFreeDoc(n_node);
				}
			}
		}
	}

}

static xmlChar *
ivy_xmlCharStrndup(const char *str, size_t len)
{
	xmlChar    *result;

	result = (xmlChar *) palloc((len + 1) * sizeof(xmlChar));
	memcpy(result, str, len);
	result[len] = '\0';

	return result;
}
#endif		/* USE_LIBXML */


/*
 * xmltype IN function
 */
Datum
ivy_xmltype_in(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	char	   *s = PG_GETARG_CSTRING(0);
	xmltype    *vardata;

	vardata = (xmltype *) cstring_to_text(s);

	PG_RETURN_XML_P(vardata);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

/*
 * xmltype OUT function
 */
Datum
ivy_xmltype_out(PG_FUNCTION_ARGS)
{
	return xml_out(fcinfo);
}

//------------------------------------
// existsnode
//------------------------------------
Datum
ivy_existsnode(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	int			res_nitems = 0;
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);
	res_nitems = ivy_xpathobjnode_nr(res);

	cleanup_ws(&ws);

	if (res_nitems > 1)
		res_nitems = 1;
	PG_RETURN_INT32(res_nitems);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_existsnode2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	int			res_nitems = 0;
	xmltype    *data = NULL;
	char	   *cns = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *ns = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		ns = PG_GETARG_TEXT_PP(2);
		cns = text_to_cstring(ns);
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);
	res_nitems = ivy_xpathobjnode_nr(res);

	cleanup_ws(&ws);

	if (res_nitems > 1)
		res_nitems = 1;
	PG_RETURN_INT32(res_nitems);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//---------------------------------------
// extractvalue
//---------------------------------------
Datum
ivy_extractvalue(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *rval = NULL;
	char	   *ret = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	initStringInfo(&result);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);

	if (res->nodesetval && res->nodesetval->nodeNr > 1)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("EXTRACTVALUE returns value of only one node")));
	}

	/* Begin - Bug#Z203, Bug#Z214 */
	if (res->nodesetval && res->nodesetval->nodeTab &&
		res->nodesetval->nodeTab[0]->parent->type == XML_DOCUMENT_NODE)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("EXTRACTVALUE can only retrieve value of leaf node")));
	}

	if (res->nodesetval && res->nodesetval->nodeTab &&
		res->nodesetval->nodeTab[0]->children->type == XML_ELEMENT_NODE)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("EXTRACTVALUE returns value of only one node")));
	}
	/* End - Bug#Z203, Bug#Z214 */

	ret = ivy_xml_xpathobjtostring(res);

	appendStringInfoString(&result, ret);
	rval = cstring_to_text_with_len(result.data, result.len);
	pfree(result.data);

	cleanup_ws(&ws);

	PG_RETURN_TEXT_P(rval);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_extractvalue2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *rval = NULL;
	text	   *ns = NULL;
	char	   *cns = NULL;
	char	   *ret = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		ns = PG_GETARG_TEXT_PP(2);
		cns = text_to_cstring(ns);
	}

	initStringInfo(&result);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);

	if (res->nodesetval && res->nodesetval->nodeNr > 1)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("EXTRACTVALUE returns value of only one node")));
	}

	/* Begin - Bug#Z203, Bug#Z214 */
	if (res->nodesetval && res->nodesetval->nodeTab &&
		res->nodesetval->nodeTab[0]->parent->type == XML_DOCUMENT_NODE)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("EXTRACTVALUE can only retrieve value of leaf node")));
	}

	if (res->nodesetval && res->nodesetval->nodeTab &&
		res->nodesetval->nodeTab[0]->children->type == XML_ELEMENT_NODE)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("EXTRACTVALUE returns value of only one node")));
	}
	/* End - Bug#Z203, Bug#Z214 */

	ret = ivy_xml_xpathobjtostring(res);

	appendStringInfoString(&result, ret);
	rval = cstring_to_text_with_len(result.data, result.len);
	pfree(result.data);

	cleanup_ws(&ws);

	PG_RETURN_TEXT_P(rval);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//--------------------------------
// extract
//--------------------------------
Datum
ivy_extract(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	xmltype    *ret = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *rval = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	initStringInfo(&result);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);
	ret = ivy_xml_xpathobjtoxmltype(res);

	cleanup_ws(&ws);

	if (ret)
	{
		ret = (xmltype *)rv_newline((text *)ret);
		PG_RETURN_XML_P(ret);
	}
	else
	{
		appendStringInfoString(&result, "");
		rval = cstring_to_text_with_len(result.data, result.len);
		pfree(result.data);

		PG_RETURN_TEXT_P(rval);
	}
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_extract2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	xmltype    *ret = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *rval = NULL;
	text	   *ns = NULL;
	char	   *cns = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		ns = PG_GETARG_TEXT_PP(2);
		cns = text_to_cstring(ns);
	}

	initStringInfo(&result);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);
	ret = ivy_xml_xpathobjtoxmltype(res);

	cleanup_ws(&ws);

	if (ret)
	{
		ret = (xmltype *)rv_newline((text *)ret);
		PG_RETURN_XML_P(ret);
	}
	else
	{
		appendStringInfoString(&result, "");
		rval = cstring_to_text_with_len(result.data, result.len);
		pfree(result.data);

		PG_RETURN_TEXT_P(rval);
	}
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//-----------------------------------
// deletexml
//-----------------------------------
Datum
ivy_deletexml(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *ret = NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);
	if (res->nodesetval && res->nodesetval->nodeTab != NULL)
		ivy_xml_delenode(res);

	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	/* Begin - BUG#M0000280 */
	if (ws.xpathcomp)
		xmlXPathFreeCompExpr(ws.xpathcomp);
	if (ws.xpathctx)
		xmlXPathFreeContext(ws.xpathctx);
	if (ws.doc)
		xmlFreeDoc(ws.doc);
	/* End - BUG#M0000280 */

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_deletexml2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *ns = NULL;
	xmltype    *ret = NULL;
	char	   *cns= NULL;
	xpath_ws	ws;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		ns = PG_GETARG_TEXT_PP(2);
		cns = text_to_cstring(ns);
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);
	if (res->nodesetval && res->nodesetval->nodeTab != NULL)
		ivy_xml_delenode(res);

	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	/* Begin - BUG#M0000280 */
	if (ws.xpathcomp)
		xmlXPathFreeCompExpr(ws.xpathcomp);
	if (ws.xpathctx)
		xmlXPathFreeContext(ws.xpathctx);
	if (ws.doc)
		xmlFreeDoc(ws.doc);
	/* End - BUG#M0000280 */

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//-----------------------------------------
// appendchildxml
//-----------------------------------------
Datum
ivy_appendchildxml(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *var = NULL;
	xmltype    *ret = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlDocPtr 	new_node = NULL;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		var = PG_GETARG_XML_P(2);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);

	new_node = xmlParseDoc(nodestring);
	if (new_node == NULL)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
				errmsg("could not parse XML new node")));
	}

	ivy_xml_addchildnode(res, (xmlNodePtr)new_node);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	xmlUnlinkNode((xmlNodePtr)ws.xpathctx->node->children);
	xmlFreeNode((xmlNodePtr)ws.xpathctx->node->children);

	ret = (xmltype *)rv_newline((text *)ret);

	if (new_node)
		xmlFreeDoc(new_node);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_appendchildxml2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *var = NULL;
	text	   *ns = NULL;
	xmltype    *ret = NULL;
	char	   *cns = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlDocPtr 	new_node = NULL;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		var = PG_GETARG_XML_P(2);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	if (!fcinfo->args[3].isnull)
	{
		ns = PG_GETARG_TEXT_PP(3);
		cns = text_to_cstring(ns);
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);

	new_node = xmlParseDoc(nodestring);
	if (new_node == NULL)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
				errmsg("could not parse XML new node")));
	}

	ivy_xml_addchildnode(res, (xmlNodePtr)new_node);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	xmlUnlinkNode((xmlNodePtr)ws.xpathctx->node->children);
	xmlFreeNode((xmlNodePtr)ws.xpathctx->node->children);

	ret = (xmltype *)rv_newline((text *)ret);

	if (new_node)
		xmlFreeDoc(new_node);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//-------------------------------------------
// insertxmlbefore
//-------------------------------------------
Datum
ivy_insertxmlbefore(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *var = NULL;
	xmltype    *ret;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		var = PG_GETARG_XML_P(2);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);

	if (res->nodesetval && res->nodesetval->nodeNr == 1 && /* Bug#Z205 */
		res->nodesetval->nodeTab && res->nodesetval->nodeTab[0]->parent->type == XML_DOCUMENT_NODE)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("invalid XPath expression")));
	}

	ivy_xml_addprevsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_insertxmlbefore2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *var = NULL;
	text	   *ns = NULL;
	xmltype    *ret;
	char	   *cns = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		var = PG_GETARG_XML_P(2);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	if (!fcinfo->args[3].isnull)
	{
		ns = PG_GETARG_TEXT_PP(3);
		cns = text_to_cstring(ns);
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);

	if (res->nodesetval && res->nodesetval->nodeNr == 1 && /* Bug#Z205 */
		res->nodesetval->nodeTab && res->nodesetval->nodeTab[0]->parent->type == XML_DOCUMENT_NODE)
	{
		cleanup_ws(&ws);
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("invalid XPath expression")));
	}

	ivy_xml_addprevsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//------------------------------------------
// insertxmlafter
//------------------------------------------
Datum
ivy_insertxmlafter(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data= NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *var = NULL;
	xmltype    *ret;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		var = PG_GETARG_XML_P(2);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);

	ivy_xml_addnextsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_insertxmlafter2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	xmltype    *var = NULL;
	text	   *ns = NULL;
	xmltype    *ret = NULL;
	char	   *cns = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		var = PG_GETARG_XML_P(2);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	if (!fcinfo->args[3].isnull)
	{
		ns = PG_GETARG_TEXT_PP(3);
		cns = text_to_cstring(ns);
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);

	ivy_xml_addnextsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//------------------------------------------
// insertchildxml
//------------------------------------------
Datum
ivy_insertchildxml(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *n_name = NULL;
	xmltype    *var = NULL;
	xmltype    *ret = NULL;
	char	   *cname = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlDocPtr 	new_node = NULL;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		n_name = PG_GETARG_TEXT_PP(2);
		cname = text_to_cstring(n_name);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				 errmsg("The document being inserted does not conform to specified child name")));

	if (!fcinfo->args[3].isnull)
	{
		var = PG_GETARG_XML_P(3);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("invalid XPath expression")));

	new_node = xmlParseDoc(nodestring);
	if (new_node == NULL)
	{
		ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
				errmsg("could not parse XML new node")));
	}
	else
	{
		/* Begin - Bug#Z204 */
		if (strcmp(cname, (char *)((xmlNodePtr)new_node->children->name)) != 0)
		{
			xmlFreeDoc(new_node);
			ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
					errmsg("The document being inserted does not conform to specified child name")));
		}
		/* End - Bug#Z204 */
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, NULL);
	ivy_xml_addchildnode(res, (xmlNodePtr)new_node);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);
	xmlUnlinkNode((xmlNodePtr)ws.xpathctx->node->children);
	xmlFreeNode((xmlNodePtr)ws.xpathctx->node->children);

	if (new_node)
		xmlFreeDoc(new_node);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_insertchildxml2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *n_name = NULL;
	xmltype    *var = NULL;
	text	   *ns = NULL;
	xmltype    *ret = NULL;
	char	   *cname = NULL;
	char	   *cns = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlDocPtr 	new_node = NULL;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	StringInfoData r;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
		xpath_expr_text = PG_GETARG_TEXT_PP(1);

	if (!fcinfo->args[2].isnull)
	{
		n_name = PG_GETARG_TEXT_PP(2);
		cname = text_to_cstring(n_name);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				 errmsg("The document being inserted does not conform to specified child name")));

	if (!fcinfo->args[3].isnull)
	{
		var = PG_GETARG_XML_P(3);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("invalid XPath expression")));

	if (!fcinfo->args[4].isnull)
	{
		ns = PG_GETARG_TEXT_PP(4);
		cns = text_to_cstring(ns);
	}

	new_node = xmlParseDoc(nodestring);
	if (new_node == NULL)
	{
		ereport(ERROR, (errcode(ERRCODE_INVALID_XML_DOCUMENT),
				errmsg("could not parse XML new node")));
	}
	else
	{
		/* Begin - Bug#Z204, Bug#Z215 */
		initStringInfo(&r);
		appendStringInfoString(&r, "<");
		appendStringInfoString(&r, cname);

		if (strstr((char *)nodestring, r.data))
		{
			if (!strstr(cname, (char *)((xmlNodePtr)new_node->children->name)))
			{
				xmlFreeDoc(new_node);
				ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
						errmsg("The document being inserted does not conform to specified child name")));
			}
		}
		else
		{
			xmlFreeDoc(new_node);
			ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
					errmsg("The document being inserted does not conform to specified child name")));
		}
		/* End - Bug#Z204, Bug#Z215 */
	}

	res = ivy_xml_xpath(&ws, xpath_expr_text, data, cns);
	ivy_xml_addchildnode(res, (xmlNodePtr)new_node);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);
	xmlUnlinkNode((xmlNodePtr)ws.xpathctx->node->children);
	xmlFreeNode((xmlNodePtr)ws.xpathctx->node->children);

	if (new_node)
		xmlFreeDoc(new_node);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//--------------------------------------------------
// insertchildxmlbefore
//--------------------------------------------------
Datum
ivy_insertchildxmlbefore(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *child_expr_text = NULL;
	xmltype    *var = NULL;
	char	   *c_expr = NULL;
	char	   *xpath_expr = NULL;
	xmltype    *ret = NULL;
	text	   *full_path = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
	{
		xpath_expr_text = PG_GETARG_TEXT_PP(1);
		xpath_expr = text_to_cstring(xpath_expr_text);
	}

	if (!fcinfo->args[2].isnull)
	{
		child_expr_text = PG_GETARG_TEXT_PP(2);
		c_expr = text_to_cstring(child_expr_text);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				 errmsg("The document being inserted does not conform to specified child name")));

	if (!fcinfo->args[3].isnull)
	{
		var = PG_GETARG_XML_P(3);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		 PG_RETURN_XML_P(data);

	initStringInfo(&result);
	appendStringInfoString(&result, xpath_expr);
	appendStringInfoString(&result, "/");
	appendStringInfoString(&result, c_expr);

	full_path = cstring_to_text(result.data);
	pfree(result.data);

	res = ivy_xml_xpath(&ws, full_path, data, NULL);
	ivy_xml_addprevsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_insertchildxmlbefore2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *child_expr_text = NULL;
	xmltype    *var = NULL;
	text	   *ns = NULL;
	xmltype    *ret = NULL;
	char	   *c_expr = NULL;
	char	   *xpath_expr = NULL;
	char	   *cns = NULL;
	text	   *full_path = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
	{
		xpath_expr_text = PG_GETARG_TEXT_PP(1);
		xpath_expr = text_to_cstring(xpath_expr_text);
	}

	if (!fcinfo->args[2].isnull)
	{
		child_expr_text = PG_GETARG_TEXT_PP(2);
		c_expr = text_to_cstring(child_expr_text);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("The document being inserted does not conform to specified child name")));

	if (!fcinfo->args[3].isnull)
	{
		var = PG_GETARG_XML_P(3);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	if (!fcinfo->args[4].isnull)
	{
		ns = PG_GETARG_TEXT_PP(4);
		cns = text_to_cstring(ns);
	}

	initStringInfo(&result);
	appendStringInfoString(&result, xpath_expr);
	appendStringInfoString(&result, "/");
	appendStringInfoString(&result, c_expr);

	full_path = cstring_to_text(result.data);
	pfree(result.data);

	res = ivy_xml_xpath(&ws, full_path, data, cns);
	ivy_xml_addprevsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

//-------------------------------------------------
// insertchildxmlafter
//-------------------------------------------------
Datum
ivy_insertchildxmlafter(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *child_expr_text = NULL;
	xmltype    *var= NULL;
	xmltype    *ret = NULL;
	char	   *c_expr = NULL;
	char	   *xpath_expr = NULL;
	text	   *full_path = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
	{
		xpath_expr_text = PG_GETARG_TEXT_PP(1);
		xpath_expr = text_to_cstring(xpath_expr_text);
	}

	if (!fcinfo->args[2].isnull)
	{
		child_expr_text = PG_GETARG_TEXT_PP(2);
		c_expr = text_to_cstring(child_expr_text);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				 errmsg("The document being inserted does not conform to specified child name")));

	if (!fcinfo->args[3].isnull)
	{
		var = PG_GETARG_XML_P(3);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	initStringInfo(&result);
	appendStringInfoString(&result, xpath_expr);
	appendStringInfoString(&result, "/");
	appendStringInfoString(&result, c_expr);

	full_path = cstring_to_text(result.data);
	pfree(result.data);

	res = ivy_xml_xpath(&ws, full_path, data, NULL);
	ivy_xml_addnextsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

Datum
ivy_insertchildxmlafter2(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	xmltype    *data = NULL;
	text	   *xpath_expr_text = NULL;
	text	   *child_expr_text = NULL;
	xmltype    *var = NULL;
	text	   *ns = NULL;
	xmltype    *ret = NULL;
	char	   *c_expr = NULL;
	char	   *xpath_expr = NULL;
	char	   *cns = NULL;
	text	   *full_path = NULL;
	char	   *cnodestr = NULL;
	int 		len;
	xpath_ws	ws;
	xmlChar	   *nodestring = NULL;
	xmlXPathObjectPtr res;

	StringInfoData result;

	if (fcinfo->args[0].isnull)
		PG_RETURN_NULL();
	else
		data = PG_GETARG_XML_P(0);

	if (fcinfo->args[1].isnull)
		PG_RETURN_NULL();
	else
	{
		xpath_expr_text = PG_GETARG_TEXT_PP(1);
		xpath_expr = text_to_cstring(xpath_expr_text);
	}

	if (!fcinfo->args[2].isnull)
	{
		child_expr_text = PG_GETARG_TEXT_PP(2);
		c_expr = text_to_cstring(child_expr_text);
	}
	else
		ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION),
				errmsg("The document being inserted does not conform to specified child name")));

	if (!fcinfo->args[3].isnull)
	{
		var = PG_GETARG_XML_P(3);
		cnodestr = VARDATA(var);
		len = VARSIZE(var) - VARHDRSZ;
		nodestring = ivy_xmlCharStrndup(cnodestr, len);
	}
	else
		PG_RETURN_XML_P(data);

	if (!fcinfo->args[4].isnull)
	{
		ns = PG_GETARG_TEXT_PP(4);
		cns = text_to_cstring(ns);
	}

	initStringInfo(&result);
	appendStringInfoString(&result, xpath_expr);
	appendStringInfoString(&result, "/");
	appendStringInfoString(&result, c_expr);

	full_path = cstring_to_text(result.data);
	pfree(result.data);

	res = ivy_xml_xpath(&ws, full_path, data, cns);
	ivy_xml_addnextsiblingnode(res, nodestring);
	ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
	ret = (xmltype *)rv_newline((text *)ret);

	cleanup_ws(&ws);

	PG_RETURN_XML_P(ret);
#else
	NO_XML_SUPPORT();
	return 0;
#endif
}

xmltype *
updatexml(List *args)
{
#ifdef USE_LIBXML
	ListCell		*f;
	ListCell		*l;
	ListCell		*v;
	List			*tmp;
	List			*datap;
	List	   		*nsp;
	char			*ns = NULL;
	char			*cxmldata = NULL;
	xmltype			*xmldata = NULL;
	xmltype			*ret = NULL;
	int 			narg = 0;
	xpath_ws		ws;
	bool			has_namespace = false;
	text			*rval = NULL;
	xmlXPathObjectPtr res;

	StringInfoData result;

	/* get the xml data */
	f = list_head(args);
	if (f->ptr_value != NULL)
	{
		datap = lfirst(f);
		xmldata = (xmltype *)DatumGetTextP(PointerGetDatum(datap));
		cxmldata = text_to_cstring(DatumGetTextP(PointerGetDatum(datap)));
		if (strcmp(cxmldata, "") == 0)
			return xmldata;
	}
	else
	{
		initStringInfo(&result);
		appendStringInfoString(&result, "");
		rval = cstring_to_text_with_len(result.data, result.len);
		pfree(result.data);

		return (xmltype *)rval;
	}

	init_ws_doc(&ws, xmldata);

	/* get the namespace_string if it exist */
	if (args->length % 2 == 0)
	{
		l = list_tail(args);
		nsp= lfirst(l);
		ns = text_to_cstring(DatumGetTextP(PointerGetDatum(nsp)));
		has_namespace = true;

		tmp = list_delete_last(args);
	}

	tmp = list_delete_first(args);
	if (tmp->length % 2 != 0)
		ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
				errmsg("invalid XPath expression")));

	v = list_head(tmp);
	for (;;)
	{
		char	   *varstr = NULL;
		char	   *cxpath = NULL;
		xmlChar	   *string = NULL;
		xmlDocPtr	vdoc = NULL;
		text	   *xpath = NULL;
		text	   *var = NULL;
		int			len2 = 0;

		/* get xpath_string */
		if (v->ptr_value != NULL)
		{
			xpath = DatumGetTextP(PointerGetDatum(lfirst(v)));
			cxpath = text_to_cstring(xpath);
			if (strcmp(cxpath, "") == 0)
				ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
						errmsg("invalid XPath expression")));
		}
		else /* handle the null */
		{
			ereport(ERROR, (errcode(ERRCODE_INTERNAL_ERROR),
					errmsg("invalid XPath expression")));
		}

		v = lnext(tmp, v);
		if (v->ptr_value != NULL)
		{
			/* get value_expr */
			var = DatumGetTextP(PointerGetDatum(lfirst(v)));

			varstr = VARDATA(var);
			len2 = VARSIZE(var) - VARHDRSZ;
			string = ivy_xmlCharStrndup(varstr, len2);
		}
		else
		{
			string = (xmlChar *)"";
		}

		v = lnext(tmp, v);

		if (has_namespace)
			res = ivy_xml_xpath2(&ws, xpath, ws.doc, ns);
		else
			res = ivy_xml_xpath2(&ws, xpath, ws.doc, NULL);

		vdoc = xmlParseDoc(string);
		/* update the node value */
		if (vdoc == NULL && strstr(cxpath, "text()"))
		{
			ivy_xml_setnodecontent(res, string);
			ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
		}
		else /* replace a node */
		{
			ivy_xml_replacenode(res, string);
			ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
			xmlFreeDoc(vdoc);
		}

		ret = (xmltype *)ivy_xml_xmlnode2xmltype((xmlNodePtr)ws.doc);
		ret = (xmltype *)rv_newline((text *)ret);

		narg += 2;
		if (narg == tmp->length)
			break;
	}

	cleanup_ws(&ws);

	return ret;
#else
	NO_XML_SUPPORT();
	return NULL;
#endif
}

Datum ivy_xmlisvalid(PG_FUNCTION_ARGS)
{
#ifdef USE_LIBXML
	if (fcinfo->args[0].isnull)
	{
		PG_RETURN_UINT32(1);
	}
	else
	{
		text *data = PG_GETARG_TEXT_PP(0);
		char *datastr = VARDATA(data);
		int32 len = VARSIZE(data) - VARHDRSZ;
		xmlDocPtr doc = NULL;
		if (len <= 0) /* Avoid crash */
		{
			PG_RETURN_BOOL(1);
		}
		doc = xmlReadMemory((const char *)datastr, len, NULL, NULL, XML_PARSE_NOBLANKS);
		if (doc)
		{
			xmlFreeDoc(doc);
			PG_RETURN_UINT32(1);
		}
		else
		{
			PG_RETURN_UINT32(0);
		}
	}
#else
	NO_XML_SUPPORT();
	return NULL;
#endif
}
