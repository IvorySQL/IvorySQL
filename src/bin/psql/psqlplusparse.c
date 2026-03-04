/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison implementation for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* C LALR(1) parser skeleton written by Richard Stallman, by
   simplifying the original so-called "semantic" parser.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

/* All symbols defined below should begin with yy or YY, to avoid
   infringing on user name space.  This should be done even for local
   variables, as they might otherwise be expanded by user macros.
   There are some unavoidable exceptions within include files to
   define necessary library symbols; they are noted "INFRINGES ON
   USER NAME SPACE" below.  */

/* Identify Bison output, and Bison version.  */
#define YYBISON 30802

/* Bison version string.  */
#define YYBISON_VERSION "3.8.2"

/* Skeleton name.  */
#define YYSKELETON_NAME "yacc.c"

/* Pure parsers.  */
#define YYPURE 1

/* Push parsers.  */
#define YYPUSH 0

/* Pull parsers.  */
#define YYPULL 1


/* Substitute the variable and function names.  */
#define yyparse         psqlplus_yyparse
#define yylex           psqlplus_yylex
#define yyerror         psqlplus_yyerror
#define yydebug         psqlplus_yydebug
#define yynerrs         psqlplus_yynerrs

/* First part of user prologue.  */
#line 1 "psqlplusparse.y"

/*-------------------------------------------------------------------------
 *
 * File: psqlplusparse.y
 *
 * Abstract:
 *		bison grammar for a oracle-compatible client commands.
 *
 * Authored by zhenmingyang@highgo.com, 20221221.
 *
 * Copyright (c) 2022-2026, IvorySQL Global Development Team
 *
 * Identification:
 *		src/bin/psql/psqlplusparse.y
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"
#include "common/logging.h"
#include "fe_utils/psqlscan_int.h"
#include "oracle_fe_utils/ora_psqlscan.h"
#include "psqlplus.h"
#include "settings.h"

static psqlplus_cmd_var *make_variable_node(void);
static psqlplus_cmd_print *make_print_node(void);
static psqlplus_cmd_execute *make_exec_node(void);
static BindVarType *make_bindvartype(int32 oid, int32 typmod, const char *typname);
static char *get_guc_settings(const char *gucname);
static print_item *make_print_item(char *name, bool valid);
static print_list *make_print_list1(print_item *item);
static print_list *merge_print_list(print_list *list1, print_list *list2);


#line 112 "psqlplusparse.c"

# ifndef YY_CAST
#  ifdef __cplusplus
#   define YY_CAST(Type, Val) static_cast<Type> (Val)
#   define YY_REINTERPRET_CAST(Type, Val) reinterpret_cast<Type> (Val)
#  else
#   define YY_CAST(Type, Val) ((Type) (Val))
#   define YY_REINTERPRET_CAST(Type, Val) ((Type) (Val))
#  endif
# endif
# ifndef YY_NULLPTR
#  if defined __cplusplus
#   if 201103L <= __cplusplus
#    define YY_NULLPTR nullptr
#   else
#    define YY_NULLPTR 0
#   endif
#  else
#   define YY_NULLPTR ((void*)0)
#  endif
# endif

#include "psqlplusparse.h"
/* Symbol kind.  */
enum yysymbol_kind_t
{
  YYSYMBOL_YYEMPTY = -2,
  YYSYMBOL_YYEOF = 0,                      /* "end of file"  */
  YYSYMBOL_YYerror = 1,                    /* error  */
  YYSYMBOL_YYUNDEF = 2,                    /* "invalid token"  */
  YYSYMBOL_K_VAR = 3,                      /* K_VAR  */
  YYSYMBOL_K_VARIABLE = 4,                 /* K_VARIABLE  */
  YYSYMBOL_K_CHAR = 5,                     /* K_CHAR  */
  YYSYMBOL_K_BYTE = 6,                     /* K_BYTE  */
  YYSYMBOL_K_NCHAR = 7,                    /* K_NCHAR  */
  YYSYMBOL_K_VARCHAR2 = 8,                 /* K_VARCHAR2  */
  YYSYMBOL_K_NVARCHAR2 = 9,                /* K_NVARCHAR2  */
  YYSYMBOL_K_NUMBER = 10,                  /* K_NUMBER  */
  YYSYMBOL_K_BINARY_FLOAT = 11,            /* K_BINARY_FLOAT  */
  YYSYMBOL_K_BINARY_DOUBLE = 12,           /* K_BINARY_DOUBLE  */
  YYSYMBOL_K_PRINT = 13,                   /* K_PRINT  */
  YYSYMBOL_K_EXECUTE = 14,                 /* K_EXECUTE  */
  YYSYMBOL_K_EXEC = 15,                    /* K_EXEC  */
  YYSYMBOL_IDENT = 16,                     /* IDENT  */
  YYSYMBOL_FCONST = 17,                    /* FCONST  */
  YYSYMBOL_LITERAL = 18,                   /* LITERAL  */
  YYSYMBOL_DQCONST = 19,                   /* DQCONST  */
  YYSYMBOL_SQCONST = 20,                   /* SQCONST  */
  YYSYMBOL_ICONST = 21,                    /* ICONST  */
  YYSYMBOL_SINGLE_QUOTE_NO_END = 22,       /* SINGLE_QUOTE_NO_END  */
  YYSYMBOL_DOUBLE_QUOTE_NO_END = 23,       /* DOUBLE_QUOTE_NO_END  */
  YYSYMBOL_TYPECAST = 24,                  /* TYPECAST  */
  YYSYMBOL_25_ = 25,                       /* '='  */
  YYSYMBOL_26_ = 26,                       /* '+'  */
  YYSYMBOL_27_ = 27,                       /* '-'  */
  YYSYMBOL_28_ = 28,                       /* '('  */
  YYSYMBOL_29_ = 29,                       /* ')'  */
  YYSYMBOL_30_ = 30,                       /* ','  */
  YYSYMBOL_31_ = 31,                       /* ';'  */
  YYSYMBOL_YYACCEPT = 32,                  /* $accept  */
  YYSYMBOL_psqlplus_toplevel_stmt = 33,    /* psqlplus_toplevel_stmt  */
  YYSYMBOL_variable_stmt = 34,             /* variable_stmt  */
  YYSYMBOL_variable_keyword = 35,          /* variable_keyword  */
  YYSYMBOL_variable_spec = 36,             /* variable_spec  */
  YYSYMBOL_opt_varname = 37,               /* opt_varname  */
  YYSYMBOL_bind_varname = 38,              /* bind_varname  */
  YYSYMBOL_bind_varvalue = 39,             /* bind_varvalue  */
  YYSYMBOL_bind_vartype = 40,              /* bind_vartype  */
  YYSYMBOL_truncate_char = 41,             /* truncate_char  */
  YYSYMBOL_print_stmt = 42,                /* print_stmt  */
  YYSYMBOL_print_items_list = 43,          /* print_items_list  */
  YYSYMBOL_print_items = 44,               /* print_items  */
  YYSYMBOL_exec_stmt = 45,                 /* exec_stmt  */
  YYSYMBOL_exec_keyword = 46,              /* exec_keyword  */
  YYSYMBOL_Sconst = 47,                    /* Sconst  */
  YYSYMBOL_opt_semi = 48,                  /* opt_semi  */
  YYSYMBOL_unreserved_keyword = 49         /* unreserved_keyword  */
};
typedef enum yysymbol_kind_t yysymbol_kind_t;




#ifdef short
# undef short
#endif

/* On compilers that do not define __PTRDIFF_MAX__ etc., make sure
   <limits.h> and (if available) <stdint.h> are included
   so that the code can choose integer types of a good width.  */

#ifndef __PTRDIFF_MAX__
# include <limits.h> /* INFRINGES ON USER NAME SPACE */
# if defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stdint.h> /* INFRINGES ON USER NAME SPACE */
#  define YY_STDINT_H
# endif
#endif

/* Narrow types that promote to a signed type and that can represent a
   signed or unsigned integer of at least N bits.  In tables they can
   save space and decrease cache pressure.  Promoting to a signed type
   helps avoid bugs in integer arithmetic.  */

#ifdef __INT_LEAST8_MAX__
typedef __INT_LEAST8_TYPE__ yytype_int8;
#elif defined YY_STDINT_H
typedef int_least8_t yytype_int8;
#else
typedef signed char yytype_int8;
#endif

#ifdef __INT_LEAST16_MAX__
typedef __INT_LEAST16_TYPE__ yytype_int16;
#elif defined YY_STDINT_H
typedef int_least16_t yytype_int16;
#else
typedef short yytype_int16;
#endif

/* Work around bug in HP-UX 11.23, which defines these macros
   incorrectly for preprocessor constants.  This workaround can likely
   be removed in 2023, as HPE has promised support for HP-UX 11.23
   (aka HP-UX 11i v2) only through the end of 2022; see Table 2 of
   <https://h20195.www2.hpe.com/V2/getpdf.aspx/4AA4-7673ENW.pdf>.  */
