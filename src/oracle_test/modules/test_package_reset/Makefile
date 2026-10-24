# src/oracle_test/modules/test_package_reset/Makefile

MODULES = test_package_reset
PGFILEDESC = "test_package_reset - test extension for PLiSQL package reset API"

EXTENSION = test_package_reset
DATA = test_package_reset--1.0.sql

REGRESS = test_package_reset
ORA_REGRESS = $(REGRESS) test_reset_one_oid test_reset_all test_reset_defaults \
	test_discard_dependencies

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/oracle_test/modules/test_package_reset
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
