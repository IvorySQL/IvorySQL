#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/kerberos
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/kerberos/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/kerberos
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

EXTRA_INSTALL += contrib/postgres_fdw
EXTRA_INSTALL += contrib/dblink

export with_gssapi with_krb_srvnam

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check
