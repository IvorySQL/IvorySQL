#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/ldap
#
# Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/ldap/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/ldap
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

export with_ldap

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check
