# contrib/spi/Makefile

MODULES = autoinc insert_username moddatetime

EXTENSION = autoinc insert_username moddatetime

DATA = autoinc--1.0.sql \
       insert_username--1.0.sql \
       moddatetime--1.0.sql
PGFILEDESC = "spi - examples of using SPI and triggers"

REGRESS = autoinc

DOCS = $(addsuffix .example, $(MODULES))

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/spi
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
