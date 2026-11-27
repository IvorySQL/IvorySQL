-- Single-character matches must retain their start and exclusive end.
SELECT REGEXP_INSTR('abc', 'a', 1) AS first_char,
       REGEXP_INSTR('abc', 'b', 1, 1) AS middle_char,
       REGEXP_INSTR('abc', 'c', 1, 1, 1) AS after_last;
SELECT REGEXP_INSTR('abc', 'a', 1, 1, 2) AS after_match;
SELECT REGEXP_INSTR('abc123def456', '[0-9]', 5) AS digit_start,
       REGEXP_INSTR('abc123def456', '[0-9]', 5, 2, 1) AS second_digit_end;

-- Oracle accepts nonnegative return_option values: zero selects the start,
-- and positive values select the position immediately following the match.
SELECT ret_opt, REGEXP_INSTR('abc', 'a', 1, 1, ret_opt) AS position
FROM (VALUES (0), (1), (2), (99), (2147483647)) AS opts(ret_opt)
ORDER BY ret_opt;

-- Exercise the VARCHAR2 overloads as well as the text/literal overloads.
SELECT sys.REGEXP_INSTR('abc'::varchar2, 'a'::varchar2) AS first_char,
       sys.REGEXP_INSTR('abc'::varchar2, 'a'::varchar2, 1, 1, 2) AS after_match;
SELECT REGEXP_INSTR('ABC', 'a', 1, 1, 1, 'i') AS case_insensitive;

-- Positions count characters, including multibyte characters.
SELECT REGEXP_INSTR(UNISTR('\4E2D\6587abc'), 'a', 1) AS char_start,
       REGEXP_INSTR(UNISTR('\4E2D\6587abc'), 'a', 1, 1, 1) AS char_end,
       REGEXP_INSTR(UNISTR('\4E2D\6587abc'), UNISTR('\6587'), 1, 1, 2) AS multibyte_end;

-- Captures use the same exclusive endpoints as the overall match.
SELECT REGEXP_INSTR('abc', '(a)(bc)', 1, 1, 0, 'c', 1) AS capture_start,
       REGEXP_INSTR('abc', '(a)(bc)', 1, 1, 1, 'c', 1) AS single_capture_end,
       REGEXP_INSTR('abc', '(a)(bc)', 1, 1, 2, 'c', 2) AS longer_capture_end;
SELECT REGEXP_INSTR('abcabc', '(a)(bc)', 1, 2, 0, 'c', 1) AS second_start,
       REGEXP_INSTR('abcabc', '(a)(bc)', 1, 2, 1, 'c', 2) AS second_end;

-- Absent or unmatched captures return zero, not the overall match's position.
SELECT REGEXP_INSTR('abc', 'abc', 1, 1, 0, 'c', 1) AS no_capture,
       REGEXP_INSTR('ab', '(ab)', 1, 1, 0, 'c', 2) AS absent_capture,
       REGEXP_INSTR('b', '(a)?b', 1, 1, 0, 'c', 1) AS unmatched_capture;

-- More than nine captures must not overrun the fixed regex match array.
SELECT REGEXP_INSTR('abcdefghij', '(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)',
                    1, 1, 0, 'c', 9) AS ninth_start,
       REGEXP_INSTR('abcdefghij', '(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)',
                    1, 1, 1, 'c', 9) AS ninth_end,
       REGEXP_INSTR('abcdefghij', '(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)',
                    1, 1, 1, 'c', 0) AS overall_end,
       REGEXP_INSTR('abcdefghij', '(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)',
                    1, 1, 0, 'c', 10) AS unsupported_capture;

-- Equal endpoints are valid empty matches, including empty captures.
SELECT REGEXP_INSTR('bbb', 'a*', 1, 1, 0) AS empty_start,
       REGEXP_INSTR('bbb', 'a*', 1, 1, 1) AS empty_end,
       REGEXP_INSTR('bbb', 'a*', 1, 2, 1) AS second_empty,
       REGEXP_INSTR('abb', 'a*', 1, 2, 0) AS empty_after_match;
SELECT REGEXP_INSTR('b', '(a*)b', 1, 1, 0, 'c', 1) AS empty_capture_start,
       REGEXP_INSTR('b', '(a*)b', 1, 1, 1, 'c', 1) AS empty_capture_end;
SELECT REGEXP_INSTR('abc', '$', 1, 1, 0) AS end_anchor,
       REGEXP_INSTR('abc', '$', 4, 1, 0) AS start_past_last,
       REGEXP_INSTR('abc', '$', 2147483647, 1, 0) AS start_far_past_last;

-- Failed searches and occurrences retain their zero result.
SELECT REGEXP_INSTR('abc', 'x', 1, 1, 1) AS no_match,
       REGEXP_INSTR('abc', 'a', 1, 2, 1) AS missing_occurrence;

-- Explicit PostgreSQL calls retain their own return_option validation.
SELECT pg_catalog.REGEXP_INSTR('abc', 'a', 1, 1, 0) AS pg_start,
       pg_catalog.REGEXP_INSTR('abc', 'a', 1, 1, 1) AS pg_end;
SELECT pg_catalog.REGEXP_INSTR('abc', 'a', 1, 1, 2);
