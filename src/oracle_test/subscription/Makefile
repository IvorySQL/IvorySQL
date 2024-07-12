#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/subscription
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/subscription/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/subscription
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

EXTRA_INSTALL = contrib/hstore

export with_icu

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check

