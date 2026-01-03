-- 44 News Automation - Initial Schema
-- Migration: 001_initial_schema
-- Created: 2026-01-03

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- For fuzzy text matching

-- ============================================================================
-- CLIENTS TABLE
-- Stores client configuration for multi-tenant support
-- ============================================================================
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE, -- URL-safe identifier

    -- Branding
    primary_color VARCHAR(7) DEFAULT '#003d96',
    background_color VARCHAR(7) DEFAULT '#f3feff',
    logo_url TEXT,

    -- Timezone & Scheduling
    timezone VARCHAR(50) DEFAULT 'Europe/London',
    send_time TIME DEFAULT '07:00:00',

    -- Google Sheet Configuration
    sheet_id VARCHAR(255), -- Google Sheet ID
    sheet_url TEXT, -- Full URL for reference
    sheet_range VARCHAR(50) DEFAULT 'A:B', -- Range to read

    -- Recipients (JSON array of email addresses)
    recipients JSONB DEFAULT '[]'::jsonb,

    -- Caps Configuration
    max_stories_per_day INTEGER DEFAULT 60,
    max_stories_per_genre INTEGER DEFAULT 6,

    -- Status
    is_active BOOLEAN DEFAULT true,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- GENRES TABLE
-- Reference table for valid genres
-- ============================================================================
CREATE TABLE genres (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    color VARCHAR(7) NOT NULL, -- Hex color for UI
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert all valid genres with their colors
INSERT INTO genres (name, color, display_order) VALUES
    ('Office Equipment & Technology', '#2563eb', 1),
    ('Food & Drink', '#dc2626', 2),
    ('Telecommunications & Internet', '#7c3aed', 3),
    ('Healthcare', '#059669', 4),
    ('Education', '#0891b2', 5),
    ('Tobacco & E-cigarettes', '#78716c', 6),
    ('Charity & Nonprofit', '#db2777', 7),
    ('Fashion', '#c026d3', 8),
    ('Retail', '#ea580c', 9),
    ('Professional & Business Services', '#4f46e5', 10),
    ('Property & Construction', '#ca8a04', 11),
    ('Agencies', '#0d9488', 12),
    ('Entertainment', '#e11d48', 13),
    ('Transportation & Logistics', '#1d4ed8', 14),
    ('Consumer Electronics', '#6366f1', 15),
    ('Travel & Tourism', '#0284c7', 16),
    ('Financial', '#15803d', 17),
    ('Utilities & Energy', '#a16207', 18),
    ('Leisure & Hospitality', '#be185d', 19),
    ('Media & Publishing', '#9333ea', 20),
    ('Government & Public Sector', '#1e40af', 21),
    ('Cosmetics & Personal Care', '#ec4899', 22),
    ('Home & Garden', '#65a30d', 23),
    ('Automotive', '#b91c1c', 24),
    ('Manufacturing & Industrial', '#64748b', 25),
    ('Household Consumer Goods', '#f59e0b', 26);

-- ============================================================================
-- RUNS TABLE
-- Tracks each daily execution per client
-- ============================================================================
CREATE TABLE runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,

    -- Run identification
    run_date DATE NOT NULL, -- The date this run is for (in client timezone)
    run_number INTEGER DEFAULT 1, -- For re-runs on same day

    -- Timing
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    -- Status: pending, running, completed, failed
    status VARCHAR(20) DEFAULT 'pending',

    -- Counts
    urls_processed INTEGER DEFAULT 0,
    urls_skipped INTEGER DEFAULT 0,
    stories_created INTEGER DEFAULT 0,
    stories_deduplicated INTEGER DEFAULT 0,

    -- Error summary
    error_count INTEGER DEFAULT 0,
    error_summary TEXT,

    -- Email status
    email_sent BOOLEAN DEFAULT false,
    email_sent_at TIMESTAMPTZ,
    email_recipients JSONB,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Ensure one run per client per date (can increment run_number for retries)
    UNIQUE(client_id, run_date, run_number)
);

-- ============================================================================
-- STORIES TABLE
-- Individual processed stories
-- ============================================================================
CREATE TABLE stories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,

    -- Original data from sheet
    original_url TEXT NOT NULL,
    genre VARCHAR(100) NOT NULL,

    -- Extracted/normalized data
    canonical_url TEXT NOT NULL,
    source_name VARCHAR(255), -- Publisher/site name

    -- Content
    original_title TEXT,
    polished_title TEXT NOT NULL,
    summary TEXT NOT NULL, -- 3-6 sentences
    why_matters TEXT NOT NULL, -- Max 3 sentences, agency-focused

    -- Raw extracted content (for reference/debugging)
    article_body TEXT,

    -- Publish date
    published_at TIMESTAMPTZ,
    publish_date_source VARCHAR(50), -- jsonld, opengraph, meta, time_element, url_pattern
    publish_date_confidence DECIMAL(3,2), -- 0.00 to 1.00

    -- LLM scoring
    agency_relevance_score INTEGER CHECK (agency_relevance_score BETWEEN 1 AND 5),

    -- Deduplication
    dedupe_key VARCHAR(64) NOT NULL, -- Hash for deduplication
    title_normalized VARCHAR(500), -- Lowercase, stripped for comparison
    content_fingerprint VARCHAR(64), -- SimHash of content

    -- Extraction metadata
    extracted_at TIMESTAMPTZ DEFAULT NOW(),
    extraction_method VARCHAR(50), -- readability, fallback, etc.
    word_count INTEGER,

    -- For ordering in output
    genre_rank INTEGER, -- Rank within genre (1-6)
    overall_rank INTEGER, -- Rank across all stories
    is_top_signal BOOLEAN DEFAULT false, -- In top 5 for email header

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- ERRORS TABLE
-- Detailed error logging for debugging
-- ============================================================================
CREATE TABLE errors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID REFERENCES runs(id) ON DELETE SET NULL,

    -- What was being processed
    url TEXT,
    genre VARCHAR(100),

    -- Error details
    stage VARCHAR(50) NOT NULL, -- fetch, extract, validate, llm, store, email
    error_type VARCHAR(100),
    error_message TEXT NOT NULL,
    error_details JSONB, -- Stack trace, response codes, etc.

    -- Whether this was retried
    retry_count INTEGER DEFAULT 0,
    was_resolved BOOLEAN DEFAULT false,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- EMAIL_LOGS TABLE
