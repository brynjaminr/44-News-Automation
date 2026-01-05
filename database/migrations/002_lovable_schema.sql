-- 44 News Automation - Lovable Dashboard Schema
-- Migration: 002_lovable_schema
-- Purpose: Schema for user-managed sources (replaces Google Sheets)

-- ============================================================================
-- SOURCES TABLE
-- User-managed news sources (replaces Google Sheets)
-- ============================================================================
CREATE TABLE IF NOT EXISTS sources (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- Supabase auth user ID

    -- Source details
    name VARCHAR(255) NOT NULL,
    url TEXT NOT NULL,
    genre VARCHAR(100) NOT NULL,

    -- Status
    is_active BOOLEAN DEFAULT true,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- USER_SETTINGS TABLE
-- Per-user configuration (matches Base44 Settings page)
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE, -- Supabase auth user ID

    -- Delivery Settings
    recipient_email VARCHAR(255) NOT NULL,
    send_time TIME DEFAULT '07:00:00',
    timezone VARCHAR(50) DEFAULT 'Europe/London',

    -- Article Limits
    max_per_source INTEGER DEFAULT 15,
    max_total_articles INTEGER DEFAULT 200,
    skip_empty_digests BOOLEAN DEFAULT false,

    -- Email Content
    email_greeting TEXT DEFAULT 'Good morning! Here''s your daily 44 Automation news digest.',
    email_footer TEXT DEFAULT 'Please stay tuned for tomorrow''s instalment to stay informed. Have a great day!',

    -- Tone & Style
    summary_tone VARCHAR(50) DEFAULT 'Professional', -- Professional, Casual, Formal
    why_matters_focus VARCHAR(50) DEFAULT 'Business Focus', -- Business Focus, Industry Trends, Consumer Impact

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- DIGESTS TABLE
-- History of sent digests
-- ============================================================================
CREATE TABLE IF NOT EXISTS digests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,

    -- Digest details
    article_count INTEGER DEFAULT 0,
    source_count INTEGER DEFAULT 0,

    -- Status
    status VARCHAR(20) DEFAULT 'pending', -- pending, processing, sent, failed
    sent_at TIMESTAMPTZ,
    error_message TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- ARTICLES TABLE
-- Processed articles for each digest
-- ============================================================================
CREATE TABLE IF NOT EXISTS articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    digest_id UUID REFERENCES digests(id) ON DELETE CASCADE,
    source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
    user_id UUID NOT NULL,

    -- Article details
    url TEXT NOT NULL,
    headline TEXT NOT NULL,
    source_name VARCHAR(255),
    genre VARCHAR(100) NOT NULL,

    -- AI-generated content
    summary TEXT,
    why_matters TEXT,

    -- Metadata
    published_at TIMESTAMPTZ,
    extracted_at TIMESTAMPTZ DEFAULT NOW(),

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_sources_user ON sources(user_id);
CREATE INDEX IF NOT EXISTS idx_sources_active ON sources(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_sources_genre ON sources(genre);

CREATE INDEX IF NOT EXISTS idx_user_settings_user ON user_settings(user_id);

CREATE INDEX IF NOT EXISTS idx_digests_user ON digests(user_id);
CREATE INDEX IF NOT EXISTS idx_digests_sent ON digests(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_digests_status ON digests(status);

CREATE INDEX IF NOT EXISTS idx_articles_digest ON articles(digest_id);
CREATE INDEX IF NOT EXISTS idx_articles_user ON articles(user_id);
CREATE INDEX IF NOT EXISTS idx_articles_genre ON articles(genre);

-- ============================================================================
-- ROW LEVEL SECURITY (for Supabase)
-- ============================================================================
ALTER TABLE sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE digests ENABLE ROW LEVEL SECURITY;
ALTER TABLE articles ENABLE ROW LEVEL SECURITY;

-- Sources policies
CREATE POLICY "Users can view own sources" ON sources
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sources" ON sources
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sources" ON sources
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own sources" ON sources
    FOR DELETE USING (auth.uid() = user_id);

-- User settings policies
CREATE POLICY "Users can view own settings" ON user_settings
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own settings" ON user_settings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own settings" ON user_settings
    FOR UPDATE USING (auth.uid() = user_id);

-- Digests policies
CREATE POLICY "Users can view own digests" ON digests
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own digests" ON digests
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Articles policies
CREATE POLICY "Users can view own articles" ON articles
    FOR SELECT USING (auth.uid() = user_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
CREATE TRIGGER update_sources_updated_at
    BEFORE UPDATE ON sources
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_settings_updated_at
    BEFORE UPDATE ON user_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Dashboard stats view
CREATE OR REPLACE VIEW dashboard_stats AS
SELECT
    user_id,
    (SELECT COUNT(*) FROM sources WHERE sources.user_id = s.user_id AND is_active = true) as active_sources,
    (SELECT COUNT(*) FROM sources WHERE sources.user_id = s.user_id) as total_sources,
    (SELECT article_count FROM digests WHERE digests.user_id = s.user_id AND status = 'sent' ORDER BY sent_at DESC LIMIT 1) as last_digest_articles,
    (SELECT COUNT(*) FROM digests WHERE digests.user_id = s.user_id AND status = 'sent') as total_digests
FROM (SELECT DISTINCT user_id FROM sources) s;

-- Recent activity view
CREATE OR REPLACE VIEW recent_activity AS
SELECT
    id,
    user_id,
    article_count,
    source_count,
    status,
    sent_at,
    created_at
FROM digests
WHERE status = 'sent'
ORDER BY sent_at DESC
LIMIT 10;
