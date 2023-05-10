#-------------------------------------------------------------------------
#
# Makefile for src/oracle_fe_utils
#
# This makefile generates a static library, liborafeutils.a,
# for use by client applications
#
# Portions Copyright (c) 2023, IvorySQL
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

/* IvorySQL:BEGIN - psql-parser */
OBJS = ora_string_utils.o \
	ora_psqlscan.o
/* IvorySQL:END - psql-parser */

all: liborafeutils.a

liborafeutils.a: $(OBJS)
	rm -f $@
	$(AR) $(AROPT) $@ $^

/* IvorySQL:BEGIN - psql-parser */
ora_psqlscan.c: FLEXFLAGS = -Cfe -p -p
ora_psqlscan.c: FLEX_NO_BACKUP=yes
ora_psqlscan.c: FLEX_FIX_WARNING=yes
/* IvorySQL:END - psql-parser */

# liborafeutils could be useful to contrib, so install it
install: all installdirs
	$(INSTALL_STLIB) liborafeutils.a '$(DESTDIR)$(libdir)/liborafeutils.a'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(libdir)'

uninstall:
	rm -f '$(DESTDIR)$(libdir)/liborafeutils.a'

/* IvorySQL:BEGIN - psql-parser */
clean distclean:
	rm -f liborafeutils.a $(OBJS) lex.backup ora_psqlscan.c
/* IvorySQL:END - psql-parser */

/* IvorySQL:BEGIN - psql-parser */
maintainer-clean: distclean
	rm -f ora_psqlscan.c ora_string_utils.o
/* IvorySQL:END - psql-parser */
