-- 44 News Automation - Enhanced Schema V2
-- Migration: 003_enhanced_schema_v2
-- Purpose: Add homepage discovery tracking, sources table, and enhanced multi-client support
-- Created: 2026-01-06

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- CLIENTS TABLE (Enhanced)
-- Multi-tenant client configuration with full customization
-- ============================================================================
DROP TABLE IF EXISTS clients CASCADE;
CREATE TABLE clients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,

    -- Branding
    primary_color VARCHAR(7) DEFAULT '#003d96',
    background_color VARCHAR(7) DEFAULT '#f3feff',
    logo_url TEXT,

    -- Timezone & Scheduling
    timezone VARCHAR(50) DEFAULT 'Europe/London',
    send_time TIME DEFAULT '07:00:00',

    -- Google Sheet Configuration
    sheet_id VARCHAR(255) NOT NULL,
    sheet_url TEXT,
    sheet_range VARCHAR(50) DEFAULT 'A:B',

    -- Recipients (JSON array of email addresses)
    recipients JSONB DEFAULT '[]'::jsonb,

    -- Caps Configuration
    max_stories_per_day INTEGER DEFAULT 60 CHECK (max_stories_per_day > 0 AND max_stories_per_day <= 100),
    max_stories_per_genre INTEGER DEFAULT 6 CHECK (max_stories_per_genre > 0 AND max_stories_per_genre <= 20),
    max_pages_per_source INTEGER DEFAULT 3 CHECK (max_pages_per_source > 0 AND max_pages_per_source <= 10),

    -- Concurrency & Timeouts
    concurrency_limit INTEGER DEFAULT 5 CHECK (concurrency_limit > 0 AND concurrency_limit <= 20),
    request_timeout_ms INTEGER DEFAULT 30000 CHECK (request_timeout_ms >= 5000 AND request_timeout_ms <= 120000),

    -- Status
    is_active BOOLEAN DEFAULT true,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- SOURCES TABLE
-- Track homepage/section URLs from Google Sheet per client
-- ============================================================================
CREATE TABLE sources (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,

    -- Source identification
    homepage_url TEXT NOT NULL,
    genre VARCHAR(100) NOT NULL,

    -- Metadata extracted from source
    source_name VARCHAR(255),
    favicon_url TEXT,

    -- Discovery stats
    last_checked_at TIMESTAMPTZ,
    articles_discovered_count INTEGER DEFAULT 0,
    articles_published_count INTEGER DEFAULT 0,
    consecutive_failures INTEGER DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT true,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(client_id, homepage_url)
);

-- ============================================================================
-- GENRES TABLE
-- Reference table for valid genres with colors
-- ============================================================================
DROP TABLE IF EXISTS genres CASCADE;
CREATE TABLE genres (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    color VARCHAR(7) NOT NULL,
    text_color VARCHAR(7) DEFAULT '#ffffff',
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert all 26 valid genres with their colors
INSERT INTO genres (name, color, text_color, display_order) VALUES
    ('Office Equipment & Technology', '#2563eb', '#ffffff', 1),
    ('Food & Drink', '#dc2626', '#ffffff', 2),
    ('Telecommunications & Internet', '#7c3aed', '#ffffff', 3),
    ('Healthcare', '#059669', '#ffffff', 4),
    ('Education', '#0891b2', '#ffffff', 5),
    ('Tobacco & E-cigarettes', '#57534e', '#ffffff', 6),
    ('Charity & Nonprofit', '#db2777', '#ffffff', 7),
    ('Fashion', '#c026d3', '#ffffff', 8),
    ('Retail', '#ea580c', '#ffffff', 9),
    ('Professional & Business Services', '#4f46e5', '#ffffff', 10),
    ('Property & Construction', '#ca8a04', '#ffffff', 11),
    ('Agencies', '#0d9488', '#ffffff', 12),
    ('Entertainment', '#e11d48', '#ffffff', 13),
    ('Transportation & Logistics', '#1d4ed8', '#ffffff', 14),
    ('Consumer Electronics', '#6366f1', '#ffffff', 15),
    ('Travel & Tourism', '#0284c7', '#ffffff', 16),
    ('Financial', '#15803d', '#ffffff', 17),
    ('Utilities & Energy', '#a16207', '#ffffff', 18),
    ('Leisure & Hospitality', '#be185d', '#ffffff', 19),
    ('Media & Publishing', '#9333ea', '#ffffff', 20),
    ('Government & Public Sector', '#1e40af', '#ffffff', 21),
    ('Cosmetics & Personal Care', '#ec4899', '#ffffff', 22),
    ('Home & Garden', '#65a30d', '#ffffff', 23),
    ('Automotive', '#b91c1c', '#ffffff', 24),
    ('Manufacturing & Industrial', '#475569', '#ffffff', 25),
    ('Household Consumer Goods', '#d97706', '#ffffff', 26)
ON CONFLICT (name) DO UPDATE SET
    color = EXCLUDED.color,
    text_color = EXCLUDED.text_color,
    display_order = EXCLUDED.display_order;

-- ============================================================================
-- RUNS TABLE
-- Track each daily execution per client
-- ============================================================================
DROP TABLE IF EXISTS runs CASCADE;
CREATE TABLE runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,

    -- Run identification
    run_date DATE NOT NULL,
    run_number INTEGER DEFAULT 1,

    -- Timing
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    -- Status: pending, running, completed, failed
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed')),

    -- Discovery stats
    homepages_processed INTEGER DEFAULT 0,
    homepages_failed INTEGER DEFAULT 0,
    candidates_discovered INTEGER DEFAULT 0,

    -- Processing stats
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

    UNIQUE(client_id, run_date, run_number)
);

