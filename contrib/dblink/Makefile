# contrib/dblink/Makefile

MODULE_big = dblink
OBJS = \
	$(WIN32RES) \
	dblink.o
PG_CPPFLAGS = -I$(libpq_srcdir)
SHLIB_LINK_INTERNAL = $(libpq)

EXTENSION = dblink
DATA = dblink--1.2.sql dblink--1.1--1.2.sql dblink--1.0--1.1.sql
PGFILEDESC = "dblink - connect to other PostgreSQL databases"

REGRESS = dblink
REGRESS_OPTS = --dlpath=$(top_builddir)/src/test/regress

# BEGIN - SQL oracle_test
ORACLE_REGRESS_OPTS = --dlpath=$(top_builddir)/src/oracle_test/regress
# END - SQL oracle_test

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
SHLIB_PREREQS = submake-libpq
subdir = contrib/dblink
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

all: ../../src/oracle_test/regress/regress$(DLSUFFIX)

../../src/oracle_test/regress/regress$(DLSUFFIX): ../../src/oracle_test/regress/oraregress$(DLSUFFIX)
	        cp $< $@
