#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/libpq_encryption
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/libpq_encryption/Makefile
#
#-------------------------------------------------------------------------

subdir = src/oracle_test/libpq_encryption
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

export with_ssl with_gssapi with_krb_srvnam

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean:
	rm -rf tmp_check
