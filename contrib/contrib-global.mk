# contrib/contrib-global.mk

NO_PGXS = 1

# Oracle test modules copied from src/test/modules may use the PostgreSQL
# test variable names.  Include them in oracle-check-world as well, while
# preserving any explicitly supplied Oracle test lists and options.
ifneq (,$(filter src/oracle_test/modules/%,$(subdir)))
ifdef REGRESS
ORA_REGRESS ?= $(REGRESS)
ifeq ($(origin ORACLE_REGRESS_OPTS),undefined)
ORACLE_REGRESS_OPTS := $(REGRESS_OPTS)
endif
endif
ifdef ISOLATION
ORA_ISOLATION ?= $(ISOLATION)
ifeq ($(origin ORA_ISOLATION_OPTS),undefined)
ORA_ISOLATION_OPTS := $(ISOLATION_OPTS)
endif
endif
endif

include $(top_srcdir)/src/makefiles/pgxs.mk