#ifdef __hpux
# undef UINT_LEAST8_MAX
# undef UINT_LEAST16_MAX
# define UINT_LEAST8_MAX 255
# define UINT_LEAST16_MAX 65535
#endif

#if defined __UINT_LEAST8_MAX__ && __UINT_LEAST8_MAX__ <= __INT_MAX__
typedef __UINT_LEAST8_TYPE__ yytype_uint8;
#elif (!defined __UINT_LEAST8_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST8_MAX <= INT_MAX)
typedef uint_least8_t yytype_uint8;
#elif !defined __UINT_LEAST8_MAX__ && UCHAR_MAX <= INT_MAX
typedef unsigned char yytype_uint8;
#else
typedef short yytype_uint8;
#endif

#if defined __UINT_LEAST16_MAX__ && __UINT_LEAST16_MAX__ <= __INT_MAX__
typedef __UINT_LEAST16_TYPE__ yytype_uint16;
#elif (!defined __UINT_LEAST16_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST16_MAX <= INT_MAX)
typedef uint_least16_t yytype_uint16;
#elif !defined __UINT_LEAST16_MAX__ && USHRT_MAX <= INT_MAX
typedef unsigned short yytype_uint16;
#else
typedef int yytype_uint16;
#endif

#ifndef YYPTRDIFF_T
# if defined __PTRDIFF_TYPE__ && defined __PTRDIFF_MAX__
#  define YYPTRDIFF_T __PTRDIFF_TYPE__
#  define YYPTRDIFF_MAXIMUM __PTRDIFF_MAX__
# elif defined PTRDIFF_MAX
#  ifndef ptrdiff_t
#   include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  endif
#  define YYPTRDIFF_T ptrdiff_t
#  define YYPTRDIFF_MAXIMUM PTRDIFF_MAX
# else
#  define YYPTRDIFF_T long
#  define YYPTRDIFF_MAXIMUM LONG_MAX
# endif
#endif

#ifndef YYSIZE_T
# ifdef __SIZE_TYPE__
#  define YYSIZE_T __SIZE_TYPE__
# elif defined size_t
#  define YYSIZE_T size_t
# elif defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  define YYSIZE_T size_t
# else
#  define YYSIZE_T unsigned
# endif
#endif

#define YYSIZE_MAXIMUM                                  \
  YY_CAST (YYPTRDIFF_T,                                 \
           (YYPTRDIFF_MAXIMUM < YY_CAST (YYSIZE_T, -1)  \
            ? YYPTRDIFF_MAXIMUM                         \
            : YY_CAST (YYSIZE_T, -1)))

#define YYSIZEOF(X) YY_CAST (YYPTRDIFF_T, sizeof (X))


/* Stored state numbers (used for stacks). */
typedef yytype_int8 yy_state_t;

/* State numbers in computations.  */
typedef int yy_state_fast_t;

#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> /* INFRINGES ON USER NAME SPACE */
#   define YY_(Msgid) dgettext ("bison-runtime", Msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(Msgid) Msgid
# endif
#endif


#ifndef YY_ATTRIBUTE_PURE
# if defined __GNUC__ && 2 < __GNUC__ + (96 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_PURE __attribute__ ((__pure__))
# else
#  define YY_ATTRIBUTE_PURE
# endif
#endif

#ifndef YY_ATTRIBUTE_UNUSED
# if defined __GNUC__ && 2 < __GNUC__ + (7 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_UNUSED __attribute__ ((__unused__))
# else
#  define YY_ATTRIBUTE_UNUSED
# endif
#endif

/* Suppress unused-variable warnings by "using" E.  */
#if ! defined lint || defined __GNUC__
# define YY_USE(E) ((void) (E))
#else
# define YY_USE(E) /* empty */
#endif

/* Suppress an incorrect diagnostic about yylval being uninitialized.  */
#if defined __GNUC__ && ! defined __ICC && 406 <= __GNUC__ * 100 + __GNUC_MINOR__
# if __GNUC__ * 100 + __GNUC_MINOR__ < 407
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")
# else
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")              \
    _Pragma ("GCC diagnostic ignored \"-Wmaybe-uninitialized\"")
# endif
# define YY_IGNORE_MAYBE_UNINITIALIZED_END      \
    _Pragma ("GCC diagnostic pop")
#else
# define YY_INITIAL_VALUE(Value) Value
#endif
#ifndef YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_END
#endif
#ifndef YY_INITIAL_VALUE
# define YY_INITIAL_VALUE(Value) /* Nothing. */
#endif

#if defined __cplusplus && defined __GNUC__ && ! defined __ICC && 6 <= __GNUC__
# define YY_IGNORE_USELESS_CAST_BEGIN                          \
    _Pragma ("GCC diagnostic push")                            \
    _Pragma ("GCC diagnostic ignored \"-Wuseless-cast\"")
# define YY_IGNORE_USELESS_CAST_END            \
    _Pragma ("GCC diagnostic pop")
#endif
#ifndef YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_END
#endif


#define YY_ASSERT(E) ((void) (0 && (E)))

#if !defined yyoverflow

/* The parser invokes alloca or malloc; define the necessary symbols.  */

# ifdef YYSTACK_USE_ALLOCA
#  if YYSTACK_USE_ALLOCA
#   ifdef __GNUC__
#    define YYSTACK_ALLOC __builtin_alloca
#   elif defined __BUILTIN_VA_ARG_INCR
#    include <alloca.h> /* INFRINGES ON USER NAME SPACE */
#   elif defined _AIX
#    define YYSTACK_ALLOC __alloca
#   elif defined _MSC_VER
#    include <malloc.h> /* INFRINGES ON USER NAME SPACE */
#    define alloca _alloca
#   else
#    define YYSTACK_ALLOC alloca
#    if ! defined _ALLOCA_H && ! defined EXIT_SUCCESS
#     include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
      /* Use EXIT_SUCCESS as a witness for stdlib.h.  */
#     ifndef EXIT_SUCCESS
#      define EXIT_SUCCESS 0
#     endif
#    endif
#   endif
#  endif
# endif

# ifdef YYSTACK_ALLOC
   /* Pacify GCC's 'empty if-body' warning.  */
#  define YYSTACK_FREE(Ptr) do { /* empty */; } while (0)
#  ifndef YYSTACK_ALLOC_MAXIMUM
    /* The OS might guarantee only one guard page at the bottom of the stack,
       and a page size can be as small as 4096 bytes.  So we cannot safely
       invoke alloca (N) if N exceeds 4096.  Use a slightly smaller number
       to allow for a few compiler-allocated temporary stack slots.  */
#   define YYSTACK_ALLOC_MAXIMUM 4032 /* reasonable circa 2006 */
#  endif
# else
#  define YYSTACK_ALLOC YYMALLOC
#  define YYSTACK_FREE YYFREE
#  ifndef YYSTACK_ALLOC_MAXIMUM
#   define YYSTACK_ALLOC_MAXIMUM YYSIZE_MAXIMUM
#  endif
#  if (defined __cplusplus && ! defined EXIT_SUCCESS \
       && ! ((defined YYMALLOC || defined malloc) \
             && (defined YYFREE || defined free)))
#   include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#   ifndef EXIT_SUCCESS
#    define EXIT_SUCCESS 0
#   endif
#  endif
#  ifndef YYMALLOC
#   define YYMALLOC malloc
#   if ! defined malloc && ! defined EXIT_SUCCESS
void *malloc (YYSIZE_T); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
#  ifndef YYFREE
#   define YYFREE free
#   if ! defined free && ! defined EXIT_SUCCESS
void free (void *); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
# endif
#endif /* !defined yyoverflow */

#if (! defined yyoverflow \
     && (! defined __cplusplus \
         || (defined YYSTYPE_IS_TRIVIAL && YYSTYPE_IS_TRIVIAL)))

/* A type that is properly aligned for any stack member.  */
union yyalloc
{
  yy_state_t yyss_alloc;
  YYSTYPE yyvs_alloc;
};

/* The size of the maximum gap between one aligned stack and the next.  */
# define YYSTACK_GAP_MAXIMUM (YYSIZEOF (union yyalloc) - 1)

/* The size of an array large to enough to hold all stacks, each with
   N elements.  */
# define YYSTACK_BYTES(N) \
     ((N) * (YYSIZEOF (yy_state_t) + YYSIZEOF (YYSTYPE)) \
      + YYSTACK_GAP_MAXIMUM)

# define YYCOPY_NEEDED 1

/* Relocate STACK from its old location to the new one.  The
   local variables YYSIZE and YYSTACKSIZE give the old and new number of
   elements in the stack, and YYPTR gives the new location of the
   stack.  Advance YYPTR to a properly aligned location for the next
   stack.  */
