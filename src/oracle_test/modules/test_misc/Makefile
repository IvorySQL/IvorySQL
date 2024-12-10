# src/oracle_test/modules/test_misc/Makefile
# add the file for requirement "SQL PARSER"

TAP_TESTS = 1

EXTRA_INSTALL=src/oracle_test/modules/injection_points

export enable_injection_points

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/oracle_test/modules/test_misc
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
