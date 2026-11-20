# src/oracle_test/modules/nbtree/Makefile

EXTRA_INSTALL = src/test/modules/injection_points contrib/amcheck

REGRESS = nbtree_half_dead_pages \
	nbtree_incomplete_splits

# nbtree_half_dead_pages cannot run in Oracle mode yet: psql in
# oracle-compatible mode fails to split statements after a $$-quoted
# body, so the CALL of wait_prunable() executes inside a multi-statement
# implicit transaction where ROLLBACK is not allowed.  Pre-existing
# psql issue, exposed here by the ORA_REGRESS fallback added to
# contrib/contrib-global.mk; re-enable once psql is fixed.
ORA_REGRESS = nbtree_incomplete_splits

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = src/oracle_test/modules/nbtree
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