# define YYSTACK_RELOCATE(Stack_alloc, Stack)                           \
    do                                                                  \
      {                                                                 \
        YYPTRDIFF_T yynewbytes;                                         \
        YYCOPY (&yyptr->Stack_alloc, Stack, yysize);                    \
        Stack = &yyptr->Stack_alloc;                                    \
        yynewbytes = yystacksize * YYSIZEOF (*Stack) + YYSTACK_GAP_MAXIMUM; \
        yyptr += yynewbytes / YYSIZEOF (*yyptr);                        \
      }                                                                 \
    while (0)

#endif

#if defined YYCOPY_NEEDED && YYCOPY_NEEDED
/* Copy COUNT objects from SRC to DST.  The source and destination do
   not overlap.  */
# ifndef YYCOPY
#  if defined __GNUC__ && 1 < __GNUC__
#   define YYCOPY(Dst, Src, Count) \
      __builtin_memcpy (Dst, Src, YY_CAST (YYSIZE_T, (Count)) * sizeof (*(Src)))
#  else
#   define YYCOPY(Dst, Src, Count)              \
      do                                        \
        {                                       \
          YYPTRDIFF_T yyi;                      \
          for (yyi = 0; yyi < (Count); yyi++)   \
            (Dst)[yyi] = (Src)[yyi];            \
        }                                       \
      while (0)
#  endif
# endif
#endif /* !YYCOPY_NEEDED */

/* YYFINAL -- State number of the termination state.  */
#define YYFINAL  31
/* YYLAST -- Last index in YYTABLE.  */
#define YYLAST   132

/* YYNTOKENS -- Number of terminals.  */
#define YYNTOKENS  32
/* YYNNTS -- Number of nonterminals.  */
#define YYNNTS  18
/* YYNRULES -- Number of rules.  */
#define YYNRULES  79
/* YYNSTATES -- Number of states.  */
#define YYNSTATES  96

/* YYMAXUTOK -- Last valid token kind.  */
#define YYMAXUTOK   279


/* YYTRANSLATE(TOKEN-NUM) -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex, with out-of-bounds checking.  */
#define YYTRANSLATE(YYX)                                \
  (0 <= (YYX) && (YYX) <= YYMAXUTOK                     \
   ? YY_CAST (yysymbol_kind_t, yytranslate[YYX])        \
   : YYSYMBOL_YYUNDEF)

/* YYTRANSLATE[TOKEN-NUM] -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex.  */
static const yytype_int8 yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
      28,    29,     2,    26,    30,    27,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,    31,
       2,    25,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14,
      15,    16,    17,    18,    19,    20,    21,    22,    23,    24
};

#if YYDEBUG
/* YYRLINE[YYN] -- Source line where rule number YYN was defined.  */
static const yytype_int16 yyrline[] =
{
       0,    73,    73,    77,    81,    91,    95,   114,   115,   119,
     127,   136,   144,   158,   172,   181,   194,   204,   221,   239,
     248,   251,   254,   255,   259,   260,   261,   262,   263,   264,
     265,   266,   267,   268,   279,   283,   290,   294,   298,   302,
     306,   310,   317,   321,   325,   329,   333,   337,   341,   348,
     349,   350,   357,   361,   370,   374,   381,   385,   389,   398,
     407,   427,   428,   437,   438,   442,   443,   447,   448,   449,
     450,   451,   452,   453,   454,   455,   456,   457,   458,   459
};
#endif

/** Accessing symbol of state STATE.  */
#define YY_ACCESSING_SYMBOL(State) YY_CAST (yysymbol_kind_t, yystos[State])

#if YYDEBUG || 0
/* The user-facing name of the symbol whose (internal) number is
   YYSYMBOL.  No bounds checking.  */
static const char *yysymbol_name (yysymbol_kind_t yysymbol) YY_ATTRIBUTE_UNUSED;

/* YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals.  */
static const char *const yytname[] =
{
  "\"end of file\"", "error", "\"invalid token\"", "K_VAR", "K_VARIABLE",
  "K_CHAR", "K_BYTE", "K_NCHAR", "K_VARCHAR2", "K_NVARCHAR2", "K_NUMBER",
  "K_BINARY_FLOAT", "K_BINARY_DOUBLE", "K_PRINT", "K_EXECUTE", "K_EXEC",
  "IDENT", "FCONST", "LITERAL", "DQCONST", "SQCONST", "ICONST",
  "SINGLE_QUOTE_NO_END", "DOUBLE_QUOTE_NO_END", "TYPECAST", "'='", "'+'",
  "'-'", "'('", "')'", "','", "';'", "$accept", "psqlplus_toplevel_stmt",
  "variable_stmt", "variable_keyword", "variable_spec", "opt_varname",
  "bind_varname", "bind_varvalue", "bind_vartype", "truncate_char",
  "print_stmt", "print_items_list", "print_items", "exec_stmt",
  "exec_keyword", "Sconst", "opt_semi", "unreserved_keyword", YY_NULLPTR
};

static const char *
yysymbol_name (yysymbol_kind_t yysymbol)
{
  return yytname[yysymbol];
}
#endif

#define YYPACT_NINF (-12)

#define yypact_value_is_default(Yyn) \
  ((Yyn) == YYPACT_NINF)

#define YYTABLE_NINF (-20)

#define yytable_value_is_error(Yyn) \
  0

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
static const yytype_int8 yypact[] =
{
      33,   -12,   -12,   112,   -12,   -12,    19,    -9,     1,    -9,
      -9,   -12,   -12,   -12,   -12,   -12,   -12,   -12,   -12,   -12,
     -12,   -12,   -12,   -12,   -12,   -12,   -12,   -12,   112,   -12,
     -12,   -12,   -12,   -12,   -12,   -12,    11,    18,   -12,   -12,
     -12,   -12,   -12,   -12,   -12,   -12,    -4,    22,    23,    24,
     -12,   -12,   -12,    62,    29,    32,    34,    35,    37,   -12,
     -12,   -12,   -12,   -12,   -12,   -12,   -12,    14,    21,   -12,
     -12,   -12,    87,    15,    30,    28,    31,   -12,   -12,   -12,
     -12,   -12,   -12,   -12,    57,    58,   -12,   -12,    82,    83,
     -12,   -12,   -12,   -12,   -12,   -12
};

/* YYDEFACT[STATE-NUM] -- Default reduction number in state STATE-NUM.
   Performed when YYTABLE does not specify something else to do.  Zero
   means the default is an error.  */
static const yytype_int8 yydefact[] =
{
       0,     8,     7,    52,    61,    62,     0,    66,    21,    66,
      66,    60,    77,    79,    70,    69,    73,    78,    75,    74,
      68,    67,    76,    72,    71,    56,    58,    59,    53,    54,
      57,     1,    65,     2,    22,     5,     0,    20,    23,     3,
       4,    55,    49,    50,    51,     6,    34,    38,    40,    44,
      46,    47,    48,    11,    14,     0,     0,     0,     0,    26,
      29,    25,    64,    63,    32,    12,    13,     0,     0,    10,
      24,    33,    16,     0,     0,     0,     0,    27,    30,    28,
      31,    17,    18,    15,     0,     0,    35,    39,     0,     0,
      41,    45,    36,    37,    42,    43
};

/* YYPGOTO[NTERM-NUM].  */
static const yytype_int8 yypgoto[] =
{
     -12,   -12,   -12,   -12,   -12,   -12,   -12,   -11,   -12,   -12,
     -12,   -12,   101,   -12,   -12,   -12,    -7,    -8
};

/* YYDEFGOTO[NTERM-NUM].  */
static const yytype_int8 yydefgoto[] =
{
       0,     6,     7,     8,    35,    36,    37,    69,    54,    45,
       9,    28,    29,    10,    11,    70,    33,    30
};

/* YYTABLE[YYPACT[STATE-NUM]] -- What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule whose
   number is the opposite.  If YYTABLE_NINF, syntax error.  */
static const yytype_int8 yytable[] =
{
      38,   -19,    39,    40,    12,    13,    14,    15,    16,    17,
      18,    19,    20,    21,    22,    23,    24,    34,    -9,    31,
      84,    85,    32,    46,    55,    47,    48,    49,    50,    51,
      52,    77,   -19,    88,    89,    78,     1,     2,    79,    42,
      43,    44,    80,    53,    86,    71,     3,     4,     5,    -9,
      56,    57,    58,    73,    72,    74,    75,    90,    76,    87,
      91,    83,     0,     0,    71,    12,    13,    14,    15,    16,
      17,    18,    19,    20,    21,    22,    23,    24,    59,    60,
      61,    62,    63,    64,    65,    66,    92,    93,    67,    68,
      12,    13,    14,    15,    16,    17,    18,    19,    20,    21,
      22,    23,    24,    59,    60,    61,    62,    63,    64,    81,
      82,    94,    95,    67,    68,    12,    13,    14,    15,    16,
      17,    18,    19,    20,    21,    22,    23,    24,    25,    41,
       0,    26,    27
};