-- ============================================================================
-- DISCOVERED_URLS TABLE
-- Track URLs discovered from homepage crawling
-- ============================================================================
CREATE TABLE discovered_urls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    source_id UUID REFERENCES sources(id) ON DELETE SET NULL,

    -- Discovery info
    homepage_url TEXT NOT NULL,
    discovered_url TEXT NOT NULL,
    genre VARCHAR(100) NOT NULL,

    -- Heuristics
    article_score INTEGER DEFAULT 0,
    link_text TEXT,
    nearby_timestamp TEXT,

    -- Processing status
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'skipped', 'failed')),
    skip_reason TEXT,

    -- Timestamps
    discovered_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,

    UNIQUE(client_id, run_id, discovered_url)
);

-- ============================================================================
-- STORIES TABLE
-- Processed and published stories
-- ============================================================================
DROP TABLE IF EXISTS stories CASCADE;
CREATE TABLE stories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    source_id UUID REFERENCES sources(id) ON DELETE SET NULL,

    -- Original data
    original_url TEXT NOT NULL,
    genre VARCHAR(100) NOT NULL,

    -- Extracted/normalized data
    canonical_url TEXT NOT NULL,
    source_name VARCHAR(255),

    -- Content
    original_title TEXT,
    polished_title TEXT NOT NULL,
    summary TEXT NOT NULL,
    why_matters TEXT NOT NULL,

    -- Raw content (for debugging)
    article_body TEXT,

    -- Publish date
    published_at TIMESTAMPTZ,
    publish_date_source VARCHAR(50),
    publish_date_confidence DECIMAL(3,2) CHECK (publish_date_confidence >= 0 AND publish_date_confidence <= 1),

    -- LLM scoring
    agency_relevance_score INTEGER CHECK (agency_relevance_score BETWEEN 1 AND 5),

    -- Deduplication
    dedupe_key VARCHAR(64) NOT NULL,
    title_normalized VARCHAR(500),
    content_fingerprint VARCHAR(64),

    -- Extraction metadata
    extracted_at TIMESTAMPTZ DEFAULT NOW(),
    word_count INTEGER,

    -- Ranking
    genre_rank INTEGER,
    overall_rank INTEGER,
    is_top_signal BOOLEAN DEFAULT false,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(client_id, run_id, dedupe_key)
);

-- ============================================================================
-- ERRORS TABLE
-- Detailed error logging
-- ============================================================================
DROP TABLE IF EXISTS errors CASCADE;
CREATE TABLE errors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID REFERENCES runs(id) ON DELETE SET NULL,

    -- What was being processed
    url TEXT,
    genre VARCHAR(100),

    -- Error details
    stage VARCHAR(50) NOT NULL CHECK (stage IN ('validation', 'discovery', 'fetch', 'extract', 'date_validation', 'article_validation', 'llm', 'store', 'email')),
    error_type VARCHAR(100),
    error_message TEXT NOT NULL,
    error_details JSONB,

    -- Retry info
    retry_count INTEGER DEFAULT 0,
    was_resolved BOOLEAN DEFAULT false,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- EMAIL_LOGS TABLE
