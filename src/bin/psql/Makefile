#-------------------------------------------------------------------------
#
# Makefile for src/bin/psql
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/bin/psql/Makefile
#
#-------------------------------------------------------------------------

PGFILEDESC = "psql - the PostgreSQL interactive terminal"
PGAPPICON=win32

subdir = src/bin/psql
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

# make this available to TAP test scripts
export with_readline

REFDOCDIR= $(top_srcdir)/doc/src/sgml/ref

override CPPFLAGS := -I. -I$(srcdir) -I$(libpq_srcdir) $(CPPFLAGS)
LDFLAGS_INTERNAL += -L$(top_builddir)/src/oracle_fe_utils -lorafeutils -L$(top_builddir)/src/fe_utils -lpgfeutils $(libpq_pgport)

OBJS = \
	$(WIN32RES) \
	command.o \
	common.o \
	copy.o \
	crosstabview.o \
	describe.o \
	help.o \
	input.o \
	large_obj.o \
	mainloop.o \
	ora_prompt.o \
	ora_psqlscanslash.o \
	prompt.o \
	psqlplusparse.o \
	psqlscanslash.o \
	sql_help.o \
	startup.o \
	stringutils.o \
	tab-complete.o \
	psqlplusscan.o \
	variables.o


all: psql

psql: $(OBJS) | submake-libpq submake-libpgport submake-libpgfeutils
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) $(LDFLAGS_EX) $(LIBS) -o $@$(X)

# See notes in src/backend/parser/Makefile about the following two rules
psqlplusparse.h: psqlplusparse.c
	touch $@
psqlplusparse.c: BISONFLAGS += -d
# Force these dependencies to be known even without dependency info built:
psqlplusparse.o psqlplusscan.o: psqlplusparse.h

help.o: sql_help.h

# ReqID:SRS-CMD-PSQL
psqlplusparse.o: psqlplusscan.c

# See notes in src/backend/parser/Makefile about the following two rules
sql_help.c: sql_help.h
	touch $@

sql_help.h: create_help.pl $(wildcard $(REFDOCDIR)/*.sgml)
	$(PERL) $< --docdir $(REFDOCDIR) --basename $*

psqlscanslash.c: FLEXFLAGS = -Cfe -p -p
psqlscanslash.c: FLEX_NO_BACKUP=yes
psqlscanslash.c: FLEX_FIX_WARNING=yes

ora_psqlscanslash.c: FLEXFLAGS = -Cfe -p -p
ora_psqlscanslash.c: FLEX_NO_BACKUP=yes
ora_psqlscanslash.c: FLEX_FIX_WARNING=yes

install: all installdirs
	$(INSTALL_PROGRAM) psql$(X) '$(DESTDIR)$(bindir)/psql$(X)'
	$(INSTALL_DATA) $(srcdir)/psqlrc.sample '$(DESTDIR)$(datadir)/psqlrc.sample'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(bindir)' '$(DESTDIR)$(datadir)'

uninstall:
	rm -f '$(DESTDIR)$(bindir)/psql$(X)' '$(DESTDIR)$(datadir)/psqlrc.sample'

clean distclean:
	rm -f psql$(X) $(OBJS) lex.backup ora_psqlscanslash.c
	rm -rf tmp_check
	rm -f ora_psqlscanslash.c sql_help.h sql_help.c psqlscanslash.c
	rm -f psqlplusscan.c psqlplusparse.c
	rm -f psqlplusparse.h

check:
	$(prove_check)

oracle-check:
	$(oracle_prove_check)

installcheck:
	$(prove_installcheck)

oracle-installcheck:
	$(oracle_prove_installcheck)
