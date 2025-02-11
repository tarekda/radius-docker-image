CREATE DATABASE radius;
USE radius;

-- Profiles (quotas, speed, free night)
CREATE TABLE radprofile (
    id INT PRIMARY KEY AUTO_INCREMENT,
    profile_name VARCHAR(64) NOT NULL,
    daily_quota BIGINT NOT NULL,
    night_start TIME,
    night_end TIME,
    speed_down INT DEFAULT 0,
    speed_up INT DEFAULT 0
);

-- User-Profile Mapping
CREATE TABLE raduserprofile (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    profile_id INT NOT NULL,
    is_fallback TINYINT(1) DEFAULT 0,
    FOREIGN KEY (profile_id) REFERENCES radprofile(id)
);

-- Usage Tracking
CREATE TABLE radusagestats (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    day DATE NOT NULL,
    usage BIGINT NOT NULL DEFAULT 0,
    UNIQUE KEY (username, day)
);

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
    username VARCHAR(64) PRIMARY KEY,
    mac_address VARCHAR(17) NOT NULL UNIQUE,
    FOREIGN KEY (username) REFERENCES radcheck(username)
);

-- Base RADIUS table (for authentication)
CREATE TABLE radcheck (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    attribute VARCHAR(64) NOT NULL,
    op VARCHAR(2) NOT NULL DEFAULT ':=',
    value VARCHAR(253) NOT NULL
);

-- Insert Default Profiles
INSERT INTO radprofile (profile_name, daily_quota, night_start, night_end, speed_down, speed_up)
VALUES 
    ('Basic', 1073741824, '00:00:00', '06:00:00', 1024, 512),
    ('Fallback', 104857600, '00:00:00', '06:00:00', 256, 128);

-- Create Radius User
CREATE USER 'radius'@'%' IDENTIFIED BY 'radiuspassword';
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'%';
FLUSH PRIVILEGES;