-- Track all emails sent
-- ============================================================================
CREATE TABLE email_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID REFERENCES runs(id) ON DELETE SET NULL,

    -- Email details
    subject VARCHAR(500) NOT NULL,
    recipients JSONB NOT NULL, -- Array of email addresses

    -- Content summary
    story_count INTEGER DEFAULT 0,
    top_signals JSONB, -- Array of top 5 story titles
    genres_included JSONB, -- Array of genres with counts

    -- Status
    status VARCHAR(20) DEFAULT 'pending', -- pending, sent, failed
    sent_at TIMESTAMPTZ,
    error_message TEXT,

    -- For no-news days
    is_no_news_email BOOLEAN DEFAULT false,
    no_news_variant INTEGER, -- 1-7 for rotating messages

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Clients
CREATE INDEX idx_clients_slug ON clients(slug);
CREATE INDEX idx_clients_active ON clients(is_active);

-- Runs
CREATE INDEX idx_runs_client_date ON runs(client_id, run_date DESC);
CREATE INDEX idx_runs_status ON runs(status);
CREATE INDEX idx_runs_date ON runs(run_date DESC);

-- Stories
CREATE INDEX idx_stories_client ON stories(client_id);
CREATE INDEX idx_stories_run ON stories(run_id);
CREATE INDEX idx_stories_genre ON stories(genre);
CREATE INDEX idx_stories_canonical_url ON stories(canonical_url);
CREATE INDEX idx_stories_dedupe_key ON stories(dedupe_key);
CREATE INDEX idx_stories_published ON stories(published_at DESC);
CREATE INDEX idx_stories_title_trgm ON stories USING gin(title_normalized gin_trgm_ops);
CREATE INDEX idx_stories_top_signals ON stories(is_top_signal) WHERE is_top_signal = true;

-- Errors
CREATE INDEX idx_errors_client ON errors(client_id);
CREATE INDEX idx_errors_run ON errors(run_id);
CREATE INDEX idx_errors_stage ON errors(stage);
CREATE INDEX idx_errors_created ON errors(created_at DESC);

-- Email logs
CREATE INDEX idx_email_logs_client ON email_logs(client_id);
CREATE INDEX idx_email_logs_run ON email_logs(run_id);
CREATE INDEX idx_email_logs_status ON email_logs(status);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update updated_at on clients
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_clients_updated_at
    BEFORE UPDATE ON clients
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_runs_updated_at
    BEFORE UPDATE ON runs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_stories_updated_at
    BEFORE UPDATE ON stories
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Today's stories view
CREATE VIEW today_stories AS
SELECT
    s.*,
    c.name as client_name,
    g.color as genre_color
FROM stories s
JOIN runs r ON s.run_id = r.id
JOIN clients c ON s.client_id = c.id
JOIN genres g ON s.genre = g.name
WHERE r.run_date = CURRENT_DATE
ORDER BY s.genre, s.genre_rank;

-- Run summary view
CREATE VIEW run_summaries AS
SELECT
    r.*,
    c.name as client_name,
    (SELECT COUNT(*) FROM stories WHERE run_id = r.id) as actual_story_count,
    (SELECT COUNT(*) FROM errors WHERE run_id = r.id) as actual_error_count
FROM runs r
JOIN clients c ON r.client_id = c.id
ORDER BY r.started_at DESC;

-- ============================================================================
-- SAMPLE CLIENT (for V1)
-- ============================================================================

INSERT INTO clients (
    name,
    slug,
    timezone,
    send_time,
    sheet_id,
    recipients,
    max_stories_per_day,
    max_stories_per_genre,
    is_active
) VALUES (
    '44 Automation Ltd',
    '44-automation',
    'Europe/London',
    '07:00:00',
    'YOUR_GOOGLE_SHEET_ID_HERE',
    '["recipient1@example.com", "recipient2@example.com"]'::jsonb,
    60,
    6,
    true
);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE clients IS 'Multi-tenant client configuration';
COMMENT ON TABLE genres IS 'Reference table for valid genres with colors';
COMMENT ON TABLE runs IS 'Daily automation run tracking per client';
COMMENT ON TABLE stories IS 'Processed news stories with LLM-enhanced content';
COMMENT ON TABLE errors IS 'Detailed error logging for debugging';
COMMENT ON TABLE email_logs IS 'Track all sent emails';

COMMENT ON COLUMN stories.dedupe_key IS 'SHA256 hash of canonical_url for deduplication';
COMMENT ON COLUMN stories.content_fingerprint IS 'SimHash of article body for near-duplicate detection';
COMMENT ON COLUMN stories.publish_date_confidence IS 'Confidence score (0-1) in extracted publish date';
COMMENT ON COLUMN runs.run_number IS 'Incremented for re-runs on same day';
