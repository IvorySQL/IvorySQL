MODULE_big = ivorysql_perf
OBJS = $(WIN32RES) ivorysql_perf.o
EXTENSION = ivorysql_perf
DATA = ivorysql_perf--1.0.sql
PGFILEDESC = "ivorysql_perf - performance sampling and reports"
TAP_TESTS = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ivorysql_perf
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
