#-------------------------------------------------------------------------
#
# Makefile for src/fe_utils
#
# This makefile generates a static library, libpgfeutils.a,
# for use by client applications
#
# Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# IDENTIFICATION
#    src/fe_utils/Makefile
#
#-------------------------------------------------------------------------

subdir = src/fe_utils
top_builddir = ../..
include $(top_builddir)/src/Makefile.global

#override CPPFLAGS := -DFRONTEND -I$(libpq_srcdir) $(CPPFLAGS)
override CPPFLAGS := -DFRONTEND -I$(libpq_srcdir) -I$(top_builddir)/src/include/oracle_fe_utils $(CPPFLAGS)

OBJS = \
	archive.o \
	cancel.o \
	conditional.o \
	connect_utils.o \
	mbprint.o \
	option_utils.o \
	parallel_slot.o \
	print.o \
	psqlscan.o \
	query_utils.o \
	recovery_gen.o \
	simple_list.o \
	string_utils.o \
	ora_keywords.o \
	ora_string_utils.o

# where to find ora_gen_keywordlist.pl and subsidiary files
TOOLSDIR = $(top_srcdir)/src/tools
GEN_KEYWORDLIST = $(PERL) -I $(TOOLSDIR) $(TOOLSDIR)/ora_gen_keywordlist.pl
GEN_KEYWORDLIST_DEPS = $(TOOLSDIR)/ora_gen_keywordlist.pl $(TOOLSDIR)/PerfectHash.pm

ifeq ($(PORTNAME), win32)
override CPPFLAGS += -DFD_SETSIZE=1024
endif

all: libpgfeutils.a

libpgfeutils.a: $(OBJS)
	rm -f $@
	$(AR) $(AROPT) $@ $^

psqlscan.c: FLEXFLAGS = -Cfe -p -p
psqlscan.c: FLEX_NO_BACKUP=yes
psqlscan.c: FLEX_FIX_WARNING=yes

# generate SQL keyword lookup table to be included into ora_keywords*.o.
ora_kwlist_d.h: $(top_srcdir)/src/include/oracle_parser/ora_kwlist.h $(GEN_KEYWORDLIST_DEPS)
	$(GEN_KEYWORDLIST) --extern $<

# Dependencies of ora_keywords*.o need to be managed explicitly to make sure
# that you don't get broken parsing code, even in a non-enable-depend build.
ora_keywords.o: ora_kwlist_d.h

ora_keywords.c: % : $(top_srcdir)/src/backend/oracle_parser/%
	rm -f $@ && $(LN_S) $< .

ora_string_utils.c: % : $(top_srcdir)/src/oracle_fe_utils/%
	rm -f $@ && $(LN_S) $< .

# libpgfeutils could be useful to contrib, so install it
install: all installdirs
	$(INSTALL_STLIB) libpgfeutils.a '$(DESTDIR)$(libdir)/libpgfeutils.a'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(libdir)'

uninstall:
	rm -f '$(DESTDIR)$(libdir)/libpgfeutils.a'

clean distclean:
	rm -f libpgfeutils.a $(OBJS) lex.backup
	rm -f psqlscan.c ora_keywords.c ora_string_utils.c ora_kwlist_d.h
