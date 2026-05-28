CREATE DATABASE IF NOT EXISTS radius;
USE radius;

-- Base RADIUS table (for authentication) - Move this up since it's referenced by others
CREATE TABLE radcheck (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    attribute VARCHAR(64) NOT NULL,
    op VARCHAR(2) NOT NULL DEFAULT ':=',
    value VARCHAR(253) NOT NULL,
    INDEX idx_username (username)
);

-- Profiles (quotas, speed, free night)
CREATE TABLE `radprofile` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `profile_name` VARCHAR(64) NOT NULL,
  `daily_quota` BIGINT NOT NULL,
  `monthly_quota` BIGINT NOT NULL,
  `night_start` TIME DEFAULT NULL,
  `night_end` TIME DEFAULT NULL,
  `speed_down` INT DEFAULT 0,
  `speed_up` INT DEFAULT 0,
  `price` INT DEFAULT 0,
  `session_timeout` INT DEFAULT 3600,
  `idle_timeout` INT DEFAULT 600,
  `max_sessions` INT DEFAULT 1,

  PRIMARY KEY (`id`)
  , UNIQUE KEY `uq_radprofile_profile_name` (`profile_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- User-Profile Mapping
CREATE TABLE raduserprofile (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    profile_id INT NOT NULL,
    freenight TINYINT(1) DEFAULT 0,
    is_fallback TINYINT(1) DEFAULT 0,
    is_monthly_exceeded TINYINT(1) DEFAULT 0,
    quota_reset_day INT DEFAULT 1,
    account_status VARCHAR(20) DEFAULT 'active',
    expires_at DATETIME NULL DEFAULT NULL,
    expiry_framed_ip VARCHAR(45) NULL DEFAULT NULL,
    FOREIGN KEY (profile_id) REFERENCES radprofile(id),
    INDEX idx_raduserprofile_username (username),
    CHECK (quota_reset_day BETWEEN 1 AND 31)
);

-- Usage Tracking
CREATE TABLE radusagestats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    day DATE NOT NULL,
    data_usage BIGINT NOT NULL DEFAULT 0,
    last_input BIGINT NOT NULL DEFAULT 0,
    last_output BIGINT NOT NULL DEFAULT 0,
    UNIQUE KEY (username, day)
) ENGINE = InnoDB;

-- NOTE:
-- Keep init scripts compatible with the MySQL docker-entrypoint behavior:
-- these files run only on first database initialization (empty datadir).
-- Avoid non-idempotent ALTER TABLE statements here.


-- User Details (name, address, phone)
CREATE TABLE user_details (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL UNIQUE,
    full_name VARCHAR(255),
    address TEXT,
    phone_number VARCHAR(20),
    email VARCHAR(255),
    FOREIGN KEY (username) REFERENCES radcheck(username)
);

-- MAC Binding
CREATE TABLE user_mac (
    username VARCHAR(64),
    mac_address VARCHAR(17) NOT NULL UNIQUE,
    PRIMARY KEY (username),
    FOREIGN KEY (username) REFERENCES radcheck(username)
);

-- Rest of the tables (no foreign keys)
CREATE TABLE connection_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50),
    mac_address VARCHAR(20),
    nas_ip VARCHAR(15),
    status ENUM('accepted', 'rejected', 'timeout', 'error','attempt'),
    acct_status ENUM('start', 'stop', 'update') NULL,
    terminate_cause ENUM('user-request', 'idle-timeout', 'session-timeout', 'lost-carrier') NULL,
    reply_message VARCHAR(255) NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_connection_logs_timestamp_status (timestamp, status),
    INDEX idx_connection_logs_mac_status_ts (mac_address, status, timestamp),
    INDEX idx_connection_logs_username_status_ts (username, status, timestamp)
);

CREATE TABLE connection_log_hourly_stats (
    bucket DATETIME NOT NULL PRIMARY KEY,
    attempts BIGINT NOT NULL DEFAULT 0,
    accepted BIGINT NOT NULL DEFAULT 0,
    rejected BIGINT NOT NULL DEFAULT 0,
    timeout BIGINT NOT NULL DEFAULT 0,
    error BIGINT NOT NULL DEFAULT 0,
    total BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    night_start TIME NOT NULL,
    night_end TIME NOT NULL,
    key_attribute VARCHAR(255) NOT NULL,
    if_enabled BOOLEAN NOT NULL DEFAULT TRUE
);


CREATE TABLE blocked_macs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    mac_address VARCHAR(17),
    reason TEXT,
    blocked_at DATETIME,
    INDEX idx_blocked_macs_mac (mac_address)
);

CREATE TABLE time_restrictions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64),
    start_time TIME,
    end_time TIME
);

-- Expenses (billing/operations)
CREATE TABLE IF NOT EXISTS expenses (
    id INT NOT NULL AUTO_INCREMENT,
    title VARCHAR(128) NOT NULL,
    category VARCHAR(64) NULL,
    amount FLOAT NOT NULL,
    currency VARCHAR(8) NOT NULL DEFAULT 'USD',
    expenseDate DATE NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'unpaid',
    notes TEXT NULL,
    createdBy VARCHAR(64) NULL,
    updatedBy VARCHAR(64) NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deletedAt DATETIME NULL,
    PRIMARY KEY (id),
    INDEX idx_expenses_expenseDate (expenseDate),
    INDEX idx_expenses_status (status),
    INDEX idx_expenses_category (category),
    INDEX idx_expenses_deletedAt (deletedAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE detailed_usage (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64),
    mac_address VARCHAR(17),
    bytes_in BIGINT,
    bytes_out BIGINT,
    session_time INT,
    nas_ip VARCHAR(15),
    timestamp DATETIME
);

-- Per-interim usage snapshots for exact rolling-window usage checks
CREATE TABLE session_usage_snapshots (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    nas_ip VARCHAR(15),
    framed_ip VARCHAR(15),
    acct_status ENUM('start', 'interim', 'stop') NOT NULL,
    bytes_in_total BIGINT NOT NULL DEFAULT 0,
    bytes_out_total BIGINT NOT NULL DEFAULT 0,
    delta_bytes_in BIGINT NOT NULL DEFAULT 0,
    delta_bytes_out BIGINT NOT NULL DEFAULT 0,
    delta_total BIGINT NOT NULL DEFAULT 0,
    snapshot_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_sus_user_time (username, snapshot_at),
    INDEX idx_sus_session_time (session_id, snapshot_at),
    INDEX idx_sus_nas_time (nas_ip, snapshot_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE session_tracking (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    mac_address VARCHAR(17) NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME,
    last_update DATETIME,
    nas_ip VARCHAR(15),
    framed_ip VARCHAR(15),
    bytes_in BIGINT DEFAULT 0,
    bytes_out BIGINT DEFAULT 0,
    session_time INT DEFAULT 0,
    daily_bytes_in BIGINT DEFAULT 0,
    daily_bytes_out BIGINT DEFAULT 0,
    daily_session_time INT DEFAULT 0,
    status ENUM('active', 'completed', 'terminated') NOT NULL,
    INDEX idx_username (username),
    INDEX idx_session (session_id),
    INDEX idx_status (status)
);

-- Default profile mapping (used for restoring profile after reset/upgrades)
CREATE TABLE IF NOT EXISTS user_default_profiles (
    username VARCHAR(64) NOT NULL,
    default_profile_id INT NOT NULL,
    PRIMARY KEY (username),
    INDEX idx_udp_default_profile_id (default_profile_id),
    CONSTRAINT fk_udp_profile FOREIGN KEY (default_profile_id) REFERENCES radprofile(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS nas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nasname VARCHAR(128) NOT NULL,
    shortname VARCHAR(32),
    type VARCHAR(30) DEFAULT 'other',
    ports INT,
    secret VARCHAR(60) NOT NULL,
    server VARCHAR(64),
    community VARCHAR(50),
    description VARCHAR(200),
    INDEX nasname_index (nasname)
);

-- Create quota logs table
CREATE TABLE quota_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    event_type VARCHAR(20) NOT NULL,
    quota_type VARCHAR(10) NOT NULL,
    timestamp DATETIME NOT NULL,
    INDEX idx_username (username),
    INDEX idx_timestamp (timestamp)
);

-- Insert Default Profiles
INSERT INTO radprofile (profile_name, daily_quota, monthly_quota, night_start, night_end, speed_down, speed_up)
VALUES 
    ('Basic', 1073741824, 32212254720, '00:00:00', '06:00:00', 1024, 512),
    -- FUP / quota fallback profile (Mikrotik-Rate-Limit will use speed_down/speed_up)
    ('Fallback', 104857600, 3221225472, '00:00:00', '06:00:00', 2048, 2048);

-- Production note:
-- Do NOT create DB users or grant ALL privileges from schema init.
-- Create the application user via your MySQL provisioning (IaC) with least-privilege grants.

-- Add this stored procedure
DELIMITER //

CREATE PROCEDURE sp_handle_quota_exceeded(
    IN p_username VARCHAR(64),
    IN p_quota_type VARCHAR(10)
)
BEGIN
    DECLARE v_fallback_profile_id INT;
    DECLARE v_current_profile_id INT;

    SELECT id INTO v_fallback_profile_id
    FROM radprofile
    WHERE profile_name = 'Fallback'
    LIMIT 1;

    SELECT profile_id INTO v_current_profile_id
    FROM raduserprofile
    WHERE username = p_username
    LIMIT 1;

    -- Save the user's normal profile for later restore (avoid overwriting with fallback)
    IF v_current_profile_id IS NOT NULL AND (v_fallback_profile_id IS NULL OR v_current_profile_id <> v_fallback_profile_id) THEN
        INSERT INTO user_default_profiles (username, default_profile_id)
        VALUES (p_username, v_current_profile_id)
        ON DUPLICATE KEY UPDATE default_profile_id = VALUES(default_profile_id);
    END IF;

    -- Update profile to fallback and set the correct flag (daily vs monthly)
    UPDATE raduserprofile
    SET profile_id = v_fallback_profile_id,
        is_monthly_exceeded = IF(LOWER(p_quota_type) = 'monthly', 1, is_monthly_exceeded),
        is_fallback = IF(LOWER(p_quota_type) = 'daily', 1, is_fallback)
    WHERE username = p_username;
    
    -- Log the event
    INSERT INTO quota_logs (username, event_type, quota_type, timestamp) 
    VALUES (p_username, 'exceeded', p_quota_type, NOW());
END //

DELIMITER ;

-- Add after your existing tables
CREATE TABLE radacct (
    radacctid BIGINT PRIMARY KEY AUTO_INCREMENT,
    acctsessionid VARCHAR(64) NOT NULL,
    acctuniqueid VARCHAR(32) NOT NULL,
    username VARCHAR(64) NOT NULL,
    realm VARCHAR(64),
    nasipaddress VARCHAR(15) NOT NULL,
    nasportid VARCHAR(32),
    nasporttype VARCHAR(32),
    acctstarttime DATETIME,
    acctupdatetime DATETIME,
    acctstoptime DATETIME,
    acctinterval INT,
    acctsessiontime INT UNSIGNED,
    acctauthentic VARCHAR(32),
    connectinfo_start VARCHAR(50),
    connectinfo_stop VARCHAR(50),
    acctinputoctets BIGINT,
    acctoutputoctets BIGINT,
    calledstationid VARCHAR(50),
    callingstationid VARCHAR(50),
    acctterminatecause VARCHAR(32),
    servicetype VARCHAR(32),
    framedprotocol VARCHAR(32),
    framedipaddress VARCHAR(15),
    framedipv6address VARCHAR(45),
    framedipv6prefix VARCHAR(45),
    framedinterfaceid VARCHAR(44),
    delegatedipv6prefix VARCHAR(45),
    INDEX username_index (username),
    INDEX framedipaddress_index (framedipaddress),
    INDEX acctsessionid_index (acctsessionid),
    INDEX acctuniqueid_index (acctuniqueid),
    INDEX acctstarttime_index (acctstarttime),
    INDEX acctstoptime_index (acctstoptime),
    INDEX nasipaddress_index (nasipaddress)
) ENGINE = INNODB;

CREATE TABLE system_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(64) NOT NULL UNIQUE,
  email VARCHAR(128) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL, -- store a securely hashed password (e.g., bcrypt)
  role ENUM('admin', 'manager', 'support') DEFAULT 'support', -- define roles as needed
  is_active BOOLEAN DEFAULT TRUE, -- to enable/disable accounts
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login TIMESTAMP NULL DEFAULT NULL
) ENGINE = INNODB;


CREATE TABLE `logs` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `level` VARCHAR(255) NOT NULL,
  `message` VARCHAR(255) NOT NULL,
  `meta` JSON DEFAULT NULL,
  `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE refresh_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    token VARCHAR(255) NOT NULL,
    user_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES system_users(id)
);