static const yytype_int8 yycheck[] =
{
       8,     0,     9,    10,     3,     4,     5,     6,     7,     8,
       9,    10,    11,    12,    13,    14,    15,    16,     0,     0,
       5,     6,    31,     5,    28,     7,     8,     9,    10,    11,
      12,    17,    31,     5,     6,    21,     3,     4,    17,    28,
      29,    30,    21,    25,    29,    53,    13,    14,    15,    31,
      28,    28,    28,    21,    25,    21,    21,    29,    21,    29,
      29,    72,    -1,    -1,    72,     3,     4,     5,     6,     7,
       8,     9,    10,    11,    12,    13,    14,    15,    16,    17,
      18,    19,    20,    21,    22,    23,    29,    29,    26,    27,
       3,     4,     5,     6,     7,     8,     9,    10,    11,    12,
      13,    14,    15,    16,    17,    18,    19,    20,    21,    22,
      23,    29,    29,    26,    27,     3,     4,     5,     6,     7,
       8,     9,    10,    11,    12,    13,    14,    15,    16,    28,
      -1,    19,    20
};

/* YYSTOS[STATE-NUM] -- The symbol kind of the accessing symbol of
   state STATE-NUM.  */
static const yytype_int8 yystos[] =
{
       0,     3,     4,    13,    14,    15,    33,    34,    35,    42,
      45,    46,     3,     4,     5,     6,     7,     8,     9,    10,
      11,    12,    13,    14,    15,    16,    19,    20,    43,    44,
      49,     0,    31,    48,    16,    36,    37,    38,    49,    48,
      48,    44,    28,    29,    30,    41,     5,     7,     8,     9,
      10,    11,    12,    25,    40,    28,    28,    28,    28,    16,
      17,    18,    19,    20,    21,    22,    23,    26,    27,    39,
      47,    49,    25,    21,    21,    21,    21,    17,    21,    17,
      21,    22,    23,    39,     5,     6,    29,    29,     5,     6,
      29,    29,    29,    29,    29,    29
};

/* YYR1[RULE-NUM] -- Symbol kind of the left-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr1[] =
{
       0,    32,    33,    33,    33,    34,    34,    35,    35,    36,
      36,    36,    36,    36,    36,    36,    36,    36,    36,    36,
      37,    37,    38,    38,    39,    39,    39,    39,    39,    39,
      39,    39,    39,    39,    40,    40,    40,    40,    40,    40,
      40,    40,    40,    40,    40,    40,    40,    40,    40,    41,
      41,    41,    42,    42,    43,    43,    44,    44,    44,    44,
      45,    46,    46,    47,    47,    48,    48,    49,    49,    49,
      49,    49,    49,    49,    49,    49,    49,    49,    49,    49
};

/* YYR2[RULE-NUM] -- Number of symbols on the right-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr2[] =
{
       0,     2,     2,     2,     2,     2,     3,     1,     1,     1,
       3,     2,     3,     3,     2,     4,     3,     4,     4,     0,
       1,     0,     1,     1,     1,     1,     1,     2,     2,     1,
       2,     2,     1,     1,     1,     4,     5,     5,     1,     4,
       1,     4,     5,     5,     1,     4,     1,     1,     1,     1,
       1,     1,     1,     2,     1,     2,     1,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     0,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     1,     1,     1,     1
};


enum { YYENOMEM = -2 };

#define yyerrok         (yyerrstatus = 0)
#define yyclearin       (yychar = YYEMPTY)

#define YYACCEPT        goto yyacceptlab
#define YYABORT         goto yyabortlab
#define YYERROR         goto yyerrorlab
#define YYNOMEM         goto yyexhaustedlab


#define YYRECOVERING()  (!!yyerrstatus)

#define YYBACKUP(Token, Value)                                    \
  do                                                              \
    if (yychar == YYEMPTY)                                        \
      {                                                           \
        yychar = (Token);                                         \
        yylval = (Value);                                         \
        YYPOPSTACK (yylen);                                       \
        yystate = *yyssp;                                         \
        goto yybackup;                                            \
      }                                                           \
    else                                                          \
      {                                                           \
        yyerror (yyscanner, YY_("syntax error: cannot back up")); \
        YYERROR;                                                  \
      }                                                           \
  while (0)

/* Backward compatibility with an undocumented macro.
   Use YYerror or YYUNDEF. */
#define YYERRCODE YYUNDEF


/* Enable debugging if requested.  */
#if YYDEBUG

# ifndef YYFPRINTF
#  include <stdio.h> /* INFRINGES ON USER NAME SPACE */
#  define YYFPRINTF fprintf
# endif

# define YYDPRINTF(Args)                        \
do {                                            \
  if (yydebug)                                  \
    YYFPRINTF Args;                             \
} while (0)




# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)                    \
do {                                                                      \
  if (yydebug)                                                            \
    {                                                                     \
      YYFPRINTF (stderr, "%s ", Title);                                   \
      yy_symbol_print (stderr,                                            \
                  Kind, Value, yyscanner); \
      YYFPRINTF (stderr, "\n");                                           \
    }                                                                     \
} while (0)


/*-----------------------------------.
| Print this symbol's value on YYO.  |
`-----------------------------------*/

static void
yy_symbol_value_print (FILE *yyo,
                       yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep, yyscan_t yyscanner)
{
  FILE *yyoutput = yyo;
  YY_USE (yyoutput);
  YY_USE (yyscanner);
  if (!yyvaluep)
    return;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}


/*---------------------------.
| Print this symbol on YYO.  |
`---------------------------*/

static void
yy_symbol_print (FILE *yyo,
                 yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep, yyscan_t yyscanner)
{
  YYFPRINTF (yyo, "%s %s (",
             yykind < YYNTOKENS ? "token" : "nterm", yysymbol_name (yykind));

  yy_symbol_value_print (yyo, yykind, yyvaluep, yyscanner);
  YYFPRINTF (yyo, ")");
}

/*------------------------------------------------------------------.
| yy_stack_print -- Print the state stack from its BOTTOM up to its |
| TOP (included).                                                   |
`------------------------------------------------------------------*/

static void
yy_stack_print (yy_state_t *yybottom, yy_state_t *yytop)
{
  YYFPRINTF (stderr, "Stack now");
  for (; yybottom <= yytop; yybottom++)
    {
      int yybot = *yybottom;
      YYFPRINTF (stderr, " %d", yybot);
    }
  YYFPRINTF (stderr, "\n");
}

# define YY_STACK_PRINT(Bottom, Top)                            \
do {                                                            \
  if (yydebug)                                                  \
    yy_stack_print ((Bottom), (Top));                           \
} while (0)


/*------------------------------------------------.
| Report that the YYRULE is going to be reduced.  |
`------------------------------------------------*/

static void
yy_reduce_print (yy_state_t *yyssp, YYSTYPE *yyvsp,
                 int yyrule, yyscan_t yyscanner)
{
  int yylno = yyrline[yyrule];
  int yynrhs = yyr2[yyrule];
  int yyi;
  YYFPRINTF (stderr, "Reducing stack by rule %d (line %d):\n",
             yyrule - 1, yylno);
  /* The symbols being reduced.  */
  for (yyi = 0; yyi < yynrhs; yyi++)
    {
      YYFPRINTF (stderr, "   $%d = ", yyi + 1);
      yy_symbol_print (stderr,
                       YY_ACCESSING_SYMBOL (+yyssp[yyi + 1 - yynrhs]),
                       &yyvsp[(yyi + 1) - (yynrhs)], yyscanner);
      YYFPRINTF (stderr, "\n");
    }
}

# define YY_REDUCE_PRINT(Rule)          \
do {                                    \
  if (yydebug)                          \
    yy_reduce_print (yyssp, yyvsp, Rule, yyscanner); \
} while (0)

/* Nonzero means print parse trace.  It is left uninitialized so that
   multiple parsers can coexist.  */
int yydebug;
#else /* !YYDEBUG */
# define YYDPRINTF(Args) ((void) 0)
# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)
# define YY_STACK_PRINT(Bottom, Top)
# define YY_REDUCE_PRINT(Rule)
#endif /* !YYDEBUG */


/* YYINITDEPTH -- initial size of the parser's stacks.  */
#ifndef YYINITDEPTH
# define YYINITDEPTH 200
#endif

/* YYMAXDEPTH -- maximum size the stacks can grow to (effective only
   if the built-in stack extension method is used).

   Do not make this value too large; the results are undefined if
   YYSTACK_ALLOC_MAXIMUM < YYSTACK_BYTES (YYMAXDEPTH)
   evaluated with infinite-precision integer arithmetic.  */

#ifndef YYMAXDEPTH
# define YYMAXDEPTH 10000
#endif






/*-----------------------------------------------.
| Release the memory associated to this symbol.  |
`-----------------------------------------------*/

static void
yydestruct (const char *yymsg,
            yysymbol_kind_t yykind, YYSTYPE *yyvaluep, yyscan_t yyscanner)
{
  YY_USE (yyvaluep);
  YY_USE (yyscanner);
  if (!yymsg)
    yymsg = "Deleting";
  YY_SYMBOL_PRINT (yymsg, yykind, yyvaluep, yylocationp);

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}






