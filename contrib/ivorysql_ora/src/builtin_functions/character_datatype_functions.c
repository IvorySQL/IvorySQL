/*-------------------------------------------------------------------------
 *
 * character_datatype_functions.c
 *
 * This file contains the implementation of Oracle's
 * character data type related built-in functions.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_functions/character_datatype_functions.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"

#include "access/detoast.h"
#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "regex/regex.h"
#include "utils/builtins.h"
#include "utils/numeric.h"


#include "../include/common_datatypes.h"

PG_FUNCTION_INFO_V1(oracharlen);
PG_FUNCTION_INFO_V1(oracharoctetlen);
PG_FUNCTION_INFO_V1(oravarcharlen);
PG_FUNCTION_INFO_V1(oravarcharoctetlen);
PG_FUNCTION_INFO_V1(rtrim1);
PG_FUNCTION_INFO_V1(rtrim2);
PG_FUNCTION_INFO_V1(ltrim1);
PG_FUNCTION_INFO_V1(ltrim2);
PG_FUNCTION_INFO_V1(trim1);
PG_FUNCTION_INFO_V1(trim2);
PG_FUNCTION_INFO_V1(ora_regexp_replace);
PG_FUNCTION_INFO_V1(ora_regexp_substr);
PG_FUNCTION_INFO_V1(ora_regexp_instr);
PG_FUNCTION_INFO_V1(ora_regexp_like);
PG_FUNCTION_INFO_V1(ora_regexp_like_no_flags);
PG_FUNCTION_INFO_V1(ora_regexp_count);
PG_FUNCTION_INFO_V1(ora_substrb_no_length);
PG_FUNCTION_INFO_V1(ora_substrb);
PG_FUNCTION_INFO_V1(ora_replace);
PG_FUNCTION_INFO_V1(ora_instrb);
PG_FUNCTION_INFO_V1(ora_asciistr);
PG_FUNCTION_INFO_V1(ora_to_multi_byte);
PG_FUNCTION_INFO_V1(ora_to_single_byte);

#define PG_STR_GET_TEXT(str_) \
	DatumGetTextP(DirectFunctionCall1(textin, CStringGetDatum(str_)))

typedef struct
{
	bool		 use_wchar;		/* T if multibyte encoding */
	char		*str1;			/* use these if not use_wchar */
	char		*str2;			/* note: these point to original texts */
	pg_wchar	*wstr1;			/* use these if use_wchar */
	pg_wchar	*wstr2;			/* note: these are palloc'd */
	int			 len1;			/* string lengths in logical characters */
	int			 len2;
	/* Skip table for Boyer-Moore-Horspool search algorithm: */
	int			 skiptablemask;	/* mask for ANDing with skiptable subscripts */
	int			 skiptable[256]; /* skip distance for given mismatched char */
} TextPositionState;

static text *text_substring_byte(Datum str, int32 start, int32 length, bool length_not_specified);
static void text_position_setup(text *t1, text *t2, TextPositionState *state, bool isbyte);
static void text_position_cleanup(TextPositionState *state);
static int	text_position_next(int start_pos, TextPositionState *state);
static int text_instring(text *str, text *search_str, int32 position, int32 occurrence, bool isByte);
static int	text_position_prev(int start_pos, TextPositionState *state);
static void appendStringInfoText(StringInfo str, const text *t);
static int getindex(const char **map, char *mbchar, int mblen);

/*
 * length/lengthb function for 'oracharchar' and 'oracharbyte' type.
 */
Datum
oracharlen(PG_FUNCTION_ARGS)
{
	BpChar	   *arg = PG_GETARG_BPCHAR_PP(0);
	int			len;

	len = VARSIZE_ANY_EXHDR(arg);

	/* in multibyte encoding, convert to number of characters */
	if (pg_database_encoding_max_length() != 1)
		len = pg_mbstrlen_with_len(VARDATA_ANY(arg), len);

	PG_RETURN_INT32(len);
}

Datum
oracharoctetlen(PG_FUNCTION_ARGS)
{
	Datum		arg = PG_GETARG_DATUM(0);

	/* We need not detoast the input at all */
	PG_RETURN_INT32(toast_raw_datum_size(arg) - VARHDRSZ);
}

/*
 * length/lengthb function for 'oravarcharchar' and 'oravarcharbyte' type.
 */
Datum
oravarcharlen(PG_FUNCTION_ARGS)
{
	Datum	   str = PG_GETARG_DATUM(0);

	/* fastpath when max encoding length is one */
	if (pg_database_encoding_max_length() == 1)
		PG_RETURN_INT32(toast_raw_datum_size(str) - VARHDRSZ);
	else
	{
		VarChar	   *t = DatumGetVarCharPP(str);

		PG_RETURN_INT32(pg_mbstrlen_with_len(VARDATA_ANY(t),
									 VARSIZE_ANY_EXHDR(t)));
	}
}

Datum
oravarcharoctetlen(PG_FUNCTION_ARGS)
{
	Datum		str = PG_GETARG_DATUM(0);

	/* We need not detoast the input at all */
	PG_RETURN_INT32(toast_raw_datum_size(str) - VARHDRSZ);
}

Datum
rtrim1(PG_FUNCTION_ARGS)
{
	VarChar	*string = PG_GETARG_VARCHAR_P(0);
	VarChar *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					" ", 1,
					false, true);

	PG_RETURN_VARCHAR_P(ret);
}

Datum
rtrim2(PG_FUNCTION_ARGS)
{
	VarChar	*string = PG_GETARG_VARCHAR_P(0);
	VarChar	*set = PG_GETARG_VARCHAR_P(1);
	VarChar *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					VARDATA_ANY(set), VARSIZE_ANY_EXHDR(set),
					false, true);

	PG_RETURN_VARCHAR_P(ret);
}

Datum
ltrim2(PG_FUNCTION_ARGS)
{
	VarChar	   *string = PG_GETARG_VARCHAR_P(0);
	VarChar	   *set = PG_GETARG_VARCHAR_P(1);
	VarChar	   *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					VARDATA_ANY(set), VARSIZE_ANY_EXHDR(set),
					true, false);

	PG_RETURN_VARCHAR_P(ret);
}

Datum
ltrim1(PG_FUNCTION_ARGS)
{
	VarChar	   *string = PG_GETARG_VARCHAR_P(0);
	VarChar	   *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					" ", 1,
					true, false);

	PG_RETURN_VARCHAR_P(ret);
}

Datum
trim2(PG_FUNCTION_ARGS)
{
	VarChar	   *string = PG_GETARG_VARCHAR_P(0);
	VarChar	   *set = PG_GETARG_VARCHAR_P(1);
	VarChar	   *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					VARDATA_ANY(set), VARSIZE_ANY_EXHDR(set),
					true, true);

	PG_RETURN_VARCHAR_P(ret);
}

Datum
trim1(PG_FUNCTION_ARGS)
{
	VarChar	   *string = PG_GETARG_VARCHAR_P(0);
	VarChar	   *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					" ", 1,
					true, true);

	PG_RETURN_VARCHAR_P(ret);
}

#define MATCHPARAM(ch) (ch == 'i' || ch == 'c' || ch == 'n' || ch == 'm' || ch == 'x')

/*
 * regexp_replace
 * letting you search a string for a regular expression pattern
 * By default, the function returns source_char with every occurrence of the regular
 * expression pattern replaced with replace_string.
 * The string returned is in the same character set as source_char.
 */
