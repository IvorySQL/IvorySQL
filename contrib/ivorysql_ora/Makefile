# contrib/ivorysql_ora/Makefile

MODULE_big = ivorysql_ora

OBJS = \
	$(WIN32RES) \
	src/ivorysql_ora.o \
	src/guc/guc.o	\
	src/datatype/oracharchar.o \
	src/datatype/oracharbyte.o \
	src/datatype/oravarcharchar.o \
	src/datatype/oravarcharbyte.o \
	src/datatype/oradate.o \
	src/datatype/oratimestamp.o \
	src/datatype/oratimestamptz.o \
	src/datatype/oratimestampltz.o \
	src/datatype/yminterval.o \
	src/datatype/dsinterval.o \
	src/datatype/compatible_oracle_precedence.o \
	src/datatype/common_datatypes.o \
	src/datatype/raw_long.o \
	src/datatype/binary_float.o \
	src/datatype/binary_double.o \
	src/builtin_functions/character_datatype_functions.o \
	src/builtin_functions/datetime_datatype_functions.o \
	src/builtin_functions/numeric_datatype_functions.o \
	src/builtin_functions/misc_functions.o \
	src/builtin_packages/dbms_output/dbms_output.o \
	src/merge/ora_merge.o \
	src/sysview/sysview_functions.o \
	src/xml_functions/ora_xml_functions.o \
	src/builtin_packages/dbms_utility/dbms_utility.o

EXTENSION = ivorysql_ora

# SQL(s) which need to be generated only if which is specified here.
DATA = ivorysql_ora--1.0.sql

all: gensql

install: install-data

clean: cleansql

# SQL(s) merge using perl
gensql: gensql.pl
	$(PERL) $< gcc_build $(patsubst ivorysql_ora--%.sql, %, $(DATA))

# Preload the compatible oracle misc sql script
install-data:
	$(INSTALL_DATA) $(srcdir)/preload_ora_misc.sql '$(DESTDIR)$(datadir)/preload_ora_misc.sql'

# Clean the generated SQL(s).
cleansql:
	rm -f $(DATA)

# REGRESS_OPTS mainly used for installcheck or debug.
#REGRESS_OPTS = --port=1521
ORA_REGRESS = \
	ora_character \
	ora_datetime \
	ora_interval \
	ora_number \
	ora_binary_float \
	ora_binary_double \
	ora_raw_long \
	ora_character_datatype_functions \
	ora_datetime_datatype_functions \
	ora_misc_functions \
	ora_merge \
	datatype_and_func_bugs \
	ora_sysview \
	ora_like_operator \
	ora_xml_functions \
	dbms_utility \
	ora_dbms_output \
	ora_ascii

SHLIB_LINK += -lxml2

# Include path for plisql.h (needed by dbms_utility)
PG_CPPFLAGS += -I$(top_srcdir)/src/pl/plisql/src

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ivorysql_ora
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif



