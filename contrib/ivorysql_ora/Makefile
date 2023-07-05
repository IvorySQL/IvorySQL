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
	src/builtin_functions/character_datatype_functions.o \
	src/builtin_functions/datetime_datatype_functions.o \
	src/builtin_functions/numeric_datatype_functions.o \
	src/builtin_functions/misc_functions.o \
	src/merge/ora_merge.o

EXTENSION = ivorysql_ora

# mayber we no need shell scripts, do xxx.sql merge within Makefile.
# reference babelfish Makefile 
DATA = ivorysql_ora--1.0.sql

# REGRESS_OPTS mainly used for installcheck or debug.
#REGRESS_OPTS = --port=1521
REGRESS = \
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
	ora_like_operator

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



