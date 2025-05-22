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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- User-Profile Mapping
CREATE TABLE raduserprofile (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    profile_id INT NOT NULL,
    is_fallback TINYINT(1) DEFAULT 0,
    is_monthly_exceeded TINYINT(1) DEFAULT 0,
    quota_reset_day INT DEFAULT 1,
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'inactive', 'suspended')),
    FOREIGN KEY (profile_id) REFERENCES radprofile(id),
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

ALTER TABLE radusagestats
    ADD COLUMN last_input BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN last_output BIGINT NOT NULL DEFAULT 0;
    
ALTER TABLE radusagestats
  ADD COLUMN session_start_input BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN session_start_output BIGINT NOT NULL DEFAULT 0;


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
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

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
    blocked_at DATETIME
);

CREATE TABLE time_restrictions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64),
    start_time TIME,
    end_time TIME
);

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
    status ENUM('active', 'completed', 'terminated') NOT NULL,
    INDEX idx_username (username),
    INDEX idx_session (session_id),
    INDEX idx_status (status)
);

ALTER TABLE session_tracking 
ADD COLUMN daily_bytes_in BIGINT DEFAULT 0,
ADD COLUMN daily_bytes_out BIGINT DEFAULT 0,
ADD COLUMN daily_session_time INT DEFAULT 0;

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
    ('Fallback', 104857600, 3221225472, '00:00:00', '06:00:00', 256, 128);

-- Create Radius User
CREATE USER IF NOT EXISTS 'radius'@'%' IDENTIFIED BY 'radiuspassword';
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'%';
FLUSH PRIVILEGES;

-- Add this stored procedure
DELIMITER //

CREATE PROCEDURE sp_handle_quota_exceeded(
    IN p_username VARCHAR(64),
    IN p_quota_type VARCHAR(10)
)
BEGIN
    -- Update profile to fallback
    UPDATE raduserprofile 
    SET profile_id = (SELECT id FROM radprofile WHERE profile_name = 'Fallback'),
        is_monthly_exceeded = 1 
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