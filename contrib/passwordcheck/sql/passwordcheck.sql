SET md5_password_warnings = off;
LOAD 'passwordcheck';

CREATE USER regress_passwordcheck_user1;

-- ok
ALTER USER regress_passwordcheck_user1 PASSWORD 'A_nice_long_password1';

-- error: too short
ALTER USER regress_passwordcheck_user1 PASSWORD 'tooshrt';

-- ok
SET passwordcheck.min_password_length = 6;
ALTER USER regress_passwordcheck_user1 PASSWORD 'V_shrt1';

-- error: contains user name
ALTER USER regress_passwordcheck_user1 PASSWORD 'xyzregress_passwordcheck_user1';

-- error: contains only letters
ALTER USER regress_passwordcheck_user1 PASSWORD 'alessnicelongpassword';

-- error: no uppercase letter
ALTER USER regress_passwordcheck_user1 PASSWORD 'a_nice_long_password1';

-- error: no lowercase letter
ALTER USER regress_passwordcheck_user1 PASSWORD 'A_NICE_LONG_PASSWORD1';

-- error: no digit
ALTER USER regress_passwordcheck_user1 PASSWORD 'A_nice_long_password';

-- error: no special character
ALTER USER regress_passwordcheck_user1 PASSWORD 'Anicelongpassword1';

-- ok: uppercase check can be configured
SET passwordcheck.require_uppercase = off;
ALTER USER regress_passwordcheck_user1 PASSWORD 'another_long_password1';
SET passwordcheck.require_uppercase = on;
ALTER USER regress_passwordcheck_user1 PASSWORD 'another_long_password1';

-- ok: lowercase check can be configured
SET passwordcheck.require_lowercase = off;
ALTER USER regress_passwordcheck_user1 PASSWORD 'ANOTHER_LONG_PASSWORD1';
SET passwordcheck.require_lowercase = on;
ALTER USER regress_passwordcheck_user1 PASSWORD 'ANOTHER_LONG_PASSWORD1';

-- ok: digit check can be configured
SET passwordcheck.require_digit = off;
ALTER USER regress_passwordcheck_user1 PASSWORD 'Another_long_password';
SET passwordcheck.require_digit = on;
ALTER USER regress_passwordcheck_user1 PASSWORD 'Another_long_password';

-- ok: special-character check can be configured
SET passwordcheck.require_special = off;
ALTER USER regress_passwordcheck_user1 PASSWORD 'Anotherlongpassword1';
SET passwordcheck.require_special = on;
ALTER USER regress_passwordcheck_user1 PASSWORD 'Anotherlongpassword1';

-- encrypted ok (password is "secret")
ALTER USER regress_passwordcheck_user1 PASSWORD 'md592350e12ac34e52dd598f90893bb3ae7';

-- error: password is user name
ALTER USER regress_passwordcheck_user1 PASSWORD 'md507a112732ed9f2087fa90b192d44e358';

DROP USER regress_passwordcheck_user1;
