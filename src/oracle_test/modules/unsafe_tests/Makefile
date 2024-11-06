# src/oracle_test/modules/unsafe_tests/Makefile
# add the file for requirement "SQL PARSER"

REGRESS = rolenames alter_system_table

# the whole point of these tests is to not run installcheck
NO_INSTALLCHECK = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/oracle_test/modules/unsafe_tests
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
