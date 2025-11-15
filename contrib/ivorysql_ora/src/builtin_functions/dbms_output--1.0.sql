/***************************************************************
 *
 * DBMS_OUTPUT package - Basic implementation
 *
 * This is a simplified implementation that wraps RAISE INFO.
 * It does not implement full Oracle DBMS_OUTPUT functionality
 * (no buffering, no GET_LINE/GET_LINES, always enabled).
 *
 ***************************************************************/

-- Create DBMS_OUTPUT package specification
CREATE OR REPLACE PACKAGE dbms_output IS
  PROCEDURE put_line(a VARCHAR2);
  PROCEDURE put(a VARCHAR2);
  PROCEDURE new_line;
  PROCEDURE enable(buffer_size INTEGER DEFAULT NULL);
  PROCEDURE disable;
END dbms_output;

-- Create DBMS_OUTPUT package body
CREATE OR REPLACE PACKAGE BODY dbms_output IS

  -- Simple implementation: just use RAISE INFO
  PROCEDURE put_line(a VARCHAR2) IS
  BEGIN
    RAISE INFO '%', a;
  END put_line;

  PROCEDURE put(a VARCHAR2) IS
  BEGIN
    -- Note: This doesn't actually buffer, just outputs immediately
    RAISE INFO '%', a;
  END put;

  PROCEDURE new_line IS
  BEGIN
    RAISE INFO ' ';
  END new_line;

  -- These are no-ops in this simple implementation
  PROCEDURE enable(buffer_size INTEGER DEFAULT NULL) IS
  BEGIN
    -- Output is always enabled
    NULL;
  END enable;

  PROCEDURE disable IS
  BEGIN
    -- Cannot actually disable output in this implementation
    NULL;
  END disable;

END dbms_output;
