# contrib/gb18030_2022/Makefile

MODULES = gb18030_2022
MODULE_big = gb18030_2022
OBJS = \
	$(WIN32RES) \
	utf8_and_gb18030_2022.o

EXTENSION = gb18030_2022
PGFILEDESC = "gb18030_2022,support gb18030 2022 with extension"
DATA = gb18030_2022--1.0.sql
REGRESS = gb18030_2022_and_utf8 \
		copy

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/gb18030_2022
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

ifeq ($(with_llvm), yes)
BITCODE_CFLAGS += -fPIC

%.bc: %.c
	$(COMPILE.c.bc) -o $@ $<

gb18030_2022.bc: utf8_and_gb18030_2022.bc
	cp $< $@

else
# create empty bitcode files to satisfy dependencies
%.bc: %.c
	@echo "LLVM disabled, creating empty bitcode file: $@"
	@touch $@

gb18030_2022.bc: utf8_and_gb18030_2022.bc
	@echo "LLVM disabled, creating empty bitcode file: $@"
	@touch $@

endif

all: $(patsubst %.o,%.bc,$(OBJS)) gb18030_2022.bc
