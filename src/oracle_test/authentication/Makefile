#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/authentication
#
# Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/authentication/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/authentication
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

oracle_check:
	$(oracle_prove_check)

oracle_installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check
