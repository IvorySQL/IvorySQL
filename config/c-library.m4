# Macros that test various C library quirks
# config/c-library.m4


# PGAC_VAR_INT_TIMEZONE
# ---------------------
# Check if the global variable `timezone' exists. If so, define
# HAVE_INT_TIMEZONE.
AC_DEFUN([PGAC_VAR_INT_TIMEZONE],
[AC_CACHE_CHECK(for int timezone, pgac_cv_var_int_timezone,
[AC_LINK_IFELSE([AC_LANG_PROGRAM([#include <time.h>
int res;],
  [#ifndef __CYGWIN__
res = timezone / 60;
#else
res = _timezone / 60;
#endif])],
  [pgac_cv_var_int_timezone=yes],
  [pgac_cv_var_int_timezone=no])])
if test x"$pgac_cv_var_int_timezone" = xyes ; then
  AC_DEFINE(HAVE_INT_TIMEZONE, 1,
            [Define to 1 if you have the global variable 'int timezone'.])
fi])# PGAC_VAR_INT_TIMEZONE


# PGAC_STRUCT_TIMEZONE
# ------------------
# Figure out how to get the current timezone.  If `struct tm' has a
# `tm_zone' member, define `HAVE_STRUCT_TM_TM_ZONE'.  Unlike the
# standard macro AC_STRUCT_TIMEZONE, we don't check for `tzname[]' if
# not found, since we don't use it.  (We use `int timezone' as a
# fallback.)
AC_DEFUN([PGAC_STRUCT_TIMEZONE],
[AC_CHECK_MEMBERS([struct tm.tm_zone],,,[#include <sys/types.h>
#include <time.h>
])
])# PGAC_STRUCT_TIMEZONE


# PGAC_FUNC_STRERROR_R_INT
# ---------------------------
# Check if strerror_r() returns int (POSIX) rather than char * (GNU libc).
# If so, define STRERROR_R_INT.
# The result is uncertain if strerror_r() isn't provided,
# but we don't much care.
AC_DEFUN([PGAC_FUNC_STRERROR_R_INT],
[AC_CACHE_CHECK(whether strerror_r returns int,
pgac_cv_func_strerror_r_int,
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM([#include <string.h>],
[[char buf[100];
  switch (strerror_r(1, buf, sizeof(buf)))
  { case 0: break; default: break; }
]])],
[pgac_cv_func_strerror_r_int=yes],
[pgac_cv_func_strerror_r_int=no])])
if test x"$pgac_cv_func_strerror_r_int" = xyes ; then
  AC_DEFINE(STRERROR_R_INT, 1,
            [Define to 1 if strerror_r() returns int.])
fi
])# PGAC_FUNC_STRERROR_R_INT


# PGAC_UNION_SEMUN
# ----------------
# Check if `union semun' exists. Define HAVE_UNION_SEMUN if so.
# If it doesn't then one could define it as
# union semun { int val; struct semid_ds *buf; unsigned short *array; }
AC_DEFUN([PGAC_UNION_SEMUN],
[AC_CHECK_TYPES([union semun], [], [],
[#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
])])# PGAC_UNION_SEMUN


# PGAC_STRUCT_SOCKADDR_MEMBERS
# ----------------------------
# Check if struct sockaddr and subtypes have 4.4BSD-style length.
AC_DEFUN([PGAC_STRUCT_SOCKADDR_SA_LEN],
[AC_CHECK_MEMBERS([struct sockaddr.sa_len], [], [],
[#include <sys/types.h>
#include <sys/socket.h>
])])# PGAC_STRUCT_SOCKADDR_MEMBERS


# PGAC_TYPE_LOCALE_T
# ------------------
# Check for the locale_t type and find the right header file.  macOS
# needs xlocale.h; standard is locale.h, but glibc <= 2.25 also had an
# xlocale.h file that we should not use, so we check the standard
# header first.
AC_DEFUN([PGAC_TYPE_LOCALE_T],
[AC_CACHE_CHECK([for locale_t], pgac_cv_type_locale_t,
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM(
[#include <locale.h>
locale_t x;],
[])],
[pgac_cv_type_locale_t=yes],
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM(
[#include <xlocale.h>
locale_t x;],
[])],
[pgac_cv_type_locale_t='yes (in xlocale.h)'],
[pgac_cv_type_locale_t=no])])])
if test "$pgac_cv_type_locale_t" = 'yes (in xlocale.h)'; then
  AC_DEFINE(LOCALE_T_IN_XLOCALE, 1,
            [Define to 1 if `locale_t' requires <xlocale.h>.])
fi])# PGAC_TYPE_LOCALE_T


# PGAC_FUNC_WCSTOMBS_L
# --------------------
# Try to find a declaration for wcstombs_l().  It might be in stdlib.h
# (following the POSIX requirement for wcstombs()), or in locale.h, or in
# xlocale.h.  If it's in the latter, define WCSTOMBS_L_IN_XLOCALE.
#
AC_DEFUN([PGAC_FUNC_WCSTOMBS_L],
[AC_CACHE_CHECK([for wcstombs_l declaration], pgac_cv_func_wcstombs_l,
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM(
[#include <stdlib.h>
#include <locale.h>],
[#ifndef wcstombs_l
(void) wcstombs_l;
#endif])],
[pgac_cv_func_wcstombs_l='yes'],
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM(
[#include <stdlib.h>
#include <locale.h>
#include <xlocale.h>],
[#ifndef wcstombs_l
(void) wcstombs_l;
#endif])],
[pgac_cv_func_wcstombs_l='yes (in xlocale.h)'],
[pgac_cv_func_wcstombs_l='no'])])])
if test "$pgac_cv_func_wcstombs_l" = 'yes (in xlocale.h)'; then
  AC_DEFINE(WCSTOMBS_L_IN_XLOCALE, 1,
            [Define to 1 if `wcstombs_l' requires <xlocale.h>.])
fi])# PGAC_FUNC_WCSTOMBS_L