Datum
ora_regexp_replace(PG_FUNCTION_ARGS)
{
	text	   *src_text = NULL;       /* source_char */
	text	   *pattern_arg = NULL;    /* pattern */
	text	   *replace_str = NULL;    /* replace_string */
	int         start_posn = 1;        /* position */
	int         occur_posn = 0;        /* occurrence */
	text       *match_para = NULL;     /* match_parameter */
	char       *match_pa_to_str = NULL;
	text       *tem = NULL;
	regex_t    *re;
	pg_re_flags flags;

	/*
	 * When there is only one parameter, error processing is performed
	 */
	if (PG_NARGS() == 1)
		ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("not enough arguments for function")));
	else if (PG_NARGS() > 1 && !PG_ARGISNULL(0))
		src_text = PG_GETARG_TEXT_PP(0);

	/*
	 * Returns null if the argument is greater than or
	 * equal to 2 and the first argument(Source string) is empty
	 */
	if (PG_NARGS() >= 2)
	{
		if(PG_ARGISNULL(0))
			PG_RETURN_NULL();

		/*
		 * Return source string when the pattern_arg is empty
		 */
		if(PG_ARGISNULL(1))
			PG_RETURN_TEXT_P(PG_GETARG_TEXT_PP(0));
		else
			pattern_arg = PG_GETARG_TEXT_PP(1);	
	}

	if (PG_NARGS() >= 3 && !PG_ARGISNULL(2))
		replace_str = PG_GETARG_TEXT_PP(2);

	if (PG_NARGS() >= 4 )
	{
		if(!PG_ARGISNULL(3))
		{
			start_posn = PG_GETARG_INT32(3);
			if(start_posn <= 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",start_posn)));
		}
		/*
		 * the fourth parameter is empty
		 * return empty
		 */
		else
			PG_RETURN_NULL();
	}

	if (PG_NARGS() >= 5)
	{
		if(!PG_ARGISNULL(4))
		{
			occur_posn = PG_GETARG_INT32(4);
			if(occur_posn < 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",occur_posn)));
		}
		/*
		 * the fifth parameter is empty
		 * return empty
		 */
		else
			PG_RETURN_NULL();
	}

	if (PG_NARGS() >= 6 && !PG_ARGISNULL(5))
	{
		match_para = PG_GETARG_TEXT_PP(5);
		match_pa_to_str = text_to_cstring(match_para);
		for (; *match_pa_to_str != '\0'; match_pa_to_str++)
		{
			if (!MATCHPARAM(*match_pa_to_str))
				ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("illegal argument for function")));
		}
	}

	if (PG_NARGS() > 6 )
		ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("too many arguments for function")));

	ora_parse_re_flags(&flags, match_para);
	re = ora_re_compile_and_cache(pattern_arg, flags.cflags, PG_GET_COLLATION());
	tem = ora_replace_text_regexp(src_text, re, replace_str, start_posn, occur_posn);
	PG_RETURN_TEXT_P(tem);
}

/*
 * REGEXP_SUBSTR extends the functionality of the SUBSTR function by letting you search a string
 * for a regular expression pattern. It is also similar to REGEXP_INSTR, but instead of returning
 * the position of the substring, it returns the substring itself. This function is useful if you
 * need the contents of a match string but not its position in the source string.
 * The function returns the string as VARCHAR2 or CLOB data in the same character
 * set as source_char.
 */
Datum
ora_regexp_substr(PG_FUNCTION_ARGS)
{
	text	   *src_text = NULL;       /* source_char */
	text	   *pattern_arg = NULL;    /* pattern */
	int         start_posn = 1;        /* position */
	int  	    occur_posn = 1;        /* occurrence */
	text       *match_para = NULL;     /* match_parameter */
	int	    	subexpr_pos = 0;	   /* subexpr for pattern */
	char 	   *match_pa_to_str = NULL;
	bool	   find_subpattern = false;
	Datum      substr;

	/*
	 * When there is only one parameter, error processing is performed
	 */
	if (PG_NARGS() == 1)
		ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("not enough arguments for function")));
	else if (PG_NARGS() > 1 && !PG_ARGISNULL(0))
		src_text = PG_GETARG_TEXT_PP(0);

	/*
	 * Returns null if the argument is greater than or
	 * equal to 2 and the first argument(Source string) is empty
	 */
	if (PG_NARGS() >= 2)
	{
		if(PG_ARGISNULL(0) || PG_ARGISNULL(1))
			PG_RETURN_NULL();
		else
			pattern_arg = PG_GETARG_TEXT_PP(1);
	}

	if (PG_NARGS() >= 3 )
	{
		if(!PG_ARGISNULL(2))
		{
			start_posn = PG_GETARG_INT32(2);
			if(start_posn <= 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",start_posn)));
		}
		/*
		 * the third parameter is empty
		 * return empty
		 */
		else
			PG_RETURN_NULL();
	}

	if (PG_NARGS() >= 4)
	{
		if(!PG_ARGISNULL(3))
		{
			occur_posn = PG_GETARG_INT32(3);
			if(occur_posn <= 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",occur_posn)));
		}
		/*
		 * the forth parameter is empty
		 * return empty
		 */
		else
			PG_RETURN_NULL();
	}

	if (PG_NARGS() >= 5 && !PG_ARGISNULL(4))
	{
		match_para = PG_GETARG_TEXT_PP(4);
		match_pa_to_str = text_to_cstring(match_para);
		for (; *match_pa_to_str != '\0'; match_pa_to_str++)
		{
			if (!MATCHPARAM(*match_pa_to_str))
				ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("illegal argument for function")));
		}
	}

	if (PG_NARGS() >= 6)
	{
		if (!PG_ARGISNULL(5))
		{
			subexpr_pos = PG_GETARG_INT32(5);
			if(subexpr_pos < 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range", subexpr_pos)));
			else if(subexpr_pos > 9)
				PG_RETURN_NULL();
		}
		else
			PG_RETURN_NULL();
	}

	find_subpattern = ora_substr_text_regexp(src_text, pattern_arg,
						match_para,PG_GET_COLLATION(),
						start_posn, occur_posn,
						subexpr_pos,&substr );
	if(find_subpattern == true)
		return substr;
	else
		PG_RETURN_NULL();
}

Datum
ora_regexp_instr(PG_FUNCTION_ARGS)
{
	text	*src_text = NULL;       /* source_char */
	text	*pattern_arg = NULL;    /* pattern */
	int		 start_posn = 1;        /* position */
	int		 occur_posn = 1;        /* occurrence */
	int	     ret_opt = 0;           /* return_opt*/
	text	*match_para = NULL;     /* match_parameter */
	int	     subexpr_pos = 0;	    /* subexpr for pattern */
	char	*match_pa_to_str = NULL;
	bool	 find_subpattern = false;
	Datum	 substr;

	/*
	 * When there is only one parameter, error processing is performed
	 */
	if (PG_NARGS() == 1)
		ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("not enough arguments for function")));
	else if (PG_NARGS() > 1 && !PG_ARGISNULL(0))
		src_text = PG_GETARG_TEXT_PP(0);

	/*
	 * Returns null if the argument is greater than or
	 * equal to 2 and the first argument(Source string) is empty
	 */
	if (PG_NARGS() >= 2)
	{
		if(PG_ARGISNULL(0) || PG_ARGISNULL(1))
			PG_RETURN_NULL();
		else
			pattern_arg = PG_GETARG_TEXT_PP(1);
	}

	if (PG_NARGS() >= 3)
	{
		if(!PG_ARGISNULL(2))
		{
			start_posn = PG_GETARG_INT32(2);
			if(start_posn <= 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",start_posn)));
		}
		else
			PG_RETURN_NULL(); /* if the third parameter is empty, return empty */
	}

	if (PG_NARGS() >= 4)
	{
		if(!PG_ARGISNULL(3))
		{
			occur_posn = PG_GETARG_INT32(3);
			if(occur_posn <= 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",occur_posn)));
		}
		else
			PG_RETURN_NULL(); /* if the forth parameter is empty, return empty */
	}

	if (PG_NARGS() >= 5)
	{
		if(!PG_ARGISNULL(4))
		{
			ret_opt = PG_GETARG_INT32(4);
			if(ret_opt < 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range",ret_opt)));
		}
		else
			PG_RETURN_NULL(); /* if the fifth parameter is empty, return empty */
	}

	if (PG_NARGS() >= 6 && !PG_ARGISNULL(5))
	{
		match_para = PG_GETARG_TEXT_PP(5);
		match_pa_to_str = text_to_cstring(match_para);
		for (; *match_pa_to_str != '\0'; match_pa_to_str++)
		{
			if (!MATCHPARAM(*match_pa_to_str))
				ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("illegal argument for function")));
		}
	}

	if (PG_NARGS() >= 7)
	{
		if (!PG_ARGISNULL(6))
		{
			subexpr_pos = PG_GETARG_INT32(6);
			if(subexpr_pos < 0)
				ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("argument '%d' is out of range", subexpr_pos)));
			else if (subexpr_pos >= 10)
				return PointerGetDatum(cstring_to_text("0"));
		}
		else
			PG_RETURN_NULL();
	}

	find_subpattern = ora_instr_text_regexp(src_text, pattern_arg,
						match_para,PG_GET_COLLATION(),
						start_posn, occur_posn,ret_opt,
						subexpr_pos,&substr);
	if(find_subpattern == true)
		return substr;
	else
		return PointerGetDatum(cstring_to_text("0"));
}

