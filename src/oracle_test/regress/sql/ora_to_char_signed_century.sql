--
-- ORA_TO_CHAR_SIGNED_CENTURY
-- Oracle-compatible SCC (signed century) format element
--
-- Oracle prefixes the century with a space for AD dates and with '-' for BC
-- dates.  FM does not suppress that sign position.
--
SELECT TO_CHAR(DATE '2024-02-29', 'SCC') AS ad,
       TO_CHAR(DATE '0001-01-01', 'SCC') AS first_year;

SELECT TO_CHAR(DATE '-0044-03-15', 'SCC') AS bc,
       TO_CHAR(DATE '-4712-01-01', 'SCC') AS bc_old;

-- the sign position is not affected by FM
SELECT TO_CHAR(DATE '2024-02-29', 'FMSCC') AS fm;

-- CC itself keeps the unsigned output
SELECT TO_CHAR(DATE '2024-02-29', 'CC') AS unsigned_cc;

-- combined with other elements
SELECT TO_CHAR(DATE '2024-02-29', 'YYYY SCC') AS combined;