/*----------.
| yyparse.  |
`----------*/

int
yyparse (yyscan_t yyscanner)
{
/* Lookahead token kind.  */
int yychar;


/* The semantic value of the lookahead symbol.  */
/* Default value used for initialization, for pacifying older GCCs
   or non-GCC compilers.  */
YY_INITIAL_VALUE (static YYSTYPE yyval_default;)
YYSTYPE yylval YY_INITIAL_VALUE (= yyval_default);

    /* Number of syntax errors so far.  */
    int yynerrs = 0;

    yy_state_fast_t yystate = 0;
    /* Number of tokens to shift before error messages enabled.  */
    int yyerrstatus = 0;

    /* Refer to the stacks through separate pointers, to allow yyoverflow
       to reallocate them elsewhere.  */

    /* Their size.  */
    YYPTRDIFF_T yystacksize = YYINITDEPTH;

    /* The state stack: array, bottom, top.  */
    yy_state_t yyssa[YYINITDEPTH];
    yy_state_t *yyss = yyssa;
    yy_state_t *yyssp = yyss;

    /* The semantic value stack: array, bottom, top.  */
    YYSTYPE yyvsa[YYINITDEPTH];
    YYSTYPE *yyvs = yyvsa;
    YYSTYPE *yyvsp = yyvs;

  int yyn;
  /* The return value of yyparse.  */
  int yyresult;
  /* Lookahead symbol kind.  */
  yysymbol_kind_t yytoken = YYSYMBOL_YYEMPTY;
  /* The variables used to return semantic value and location from the
     action routines.  */
  YYSTYPE yyval;



#define YYPOPSTACK(N)   (yyvsp -= (N), yyssp -= (N))

  /* The number of symbols on the RHS of the reduced rule.
     Keep to zero when no symbol should be popped.  */
  int yylen = 0;

  YYDPRINTF ((stderr, "Starting parse\n"));

  yychar = YYEMPTY; /* Cause a token to be read.  */

  goto yysetstate;


/*------------------------------------------------------------.
| yynewstate -- push a new state, which is found in yystate.  |
`------------------------------------------------------------*/
yynewstate:
  /* In all cases, when you get here, the value and location stacks
     have just been pushed.  So pushing a state here evens the stacks.  */
  yyssp++;


/*--------------------------------------------------------------------.
| yysetstate -- set current state (the top of the stack) to yystate.  |
`--------------------------------------------------------------------*/
yysetstate:
  YYDPRINTF ((stderr, "Entering state %d\n", yystate));
  YY_ASSERT (0 <= yystate && yystate < YYNSTATES);
  YY_IGNORE_USELESS_CAST_BEGIN
  *yyssp = YY_CAST (yy_state_t, yystate);
  YY_IGNORE_USELESS_CAST_END
  YY_STACK_PRINT (yyss, yyssp);

  if (yyss + yystacksize - 1 <= yyssp)
#if !defined yyoverflow && !defined YYSTACK_RELOCATE
    YYNOMEM;
#else
    {
      /* Get the current used size of the three stacks, in elements.  */
      YYPTRDIFF_T yysize = yyssp - yyss + 1;

# if defined yyoverflow
      {
        /* Give user a chance to reallocate the stack.  Use copies of
           these so that the &'s don't force the real ones into
           memory.  */
        yy_state_t *yyss1 = yyss;
        YYSTYPE *yyvs1 = yyvs;

        /* Each stack pointer address is followed by the size of the
           data in use in that stack, in bytes.  This used to be a
           conditional around just the two extra args, but that might
           be undefined if yyoverflow is a macro.  */
        yyoverflow (YY_("memory exhausted"),
                    &yyss1, yysize * YYSIZEOF (*yyssp),
                    &yyvs1, yysize * YYSIZEOF (*yyvsp),
                    &yystacksize);
        yyss = yyss1;
        yyvs = yyvs1;
      }
# else /* defined YYSTACK_RELOCATE */
      /* Extend the stack our own way.  */
      if (YYMAXDEPTH <= yystacksize)
        YYNOMEM;
      yystacksize *= 2;
      if (YYMAXDEPTH < yystacksize)
        yystacksize = YYMAXDEPTH;

      {
        yy_state_t *yyss1 = yyss;
        union yyalloc *yyptr =
          YY_CAST (union yyalloc *,
                   YYSTACK_ALLOC (YY_CAST (YYSIZE_T, YYSTACK_BYTES (yystacksize))));
        if (! yyptr)
          YYNOMEM;
        YYSTACK_RELOCATE (yyss_alloc, yyss);
        YYSTACK_RELOCATE (yyvs_alloc, yyvs);
#  undef YYSTACK_RELOCATE
        if (yyss1 != yyssa)
          YYSTACK_FREE (yyss1);
      }
# endif

      yyssp = yyss + yysize - 1;
      yyvsp = yyvs + yysize - 1;

      YY_IGNORE_USELESS_CAST_BEGIN
      YYDPRINTF ((stderr, "Stack size increased to %ld\n",
                  YY_CAST (long, yystacksize)));
      YY_IGNORE_USELESS_CAST_END

      if (yyss + yystacksize - 1 <= yyssp)
        YYABORT;
    }
#endif /* !defined yyoverflow && !defined YYSTACK_RELOCATE */


  if (yystate == YYFINAL)
    YYACCEPT;

  goto yybackup;


/*-----------.
| yybackup.  |
`-----------*/
yybackup:
  /* Do appropriate processing given the current state.  Read a
     lookahead token if we need one and don't already have one.  */

  /* First try to decide what to do without reference to lookahead token.  */
  yyn = yypact[yystate];
  if (yypact_value_is_default (yyn))
    goto yydefault;

  /* Not known => get a lookahead token if don't already have one.  */

  /* YYCHAR is either empty, or end-of-input, or a valid lookahead.  */
  if (yychar == YYEMPTY)
    {
      YYDPRINTF ((stderr, "Reading a token\n"));
      yychar = yylex (&yylval, yyscanner);
    }

  if (yychar <= YYEOF)
    {
      yychar = YYEOF;
      yytoken = YYSYMBOL_YYEOF;
      YYDPRINTF ((stderr, "Now at end of input.\n"));
    }
  else if (yychar == YYerror)
    {
      /* The scanner already issued an error message, process directly
         to error recovery.  But do not keep the error token as
         lookahead, it is too special and may lead us to an endless
         loop in error recovery. */
      yychar = YYUNDEF;
      yytoken = YYSYMBOL_YYerror;
      goto yyerrlab1;
    }
  else
    {
      yytoken = YYTRANSLATE (yychar);
      YY_SYMBOL_PRINT ("Next token is", yytoken, &yylval, &yylloc);
    }

  /* If the proper action on seeing token YYTOKEN is to reduce or to
     detect an error, take that action.  */
  yyn += yytoken;
  if (yyn < 0 || YYLAST < yyn || yycheck[yyn] != yytoken)
    goto yydefault;
  yyn = yytable[yyn];
  if (yyn <= 0)
    {
      if (yytable_value_is_error (yyn))
        goto yyerrlab;
      yyn = -yyn;
      goto yyreduce;
    }

  /* Count tokens shifted since error; after three, turn off error
     status.  */
  if (yyerrstatus)
    yyerrstatus--;

  /* Shift the lookahead token.  */
  YY_SYMBOL_PRINT ("Shifting", yytoken, &yylval, &yylloc);
  yystate = yyn;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END

  /* Discard the shifted token.  */
  yychar = YYEMPTY;
  goto yynewstate;


/*-----------------------------------------------------------.
| yydefault -- do the default action for the current state.  |
`-----------------------------------------------------------*/
yydefault:
  yyn = yydefact[yystate];
  if (yyn == 0)
    goto yyerrlab;
  goto yyreduce;


/*-----------------------------.
| yyreduce -- do a reduction.  |
`-----------------------------*/
yyreduce:
  /* yyn is the number of a rule to reduce with.  */
  yylen = yyr2[yyn];

  /* If YYLEN is nonzero, implement the default value of the action:
     '$$ = $1'.

     Otherwise, the following line sets YYVAL to garbage.
     This behavior is undocumented and Bison
     users should not rely upon it.  Assigning to YYVAL
     unconditionally makes the parser a bit smaller, and it avoids a
     GCC warning that YYVAL may be used uninitialized.  */
  yyval = yyvsp[1-yylen];


  YY_REDUCE_PRINT (yyn);
  switch (yyn)
    {
  case 2: /* psqlplus_toplevel_stmt: variable_stmt opt_semi  */
#line 74 "psqlplusparse.y"
                        {
				psql_yyget_extra(yyscanner)->psqlpluscmd = (yyvsp[-1].psqlplus_cmd);
			}
#line 1230 "psqlplusparse.c"
    break;

  case 3: /* psqlplus_toplevel_stmt: print_stmt opt_semi  */
#line 78 "psqlplusparse.y"
                        {
				psql_yyget_extra(yyscanner)->psqlpluscmd = (yyvsp[-1].psqlplus_cmd);
			}
#line 1238 "psqlplusparse.c"
    break;

  case 4: /* psqlplus_toplevel_stmt: exec_stmt opt_semi  */
#line 82 "psqlplusparse.y"
                        {
				psql_yyget_extra(yyscanner)->psqlpluscmd = (yyvsp[-1].psqlplus_cmd);
			}
#line 1246 "psqlplusparse.c"
    break;

  case 5: /* variable_stmt: variable_keyword variable_spec  */
#line 92 "psqlplusparse.y"
                {
			(yyval.psqlplus_cmd) = (yyvsp[0].psqlplus_cmd);
		}
#line 1254 "psqlplusparse.c"
    break;

  case 6: /* variable_stmt: variable_keyword opt_varname truncate_char  */
#line 96 "psqlplusparse.y"
                {
			/*
			 * Oracle's unusual behavior, when encountering these characters 
			 * represented by $3, ignore these characters and the following text.
			 */
			PsqlScanState		state = psql_yyget_extra(yyscanner);
			psqlplus_cmd_var	*var = make_variable_node();

			if ((yyvsp[-1].str))
				var->var_name = (yyvsp[-1].str);

			var->list_bind_var = true;
			state->psqlpluscmd = (psqlplus_cmd *) var;
			return 0;
		}
#line 1274 "psqlplusparse.c"
    break;

  case 9: /* variable_spec: bind_varname  */
#line 120 "psqlplusparse.y"
                        {
				/* list the specified bind variables */
				psqlplus_cmd_var *var = make_variable_node();
				var->var_name = (yyvsp[0].str);
				var->list_bind_var = true;
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) var;
			}
#line 1286 "psqlplusparse.c"
    break;

  case 10: /* variable_spec: bind_varname '=' bind_varvalue  */
#line 128 "psqlplusparse.y"
                        {
				/* bind variable assignment */
				psqlplus_cmd_var *var = make_variable_node();
				var->assign_bind_var = true;
				var->var_name = (yyvsp[-2].str);
				var->init_value = (yyvsp[0].str);
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) var;
			}
