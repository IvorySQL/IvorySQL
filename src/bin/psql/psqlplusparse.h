/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison interface for Yacc-like parsers in C

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

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

#ifndef YY_PSQLPLUS_YY_PSQLPLUSPARSE_H_INCLUDED
# define YY_PSQLPLUS_YY_PSQLPLUSPARSE_H_INCLUDED
/* Debug traces.  */
#ifndef YYDEBUG
# define YYDEBUG 0
#endif
#if YYDEBUG
extern int psqlplus_yydebug;
#endif

/* Token kinds.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
    YYEMPTY = -2,
    YYEOF = 0,                     /* "end of file"  */
    YYerror = 256,                 /* error  */
    YYUNDEF = 257,                 /* "invalid token"  */
    K_VAR = 258,                   /* K_VAR  */
    K_VARIABLE = 259,              /* K_VARIABLE  */
    K_CHAR = 260,                  /* K_CHAR  */
    K_BYTE = 261,                  /* K_BYTE  */
    K_NCHAR = 262,                 /* K_NCHAR  */
    K_VARCHAR2 = 263,              /* K_VARCHAR2  */
    K_NVARCHAR2 = 264,             /* K_NVARCHAR2  */
    K_NUMBER = 265,                /* K_NUMBER  */
    K_BINARY_FLOAT = 266,          /* K_BINARY_FLOAT  */
    K_BINARY_DOUBLE = 267,         /* K_BINARY_DOUBLE  */
    K_PRINT = 268,                 /* K_PRINT  */
    K_EXECUTE = 269,               /* K_EXECUTE  */
    K_EXEC = 270,                  /* K_EXEC  */
    IDENT = 271,                   /* IDENT  */
    FCONST = 272,                  /* FCONST  */
    LITERAL = 273,                 /* LITERAL  */
    DQCONST = 274,                 /* DQCONST  */
    SQCONST = 275,                 /* SQCONST  */
    ICONST = 276,                  /* ICONST  */
    SINGLE_QUOTE_NO_END = 277,     /* SINGLE_QUOTE_NO_END  */
    DOUBLE_QUOTE_NO_END = 278,     /* DOUBLE_QUOTE_NO_END  */
    TYPECAST = 279                 /* TYPECAST  */
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
#line 45 "psqlplusparse.y"

	psql_YYSTYPE		psql_yysype;
	int					ival;
	char				*str;
	const char			*keyword;
	psqlplus_cmd		*psqlplus_cmd;
	BindVarType			*bindvartype;
	print_list			*print_item_list;

#line 98 "psqlplusparse.h"

};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif




int psqlplus_yyparse (yyscan_t yyscanner);


#endif /* !YY_PSQLPLUS_YY_PSQLPLUSPARSE_H_INCLUDED  */