-- Track all sent emails
-- ============================================================================
DROP TABLE IF EXISTS email_logs CASCADE;
CREATE TABLE email_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    run_id UUID REFERENCES runs(id) ON DELETE SET NULL,

    -- Email details
    subject VARCHAR(500) NOT NULL,
    recipients JSONB NOT NULL,

    -- Content summary
    story_count INTEGER DEFAULT 0,
    top_signals JSONB,
    genres_included JSONB,

    -- Status
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
    sent_at TIMESTAMPTZ,
    error_message TEXT,

    -- No-news handling
    is_no_news_email BOOLEAN DEFAULT false,
    no_news_variant INTEGER CHECK (no_news_variant BETWEEN 1 AND 7),
    consecutive_no_news_days INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Clients
CREATE INDEX idx_clients_slug ON clients(slug);
CREATE INDEX idx_clients_active ON clients(is_active) WHERE is_active = true;

-- Sources
CREATE INDEX idx_sources_client ON sources(client_id);
CREATE INDEX idx_sources_url ON sources(homepage_url);
CREATE INDEX idx_sources_genre ON sources(genre);
CREATE INDEX idx_sources_active ON sources(is_active) WHERE is_active = true;

-- Runs
CREATE INDEX idx_runs_client_date ON runs(client_id, run_date DESC);
CREATE INDEX idx_runs_status ON runs(status);
CREATE INDEX idx_runs_date ON runs(run_date DESC);

-- Discovered URLs
CREATE INDEX idx_discovered_client ON discovered_urls(client_id);
CREATE INDEX idx_discovered_run ON discovered_urls(run_id);
CREATE INDEX idx_discovered_status ON discovered_urls(status);
CREATE INDEX idx_discovered_url ON discovered_urls(discovered_url);

-- Stories
CREATE INDEX idx_stories_client ON stories(client_id);
CREATE INDEX idx_stories_run ON stories(run_id);
CREATE INDEX idx_stories_genre ON stories(genre);
CREATE INDEX idx_stories_canonical ON stories(canonical_url);
CREATE INDEX idx_stories_dedupe ON stories(dedupe_key);
CREATE INDEX idx_stories_published ON stories(published_at DESC);
CREATE INDEX idx_stories_title_trgm ON stories USING gin(title_normalized gin_trgm_ops);
CREATE INDEX idx_stories_top ON stories(is_top_signal) WHERE is_top_signal = true;
CREATE INDEX idx_stories_client_date ON stories(client_id, published_at DESC);

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

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_clients_updated_at BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sources_updated_at BEFORE UPDATE ON sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_runs_updated_at BEFORE UPDATE ON runs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_stories_updated_at BEFORE UPDATE ON stories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Today's stories view
CREATE OR REPLACE VIEW v_today_stories AS
SELECT
    s.*,
    c.name AS client_name,
    c.slug AS client_slug,
    g.color AS genre_color,
    g.text_color AS genre_text_color
FROM stories s
JOIN runs r ON s.run_id = r.id
JOIN clients c ON s.client_id = c.id
LEFT JOIN genres g ON s.genre = g.name
WHERE r.run_date = CURRENT_DATE
  AND r.status = 'completed'
ORDER BY s.genre, s.genre_rank;

-- Run summaries view
CREATE OR REPLACE VIEW v_run_summaries AS
SELECT
    r.*,
    c.name AS client_name,
    c.slug AS client_slug,
    (SELECT COUNT(*) FROM stories WHERE run_id = r.id) AS actual_story_count,
    (SELECT COUNT(*) FROM errors WHERE run_id = r.id) AS actual_error_count,
    (SELECT COUNT(*) FROM discovered_urls WHERE run_id = r.id) AS urls_discovered,
    (SELECT COUNT(*) FROM discovered_urls WHERE run_id = r.id AND status = 'processed') AS urls_processed_count
FROM runs r
JOIN clients c ON r.client_id = c.id
ORDER BY r.started_at DESC;

-- Client dashboard stats view
CREATE OR REPLACE VIEW v_client_stats AS
SELECT
    c.id AS client_id,
    c.name,
    c.slug,
    COUNT(DISTINCT s.id) AS total_sources,
    COUNT(DISTINCT CASE WHEN s.is_active THEN s.id END) AS active_sources,
    (SELECT COUNT(*) FROM runs WHERE client_id = c.id AND status = 'completed') AS total_runs,
    (SELECT COUNT(*) FROM stories WHERE client_id = c.id) AS total_stories,
    (SELECT MAX(run_date) FROM runs WHERE client_id = c.id AND status = 'completed') AS last_run_date,
    (SELECT stories_created FROM runs WHERE client_id = c.id AND status = 'completed' ORDER BY run_date DESC LIMIT 1) AS last_run_stories
FROM clients c
LEFT JOIN sources s ON s.client_id = c.id
WHERE c.is_active = true
GROUP BY c.id, c.name, c.slug;

