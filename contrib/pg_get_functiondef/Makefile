# contrib/pg_get_functiondef/Makefile

MODULE_big = pg_get_functiondef
OBJS = \
	$(WIN32RES) \
	pg_get_functiondef_no_input.o \
	pg_get_functiondef_mul.o \
	pg_get_functiondef_extend.o

EXTENSION = pg_get_functiondef
DATA = pg_get_functiondef--1.0.sql
PGFILEDESC = "pg_get_functiondef - Enhancement of existing pg_get_functiondef"

REGRESS = pg_get_functiondef
ORA_REGRESS = pg_get_functiondef

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pg_get_functiondef
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
