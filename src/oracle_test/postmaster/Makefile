#-------------------------------------------------------------------------
#
# Makefile for src/test/postmaster
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/test/postmaster/Makefile
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/postmaster
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

check:
	$(oracle_prove_check)

installcheck:
	$(oracle_prove_installcheck)

clean distclean:
	rm -rf tmp_check