-- Genre distribution view
CREATE OR REPLACE VIEW v_genre_distribution AS
SELECT
    s.client_id,
    s.genre,
    g.color AS genre_color,
    COUNT(*) AS story_count,
    AVG(s.agency_relevance_score) AS avg_relevance_score,
    MAX(s.published_at) AS latest_story_date
FROM stories s
JOIN genres g ON s.genre = g.name
GROUP BY s.client_id, s.genre, g.color
ORDER BY s.client_id, story_count DESC;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to get stories for a specific date and client
CREATE OR REPLACE FUNCTION get_stories_for_date(
    p_client_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    id UUID,
    genre VARCHAR(100),
    genre_color VARCHAR(7),
    polished_title TEXT,
    summary TEXT,
    why_matters TEXT,
    canonical_url TEXT,
    source_name VARCHAR(255),
    published_at TIMESTAMPTZ,
    agency_relevance_score INTEGER,
    genre_rank INTEGER,
    is_top_signal BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        s.genre,
        g.color AS genre_color,
        s.polished_title,
        s.summary,
        s.why_matters,
        s.canonical_url,
        s.source_name,
        s.published_at,
        s.agency_relevance_score,
        s.genre_rank,
        s.is_top_signal
    FROM stories s
    JOIN runs r ON s.run_id = r.id
    LEFT JOIN genres g ON s.genre = g.name
    WHERE s.client_id = p_client_id
      AND r.run_date = p_date
      AND r.status = 'completed'
    ORDER BY s.genre, s.genre_rank;
END;
$$ LANGUAGE plpgsql;

-- Function to search stories
CREATE OR REPLACE FUNCTION search_stories(
    p_client_id UUID,
    p_search_term TEXT,
    p_genre VARCHAR(100) DEFAULT NULL,
    p_date_from DATE DEFAULT NULL,
    p_date_to DATE DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
    id UUID,
    genre VARCHAR(100),
    genre_color VARCHAR(7),
    polished_title TEXT,
    summary TEXT,
    canonical_url TEXT,
    source_name VARCHAR(255),
    published_at TIMESTAMPTZ,
    relevance REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        s.genre,
        g.color AS genre_color,
        s.polished_title,
        s.summary,
        s.canonical_url,
        s.source_name,
        s.published_at,
        similarity(s.title_normalized, lower(p_search_term)) AS relevance
    FROM stories s
    LEFT JOIN genres g ON s.genre = g.name
    WHERE s.client_id = p_client_id
      AND (p_search_term IS NULL OR s.title_normalized ILIKE '%' || p_search_term || '%'
           OR s.summary ILIKE '%' || p_search_term || '%')
      AND (p_genre IS NULL OR s.genre = p_genre)
      AND (p_date_from IS NULL OR s.published_at >= p_date_from)
      AND (p_date_to IS NULL OR s.published_at <= p_date_to + INTERVAL '1 day')
    ORDER BY
        CASE WHEN p_search_term IS NOT NULL
             THEN similarity(s.title_normalized, lower(p_search_term))
             ELSE 0 END DESC,
        s.published_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SAMPLE DATA (V1 Client)
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
    max_pages_per_source,
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
    3,
    true
) ON CONFLICT (slug) DO UPDATE SET
    updated_at = NOW();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE clients IS 'Multi-tenant client configuration with full customization';
COMMENT ON TABLE sources IS 'Homepage/section URLs from Google Sheet per client';
COMMENT ON TABLE genres IS 'Reference table for the 26 valid genres with colors';
COMMENT ON TABLE runs IS 'Daily automation run tracking per client';
COMMENT ON TABLE discovered_urls IS 'URLs discovered from homepage crawling';
COMMENT ON TABLE stories IS 'Processed and published news stories';
COMMENT ON TABLE errors IS 'Detailed error logging for debugging';
COMMENT ON TABLE email_logs IS 'Track all sent emails';

COMMENT ON COLUMN stories.dedupe_key IS 'SHA256 hash of canonical_url for deduplication';
COMMENT ON COLUMN stories.content_fingerprint IS 'SHA256 hash of first 1000 chars for near-duplicate detection';
COMMENT ON COLUMN stories.publish_date_confidence IS 'Confidence score (0-1) in extracted publish date';
COMMENT ON COLUMN stories.publish_date_source IS 'Source: jsonld_published, jsonld_modified, opengraph, meta, time_element, url_pattern';
COMMENT ON COLUMN runs.run_number IS 'Incremented for re-runs on same day';
COMMENT ON COLUMN email_logs.no_news_variant IS 'Rotating message variant (1-7) for no-news days';
