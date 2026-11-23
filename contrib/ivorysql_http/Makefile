MODULE_big = ivorysql_http
OBJS = $(WIN32RES) ivorysql_http.o
EXTENSION = ivorysql_http
DATA = ivorysql_http--1.0.sql
PGFILEDESC = "ivorysql_http - Oracle-style HTTP request package"
TAP_TESTS = 1
CURL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags libcurl)
CURL_LIBS ?= $(shell $(PKG_CONFIG) --libs libcurl)
PG_CPPFLAGS += $(CURL_CFLAGS)
SHLIB_LINK += $(CURL_LIBS)

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ivorysql_http
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