/*
 * ora_regexp_like()
 * if source string matched by a regular expression return true or return false;
 */
Datum
ora_regexp_like(PG_FUNCTION_ARGS)
{
	text		*s = PG_ARGISNULL(0) ? NULL :PG_GETARG_TEXT_P(0);
	text		*p = PG_ARGISNULL(1) ? NULL :PG_GETARG_TEXT_P(1);
	text		*in_flag = PG_ARGISNULL(2) ? PG_STR_GET_TEXT("") : PG_GETARG_TEXT_P(2);
	char		*in_flag_p = NULL;
	int			in_flag_len, i, out_flag;
	bool		match;
	regmatch_t	pmatch[2];

	if ((NULL == s) || (NULL == p))
	{
		PG_RETURN_BOOL(false);
	}

	in_flag_p = VARDATA(in_flag);
	in_flag_len = (VARSIZE(in_flag) - VARHDRSZ);

	/* parse flag options */
	out_flag = REG_ADVANCED;
	for (i = 0; i <in_flag_len; i++)
	{
		switch (in_flag_p[i])
		{
			case 'i':
				out_flag  |=  REG_ICASE;
				break;
			case 'n':
				out_flag |= REG_NEWLINE;
				break;
			case 'c':
				out_flag  &=  ~REG_ICASE;
				break;
			case 'x':
				out_flag |= REG_EXPANDED;
				break;
			default:
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						 errmsg("invalid option of regexp_like: %c",
						 in_flag_p[i])));
				break;
		}
	}

	/*
	 * We pass two regmatch_t structs to get info about the overall match and
	 * the match for the first parenthesized subexpression (if any). If there
	 * is a parenthesized subexpression, we return what it matched; else
	 * return what the whole regexp matched.
	 */
	match = RE_compile_and_execute(p,
								VARDATA(s),
								VARSIZE(s) - VARHDRSZ,
								out_flag,
								PG_GET_COLLATION(),
								2, pmatch);

	/* match? then return the substring matching the pattern */
	if (match)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

/*
 * ora_regexp_like_no_flag()
 * if source string matched by a regular expression return true or return false;
 * the flag defalut is PATTERN_FLAG;
 */
Datum
ora_regexp_like_no_flags(PG_FUNCTION_ARGS)
{
	text		*s = PG_ARGISNULL(0) ? NULL :PG_GETARG_TEXT_P(0);
	text		*p = PG_ARGISNULL(1) ? NULL :PG_GETARG_TEXT_P(1);
	int			out_flag;
	bool		match;
	regmatch_t	pmatch[2];

	if ((NULL == s) || (NULL == p) )
	{
		PG_RETURN_BOOL(false);
	}
	/* parse flag options */
	out_flag = REG_ADVANCED;

	/*
	 * We pass two regmatch_t structs to get info about the overall match and
	 * the match for the first parenthesized subexpression (if any). If there
	 * is a parenthesized subexpression, we return what it matched; else
	 * return what the whole regexp matched.
	 */
	match = RE_compile_and_execute(p,
								VARDATA(s),
								VARSIZE(s) - VARHDRSZ,
								out_flag,
								PG_GET_COLLATION(),
								2, pmatch);

	/* match? then return the substring matching the pattern */
	if (match)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

/********************************************************************
 * regexp_count
 *
 * Purpose:
 *	 Returning the number of times a pattern occurs
 *	 in a source string.
 ********************************************************************/
Datum
ora_regexp_count(PG_FUNCTION_ARGS)
{
	text	   *s = NULL;
	text	   *p = NULL;
	int32		position = 0;
	text	   *match_param = NULL;
	regex_t    *re;
	regmatch_t	pmatch[10];
	int			src_text_len;
	int			search_start;
	int			occurrence_cnt = 0;
	pg_wchar   *data;
	size_t		data_len;
	pg_re_flags flags;
	int			num = 0;
	bool		flag = false;
	
	if (PG_ARGISNULL(2))
		PG_RETURN_NULL();

	/* get the value of the parameters safely */
	position = DatumGetInt32(DirectFunctionCall1(numeric_int4, DirectFunctionCall2(numeric_trunc, PG_GETARG_DATUM(2),Int32GetDatum(0))));
	
	/* position and occurrence must be positive integer */
	if (position <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("argument \"%d\" is out of range", position)));

	if (PG_ARGISNULL(3))
	{
		flags.cflags = REG_ADVANCED;
		flags.glob = false;	
	}
	else
	{
		char	*paramstr = NULL;
		match_param = PG_GETARG_TEXT_PP(3);
		paramstr = text_to_cstring(match_param);
		if (paramstr && paramstr[0] != '\0')
		{
			if (paramstr[0] != 'x' && paramstr[0] != 'm' && paramstr[0] != 'i' && 
				paramstr[0] != 'c' && paramstr[0] != 'n' && paramstr[0] != 'g')
					ereport(ERROR,
							 (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("the 4th argument is illegal parameter for function. the parameter can be one of x, m, i, c, n.")));
		}
		ora_parse_re_flags(&flags, match_param);
	}

	if (PG_ARGISNULL(0) || 
		PG_ARGISNULL(1))
		PG_RETURN_NULL();

	s = PG_GETARG_TEXT_PP(0);
	p = PG_GETARG_TEXT_PP(1);
	src_text_len = VARSIZE_ANY_EXHDR(s);
	
	if (PG_NARGS() == 4)
	{
		char	*str = text_to_cstring(s);
		int 	 len = strlen(str);
		int 	 i = 0;
		if (len > 0) 
		{
			for (i = 0;i < len; i++)
			{
				if (str[i] == '\n')
					num++;
			}
			if (str[len - 1] == '\n')
				flag = true;
		}
	}
	/* Compile RE */
	re = RE_compile_and_cache(p, flags.cflags, PG_GET_COLLATION());

	/* Convert data string to wide characters. */
	data = (pg_wchar *) palloc((src_text_len + 1) * sizeof(pg_wchar));
	data_len = pg_mb2wchar_with_len(VARDATA_ANY(s), data, src_text_len);

	search_start = position - 1;
	while (search_start <= data_len)
	{
		int			regexec_result;

		CHECK_FOR_INTERRUPTS();

		regexec_result = pg_regexec(re,
									data,
									data_len,
									search_start,
									NULL,		/* no details */
									REGEXP_REPLACE_BACKREF_CNT,
									pmatch,
									0);

		if (regexec_result == REG_NOMATCH)
			break;

		if (regexec_result != REG_OKAY)
		{
			char		errMsg[100];

			CHECK_FOR_INTERRUPTS();
			pg_regerror(regexec_result, re, errMsg, sizeof(errMsg));
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_REGULAR_EXPRESSION),
					 errmsg("regular expression failed: %s", errMsg)));
		}

		/* Count the number of matches */
		occurrence_cnt++;

		/*
		 * Advance search position.  Normally we start the next search at the
		 * end of the previous match; but if the match was of zero length, we
		 * have to advance by one character, or we'd just find the same match
		 * again.
		 */
		search_start = pmatch[0].rm_eo;
		if (pmatch[0].rm_so == pmatch[0].rm_eo)
			search_start++;
	}

	if (flags.cflags == (REG_ICASE | REG_ADVANCED) || (flags.cflags == REG_ADVANCED))
	{
		if (!strncmp(p->vl_dat ,".",1))
			occurrence_cnt -= num;
	}	
	if (flags.cflags == (REG_NEWLINE | REG_ADVANCED) && !strncmp(p->vl_dat ,".",1))
		occurrence_cnt += num;
	if (flags.cflags == (REG_NEWLINE | REG_ADVANCED) && !strncmp(p->vl_dat ,"^",1))
	{
		if (num)
			occurrence_cnt = num;
	}
	if (flags.cflags ==  REG_ADVANCED && !strncmp(p->vl_dat ,"^",1) && flag)
	{
		if (num > 1)
			occurrence_cnt += 1;
	}
	pfree(data);

	PG_RETURN_INT32(occurrence_cnt);
}