#line 1299 "psqlplusparse.c"
    break;

  case 11: /* variable_spec: bind_varname '='  */
#line 137 "psqlplusparse.y"
                        {
				/* An error scenario, bind variable assignment without a value */
				psqlplus_cmd_var *var = make_variable_node();
				var->assign_bind_var = true;
				var->var_name = (yyvsp[-1].str);
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) var;
			}
#line 1311 "psqlplusparse.c"
    break;

  case 12: /* variable_spec: bind_varname '=' SINGLE_QUOTE_NO_END  */
#line 145 "psqlplusparse.y"
                        {
				/*
				 * An error scenario
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = (yyvsp[-2].str);
				var->init_value = (yyvsp[0].str);
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
#line 1329 "psqlplusparse.c"
    break;

  case 13: /* variable_spec: bind_varname '=' DOUBLE_QUOTE_NO_END  */
#line 159 "psqlplusparse.y"
                        {
				/*
				 * An error scenario
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = (yyvsp[-2].str);
				var->init_value = (yyvsp[0].str);
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
#line 1347 "psqlplusparse.c"
    break;

  case 14: /* variable_spec: bind_varname bind_vartype  */
#line 173 "psqlplusparse.y"
                        {
				/* declare a bind variable */
				psqlplus_cmd_var *var = make_variable_node();
				var->var_name = (yyvsp[-1].str);
				var->vartype = (yyvsp[0].bindvartype);
				var->list_bind_var = false;
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) var;
			}
#line 1360 "psqlplusparse.c"
    break;

  case 15: /* variable_spec: bind_varname bind_vartype '=' bind_varvalue  */
#line 182 "psqlplusparse.y"
                        {
				/* declare a bind variable with an initial value */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = (yyvsp[-3].str);
				var->vartype = (yyvsp[-2].bindvartype);
				var->init_value = (yyvsp[0].str);
				var->list_bind_var = false;
				var->initial_nonnull_value = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
#line 1377 "psqlplusparse.c"
    break;

  case 16: /* variable_spec: bind_varname bind_vartype '='  */
#line 195 "psqlplusparse.y"
                        {
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = (yyvsp[-2].str);
				var->vartype = (yyvsp[-1].bindvartype);
				var->init_value = NULL;
				var->list_bind_var = false;
				var->initial_nonnull_value = true;
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) var;
			}
#line 1391 "psqlplusparse.c"
    break;

  case 17: /* variable_spec: bind_varname bind_vartype '=' SINGLE_QUOTE_NO_END  */
#line 205 "psqlplusparse.y"
                        {
				/*
				 * An error scenario, implemented separately in 
				 * order to reduce interaction with the server.
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var *var = make_variable_node();
				var->var_name = (yyvsp[-3].str);
				var->vartype = (yyvsp[-2].bindvartype);
				var->init_value = (yyvsp[0].str);
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				var->initial_nonnull_value = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
#line 1412 "psqlplusparse.c"
    break;

  case 18: /* variable_spec: bind_varname bind_vartype '=' DOUBLE_QUOTE_NO_END  */
#line 222 "psqlplusparse.y"
                        {
				/*
				 * An error scenario, implemented separately in 
				 * order to reduce interaction with the server.
				 */
				PsqlScanState		state = psql_yyget_extra(yyscanner);
				psqlplus_cmd_var	*var = make_variable_node();
				var->var_name = (yyvsp[-3].str);
				var->vartype = (yyvsp[-2].bindvartype);
				var->init_value = (yyvsp[0].str);
				var->list_bind_var = false;
				var->miss_termination_quote = true;
				var->initial_nonnull_value = true;
				state->psqlpluscmd = (psqlplus_cmd *) var;
				return 0;
			}
#line 1433 "psqlplusparse.c"
    break;

  case 19: /* variable_spec: %empty  */
#line 239 "psqlplusparse.y"
                        {
				/* list all bind variables */
				psqlplus_cmd_var *var = make_variable_node();
				var->list_bind_var = true;
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) var;
			}
#line 1444 "psqlplusparse.c"
    break;

  case 20: /* opt_varname: bind_varname  */
#line 249 "psqlplusparse.y"
                        {  (yyval.str) = (yyvsp[0].str); }
#line 1450 "psqlplusparse.c"
    break;

  case 21: /* opt_varname: %empty  */
#line 251 "psqlplusparse.y"
                        {  (yyval.str) = NULL; }
#line 1456 "psqlplusparse.c"
    break;

  case 22: /* bind_varname: IDENT  */
#line 254 "psqlplusparse.y"
                                        { (yyval.str) = (yyvsp[0].str); }
#line 1462 "psqlplusparse.c"
    break;

  case 23: /* bind_varname: unreserved_keyword  */
#line 255 "psqlplusparse.y"
                                        { (yyval.str) = pg_strdup((yyvsp[0].keyword)); }
#line 1468 "psqlplusparse.c"
    break;

  case 24: /* bind_varvalue: Sconst  */
#line 259 "psqlplusparse.y"
                                                        { (yyval.str) = (yyvsp[0].str); }
#line 1474 "psqlplusparse.c"
    break;

  case 25: /* bind_varvalue: LITERAL  */
#line 260 "psqlplusparse.y"
                                                        { (yyval.str) = (yyvsp[0].str); }
#line 1480 "psqlplusparse.c"
    break;

  case 26: /* bind_varvalue: IDENT  */
#line 261 "psqlplusparse.y"
                                                        { (yyval.str) = (yyvsp[0].str); }
#line 1486 "psqlplusparse.c"
    break;

  case 27: /* bind_varvalue: '+' FCONST  */
#line 262 "psqlplusparse.y"
                                                { (yyval.str) = (yyvsp[0].str); }
#line 1492 "psqlplusparse.c"
    break;

  case 28: /* bind_varvalue: '-' FCONST  */
#line 263 "psqlplusparse.y"
                                                { (yyval.str) = psprintf("-%s", (yyvsp[0].str)); }
#line 1498 "psqlplusparse.c"
    break;

  case 29: /* bind_varvalue: FCONST  */
#line 264 "psqlplusparse.y"
                                                        { (yyval.str) = (yyvsp[0].str); }
#line 1504 "psqlplusparse.c"
    break;

  case 30: /* bind_varvalue: '+' ICONST  */
#line 265 "psqlplusparse.y"
                                                { (yyval.str) = psprintf("+%d", (yyvsp[0].ival)); }
#line 1510 "psqlplusparse.c"
    break;

  case 31: /* bind_varvalue: '-' ICONST  */
#line 266 "psqlplusparse.y"
                                                { (yyval.str) = psprintf("-%d", (yyvsp[0].ival)); }
#line 1516 "psqlplusparse.c"
    break;

  case 32: /* bind_varvalue: ICONST  */
#line 267 "psqlplusparse.y"
                                                        { (yyval.str) = psprintf("%d", (yyvsp[0].ival)); }
#line 1522 "psqlplusparse.c"
    break;

  case 33: /* bind_varvalue: unreserved_keyword  */
#line 268 "psqlplusparse.y"
                                        { (yyval.str) = pg_strdup((yyvsp[0].keyword)); }
#line 1528 "psqlplusparse.c"
    break;

  case 34: /* bind_vartype: K_CHAR  */
#line 280 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORACHARCHAROID, 1, (yyvsp[0].keyword));
			}
