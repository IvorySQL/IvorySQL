#-------------------------------------------------------------------------
#
# Makefile for src/test/icu
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/test/icu/Makefile
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/icu
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

export with_icu

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check