/********************************************************************
 * ora_substrb
 *
 * Purpose:
 *	 Return a substring starting at the specified position in bytes.
 *
 ********************************************************************/
Datum
ora_substrb(PG_FUNCTION_ARGS)
{
	text	*res;
	int32	len;
	int32 	start = DatumGetInt32(DirectFunctionCall1(numeric_int4, PG_GETARG_DATUM(1)));
	int32	length = DatumGetInt32(DirectFunctionCall1(numeric_int4, PG_GETARG_DATUM(2)));

	res = text_substring_byte(PG_GETARG_DATUM(0), start, length, false);
	len = VARSIZE_ANY_EXHDR(res);
	
	if (len == 0)
	{
		pfree(res);
		PG_RETURN_NULL();
	}
	
	PG_RETURN_TEXT_P(res);
}

Datum
ora_substrb_no_length(PG_FUNCTION_ARGS)
{
	text	*res;
	int32	len;
	int32	start = DatumGetInt32(DirectFunctionCall1(numeric_int4, PG_GETARG_DATUM(1)));

	res = text_substring_byte(PG_GETARG_DATUM(0), start, -1, true);
	len = VARSIZE_ANY_EXHDR(res);

	if (len == 0)
	{
		pfree(res);
		PG_RETURN_NULL();
	}

	PG_RETURN_TEXT_P(res);
}

/********************************************************************
 *
 * ora_replace
 *
 * from:
 *	 text replace_text(text src_text,
 *					   text from_sub_text,
 *					   text to_sub_text)
 *
 * Purpose:
 *	 Replace all occurrences of 'from_sub_text' in 'src_text' with
 *	 'to_sub_text'.
 *
 * Modify:
 * 	1. Change the 'strict' property of the function from 'true' to
 *	   'false'.
 *	2. Returns 'src_text' if 'from_sub_text' == NULL or 'src_text' == NULL.
 *	3. If 'to_sub_text' is omitted or null, then all occurrences of 
 *	   'from_sub_text' are removed.
 *
 ********************************************************************/
Datum
ora_replace(PG_FUNCTION_ARGS)
{
	text	   *src_text = NULL;
	text	   *from_sub_text = NULL;
	text	   *to_sub_text = NULL;
	int			src_text_len;
	int			from_sub_text_len;
	TextPositionState state;
	text	   *ret_text;
	int			start_posn;
	int			curr_posn;
	int			chunk_len;
	char	   *start_ptr;
	StringInfoData str;

	/*
	 * Compatible with oracle, if arg1 or agr2 is null return 'src_text'.
	 * if arg3 is null, then all occurrences of arg2 are removed.
	 */
	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();
	else if (PG_ARGISNULL(1))
		PG_RETURN_TEXT_P(PG_GETARG_TEXT_PP(0));
	
	src_text = PG_GETARG_TEXT_PP(0);
	from_sub_text = PG_GETARG_TEXT_PP(1);
	if (!PG_ARGISNULL(2))
		to_sub_text = PG_GETARG_TEXT_PP(2);

	text_position_setup(src_text, from_sub_text, &state, false);

	/*
	 * Note: we check the converted string length, not the original, because
	 * they could be different if the input contained invalid encoding.
	 */
	src_text_len = state.len1;
	from_sub_text_len = state.len2;

	/* Return unmodified source string if empty source or pattern */
	if (src_text_len < 1 || from_sub_text_len < 1)
	{
		text_position_cleanup(&state);
		PG_RETURN_TEXT_P(src_text);
	}

	start_posn = 1;
	curr_posn = text_position_next(1, &state);

	/* When the from_sub_text is not found, there is nothing to do. */
	if (curr_posn == 0)
	{
		text_position_cleanup(&state);
		PG_RETURN_TEXT_P(src_text);
	}

	/* start_ptr points to the start_posn'th character of src_text */
	start_ptr = VARDATA_ANY(src_text);

	initStringInfo(&str);

	do
	{
		CHECK_FOR_INTERRUPTS();

		/* copy the data skipped over by last text_position_next() */
		chunk_len = charlen_to_bytelen(start_ptr, curr_posn - start_posn);
		appendBinaryStringInfo(&str, start_ptr, chunk_len);

		if (to_sub_text != NULL)
			appendStringInfoText(&str, to_sub_text);

		start_posn = curr_posn;
		start_ptr += chunk_len;
		start_posn += from_sub_text_len;
		start_ptr += charlen_to_bytelen(start_ptr, from_sub_text_len);

		curr_posn = text_position_next(start_posn, &state);
	}
	while (curr_posn > 0);

	/* copy trailing data */
	chunk_len = ((char *) src_text + VARSIZE_ANY(src_text)) - start_ptr;
	appendBinaryStringInfo(&str, start_ptr, chunk_len);

	text_position_cleanup(&state);

	ret_text = cstring_to_text_with_len(str.data, str.len);
	pfree(str.data);

	PG_RETURN_TEXT_P(ret_text);
}

/**********************************************************************
 *
 * ora_instrb --- calculates strings using bytes instead of characters
 *
 **********************************************************************/
Datum
ora_instrb(PG_FUNCTION_ARGS)
{
	text	*str = NULL;
	text	*search_str = NULL;
	int32	position = DatumGetInt32(DirectFunctionCall1(numeric_int4, DirectFunctionCall2(numeric_trunc, PG_GETARG_DATUM(2),Int32GetDatum(0))));
	int32	occurrence = DatumGetInt32(DirectFunctionCall1(numeric_int4, DirectFunctionCall2(numeric_trunc, PG_GETARG_DATUM(3),Int32GetDatum(0))));

	if (position == 0)
		PG_RETURN_INT32(0);
	
	if (occurrence <= 0)
		ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("The parameter of occurrence must be positive")));

	str = PG_GETARG_TEXT_PP(0);
	search_str = PG_GETARG_TEXT_PP(1);

	PG_RETURN_INT32(text_instring(str,
								  search_str,
								  position,
								  occurrence,
								  true));
}


/*
 * text_substring_byte -
 * Does the real work for ora_substrb().
 *
 *  The byte version of text_substring function.
 */
