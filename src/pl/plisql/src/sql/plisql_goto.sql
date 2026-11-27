--
-- Tests for Oracle-compatible GOTO statement and statement labels (<<label>>)
--

-- 1. Forward GOTO and <<label>> NULL placeholder in anonymous block
DO $$
DECLARE
    v_step VARCHAR2(100) := 'start';
BEGIN
    v_step := v_step || '->before';
    GOTO skip_middle;
    v_step := v_step || '->unreachable';

    <<skip_middle>>
    v_step := v_step || '->after';
    GOTO finish_block;
    v_step := v_step || '->unreachable2';

    <<finish_block>>
    NULL;
    RAISE NOTICE 'anon trace: %', v_step;
END;
$$;

-- 2. Conditional IF/ELSE branching with GOTO in a PROCEDURE (#1142 pattern)
CREATE OR REPLACE PROCEDURE proc_goto_branch(p_flag IN BOOLEAN, p_out OUT VARCHAR2) IS
    v_print BOOLEAN := p_flag;
BEGIN
    <<check_value>>
    IF v_print = TRUE THEN
        GOTO print_msg;
    ELSE
        GOTO do_nothing;
    END IF;

    <<print_msg>>
    p_out := 'printed';
    RETURN;

    <<do_nothing>>
    p_out := 'skipped';
    RETURN;
END proc_goto_branch;
/

DECLARE
    v_res VARCHAR2(50);
BEGIN
    proc_goto_branch(TRUE, v_res);
    RAISE NOTICE 'flag=TRUE  -> %', v_res;
    proc_goto_branch(FALSE, v_res);
    RAISE NOTICE 'flag=FALSE -> %', v_res;
END;
/

DROP PROCEDURE proc_goto_branch;

-- 3. Backward GOTO loop in a standalone FUNCTION
CREATE OR REPLACE FUNCTION fn_goto_sum(n IN INTEGER) RETURN INTEGER IS
    i     INTEGER := 1;
    total INTEGER := 0;
BEGIN
    <<loop_top>>
    IF i > n THEN
        GOTO loop_done;
    END IF;
    total := total + i;
    i := i + 1;
    GOTO loop_top;

    <<loop_done>>
    RETURN total;
END fn_goto_sum;
/

SELECT fn_goto_sum(0) AS s0, fn_goto_sum(5) AS s5, fn_goto_sum(10) AS s10 FROM dual;
DROP FUNCTION fn_goto_sum;

-- 4. Stacked labels on statements and blocks, plus jumping to labeled sub-block/loop
CREATE OR REPLACE FUNCTION fn_goto_stacked(mode_in IN INTEGER) RETURN VARCHAR2 IS
    v_mode INTEGER := mode_in;
    trace  VARCHAR2(200) := 'init';
    cnt    INTEGER := 0;
BEGIN
    IF v_mode = 1 THEN
        GOTO alias_a;
    ELSIF v_mode = 2 THEN
        GOTO alias_b;
    ELSIF v_mode = 3 THEN
        GOTO sub_blk;
    ELSIF v_mode = 4 THEN
        GOTO outer_alias;
    END IF;

    <<alias_a>>
    <<alias_b>>
    trace := trace || '->stacked_stmt';
    RETURN trace;

    <<outer_alias>>
    <<sub_blk>>
    DECLARE
        local_v VARCHAR2(20) := '->in_sub_blk';
    BEGIN
        trace := trace || local_v;
    END sub_blk;

    <<loop_lbl>>
    FOR k IN 1..2 LOOP
        cnt := cnt + 1;
        IF cnt = 1 AND v_mode = 4 THEN
            trace := trace || '->restart_for';
            v_mode := 99;
            GOTO loop_lbl;
        END IF;
    END LOOP loop_lbl;

    trace := trace || '->cnt=' || cnt;
    RETURN trace;
END fn_goto_stacked;
/

SELECT fn_goto_stacked(1) AS m1,
       fn_goto_stacked(2) AS m2,
       fn_goto_stacked(3) AS m3,
       fn_goto_stacked(4) AS m4
FROM dual;
DROP FUNCTION fn_goto_stacked;

-- 5. Jumping out of cursor FOR loop automatically closes the cursor
CREATE TABLE goto_cur_tab(id INTEGER, val VARCHAR2(20));
INSERT INTO goto_cur_tab VALUES (1, 'one'), (2, 'two'), (3, 'three');

CREATE OR REPLACE FUNCTION fn_goto_cursor_cleanup() RETURN VARCHAR2 IS
    c_items CURSOR IS SELECT id, val FROM goto_cur_tab ORDER BY id;
    v_id  INTEGER;
    v_val VARCHAR2(20);
    seen  VARCHAR2(100) := '';
BEGIN
    FOR rec IN c_items LOOP
        seen := seen || rec.val || ',';
        IF rec.id = 2 THEN
            GOTO after_cursor_loop;
        END IF;
    END LOOP;

    <<after_cursor_loop>>
    -- Cursor c_items must have been closed when GOTO exited the FOR loop,
    -- so opening it explicitly here must succeed without "cursor already in use".
    OPEN c_items;
    FETCH c_items INTO v_id, v_val;
    CLOSE c_items;
    RETURN seen || 'reopened=' || v_val;
END fn_goto_cursor_cleanup;
/

SELECT fn_goto_cursor_cleanup() FROM dual;
DROP FUNCTION fn_goto_cursor_cleanup;

-- 6. Jumping out of inner block with EXCEPTION clause & outward from EXCEPTION handler
CREATE OR REPLACE FUNCTION fn_goto_exceptions(trigger_err IN BOOLEAN) RETURN VARCHAR2 IS
    log_str VARCHAR2(200) := 'begin';
    dummy   INTEGER;
BEGIN
    BEGIN
        INSERT INTO goto_cur_tab VALUES (10, 'ten');
        IF NOT trigger_err THEN
            log_str := log_str || '->no_err_jump';
            GOTO outer_done;
        END IF;
        -- Trigger DIVISION_BY_ZERO so inner subtransaction rolls back the INSERT
        dummy := 1 / 0;
    EXCEPTION
        WHEN DIVISION_BY_ZERO THEN
            log_str := log_str || '->caught_div0';
            GOTO handler_step2;
            log_str := log_str || '->skipped_in_handler';
            <<handler_step2>>
            log_str := log_str || '->jump_outward';
            GOTO outer_done;
    END;

    log_str := log_str || '->unreachable_after_inner';

    <<outer_done>>
    SELECT count(*) INTO dummy FROM goto_cur_tab WHERE id = 10;
    RETURN log_str || '->rows10=' || dummy;
END fn_goto_exceptions;
/

SELECT fn_goto_exceptions(TRUE) FROM dual;
SELECT fn_goto_exceptions(FALSE) FROM dual;
DROP FUNCTION fn_goto_exceptions;
DROP TABLE goto_cur_tab;

-- 7. Inner block label shadowing an outer label of the same name
CREATE OR REPLACE FUNCTION fn_goto_shadow() RETURN VARCHAR2 IS
    trace VARCHAR2(100) := 'start';
BEGIN
    BEGIN
        trace := trace || '->inner1';
        GOTO done;
        trace := trace || '->bad1';
        <<done>>
        trace := trace || '->inner_done';
    END;

    trace := trace || '->outer1';
    GOTO done;
    trace := trace || '->bad2';

    <<done>>
    trace := trace || '->outer_done';
    RETURN trace;
END fn_goto_shadow;
/

SELECT fn_goto_shadow() FROM dual;
DROP FUNCTION fn_goto_shadow;

-- 8. GOTO inside PACKAGE, nested subprogram, and TRIGGER
CREATE OR REPLACE PACKAGE pkg_goto_test IS
    FUNCTION compute(x NUMBER) RETURN VARCHAR2;
END pkg_goto_test;
/

CREATE OR REPLACE PACKAGE BODY pkg_goto_test IS
    FUNCTION compute(x NUMBER) RETURN VARCHAR2 IS
        FUNCTION helper(v NUMBER) RETURN VARCHAR2 IS
        BEGIN
            IF v < 0 THEN
                GOTO neg_lbl;
            END IF;
            RETURN 'nonneg';
            <<neg_lbl>>
            RETURN 'neg';
        END helper;
    BEGIN
        IF x = 0 THEN
            GOTO zero_lbl;
        END IF;
        RETURN 'pkg:' || helper(x);
        <<zero_lbl>>
        RETURN 'pkg:zero';
    END compute;
END pkg_goto_test;
/

SELECT pkg_goto_test.compute(-5) AS c_neg,
       pkg_goto_test.compute(0) AS c_zero,
       pkg_goto_test.compute(7) AS c_pos
FROM dual;

DROP PACKAGE pkg_goto_test;

CREATE TABLE goto_trig_tab(x INTEGER, tag VARCHAR2(20));

CREATE OR REPLACE FUNCTION fn_goto_trg() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.x < 0 THEN
        GOTO clamp_zero;
    END IF;
    NEW.tag := 'ok';
    GOTO done_trg;

    <<clamp_zero>>
    NEW.x := 0;
    NEW.tag := 'clamped';

    <<done_trg>>
    RETURN NEW;
END;
$$ LANGUAGE plisql;
/

CREATE TRIGGER trg_goto_bi BEFORE INSERT ON goto_trig_tab
FOR EACH ROW EXECUTE FUNCTION fn_goto_trg();

INSERT INTO goto_trig_tab(x) VALUES (-9), (4);
SELECT x, tag FROM goto_trig_tab ORDER BY x;

DROP TABLE goto_trig_tab;
DROP FUNCTION fn_goto_trg;

-- 9. Compile-time error checks for illegal GOTO constructs

-- 9a. Undefined label
CREATE OR REPLACE FUNCTION goto_err_undef() RETURN VOID IS
BEGIN
    GOTO missing_label;
END;
/

-- 9b. Jumping into an IF statement from outside
CREATE OR REPLACE FUNCTION goto_err_into_if(flag BOOLEAN) RETURN VOID IS
BEGIN
    GOTO inside_if;
    IF flag THEN
        <<inside_if>>
        NULL;
    END IF;
END;
/

-- 9c. Jumping between IF / ELSE clauses
CREATE OR REPLACE FUNCTION goto_err_across_if(flag BOOLEAN) RETURN VOID IS
BEGIN
    IF flag THEN
        GOTO in_else;
    ELSE
        <<in_else>>
        NULL;
    END IF;
END;
/

-- 9d. Jumping between CASE WHEN clauses
CREATE OR REPLACE FUNCTION goto_err_across_case(x INTEGER) RETURN VOID IS
BEGIN
    CASE x
        WHEN 1 THEN
            GOTO when_two;
        WHEN 2 THEN
            <<when_two>>
            NULL;
        ELSE
            NULL;
    END CASE;
END;
/

-- 9e. Jumping into a LOOP body from outside
CREATE OR REPLACE FUNCTION goto_err_into_loop() RETURN VOID IS
BEGIN
    GOTO inside_loop;
    FOR i IN 1..3 LOOP
        <<inside_loop>>
        NULL;
    END LOOP;
END;
/

-- 9f. Jumping into an inner sub-block from outside
CREATE OR REPLACE FUNCTION goto_err_into_subblock() RETURN VOID IS
BEGIN
    GOTO inside_sub;
    BEGIN
        <<inside_sub>>
        NULL;
    END;
END;
/

-- 9g. Jumping into an EXCEPTION handler
CREATE OR REPLACE FUNCTION goto_err_into_exc() RETURN VOID IS
BEGIN
    GOTO inside_handler;
EXCEPTION
    WHEN OTHERS THEN
        <<inside_handler>>
        NULL;
END;
/

-- 9h. Jumping from an EXCEPTION handler back into the current block
CREATE OR REPLACE FUNCTION goto_err_exc_to_body() RETURN VOID IS
BEGIN
    <<body_lbl>>
    RAISE DIVISION_BY_ZERO;
EXCEPTION
    WHEN DIVISION_BY_ZERO THEN
        GOTO body_lbl;
END;
/

-- 9i. Jumping to the outermost subprogram label
CREATE OR REPLACE FUNCTION goto_err_top_label() RETURN VOID IS
BEGIN
    GOTO goto_err_top_label;
END goto_err_top_label;
/

-- 9j. Duplicate statement label in the same block
CREATE OR REPLACE FUNCTION goto_err_dup_label() RETURN VOID IS
BEGIN
    <<dup_lbl>>
    NULL;
    <<dup_lbl>>
    NULL;
END;
/

-- 9k. Dangling label at end of block with no statement following it
CREATE OR REPLACE FUNCTION goto_err_dangling_label() RETURN VOID IS
BEGIN
    <<dangling_lbl>>
END;
/

DROP FUNCTION goto_err_undef;
DROP FUNCTION goto_err_into_if;
DROP FUNCTION goto_err_across_if;
DROP FUNCTION goto_err_across_case;
DROP FUNCTION goto_err_into_loop;
DROP FUNCTION goto_err_into_subblock;
DROP FUNCTION goto_err_into_exc;
DROP FUNCTION goto_err_exc_to_body;
DROP FUNCTION goto_err_top_label;
DROP FUNCTION goto_err_dup_label;
DROP FUNCTION goto_err_dangling_label;

-- 9l. Anonymous DO block compile-time errors (direct ERROR reporting)
DO $$
BEGIN
    GOTO no_such_target;
END;
$$;

DO $$
BEGIN
    GOTO into_branch;
    IF TRUE THEN
        <<into_branch>>
        NULL;
    END IF;
END;
$$;

-- 9m. Block-scoped label hiding (Oracle PLS-00375): an unreachable label
-- declared inside an inner block must hide a same-named outer label rather
-- than resolving outward across the inner block boundary.
CREATE OR REPLACE FUNCTION goto_err_shadow_if_hides_outer() RETURN VOID IS
BEGIN
    BEGIN
        IF TRUE THEN
            <<shared_lbl>>
            NULL;
        END IF;
        GOTO shared_lbl;
    END;
    <<shared_lbl>>
    NULL;
END;
/
DROP FUNCTION goto_err_shadow_if_hides_outer;

CREATE OR REPLACE FUNCTION goto_err_shadow_exc_hides_outer() RETURN VOID IS
BEGIN
    BEGIN
        <<shared_lbl>>
        RAISE DIVISION_BY_ZERO;
    EXCEPTION
        WHEN OTHERS THEN
            GOTO shared_lbl;
    END;
    <<shared_lbl>>
    NULL;
END;
/
DROP FUNCTION goto_err_shadow_exc_hides_outer;

DO $$
BEGIN
    BEGIN
        IF TRUE THEN
            <<shared_lbl>>
            NULL;
        END IF;
        GOTO shared_lbl;
    END;
    <<shared_lbl>>
    NULL;
END;
$$;

DO $$
BEGIN
    BEGIN
        <<shared_lbl>>
        RAISE DIVISION_BY_ZERO;
    EXCEPTION
        WHEN OTHERS THEN
            GOTO shared_lbl;
    END;
    <<shared_lbl>>
    NULL;
END;
$$;
