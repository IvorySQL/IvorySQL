SRCS		+= $(NAME).c
OBJS		+= $(NAME).o $(WIN32RES)

rpath =

all: all-shared-lib

include $(top_srcdir)/src/Makefile.shlib

install: all installdirs install-lib

installdirs: installdirs-lib

uninstall: uninstall-lib

clean distclean: clean-lib
	rm -f $(OBJS)
