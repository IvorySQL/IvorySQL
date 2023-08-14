# contrib/ora_btree_gin/Makefile

MODULE_big = ora_btree_gin
OBJS = \
	$(WIN32RES) \
	ora_btree_gin.o

EXTENSION = ora_btree_gin
DATA = ora_btree_gin--1.0.sql

PGFILEDESC = "ora_btree_gin - B-tree equivalent GIN operator classes"

ORA_REGRESS = init number varchar2 binary_float binary_double \
	  date timestamp timestamptz timestampltz

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ora_btree_gin
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