CREATE TABLE `invoices` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_profile_id` INT NOT NULL,
  `user_details_id` INT NOT NULL,
  `billing_month` DATE NOT NULL,
  `amount` FLOAT NOT NULL,
  `status` VARCHAR(10) NOT NULL DEFAULT 'unpaid',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `paid_at` TIMESTAMP NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  KEY `idx_user_profile_id` (`user_profile_id`),
  KEY `idx_user_details_id` (`user_details_id`),

  CONSTRAINT `fk_invoice_user_profile`
    FOREIGN KEY (`user_profile_id`) REFERENCES `raduserprofile` (`id`)
    ON DELETE CASCADE
    ON UPDATE NO ACTION,

  CONSTRAINT `fk_invoice_user_details`
    FOREIGN KEY (`user_details_id`) REFERENCES `user_details` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `external_invoices` (
  `id`            INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  `username`      VARCHAR(64)      NOT NULL,
  `fullName`     VARCHAR(128)     NOT NULL,
  `email`         VARCHAR(128)         NULL,
  `phoneNumber`  VARCHAR(32)      NOT NULL,
  `address`       TEXT                 NULL,
  `provider`      VARCHAR(10)      NOT NULL DEFAULT '',
  `billingMonth` DATE            NOT NULL,
  `amount`        FLOAT           NOT NULL,
  `status`        VARCHAR(10)     NOT NULL DEFAULT 'unpaid',
  `createdAt`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `paidAt`       TIMESTAMP            NULL DEFAULT NULL,
  `modifiedBy`   VARCHAR(64)          NULL,
  `modifiedAt`   TIMESTAMP            NULL
                       DEFAULT CURRENT_TIMESTAMP
                       ON UPDATE CURRENT_TIMESTAMP,
  `deletedAt`    TIMESTAMP            NULL,
  `deletedBy`    VARCHAR(64)          NULL,
  `lastAction`   VARCHAR(255)         NULL,
  PRIMARY KEY (`id`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

  CREATE TABLE `modification_logs` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `invoice_id`  INT   NULL,               -- FK to external_invoices.id
  `username`    VARCHAR(64)  NOT NULL,
  `action`      VARCHAR(255) NOT NULL,
  `timestamp`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `changes`     JSON              NULL,

  PRIMARY KEY (`id`),

  CONSTRAINT `fk_modlog_invoice`
    FOREIGN KEY (`invoice_id`)
    REFERENCES `external_invoices` (`id`)
    ON UPDATE CASCADE
    ON DELETE SET NULL
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;





-- Replace the WHERE clause indexes with regular indexes
CREATE INDEX radacct_active_session_idx ON radacct (username, acctstarttime, acctstoptime);

CREATE INDEX radacct_bulk_close ON radacct (nasipaddress, acctstarttime, acctstoptime);