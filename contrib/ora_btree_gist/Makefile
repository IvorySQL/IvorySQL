# contrib/ora_btree_gist/Makefile

MODULE_big = ora_btree_gist

OBJS =  \
	$(WIN32RES) \
	btree_gist.o \
	btree_number.o \
	btree_interval.o \
	btree_binary_float.o \
	btree_binary_double.o \
	btree_varcharchar.o \
	btree_timestamp.o \
	btree_yminterval.o \
	btree_dsinterval.o \
	btree_utils_num.o \
	btree_utils_var.o \

EXTENSION = ora_btree_gist
DATA = ora_btree_gist--1.0.sql
PGFILEDESC = "ora_btree_gist - B-tree equivalent GiST operator classes"

# The varchar2_utf8 test exercises the multibyte prefix logic in
# gbt_var_node_cp_len(), so pin the regression database to UTF8 instead of
# relying on whatever encoding initdb derives from the invoking environment's
# locale.
ENCODING = UTF8

# ENCODING alone is not enough: without --no-locale, pg_regress still creates
# the test database with the locale of the invoking environment, and a locale
# whose encoding is not UTF8 (for example zh_CN.gbk) makes the CREATE DATABASE
# ... ENCODING='UTF8' emitted by pg_regress fail before a single test runs.
# --no-locale pins the database to the C locale, which is compatible with
# UTF8, so the module can be checked from any environment.
ORACLE_REGRESS_OPTS += --no-locale

ORA_REGRESS = init number varchar2 varchar2_utf8 binary_float binary_double date \
	  timestamp timestamptz timestampltz yminterval dsinterval
EXTRA_INSTALL = contrib/ivorysql_ora

SHLIB_LINK += $(filter -lm, $(LIBS))

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ora_btree_gist
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
