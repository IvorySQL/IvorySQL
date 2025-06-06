#-------------------------------------------------------------------------
#
# Makefile--
#    Makefile for src/backend/oracle_parser
#
# Copyright (c) 2023-2025, IvorySQL Global Development Team
# IDENTIFICATION
#    src/backend/oracle_parser/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------
subdir = src/backend/oracle_parser
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

PGFILEDESC = "liboracle_parser - raw parser for oracle"
NAME = liboracle_parser

# include our headers first
override CPPFLAGS := -I. -I$(srcdir) $(CPPFLAGS)
rpath =

OBJS = ora_keywords.o ora_gram.o ora_scan.o liboracle_parser.o $(WIN32RES)

# where to find ora_gen_keywordlist.pl and subsidiary files
TOOLSDIR = $(top_srcdir)/src/tools
GEN_KEYWORDLIST = $(PERL) -I $(TOOLSDIR) $(TOOLSDIR)/ora_gen_keywordlist.pl
GEN_KEYWORDLIST_DEPS = $(TOOLSDIR)/ora_gen_keywordlist.pl $(TOOLSDIR)/PerfectHash.pm

all: all-shared-lib

include $(top_srcdir)/src/Makefile.shlib

install: all installdirs install-lib

installdirs: installdirs-lib

uninstall: uninstall-lib


# See notes in src/backend/oracle_parser/Makefile about the following two rules
ora_gram.h: ora_gram.c
	touch $@

ora_gram.c: BISONFLAGS += -d
ora_gram.c: BISON_CHECK_CMD = $(PERL) $(srcdir)/../parser/check_keywords.pl $< $(srcdir)/../../include/oracle_parser/ora_kwlist.h

ora_scan.c: FLEXFLAGS = -CF -p -p
ora_scan.c: FLEX_NO_BACKUP=yes
ora_scan.c: FLEX_FIX_WARNING=yes

# Force these dependencies to be known even without dependency info built:
ora_scan.o ora_gram.o ora_keywords.o liboracle_parser.o: ora_gram.h

# generate SQL keyword lookup table to be included into ora_keywords*.o.
ora_kwlist_d.h: $(top_srcdir)/src/include/oracle_parser/ora_kwlist.h $(GEN_KEYWORDLIST_DEPS)
	$(GEN_KEYWORDLIST) --extern $<

# Dependencies of ora_keywords*.o need to be managed explicitly to make sure
# that you don't get broken parsing code, even in a non-enable-depend build.
ora_keywords.o : ora_kwlist_d.h


distprep: ora_scan.c ora_gram.c ora_kwlist_d.h

# ora_gram.c, ora_gram.h, and ora_scan.c are in the distribution tarball, so they
# are not clean here.
clean distclean: clean-lib
	rm -f lex.backup $(OBJS)

maintainer-clean: clean
	rm -f ora_scan.c ora_gram.c ora_kwlist_d.h