static text *
text_substring_byte(Datum str, int32 start, int32 length, bool length_not_specified)
{
	int32		eml = pg_database_encoding_max_length();
	int32		S = start;		/* start position */
	int32		S1;				/* adjusted start position */
	int32		L1;				/* adjusted substring length */

	if (length_not_specified == false && length < 1)
		return cstring_to_text("");	

	/* life is easy if the encoding max length is 1 */
	if (eml == 1)
	{	
		if (S < 0)
		{
			int		blen;
			blen = (int) (toast_raw_datum_size(str) - VARHDRSZ);
			S1 = S + blen + 1;

			if (S1 < 1)
				return cstring_to_text("");
		}
		else
		{
			S1 = Max(S, 1);
		}

		if (length_not_specified)	/* special case - get length to end of string */
			L1 = -1;
		else
			L1 = length;

		/*
		 * If the start position is past the end of the string, SQL99 says to
		 * return a zero-length string -- PG_GETARG_TEXT_P_SLICE() will do
		 * that for us. Convert to zero-based starting position
		 */
		return DatumGetTextPSlice(str, S1 - 1, L1);
	}
	else if (eml > 1)
	{
		/*
		 * When encoding max length is > 1, we can't get LC without
		 * detoasting, so we'll grab a conservatively large slice now and go
		 * back later to do the right thing
		 */
		int32	slice_start;
		int32	slice_size;
		int32	slice_strlen;
		text	*slice;
		int32	E1;
		char	*p;
		char	*sliceBegin;
		char	*subStrBegin;	/* real beginning position */
		char	*subStrEnd;		/* real ending position */
		bool	prefixSpace = false;	/* if attach a prefix space */
		bool	suffixSpace = false;	/* if attach a suffix space */
		int32	prefixSpaceCnt = 0;
		int32	suffixSpaceCnt = 0;
		text	*ret;

		if (S < 0)
		{
			int		blen;
			blen = VARSIZE_ANY_EXHDR(DatumGetTextPP(str));
			S1 = blen + S + 1;

			if (S1 < 1)
				return cstring_to_text("");
		}
		else
		{
			S1 = Max(S, 1);
		}

		/*
		 * We need to start at position zero because there is no way to know
		 * in advance which byte offset corresponds to the supplied start
		 * position.
		 */
		slice_start = 0;

		if (length_not_specified)		/* special case - get length to end of
										 * string */
			slice_size = L1 = -1;
		else
		{
			L1 = length;
			slice_size = S1 + L1 + eml;
		}

		/*
		 * If we're working with an untoasted source, no need to do an extra
		 * copying step.
		 */
		if (VARATT_IS_COMPRESSED(DatumGetPointer(str)) ||
			VARATT_IS_EXTERNAL(DatumGetPointer(str)))
			slice = DatumGetTextPSlice(str, slice_start, slice_size);
		else
			slice = (text *) DatumGetPointer(str);

		/* Now we can get the actual length of the slice in bytes */
		slice_strlen = VARSIZE_ANY_EXHDR(slice);

		/* see if we got back an empty string */
		if (slice_strlen == 0)
		{
			if (slice != (text *) DatumGetPointer(str))
				pfree(slice);
			return cstring_to_text("");
		}

		/*
		 * Check that the start position wasn't > slice_strlen. If so, SQL99
		 * says to return a zero-length string.
		 */
		if (S1 > slice_strlen)
		{
			if (slice != (text *) DatumGetPointer(str))
				pfree(slice);
			return cstring_to_text("");
		}

		/*
		 * Adjust L1 and E1 now that we know the slice string length. Again
		 * remember that S1 is one based, and slice_start is zero based.
		 */
		if (L1 > -1)
			E1 = Min(S1 + L1, slice_start + 1 + slice_strlen);
		else
			E1 = slice_start + 1 + slice_strlen;

		sliceBegin = subStrBegin = VARDATA_ANY(slice);
		while (subStrBegin < sliceBegin + S1 - 1)
			subStrBegin += pg_mblen(subStrBegin);

		if (subStrBegin > sliceBegin + S1 - 1)
		{
			prefixSpace = true;
			prefixSpaceCnt = subStrBegin - (sliceBegin + S1 - 1);
		}

		subStrEnd = subStrBegin;
		while (subStrEnd + pg_mblen(subStrEnd) <= sliceBegin + E1 - 1)
			subStrEnd += pg_mblen(subStrEnd);

		if (subStrEnd < sliceBegin + E1 - 1)
		{
			suffixSpace = true;
			suffixSpaceCnt = sliceBegin + E1 - 1 - subStrEnd;
		}

		if (subStrEnd == subStrBegin)
		{
			if (prefixSpace && suffixSpace)
				return cstring_to_text("  ");
			else
				return cstring_to_text(" ");
		}

		ret = (text *) palloc(VARHDRSZ + (subStrEnd - subStrBegin + prefixSpaceCnt + suffixSpaceCnt));
		SET_VARSIZE(ret, VARHDRSZ + (subStrEnd - subStrBegin + prefixSpaceCnt + suffixSpaceCnt));
		
		p = VARDATA(ret);

		/* attach prefix spaces */
		if (prefixSpace)
		{
			while(prefixSpaceCnt--)
				*p++ = ' ';
		}

		/* copy the visible characters to slice result */
		memcpy(p, subStrBegin, (subStrEnd - subStrBegin));
		p += subStrEnd - subStrBegin;

		/* attach suffix spaces */
		if (suffixSpace)
		{
			while(suffixSpaceCnt--)
				*p++ = ' ';
		}

		if (slice != (text *) DatumGetPointer(str))
			pfree(slice);

		return ret;
	}
	else
		elog(ERROR, "invalid backend encoding: encoding max length < 1");

	/* not reached: suppress compiler warning */
	return NULL;
}

/*
 * text_position_setup, text_position_next, text_position_cleanup -
 * Component steps of text_position()
 *
 * These are broken out so that a string can be efficiently searched for
 * multiple occurrences of the same pattern.  text_position_next may be
 * called multiple times with increasing values of start_pos, which is
 * the 1-based character position to start the search from. The "state"
 * variable is normally just a local variable in the caller.
 *
 * Modify:
 *  Add the boolean type parameter isbyte, if isbyte is true then processed
 *  in single byte encoding.
 */
static void
text_position_setup(text *t1, text *t2, TextPositionState *state, bool isbyte)
{
	int			len1 = VARSIZE_ANY_EXHDR(t1);
	int			len2 = VARSIZE_ANY_EXHDR(t2);

	if (pg_database_encoding_max_length() == 1 ||
		isbyte)
	{
		/* simple case - single byte encoding */
		state->use_wchar = false;
		state->str1 = VARDATA_ANY(t1);
		state->str2 = VARDATA_ANY(t2);
		state->len1 = len1;
		state->len2 = len2;
	}
	else
	{
		/* not as simple - multibyte encoding */
		pg_wchar   *p1,
				   *p2;

		p1 = (pg_wchar *) palloc((len1 + 1) * sizeof(pg_wchar));
		len1 = pg_mb2wchar_with_len(VARDATA_ANY(t1), p1, len1);
		p2 = (pg_wchar *) palloc((len2 + 1) * sizeof(pg_wchar));
		len2 = pg_mb2wchar_with_len(VARDATA_ANY(t2), p2, len2);

		state->use_wchar = true;
		state->wstr1 = p1;
		state->wstr2 = p2;
		state->len1 = len1;
		state->len2 = len2;
	}

	/*
	 * Prepare the skip table for Boyer-Moore-Horspool searching.  In these
	 * notes we use the terminology that the "haystack" is the string to be
	 * searched (t1) and the "needle" is the pattern being sought (t2).
	 *
	 * If the needle is empty or bigger than the haystack then there is no
	 * point in wasting cycles initializing the table.  We also choose not to
	 * use B-M-H for needles of length 1, since the skip table can't possibly
	 * save anything in that case.
	 */
	if (len1 >= len2 && len2 > 1)
	{
		int			searchlength = len1 - len2;
		int			skiptablemask;
		int			last;
		int			i;

		/*
		 * First we must determine how much of the skip table to use.  The
		 * declaration of TextPositionState allows up to 256 elements, but for
		 * short search problems we don't really want to have to initialize so
		 * many elements --- it would take too long in comparison to the
		 * actual search time.  So we choose a useful skip table size based on
		 * the haystack length minus the needle length.  The closer the needle
		 * length is to the haystack length the less useful skipping becomes.
		 *
		 * Note: since we use bit-masking to select table elements, the skip
		 * table size MUST be a power of 2, and so the mask must be 2^N-1.
		 */
		if (searchlength < 16)
			skiptablemask = 3;
		else if (searchlength < 64)
			skiptablemask = 7;
		else if (searchlength < 128)
			skiptablemask = 15;
		else if (searchlength < 512)
			skiptablemask = 31;
		else if (searchlength < 2048)
			skiptablemask = 63;
		else if (searchlength < 4096)
			skiptablemask = 127;
		else
			skiptablemask = 255;
		state->skiptablemask = skiptablemask;

		/*
		 * Initialize the skip table.  We set all elements to the needle
		 * length, since this is the correct skip distance for any character
		 * not found in the needle.
		 */
		for (i = 0; i <= skiptablemask; i++)
			state->skiptable[i] = len2;

		/*
		 * Now examine the needle.  For each character except the last one,
		 * set the corresponding table element to the appropriate skip
		 * distance.  Note that when two characters share the same skip table
		 * entry, the one later in the needle must determine the skip
		 * distance.
		 */
		last = len2 - 1;

		if (!state->use_wchar)
		{
			const char *str2 = state->str2;

			for (i = 0; i < last; i++)
				state->skiptable[(unsigned char) str2[i] & skiptablemask] = last - i;
		}
		else
		{
			const pg_wchar *wstr2 = state->wstr2;

			for (i = 0; i < last; i++)
				state->skiptable[wstr2[i] & skiptablemask] = last - i;
		}
	}
}