#line 1536 "psqlplusparse.c"
    break;

  case 35: /* bind_vartype: K_CHAR '(' ICONST ')'  */
#line 284 "psqlplusparse.y"
                        {
				if (pg_strcasecmp(get_guc_settings("nls_length_semantics"), "byte") == 0)
					(yyval.bindvartype) = make_bindvartype(ORACHARBYTEOID, (yyvsp[-1].ival), (yyvsp[-3].keyword));
				else
					(yyval.bindvartype) = make_bindvartype(ORACHARCHAROID, (yyvsp[-1].ival), (yyvsp[-3].keyword));
			}
#line 1547 "psqlplusparse.c"
    break;

  case 36: /* bind_vartype: K_CHAR '(' ICONST K_CHAR ')'  */
#line 291 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORACHARCHAROID, (yyvsp[-2].ival), (yyvsp[-4].keyword));
			}
#line 1555 "psqlplusparse.c"
    break;

  case 37: /* bind_vartype: K_CHAR '(' ICONST K_BYTE ')'  */
#line 295 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORACHARBYTEOID, (yyvsp[-2].ival), (yyvsp[-4].keyword));
			}
#line 1563 "psqlplusparse.c"
    break;

  case 38: /* bind_vartype: K_NCHAR  */
#line 299 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORACHARCHAROID, 1, (yyvsp[0].keyword));
			}
#line 1571 "psqlplusparse.c"
    break;

  case 39: /* bind_vartype: K_NCHAR '(' ICONST ')'  */
#line 303 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORACHARCHAROID, (yyvsp[-1].ival), (yyvsp[-3].keyword));
			}
#line 1579 "psqlplusparse.c"
    break;

  case 40: /* bind_vartype: K_VARCHAR2  */
#line 307 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORAVARCHARCHAROID, 1, (yyvsp[0].keyword));
			}
#line 1587 "psqlplusparse.c"
    break;

  case 41: /* bind_vartype: K_VARCHAR2 '(' ICONST ')'  */
#line 311 "psqlplusparse.y"
                        {
				if (pg_strcasecmp(get_guc_settings("nls_length_semantics"), "byte") == 0)
					(yyval.bindvartype) = make_bindvartype(ORAVARCHARBYTEOID, (yyvsp[-1].ival), (yyvsp[-3].keyword));
				else
					(yyval.bindvartype) = make_bindvartype(ORAVARCHARCHAROID, (yyvsp[-1].ival), (yyvsp[-3].keyword));
			}
#line 1598 "psqlplusparse.c"
    break;

  case 42: /* bind_vartype: K_VARCHAR2 '(' ICONST K_CHAR ')'  */
#line 318 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORAVARCHARCHAROID, (yyvsp[-2].ival), (yyvsp[-4].keyword));
			}
#line 1606 "psqlplusparse.c"
    break;

  case 43: /* bind_vartype: K_VARCHAR2 '(' ICONST K_BYTE ')'  */
#line 322 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORAVARCHARBYTEOID, (yyvsp[-2].ival), (yyvsp[-4].keyword));
			}
#line 1614 "psqlplusparse.c"
    break;

  case 44: /* bind_vartype: K_NVARCHAR2  */
#line 326 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORAVARCHARCHAROID, 1, (yyvsp[0].keyword));
			}
#line 1622 "psqlplusparse.c"
    break;

  case 45: /* bind_vartype: K_NVARCHAR2 '(' ICONST ')'  */
#line 330 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(ORAVARCHARCHAROID, (yyvsp[-1].ival), (yyvsp[-3].keyword));
			}
#line 1630 "psqlplusparse.c"
    break;

  case 46: /* bind_vartype: K_NUMBER  */
#line 334 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(NUMBEROID, -1, (yyvsp[0].keyword));
			}
#line 1638 "psqlplusparse.c"
    break;

  case 47: /* bind_vartype: K_BINARY_FLOAT  */
#line 338 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(BINARY_FLOATOID, -1, (yyvsp[0].keyword));
			}
#line 1646 "psqlplusparse.c"
    break;

  case 48: /* bind_vartype: K_BINARY_DOUBLE  */
#line 342 "psqlplusparse.y"
                        {
				(yyval.bindvartype) = make_bindvartype(BINARY_DOUBLEOID, -1, (yyvsp[0].keyword));
			}
#line 1654 "psqlplusparse.c"
    break;

  case 52: /* print_stmt: K_PRINT  */
#line 358 "psqlplusparse.y"
                        {
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) make_print_node();
			}
#line 1662 "psqlplusparse.c"
    break;

  case 53: /* print_stmt: K_PRINT print_items_list  */
#line 362 "psqlplusparse.y"
                        {
				psqlplus_cmd_print *n = make_print_node();
				n->print_items = (yyvsp[0].print_item_list);
				(yyval.psqlplus_cmd) = (psqlplus_cmd *) n;
			}
#line 1672 "psqlplusparse.c"
    break;

  case 54: /* print_items_list: print_items  */
#line 371 "psqlplusparse.y"
                {
			(yyval.print_item_list) = (yyvsp[0].print_item_list);
		}
#line 1680 "psqlplusparse.c"
    break;

  case 55: /* print_items_list: print_items_list print_items  */
#line 375 "psqlplusparse.y"
                {
			(yyval.print_item_list) = merge_print_list((yyvsp[-1].print_item_list), (yyvsp[0].print_item_list));
		}
#line 1688 "psqlplusparse.c"
    break;

  case 56: /* print_items: IDENT  */
#line 382 "psqlplusparse.y"
                {
			(yyval.print_item_list) = make_print_list1(make_print_item((yyvsp[0].str), true));
		}
#line 1696 "psqlplusparse.c"
    break;

  case 57: /* print_items: unreserved_keyword  */
#line 386 "psqlplusparse.y"
                {
			(yyval.print_item_list) = make_print_list1(make_print_item(pg_strdup((yyvsp[0].keyword)), true));
		}
#line 1704 "psqlplusparse.c"
    break;

  case 58: /* print_items: DQCONST  */
#line 390 "psqlplusparse.y"
                {
			/*
			 * When PRINT specifies a bind variable name,
			 * it can be surrounded by double quotes but
			 * not single quotes.
			 */
			(yyval.print_item_list) = make_print_list1(make_print_item((yyvsp[0].str), true));
		}
#line 1717 "psqlplusparse.c"
    break;

  case 59: /* print_items: SQCONST  */
#line 399 "psqlplusparse.y"
                {
			(yyval.print_item_list) = make_print_list1(make_print_item((yyvsp[0].str), false));
		}
#line 1725 "psqlplusparse.c"
    break;

  case 60: /* exec_stmt: exec_keyword  */
#line 408 "psqlplusparse.y"
                {
			PsqlScanState state = psql_yyget_extra(yyscanner);

			if (state->is_sqlplus_cmd)
			{
				psqlplus_cmd_execute *exec = make_exec_node();
				int	offset = strlen(state->scanbuf);
				exec->plisqlstmts = pg_strdup(state->scanline + offset);
				state->psqlpluscmd = (psqlplus_cmd *) exec;
				return 0;
			}
			else
			{
				return 1;
			}
		}
#line 1746 "psqlplusparse.c"
    break;

  case 63: /* Sconst: SQCONST  */
#line 437 "psqlplusparse.y"
                                { (yyval.str) = (yyvsp[0].str); }
#line 1752 "psqlplusparse.c"
    break;

  case 64: /* Sconst: DQCONST  */
#line 438 "psqlplusparse.y"
                                { (yyval.str) = (yyvsp[0].str); }
#line 1758 "psqlplusparse.c"
    break;


#line 1762 "psqlplusparse.c"

      default: break;
    }
  /* User semantic actions sometimes alter yychar, and that requires
     that yytoken be updated with the new translation.  We take the
     approach of translating immediately before every use of yytoken.
     One alternative is translating here after every semantic action,
     but that translation would be missed if the semantic action invokes
     YYABORT, YYACCEPT, or YYERROR immediately after altering yychar or
     if it invokes YYBACKUP.  In the case of YYABORT or YYACCEPT, an
     incorrect destructor might then be invoked immediately.  In the
     case of YYERROR or YYBACKUP, subsequent parser actions might lead
     to an incorrect destructor call or verbose syntax error message
     before the lookahead is translated.  */
  YY_SYMBOL_PRINT ("-> $$ =", YY_CAST (yysymbol_kind_t, yyr1[yyn]), &yyval, &yyloc);

  YYPOPSTACK (yylen);
  yylen = 0;

  *++yyvsp = yyval;

  /* Now 'shift' the result of the reduction.  Determine what state
     that goes to, based on the state we popped back to and the rule
     number reduced by.  */
  {
    const int yylhs = yyr1[yyn] - YYNTOKENS;
    const int yyi = yypgoto[yylhs] + *yyssp;
    yystate = (0 <= yyi && yyi <= YYLAST && yycheck[yyi] == *yyssp
               ? yytable[yyi]
               : yydefgoto[yylhs]);
  }

  goto yynewstate;


