-- Database Schema for Inspection Platform
-- RDS MySQL 8.0

CREATE DATABASE IF NOT EXISTS inspection_platform;
USE inspection_platform;

-- Inspections table
CREATE TABLE inspections (
    inspection_id VARCHAR(20) PRIMARY KEY,
    property_address VARCHAR(500) NOT NULL,
    inspector_name VARCHAR(255) NOT NULL,
    inspector_email VARCHAR(255) NOT NULL,
    client_name VARCHAR(255) DEFAULT '',
    client_email VARCHAR(255) DEFAULT '',
    status ENUM('DRAFT', 'SUBMITTED', 'REPORT_GENERATED') DEFAULT 'DRAFT',
    
    -- Checklist fields (nullable until filled)
    checklist_roof ENUM('Good', 'Fair', 'Poor') DEFAULT NULL,
    checklist_foundation ENUM('Good', 'Fair', 'Poor') DEFAULT NULL,
    checklist_plumbing ENUM('Good', 'Fair', 'Poor') DEFAULT NULL,
    checklist_electrical ENUM('Good', 'Fair', 'Poor') DEFAULT NULL,
    checklist_hvac ENUM('Good', 'Fair', 'Poor') DEFAULT NULL,
    
    notes TEXT DEFAULT '',
    
    report_generated_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Indexes for common queries
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    INDEX idx_status_created (status, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Images table (one-to-many relationship with inspections)
CREATE TABLE inspection_images (
    image_id VARCHAR(20) PRIMARY KEY,
    inspection_id VARCHAR(20) NOT NULL,
    s3_key VARCHAR(500) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    content_type VARCHAR(100) DEFAULT 'image/jpeg',
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (inspection_id) REFERENCES inspections(inspection_id) ON DELETE CASCADE,
    INDEX idx_inspection_id (inspection_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- View for easy querying with image count
CREATE VIEW inspection_summary AS
SELECT 
    i.*,
    COUNT(img.image_id) as total_images
FROM inspections i
LEFT JOIN inspection_images img ON i.inspection_id = img.inspection_id
GROUP BY i.inspection_id;