static void
text_position_cleanup(TextPositionState *state)
{
	if (state->use_wchar)
	{
		pfree(state->wstr1);
		pfree(state->wstr2);
	}
}

static int
text_position_next(int start_pos, TextPositionState *state)
{
	int			haystack_len = state->len1;
	int			needle_len = state->len2;
	int			skiptablemask = state->skiptablemask;

	Assert(start_pos > 0);		/* else caller error */

	if (needle_len <= 0)
		return start_pos;		/* result for empty pattern */

	start_pos--;				/* adjust for zero based arrays */

	/* Done if the needle can't possibly fit */
	if (haystack_len < start_pos + needle_len)
		return 0;

	if (!state->use_wchar)
	{
		/* simple case - single byte encoding */
		const char *haystack = state->str1;
		const char *needle = state->str2;
		const char *haystack_end = &haystack[haystack_len];
		const char *hptr;

		if (needle_len == 1)
		{
			/* No point in using B-M-H for a one-character needle */
			char		nchar = *needle;

			hptr = &haystack[start_pos];
			while (hptr < haystack_end)
			{
				if (*hptr == nchar)
					return hptr - haystack + 1;
				hptr++;
			}
		}
		else
		{
			const char *needle_last = &needle[needle_len - 1];

			/* Start at startpos plus the length of the needle */
			hptr = &haystack[start_pos + needle_len - 1];
			while (hptr < haystack_end)
			{
				/* Match the needle scanning *backward* */
				const char *nptr;
				const char *p;

				nptr = needle_last;
				p = hptr;
				while (*nptr == *p)
				{
					/* Matched it all?	If so, return 1-based position */
					if (nptr == needle)
						return p - haystack + 1;
					nptr--, p--;
				}

				/*
				 * No match, so use the haystack char at hptr to decide how
				 * far to advance.  If the needle had any occurrence of that
				 * character (or more precisely, one sharing the same
				 * skiptable entry) before its last character, then we advance
				 * far enough to align the last such needle character with
				 * that haystack position.  Otherwise we can advance by the
				 * whole needle length.
				 */
				hptr += state->skiptable[(unsigned char) *hptr & skiptablemask];
			}
		}
	}
	else
	{
		/* The multibyte char version. This works exactly the same way. */
		const pg_wchar *haystack = state->wstr1;
		const pg_wchar *needle = state->wstr2;
		const pg_wchar *haystack_end = &haystack[haystack_len];
		const pg_wchar *hptr;

		if (needle_len == 1)
		{
			/* No point in using B-M-H for a one-character needle */
			pg_wchar	nchar = *needle;

			hptr = &haystack[start_pos];
			while (hptr < haystack_end)
			{
				if (*hptr == nchar)
					return hptr - haystack + 1;
				hptr++;
			}
		}
		else
		{
			const pg_wchar *needle_last = &needle[needle_len - 1];

			/* Start at startpos plus the length of the needle */
			hptr = &haystack[start_pos + needle_len - 1];
			while (hptr < haystack_end)
			{
				/* Match the needle scanning *backward* */
				const pg_wchar *nptr;
				const pg_wchar *p;

				nptr = needle_last;
				p = hptr;
				while (*nptr == *p)
				{
					/* Matched it all?	If so, return 1-based position */
					if (nptr == needle)
						return p - haystack + 1;
					nptr--, p--;
				}

				/*
				 * No match, so use the haystack char at hptr to decide how
				 * far to advance.  If the needle had any occurrence of that
				 * character (or more precisely, one sharing the same
				 * skiptable entry) before its last character, then we advance
				 * far enough to align the last such needle character with
				 * that haystack position.  Otherwise we can advance by the
				 * whole needle length.
				 */
				hptr += state->skiptable[*hptr & skiptablemask];
			}
		}
	}

	return 0;	/* not found */
}

/*
 * text_instring - 
 * Does the real work for ora_instr() and ora_instrb().
 */
static int
text_instring(text *str, text *search_str, int32 position, int32 occurrence, bool isByte)
{
	int32	maxTimes;
	int32	i;
	int32	src_text_len;	/* length of src text */
	int32	sub_text_len;	/* length of search_str text */
	int32	result;
	TextPositionState	state;

	text_position_setup(str, search_str, &state, isByte);

	src_text_len = state.len1;
	sub_text_len = state.len2;

	if (src_text_len <= 0 || sub_text_len <= 0)
	{
		text_position_cleanup(&state);
		return 0;
	}

	/*
	 * If occurrence is greater than 1, then the database searches for the
	 * second occurrence beginning with the second character in the first
	 * occurrence of string. So, if position is positive, then the maxinum
	 * occurrences is:
	 *
	 *     src_text_len = src_text_len - position + 1
	 *     maxTimes = src_text_len - sub_text_len + 1
	 *
	 * But if position is negative, then Oracle counts backward from the end
	 * of string and then searches backward from the resulting position. An
	 * additional search forward from the resulting positionis performed at
	 * the result position. So maxTimes need to plus 1.
	 */
	if (position > 0)
		maxTimes = src_text_len - sub_text_len - position + 2;
	else
		maxTimes = src_text_len - Max(sub_text_len, -position) + 1;

	if (abs(position) > src_text_len || src_text_len < sub_text_len || occurrence > maxTimes)
	{
		text_position_cleanup(&state);
		return 0;
	}
	
	if (position > 0)
	{
		/*searching from begin with the specific times */
		result = position - 1;
		
		for (i = 0; i < occurrence; i++)
		{
			result = text_position_next(result + 1, &state);
			if (result == 0)
				break;
		}
	}
	else
	{
		/*searching from back with the specific times */
		result = src_text_len + position + 2;
		
		for (i = 0; i < occurrence; i++)
		{
			result = text_position_prev(result - 1, &state);
			if (result == 0)
				break;
		}
	}

	text_position_cleanup(&state);

	return result;
}

/*
 * appendStringInfoText
 *
 * Append a text to str.
 * Like appendStringInfoString(str, text_to_cstring(t)) but faster.
 */
static void
appendStringInfoText(StringInfo str, const text *t)
{
	appendBinaryStringInfo(str, VARDATA_ANY(t), VARSIZE_ANY_EXHDR(t));
}

/*
 *	text_position_prev - 
 *	searches substring backward from specify position.
 *
 *	This function is used to implement oracle 'instr' function,
 *	when the instr function's position parameter is negative.
 */
