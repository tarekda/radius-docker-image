-- Add a NAS device (adjust IP and secret according to your setup)
INSERT INTO nas (
    nasname,
    shortname,
    type,
    ports,
    secret,
    description
) VALUES (
    '172.8.16.2',          -- Your NAS IP
    'mikrotik1',
    'other',
    0,
    'tisp123',          -- Your shared secret
    'MikroTik Test Router'
);

-- First clear existing profiles if any exist
DELETE FROM radprofile;

-- Reset the auto-increment
ALTER TABLE radprofile AUTO_INCREMENT = 1;

-- Add test profiles with different quotas and speeds
INSERT INTO radprofile (
    profile_name,
    daily_quota,
    monthly_quota,
    speed_down,
    speed_up,
    session_timeout,
    idle_timeout,
    max_sessions
) VALUES 
    ('Basic', 1073741824, 10737418240, 1024, 512, 3600, 600, 1),     -- 1GB daily, 10GB monthly, 1Mbps/512Kbps
    ('Premium', 5368709120, 53687091200, 2048, 1024, 7200, 900, 2),  -- 5GB daily, 50GB monthly, 2Mbps/1Mbps
    ('Business', 10737418240, 107374182400, 4096, 2048, 0, 1800, 5); -- 10GB daily, 100GB monthly, 4Mbps/2Mbps

-- Clear existing user profiles
DELETE FROM raduserprofile;
ALTER TABLE raduserprofile AUTO_INCREMENT = 1;

-- Add test users
INSERT INTO raduserprofile (
    username,
    profile_id,
    freenight,
    quota_reset_day,
    is_monthly_exceeded,
    account_status
) VALUES 
    ('testbasic', 1, 0, DAY(NOW()), 0, 'active'),        -- Basic profile has ID 1
    ('testpremium', 2, 1, DAY(NOW()), 0, 'active'),      -- Premium profile has ID 2
    ('testbusiness', 3, 0, DAY(NOW()), 0, 'active'),     -- Business profile has ID 3
    ('testsuspended', 1, 0, DAY(NOW()), 0, 'suspended'); -- Using Basic profile (ID 1)

-- Add passwords for the users
INSERT INTO radcheck (
    username,
    attribute,
    op,
    value
) VALUES 
    ('testbasic', 'Cleartext-Password', ':=', 'password123'),
    ('testpremium', 'Cleartext-Password', ':=', 'password123'),
    ('testbusiness', 'Cleartext-Password', ':=', 'password123'),
    ('testsuspended', 'Cleartext-Password', ':=', 'password123');

-- Add some user details
INSERT INTO user_details (
    username,
    full_name,
    address,
    phone_number,
    email
) VALUES 
    ('testbasic', 'Basic User', '123 Test St', '+1234567890', 'basic@test.com'),
    ('testpremium', 'Premium User', '456 Test Ave', '+1234567891', 'premium@test.com'),
    ('testbusiness', 'Business User', '789 Test Blvd', '+1234567892', 'business@test.com'),
    ('testsuspended', 'Suspended User', '321 Test Rd', '+1234567893', 'suspended@test.com');

-- Add some MAC bindings (example MACs)
INSERT INTO user_mac (
    username,
    mac_address
) VALUES 
    ('testbasic', '00:11:22:33:44:55'),
    ('testpremium', '00:11:22:33:44:66'),
    ('testbusiness', '00:11:22:33:44:77');

-- Add some sample usage data
INSERT INTO radusagestats (
    username,
    day,
    data_usage
) VALUES 
    ('testbasic', CURDATE(), 536870912),      -- 512MB used today
    ('testpremium', CURDATE(), 1073741824),   -- 1GB used today
    ('testbusiness', CURDATE(), 2147483648);  -- 2GB used today 


INSERT INTO settings (night_start, night_end, key_attribute, if_enabled)
VALUES ('00:00:00', '09:00:00', 'Free-Night', TRUE);
