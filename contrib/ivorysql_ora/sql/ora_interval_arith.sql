--
-- Subtracting intervals must keep the mathematical value across the whole
-- supported range.  dsinterval_mi() reduced both operands to one int64
-- microsecond count, which overflows for large day to second values.
--
SELECT INTERVAL '106751992 00:00:00' DAY(9) TO SECOND - INTERVAL '0 00:00:00' DAY TO SECOND AS day_mi_ovf;
SELECT INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND - INTERVAL '0 00:00:00' DAY TO SECOND AS day_mi_ovf_neg;
SELECT INTERVAL '106751992 00:00:00' DAY(9) TO SECOND - INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND AS day_mi_ovf_sum;
