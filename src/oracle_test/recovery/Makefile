#-------------------------------------------------------------------------
#
# Makefile for src/oracle_test/recovery
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/recovery/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

EXTRA_INSTALL=contrib/pg_prewarm \
	contrib/pg_stat_statements \
	contrib/test_decoding \
	src/oracle_test/modules/injection_points

subdir = src/oracle_test/recovery
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

export enable_injection_points

# required for 017_shm.pl and 027_stream_regress.pl
REGRESS_SHLIB=$(abs_top_builddir)/src/oracle_test/regress/regress$(DLSUFFIX)
export REGRESS_SHLIB

oracle-check:
	$(oracle_prove_check)

oracle-installcheck:
	$(oracle_prove_installcheck)

clean distclean maintainer-clean:
	rm -rf tmp_check
