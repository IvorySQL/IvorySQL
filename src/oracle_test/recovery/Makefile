#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/recovery
#
# Portions Copyright (c) 2022, IvorySQL-2.0
#
# src/oracle_test/recovery/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

EXTRA_INSTALL=contrib/test_decoding

subdir = src/oracle_test/recovery
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

# required for 017_shm.pl
REGRESS_SHLIB=$(abs_top_builddir)/src/oracle_test/regress/regress$(DLSUFFIX)
export REGRESS_SHLIB

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check
