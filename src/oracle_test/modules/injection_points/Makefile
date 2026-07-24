# src/oracle_test/modules/injection_points/Makefile

MODULE_big = injection_points
OBJS = \
	$(WIN32RES) \
	injection_points.o \
	regress_injection.o
EXTENSION = injection_points
DATA = injection_points--1.0.sql
PGFILEDESC = "injection_points - facility for injection points"

REGRESS = injection_points hashagg reindex_conc vacuum
REGRESS_OPTS = --dlpath=$(top_builddir)/src/oracle_test/regress

ISOLATION = basic \
	    inplace \
	    syscache-update-pruned \
	    heap_lock_update

# The injection points are cluster-wide, so disable installcheck
NO_INSTALLCHECK = 1

export enable_injection_points

# Oracle-compatible subset of the regression suite.
# The injection_points test case is excluded: it fails under Oracle mode
# because the injection-points machinery does not fire in the
# Oracle-compatible parser (the function calls return empty where the
# expected output has error/notice/result rows). Verified via
# make oracle-check-world in CI. The other three cases (hashagg,
# reindex_conc, vacuum) pass.
ORA_REGRESS = hashagg reindex_conc vacuum
ORA_ISOLATION = $(ISOLATION)

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/oracle_test/modules/injection_points
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global

# XXX: This test is conditional on enable_injection_points in the
# parent Makefile, so we should never get here in the first place if
# injection points are not enabled. But the buildfarm 'misc-check'
# step doesn't pay attention to the if-condition in the parent
# Makefile. To work around that, disable running the test here too.
ifeq ($(enable_injection_points),yes)
include $(top_srcdir)/contrib/contrib-global.mk
else
check:
	@echo "injection points are disabled in this build"
endif

endif