static int
text_position_prev(int start_pos, TextPositionState *state)
{
	int			pos = 0,
				p,
				px;

	/* start_pos is one-based */
	Assert(start_pos > 0);

	if (state->len2 <= 0)
		return start_pos;	/* result for empty pattern */

	if (!state->use_wchar)
	{
		/* simple case - single byte encoding */
		char	   *p1 = state->str1;
		char	   *p2 = state->str2;

		/*
		 *	Assuming that the end of the string is a matching substring,
		 *	calculate the start of the last substring, that is the value
		 *	of 'px'. If the specified starting position(start_pos) is
		 *	greater than 'px', then 'px' equal to the position of the
		 *	last substring. otherwise 'px' equal to the specified start
		 *	position(start_pos).
		 *
		 *	Note that 'p' and 'px' is zero-based.
		 */
		px = (state->len1 - state->len2);
		if (start_pos - 1 < px)
			px = start_pos - 1;

		p1 += px;

		if (state->len2 == 1)
		{
			for (p = px; p >= 0; p--)
			{
				if (*p1 == *p2)
				{
					pos = p + 1;
					break;
				}
				p1--;
			}
		}
		else
		{
			for (p = px; p >= 0; p--)
			{
				if ((*p1 == *p2) && (strncmp(p1, p2, state->len2) == 0))
				{
					pos = p + 1;
					break;
				}
				p1--;
			}
		}
	}
	else
	{
		/* not as simple - multibyte encoding */
		pg_wchar   *p1 = state->wstr1;
		pg_wchar   *p2 = state->wstr2;

		px = (state->len1 - state->len2);
		if (start_pos - 1 < px)
			px = start_pos - 1;

		p1 += px;

		if (state->len2 == 1)
		{
			for (p = px; p >= 0; p--)
			{
				if (*p1 == *p2)
				{
					pos = p + 1;
					break;
				}
				p1--;
			}
		}
		else
		{
			for (p = px; p >= 0; p--)
			{
				if ((*p1 == *p2) && (pg_wchar_strncmp(p1, p2, state->len2) == 0))
				{
					pos = p + 1;
					break;
				}
				p1--;
			}
		}
	}

	return pos;
}

/*
 *	appendUTF16Escape
 *
 *	Converts a UTF-16 code unit to a Unicode escape sequence (\xxxx) 
 * 	and appends it to the output string.
 */
static void 
appendUTF16Escape(StringInfoData* outputString, uint16_t codePoint) {
    char buffer[10];
    snprintf(buffer, sizeof(buffer), "\\%04X", codePoint);
    appendStringInfoString(outputString, buffer);
}

/********************************************************************
 * ora_asciistr
 *
 * Purpose:
 *	 It takes string as a argument, or an expression that resolves to 
 * 	 a string, in any character set and returns an ASCII 
 *   version of the string in the database character set. 
 *   Non-ASCII characters are converted to the form \xxxx, 
 *   where xxxx represents a UTF-16 code unit. 
 ********************************************************************/
Datum 
ora_asciistr(PG_FUNCTION_ARGS) {
	StringInfoData 	output;
	text 			*str_arg = NULL;
	char 			*str = NULL;
    char			*end = NULL;
	
	initStringInfo(&output);
	str_arg = PG_GETARG_TEXT_PP(0);
	str = VARDATA_ANY(str_arg);
	end = str + VARSIZE_ANY_EXHDR(str_arg);

    while (str < end) {
        unsigned char c = *str;
        uint32_t codePoint;
		
		if (c == '\\') {
			/* Handle backslash character */
			appendUTF16Escape(&output, 0x005C);  // UTF-16 representation of backslash
			str++;
        } 
        else if (c < 0x80) {
            /* ASCII character */
            appendStringInfoChar(&output, c);
            str++;
        } else if ((c & 0xE0) == 0xC0) {
            /* Two-byte UTF-8 sequence */
            codePoint = ((c & 0x1F) << 6) | (str[1] & 0x3F);
            appendUTF16Escape(&output, (uint16_t) codePoint);
            str += 2;
        } else if ((c & 0xF0) == 0xE0) {
            /* Three-byte UTF-8 sequence */
            codePoint = ((c & 0x0F) << 12) | ((str[1] & 0x3F) << 6) | (str[2] & 0x3F);
            appendUTF16Escape(&output, (uint16_t) codePoint);
            str += 3;
        } else if ((c & 0xF8) == 0xF0) {
            /* Four-byte UTF-8 sequence */
			uint16_t highSurrogate, lowSurrogate;

            codePoint = ((c & 0x07) << 18) | ((str[1] & 0x3F) << 12) | ((str[2] & 0x3F) << 6) | (str[3] & 0x3F);
            codePoint -= 0x10000;
            highSurrogate = 0xD800 | (codePoint >> 10);
            lowSurrogate = 0xDC00 | (codePoint & 0x3FF);
            appendUTF16Escape(&output, highSurrogate);
            appendUTF16Escape(&output, lowSurrogate);
            str += 4;
        } else {
            /* Invalid UTF-8 byte */
			ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE), errmsg("Invalid bytes")));
            str++;
        }
    }
	
    PG_RETURN_TEXT_P(cstring_to_text_with_len(output.data, output.len));
}


/* 3 is enough, but it is defined as 4 in backend code. */
#ifndef MAX_CONVERSION_GROWTH
#define MAX_CONVERSION_GROWTH  4
#endif

/*
 * Convert a tilde (~) to ...
 *	1: a full width tilde. (same as JA16EUCTILDE in oracle)
 *	0: a full width overline. (same as JA16EUC in oracle)
 *
 * Note - there is a difference with Oracle - it returns \342\210\274
 * what is a tilde char. Orafce returns fullwidth tilde. If it is a
 * problem, fix it for sef in code.
 */
#define JA_TO_FULL_WIDTH_TILDE	1

static const char *
TO_MULTI_BYTE_UTF8[95] =
{
	"\343\200\200",
	"\357\274\201",
	"\342\200\235",
	"\357\274\203",
	"\357\274\204",
	"\357\274\205",
	"\357\274\206",
	"\342\200\231",
	"\357\274\210",
	"\357\274\211",
	"\357\274\212",
	"\357\274\213",
	"\357\274\214",
	"\357\274\215",
	"\357\274\216",
	"\357\274\217",
	"\357\274\220",
	"\357\274\221",
	"\357\274\222",
	"\357\274\223",
	"\357\274\224",
	"\357\274\225",
	"\357\274\226",
	"\357\274\227",
	"\357\274\230",
	"\357\274\231",
	"\357\274\232",
	"\357\274\233",
	"\357\274\234",
	"\357\274\235",
	"\357\274\236",
	"\357\274\237",
	"\357\274\240",
	"\357\274\241",
	"\357\274\242",
	"\357\274\243",
	"\357\274\244",
	"\357\274\245",
	"\357\274\246",
	"\357\274\247",
	"\357\274\250",
	"\357\274\251",
	"\357\274\252",
	"\357\274\253",
	"\357\274\254",
	"\357\274\255",
	"\357\274\256",
	"\357\274\257",
	"\357\274\260",
	"\357\274\261",
	"\357\274\262",
	"\357\274\263",
	"\357\274\264",
	"\357\274\265",
	"\357\274\266",
	"\357\274\267",
	"\357\274\270",
	"\357\274\271",
	"\357\274\272",
	"\357\274\273",
	"\357\274\274",
	"\357\274\275",
	"\357\274\276",
	"\357\274\277",
	"\342\200\230",
	"\357\275\201",
	"\357\275\202",
	"\357\275\203",
	"\357\275\204",
	"\357\275\205",
	"\357\275\206",
	"\357\275\207",
	"\357\275\210",
	"\357\275\211",
	"\357\275\212",
	"\357\275\213",
	"\357\275\214",
	"\357\275\215",
	"\357\275\216",
	"\357\275\217",
	"\357\275\220",
	"\357\275\221",
	"\357\275\222",
	"\357\275\223",
	"\357\275\224",
	"\357\275\225",
	"\357\275\226",
	"\357\275\227",
	"\357\275\230",
	"\357\275\231",
	"\357\275\232",
	"\357\275\233",
	"\357\275\234",
	"\357\275\235",
#if JA_TO_FULL_WIDTH_TILDE
	"\357\275\236"
#else
	"\357\277\243"
#endif
};

