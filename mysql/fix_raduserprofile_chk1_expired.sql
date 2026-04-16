-- One-time fix: allow account_status = 'expired' (backend job + RADIUS UPDATE).
-- Error: QueryFailedError: Check constraint 'raduserprofile_chk_1' is violated
--
--   mysql -u USER -p radius < fix_raduserprofile_chk1_expired.sql
--
-- If constraint name differs, list CHECKs on raduserprofile and DROP the one on account_status.

USE radius;

ALTER TABLE raduserprofile DROP CHECK raduserprofile_chk_1;
