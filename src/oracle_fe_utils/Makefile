#-------------------------------------------------------------------------
#
# Makefile for src/oracle_fe_utils
#
# This makefile generates a static library, liborafeutils.a,
# for use by client applications
#
# Portions Copyright (c) 2022, IvorySQL
#
# IDENTIFICATION
#    src/oracle_fe_utils/Makefile
#
# add the file for requirement "SQL PARSER"
#
#-------------------------------------------------------------------------

subdir = src/oracle_fe_utils
top_builddir = ../..
include $(top_builddir)/src/Makefile.global

override CPPFLAGS := -DFRONTEND -I$(libpq_srcdir) $(CPPFLAGS)

OBJS = ora_string_utils.o

all: liborafeutils.a

liborafeutils.a: $(OBJS)
	rm -f $@
	$(AR) $(AROPT) $@ $^

# liborafeutils could be useful to contrib, so install it
install: all installdirs
	$(INSTALL_STLIB) liborafeutils.a '$(DESTDIR)$(libdir)/liborafeutils.a'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(libdir)'

uninstall:
	rm -f '$(DESTDIR)$(libdir)/liborafeutils.a'

clean distclean:
	rm -f liborafeutils.a $(OBJS) lex.backup

maintainer-clean: distclean
	rm -f ora_string_utils.o