static const char *
TO_MULTI_BYTE_EUCJP[95] =
{
	"\241\241",
	"\241\252",
	"\241\311",
	"\241\364",
	"\241\360",
	"\241\363",
	"\241\365",
	"\241\307",
	"\241\312",
	"\241\313",
	"\241\366",
	"\241\334",
	"\241\244",
	"\241\335",
	"\241\245",
	"\241\277",
	"\243\260",
	"\243\261",
	"\243\262",
	"\243\263",
	"\243\264",
	"\243\265",
	"\243\266",
	"\243\267",
	"\243\270",
	"\243\271",
	"\241\247",
	"\241\250",
	"\241\343",
	"\241\341",
	"\241\344",
	"\241\251",
	"\241\367",
	"\243\301",
	"\243\302",
	"\243\303",
	"\243\304",
	"\243\305",
	"\243\306",
	"\243\307",
	"\243\310",
	"\243\311",
	"\243\312",
	"\243\313",
	"\243\314",
	"\243\315",
	"\243\316",
	"\243\317",
	"\243\320",
	"\243\321",
	"\243\322",
	"\243\323",
	"\243\324",
	"\243\325",
	"\243\326",
	"\243\327",
	"\243\330",
	"\243\331",
	"\243\332",
	"\241\316",
	"\241\357",
	"\241\317",
	"\241\260",
	"\241\262",
	"\241\306",		/* Oracle returns different value \241\307 */
	"\243\341",
	"\243\342",
	"\243\343",
	"\243\344",
	"\243\345",
	"\243\346",
	"\243\347",
	"\243\350",
	"\243\351",
	"\243\352",
	"\243\353",
	"\243\354",
	"\243\355",
	"\243\356",
	"\243\357",
	"\243\360",
	"\243\361",
	"\243\362",
	"\243\363",
	"\243\364",
	"\243\365",
	"\243\366",
	"\243\367",
	"\243\370",
	"\243\371",
	"\243\372",
	"\241\320",
	"\241\303",
	"\241\321",
#if JA_TO_FULL_WIDTH_TILDE
	"\241\301"
#else
	"\241\261"
#endif
};

static const char *
TO_MULTI_BYTE__EUCCN[95] =
{
	"\241\241",
	"\243\241",
	"\243\242",
	"\243\243",
	"\243\244",
	"\243\245",
	"\243\246",
	"\243\247",
	"\243\250",
	"\243\251",
	"\243\252",
	"\243\253",
	"\243\254",
	"\243\255",
	"\243\256",
	"\243\257",
	"\243\260",
	"\243\261",
	"\243\262",
	"\243\263",
	"\243\264",
	"\243\265",
	"\243\266",
	"\243\267",
	"\243\270",
	"\243\271",
	"\243\272",
	"\243\273",
	"\243\274",
	"\243\275",
	"\243\276",
	"\243\277",
	"\243\300",
	"\243\301",
	"\243\302",
	"\243\303",
	"\243\304",
	"\243\305",
	"\243\306",
	"\243\307",
	"\243\310",
	"\243\311",
	"\243\312",
	"\243\313",
	"\243\314",
	"\243\315",
	"\243\316",
	"\243\317",
	"\243\320",
	"\243\321",
	"\243\322",
	"\243\323",
	"\243\324",
	"\243\325",
	"\243\326",
	"\243\327",
	"\243\330",
	"\243\331",
	"\243\332",
	"\243\333",
	"\243\334",
	"\243\335",
	"\243\336",
	"\243\337",
	"\243\340",
	"\243\341",
	"\243\342",
	"\243\343",
	"\243\344",
	"\243\345",
	"\243\346",
	"\243\347",
	"\243\350",
	"\243\351",
	"\243\352",
	"\243\353",
	"\243\354",
	"\243\355",
	"\243\356",
	"\243\357",
	"\243\360",
	"\243\361",
	"\243\362",
	"\243\363",
	"\243\364",
	"\243\365",
	"\243\366",
	"\243\367",
	"\243\370",
	"\243\371",
	"\243\372",
	"\243\373",
	"\243\374",
	"\243\375",
	"\243\376",
};

Datum
ora_to_multi_byte(PG_FUNCTION_ARGS)
{
	text	   *src;
	text	   *dst;
	const char *s;
	char	   *d;
	int			srclen;

#if defined(_MSC_VER) && (defined(_M_X64) || defined(__amd64__))

	__int64			dstlen;

#else

	int			dstlen;

	#endif

	int			i;
	const char **map;

	switch (GetDatabaseEncoding())
	{
		case PG_UTF8:
			map = TO_MULTI_BYTE_UTF8;
			break;
		case PG_EUC_JP:
		case PG_EUC_JIS_2004:
			map = TO_MULTI_BYTE_EUCJP;
			break;
		case PG_EUC_CN:
			map = TO_MULTI_BYTE__EUCCN;
			break;
		/*
		 * TODO: Add converter for encodings.
		 */
		default:	/* no need to convert */
			PG_RETURN_DATUM(PG_GETARG_DATUM(0));
	}

	src = PG_GETARG_TEXT_PP(0);
	s = VARDATA_ANY(src);
	srclen = VARSIZE_ANY_EXHDR(src);
	dst = (text *) palloc(VARHDRSZ + srclen * MAX_CONVERSION_GROWTH);
	d = VARDATA(dst);

	for (i = 0; i < srclen; i++)
	{
		unsigned char	u = (unsigned char) s[i];
		if (0x20 <= u && u <= 0x7e)
		{
			const char *m = map[u - 0x20];
			while (*m)
			{
				*d++ = *m++;
			}
		}
		else
		{
			*d++ = s[i];
		}
	}

	dstlen = d - VARDATA(dst);
	SET_VARSIZE(dst, VARHDRSZ + dstlen);

	PG_RETURN_TEXT_P(dst);
}

static int
getindex(const char **map, char *mbchar, int mblen)
{
	int		i;

	for (i = 0; i < 95; i++)
	{
		if (!memcmp(map[i], mbchar, mblen))
			return i;
	}

	return -1;
}

Datum
ora_to_single_byte(PG_FUNCTION_ARGS)
{
	text	   *src;
	text	   *dst;
	char	   *s;
	char	   *d;
	int			srclen;

#if defined(_MSC_VER) && (defined(_M_X64) || defined(__amd64__))

	__int64			dstlen;

#else
	
	int			dstlen;

#endif

	const char **map;

	switch (GetDatabaseEncoding())
	{
		case PG_UTF8:
			map = TO_MULTI_BYTE_UTF8;
			break;
		case PG_EUC_JP:
		case PG_EUC_JIS_2004:
			map = TO_MULTI_BYTE_EUCJP;
			break;
		case PG_EUC_CN:
			map = TO_MULTI_BYTE__EUCCN;
			break;
		/*
		 * TODO: Add converter for encodings.
		 */
		default:	/* no need to convert */
			PG_RETURN_DATUM(PG_GETARG_DATUM(0));
	}

	src = PG_GETARG_TEXT_PP(0);
	s = VARDATA_ANY(src);
	srclen = VARSIZE_ANY_EXHDR(src);

	/* XXX - The output length should be <= input length */
	dst = (text *) palloc0(VARHDRSZ + srclen);
	d = VARDATA(dst);

	while (s - VARDATA_ANY(src) < srclen)
	{
		char   *u = s;
		int		clen;
		int		mapindex;

		clen = pg_mblen(u);
		s += clen;

		if (clen == 1)
			*d++ = *u;
		else if ((mapindex = getindex(map, u, clen)) >= 0)
		{
			const char m = 0x20 + mapindex;
			*d++ = m;
		}
		else
		{
			memcpy(d, u, clen);
			d += clen;
		}
	}

	dstlen = d - VARDATA(dst);
	SET_VARSIZE(dst, VARHDRSZ + dstlen);

	PG_RETURN_TEXT_P(dst);
}
