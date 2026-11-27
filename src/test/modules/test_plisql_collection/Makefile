# src/test/modules/test_plisql_collection/Makefile

MODULE_big = test_plisql_collection
OBJS = \
	$(WIN32RES) \
	pl_collection_runtime.o \
	test_plisql_collection.o
PGFILEDESC = "test_plisql_collection - unit tests for the plisql collection runtime"

EXTENSION = test_plisql_collection
DATA = test_plisql_collection--1.0.sql

REGRESS = test_plisql_collection

# The runtime is compiled directly into this module rather than called
# through plisql.so: plisql is built with hidden symbol visibility, and the
# runtime is deliberately free of plisql compiler dependencies precisely so
# that it can be built and tested standalone like this.
#
# The path is derived from $(srcdir), not $(top_srcdir): under USE_PGXS=1,
# top_srcdir is just top_builddir (effectively "."), not the repository
# root, so $(top_srcdir)/src/pl/plisql/src would not exist.  $(srcdir) is
# this module's own directory in every build mode, so walking up from it is
# correct whether or not PGXS is in use.
PG_CPPFLAGS = -I$(srcdir)/../../../pl/plisql/src

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/test/modules/test_plisql_collection
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

# Must follow the includes above: vpath is processed immediately, so
# srcdir has to be defined by the time this line is read.
vpath pl_collection_runtime.c $(srcdir)/../../../pl/plisql/src
