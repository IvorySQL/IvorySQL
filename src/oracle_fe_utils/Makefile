#-------------------------------------------------------------------------
# Copyright 2025 IvorySQL Global Development Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Makefile for src/oracle_fe_utils
#
# This makefile generates a static library, liborafeutils.a,
# for use by client applications
#
# Copyright (c) 2023-2026, IvorySQL Global Development Team
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

OBJS = ora_string_utils.o \
	ora_psqlscan.o

all: liborafeutils.a

liborafeutils.a: $(OBJS)
	rm -f $@
	$(AR) $(AROPT) $@ $^

ora_psqlscan.c: FLEXFLAGS = -Cfe -p -p
ora_psqlscan.c: FLEX_NO_BACKUP=yes
ora_psqlscan.c: FLEX_FIX_WARNING=yes

# liborafeutils could be useful to contrib, so install it
install: all installdirs
	$(INSTALL_STLIB) liborafeutils.a '$(DESTDIR)$(libdir)/liborafeutils.a'

installdirs:
	$(MKDIR_P) '$(DESTDIR)$(libdir)'

uninstall:
	rm -f '$(DESTDIR)$(libdir)/liborafeutils.a'

clean distclean:
	rm -f liborafeutils.a $(OBJS) lex.backup ora_psqlscan.c

maintainer-clean: distclean
	rm -f ora_psqlscan.c ora_string_utils.o
