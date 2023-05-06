#-------------------------------------------------------------------------
#
# GNUmakefile--
#    Makefile for src/oracle_test/regress (the regression tests)
#
# Portions Copyright (c) 2023, Ivory SQL Global Development Team
# Portions Copyright (c) 1996-2023, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/oracle_test/regress/GNUmakefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

PGFILEDESC = "pg_regress - test driver"
PGAPPICON = win32

subdir = src/oracle_test/regress
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

# maximum simultaneous connections for parallel tests
MAXCONNOPT =
ifdef MAX_CONNECTIONS
MAXCONNOPT += --max-connections=$(MAX_CONNECTIONS)
endif

# stuff to pass into build of pg_regress
EXTRADEFS = '-DHOST_TUPLE="$(host_tuple)"' \
	'-DSHELLPROG="$(SHELL)"' \
	'-DDLSUFFIX="$(DLSUFFIX)"'

##
## Prepare for tests
##

# Build regression test driver

all: pg_regress$(X)

pg_regress$(X): pg_regress.o pg_regress_main.o $(WIN32RES) | submake-libpgport
	$(CC) $(CFLAGS) $^ $(LDFLAGS) $(LDFLAGS_EX) $(LIBS) -o $@

# dependencies ensure that path changes propagate
pg_regress.o: pg_regress.c $(top_builddir)/src/port/pg_config_paths.h
pg_regress.o: override CPPFLAGS += -I$(top_builddir)/src/port $(EXTRADEFS)

# note: because of the submake dependency, this rule's action is really a no-op
$(top_builddir)/src/port/pg_config_paths.h: | submake-libpgport
	$(MAKE) -C $(top_builddir)/src/port pg_config_paths.h

install: all installdirs
	$(INSTALL_PROGRAM) pg_regress$(X) '$(DESTDIR)$(pgxsdir)/$(subdir)/pg_regress$(X)'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(pgxsdir)/$(subdir)'

uninstall:
	rm -f '$(DESTDIR)$(pgxsdir)/$(subdir)/pg_regress$(X)'


# Build dynamically-loaded object file for CREATE FUNCTION ... LANGUAGE C.

NAME = oraregress
OBJS = $(WIN32RES) regress.o

include $(top_srcdir)/src/Makefile.shlib

all: all-lib

# Ensure parallel safety if a build is started in this directory
$(OBJS): | submake-libpgport submake-generated-headers


# not installed by default

regress_data_files = \
	$(wildcard $(srcdir)/sql/*.sql) \
	$(wildcard $(srcdir)/expected/*.out) \
	$(wildcard $(srcdir)/data/*.data) \
	$(srcdir)/parallel_schedule $(srcdir)/resultmap

install-tests: all install install-lib installdirs-tests
	$(MAKE) -C $(top_builddir)/contrib/spi install
	for file in $(subst $(srcdir)/,,$(regress_data_files)); do \
		$(INSTALL_DATA) $(srcdir)/$$file '$(DESTDIR)$(pkglibdir)/regress/'$$file || exit; \
	done

installdirs-tests: installdirs
	$(MKDIR_P)  $(patsubst $(srcdir)/%/,'$(DESTDIR)$(pkglibdir)/regress/%',$(sort $(dir $(regress_data_files))))


# Get some extra C modules from contrib/spi

all: refint$(DLSUFFIX) autoinc$(DLSUFFIX)

refint$(DLSUFFIX): $(top_builddir)/contrib/spi/refint$(DLSUFFIX)
	cp $< $@

autoinc$(DLSUFFIX): $(top_builddir)/contrib/spi/autoinc$(DLSUFFIX)
	cp $< $@

$(top_builddir)/contrib/spi/refint$(DLSUFFIX): | submake-contrib-spi ;

$(top_builddir)/contrib/spi/autoinc$(DLSUFFIX): | submake-contrib-spi ;

submake-contrib-spi: | submake-libpgport submake-generated-headers
	$(MAKE) -C $(top_builddir)/contrib/spi

.PHONY: submake-contrib-spi


##
## Run tests
##

ORACLE_REGRESS_OPTS = --dlpath=. --max-concurrent-tests=20 \
	$(EXTRA_REGRESS_OPTS)

oracle-check: all
	$(oracle_regress_check) $(ORACLE_REGRESS_OPTS) --schedule=$(srcdir)/parallel_schedule $(MAXCONNOPT) $(EXTRA_TESTS)

oracle-check-tests: all | temp-install
	$(oracle_regress_check) $(ORACLE_REGRESS_OPTS) $(MAXCONNOPT) $(TESTS) $(EXTRA_TESTS)

oracle-installcheck: all
	$(oracle_regress_installcheck) $(ORACLE_REGRESS_OPTS) --schedule=$(srcdir)/parallel_schedule --max-connections=1 $(EXTRA_TESTS)

oracle-installcheck-parallel: all
	$(oracle_regress_installcheck) $(ORACLE_REGRESS_OPTS) --schedule=$(srcdir)/parallel_schedule $(MAXCONNOPT) $(EXTRA_TESTS)

oracle-installcheck-tests: all
	$(oracle_regress_installcheck) $(ORACLE_REGRESS_OPTS) $(TESTS) $(EXTRA_TESTS)

# old interfaces follow...

runcheck: oracle-check
runtest: oracle-installcheck
runtest-parallel: installcheck-parallel oracle-installcheck-parallel

bigtest: all
	$(oracle_regress_installcheck) $(ORACLE_REGRESS_OPTS) --schedule=$(srcdir)/parallel_schedule --max-connections=1 numeric_big

bigcheck: all | temp-install
	$(oracle_regress_check) $(ORACLE_REGRESS_OPTS) --schedule=$(srcdir)/parallel_schedule $(MAXCONNOPT) numeric_big


##
## Clean up
##

clean distclean maintainer-clean: clean-lib
# things built by `all' target
	rm -f $(OBJS) refint$(DLSUFFIX) autoinc$(DLSUFFIX)
	rm -f pg_regress_main.o pg_regress.o pg_regress$(X)
# things created by various check targets
	rm -rf $(oracle_regress_clean_files)
	rm -rf regress$(DLSUFFIX)