/*--------------------------------------.
| yyerrlab -- here on detecting error.  |
`--------------------------------------*/
yyerrlab:
  /* Make sure we have latest lookahead translation.  See comments at
     user semantic actions for why this is necessary.  */
  yytoken = yychar == YYEMPTY ? YYSYMBOL_YYEMPTY : YYTRANSLATE (yychar);
  /* If not already recovering from an error, report this error.  */
  if (!yyerrstatus)
    {
      ++yynerrs;
      yyerror (yyscanner, YY_("syntax error"));
    }

  if (yyerrstatus == 3)
    {
      /* If just tried and failed to reuse lookahead token after an
         error, discard it.  */

      if (yychar <= YYEOF)
        {
          /* Return failure if at end of input.  */
          if (yychar == YYEOF)
            YYABORT;
        }
      else
        {
          yydestruct ("Error: discarding",
                      yytoken, &yylval, yyscanner);
          yychar = YYEMPTY;
        }
    }

  /* Else will try to reuse lookahead token after shifting the error
     token.  */
  goto yyerrlab1;


/*---------------------------------------------------.
| yyerrorlab -- error raised explicitly by YYERROR.  |
`---------------------------------------------------*/
yyerrorlab:
  /* Pacify compilers when the user code never invokes YYERROR and the
     label yyerrorlab therefore never appears in user code.  */
  if (0)
    YYERROR;
  ++yynerrs;

  /* Do not reclaim the symbols of the rule whose action triggered
     this YYERROR.  */
  YYPOPSTACK (yylen);
  yylen = 0;
  YY_STACK_PRINT (yyss, yyssp);
  yystate = *yyssp;
  goto yyerrlab1;


/*-------------------------------------------------------------.
| yyerrlab1 -- common code for both syntax error and YYERROR.  |
`-------------------------------------------------------------*/
yyerrlab1:
  yyerrstatus = 3;      /* Each real token shifted decrements this.  */

  /* Pop stack until we find a state that shifts the error token.  */
  for (;;)
    {
      yyn = yypact[yystate];
      if (!yypact_value_is_default (yyn))
        {
          yyn += YYSYMBOL_YYerror;
          if (0 <= yyn && yyn <= YYLAST && yycheck[yyn] == YYSYMBOL_YYerror)
            {
              yyn = yytable[yyn];
              if (0 < yyn)
                break;
            }
        }

      /* Pop the current state because it cannot handle the error token.  */
      if (yyssp == yyss)
        YYABORT;


      yydestruct ("Error: popping",
                  YY_ACCESSING_SYMBOL (yystate), yyvsp, yyscanner);
      YYPOPSTACK (1);
      yystate = *yyssp;
      YY_STACK_PRINT (yyss, yyssp);
    }

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END


  /* Shift the error token.  */
  YY_SYMBOL_PRINT ("Shifting", YY_ACCESSING_SYMBOL (yyn), yyvsp, yylsp);

  yystate = yyn;
  goto yynewstate;


/*-------------------------------------.
| yyacceptlab -- YYACCEPT comes here.  |
`-------------------------------------*/
yyacceptlab:
  yyresult = 0;
  goto yyreturnlab;


/*-----------------------------------.
| yyabortlab -- YYABORT comes here.  |
`-----------------------------------*/
yyabortlab:
  yyresult = 1;
  goto yyreturnlab;


/*-----------------------------------------------------------.
| yyexhaustedlab -- YYNOMEM (memory exhaustion) comes here.  |
`-----------------------------------------------------------*/
yyexhaustedlab:
  yyerror (yyscanner, YY_("memory exhausted"));
  yyresult = 2;
  goto yyreturnlab;


/*----------------------------------------------------------.
| yyreturnlab -- parsing is finished, clean up and return.  |
`----------------------------------------------------------*/
yyreturnlab:
  if (yychar != YYEMPTY)
    {
      /* Make sure we have latest lookahead translation.  See comments at
         user semantic actions for why this is necessary.  */
      yytoken = YYTRANSLATE (yychar);
      yydestruct ("Cleanup: discarding lookahead",
                  yytoken, &yylval, yyscanner);
    }
  /* Do not reclaim the symbols of the rule whose action triggered
     this YYABORT or YYACCEPT.  */
  YYPOPSTACK (yylen);
  YY_STACK_PRINT (yyss, yyssp);
  while (yyssp != yyss)
    {
      yydestruct ("Cleanup: popping",
                  YY_ACCESSING_SYMBOL (+*yyssp), yyvsp, yyscanner);
      YYPOPSTACK (1);
    }
#ifndef yyoverflow
  if (yyss != yyssa)
    YYSTACK_FREE (yyss);
#endif

  return yyresult;
}

#line 462 "psqlplusparse.y"


static psqlplus_cmd_var *
make_variable_node(void)
{
	psqlplus_cmd_var *var = pg_malloc0(sizeof(psqlplus_cmd_var));
	var->cmd_type = PSQLPLUS_CMD_VARIABLE;
	var->var_name = NULL;
	var->vartype = NULL;
	var->init_value = NULL;
	var->miss_termination_quote = false;
	var->list_bind_var = false;
	var->assign_bind_var = false;
	var->initial_nonnull_value = false;
	return var;
}

static psqlplus_cmd_print *
make_print_node(void)
{
	psqlplus_cmd_print *print = pg_malloc0(sizeof(psqlplus_cmd_print));
	print->cmd_type = PSQLPLUS_CMD_PRINT;
	print->print_items = NULL;
	return print;
}

static psqlplus_cmd_execute *
make_exec_node(void)
{
	psqlplus_cmd_execute *exec = pg_malloc0(sizeof(psqlplus_cmd_execute));
	exec->cmd_type = PSQLPLUS_CMD_EXECUTE;
	exec->plisqlstmts = NULL;
	return exec;
}

static BindVarType *
make_bindvartype(int32 oid, int32 typmod, const char *typname)
{
	BindVarType *vartype;

	/*
	 * We emulate what anychar_typmodin does here, avoiding the
	 * need to send queries to the server, typmod value need to
	 * add a 4-byte header length for character datatype.
	 */
	if (oid == ORACHARCHAROID ||
		oid == ORACHARBYTEOID ||
		oid == ORAVARCHARCHAROID ||
		oid == ORAVARCHARBYTEOID)
		typmod = typmod + 4;

	vartype = pg_malloc0(sizeof(BindVarType));
	vartype->name = pg_strdup(typname);
	vartype->oid = oid;
	vartype->typmod = typmod;

	return vartype;
}


/*
 * Get the value of the specified GUC.
 */
static char *
get_guc_settings(const char *gucname)
{
	PQExpBuffer query = createPQExpBuffer();
	PGresult	*res;
	char		*val = NULL;

	appendPQExpBuffer(query, "SELECT setting from pg_settings where name = '%s';", gucname);
	res = PQexec(pset.db, query->data);

	if (PQresultStatus(res) == PGRES_TUPLES_OK &&
		PQntuples(res) == 1 &&
		!PQgetisnull(res, 0, 0))
	{		
		val = pg_strdup(PQgetvalue(res, 0, 0));
	}

	PQclear(res);
	destroyPQExpBuffer(query);

	return val;
}

static print_item *
make_print_item(char *name, bool valid)
{
	print_item *item = pg_malloc0(sizeof(print_item));

	item->bv_name = name;
	item->valid = valid;

	return item;
}

static print_list *
make_print_list1(print_item *item)
{
	print_list	*pl = pg_malloc0(sizeof(print_list));
	pl->items = (print_item **) pg_malloc0(sizeof(print_item *) * 1);
	pl->items[0] = item;
	pl->length = 1;

	return pl;
}

static print_list *
merge_print_list(print_list *list1, print_list *list2)
{
	int	newlen;
	int i;

	if (list1 == NULL)
		return list2;
	if (list2 == NULL)
		return list1;

	newlen = list1->length + list2->length;
	list1->items = (print_item **) pg_realloc(list1->items, sizeof(print_item *) * newlen);

	for (i = 0; i < list2->length; i++)
	{
		list1->items[list1->length] = list2->items[i];
		list1->length++;
	}

	return list1;
}

int
psqlplus_yylex(YYSTYPE *lvalp, yyscan_t yyscanner)
{
	return orapsql_yylex(&(lvalp->psql_yysype), yyscanner);
}

void
psqlplus_yyerror(yyscan_t yyscanner, const char *message)
{
	/* do nothing */
}

/* yylex and the yylval macro, which flex will have its own definition */
#undef yylval
#undef yylex

