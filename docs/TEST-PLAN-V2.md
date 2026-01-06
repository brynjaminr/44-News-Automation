# 44 News Automation - Test Plan V2

## Overview

This document defines the comprehensive test plan for the 44 News Automation system, including acceptance criteria, test cases, and expected outputs.

---

## Test Environment Setup

### Prerequisites

1. **PostgreSQL Database**
   - Create database: `news_automation_test`
   - Run migration: `003_enhanced_schema_v2.sql`
   - Insert test client record

2. **n8n Instance**
   - Import workflow JSON
   - Configure credentials:
     - PostgreSQL connection
     - Google Sheets OAuth
     - OpenAI API key
     - IONOS SMTP

3. **Google Sheet**
   - Create test sheet with columns: URL, Genre
   - Add sample homepage URLs

4. **Environment Variables**
   ```bash
   DATABASE_URL=postgresql://user:pass@localhost:5432/news_automation_test
   SMTP_HOST=smtp.ionos.co.uk
   SMTP_PORT=587
   SMTP_USER=news@44automationltd.com
   SMTP_PASS=***
   SMTP_FROM=news@44automationltd.com
   OPENAI_API_KEY=sk-***
   ADMIN_ALERT_EMAIL=admin@44automationltd.com
   ```

---

## Test Categories

### 1. Input Validation Tests

#### TC-IV-001: Valid Genre Acceptance
**Description**: System accepts rows with valid genres from the 26-item list.

**Steps**:
1. Add row: `https://www.finextra.com/ | Financial`
2. Run workflow

**Expected**: Row processed, no validation error logged.

**Acceptance Criteria**:
- [ ] Row appears in discovery queue
- [ ] Genre stored correctly as "Financial"

---

#### TC-IV-002: Invalid Genre Rejection
**Description**: System rejects rows with genres not in the allowed list.

**Steps**:
1. Add row: `https://example.com/ | InvalidGenre`
2. Run workflow

**Expected**: Row skipped, error logged.

**Acceptance Criteria**:
- [ ] Error logged with reason "Invalid genre: InvalidGenre"
- [ ] Row not processed further
- [ ] Run continues with other rows

---

#### TC-IV-003: Missing URL Handling
**Description**: System handles rows with missing URLs.

**Steps**:
1. Add row: ` | Financial` (empty URL)
2. Run workflow

**Expected**: Row skipped, error logged.

**Acceptance Criteria**:
- [ ] Error logged with reason "Missing URL"
- [ ] Run continues with other rows

---

#### TC-IV-004: Missing Genre Handling
**Description**: System handles rows with missing genres.

**Steps**:
1. Add row: `https://example.com/ |` (empty genre)
2. Run workflow

**Expected**: Row skipped, error logged.

**Acceptance Criteria**:
- [ ] Error logged with reason "Missing genre"
- [ ] Run continues with other rows

---

#### TC-IV-005: All 26 Genres Accepted
**Description**: System accepts all 26 valid genres.

**Steps**:
1. Add one row for each of the 26 genres
2. Run workflow

**Expected**: All 26 rows processed.

**Acceptance Criteria**:
- [ ] 26 homepages fetched
- [ ] No genre validation errors

---

### 2. Homepage Discovery Tests

#### TC-HD-001: Link Extraction from Homepage
**Description**: System extracts article-like links from homepage HTML.

**Steps**:
1. Add row: `https://www.bbc.com/news | Media & Publishing`
2. Run workflow

**Expected**: Multiple article candidate URLs discovered.

**Acceptance Criteria**:
- [ ] At least 5 article candidates found
- [ ] All candidates are same-domain
- [ ] No excluded paths (/tag/, /author/, etc.)

---

#### TC-HD-002: Date Pattern Recognition
**Description**: System identifies URLs with date patterns as article-like.

**Steps**:
1. Provide homepage with links like `/2026/01/06/article-slug`
2. Run extraction

**Expected**: Date-pattern URLs scored higher.

**Acceptance Criteria**:
- [ ] URLs with date patterns have article_score >= 3
- [ ] Date extracted from URL as fallback

---

#### TC-HD-003: Excluded Path Filtering
**Description**: System excludes non-article paths.

**Steps**:
1. Provide homepage with links including:
   - `/tag/finance/`
   - `/author/john-doe/`
   - `/about/`
   - `/login/`
   - `/subscribe/`

**Expected**: All excluded paths filtered out.

**Acceptance Criteria**:
- [ ] Zero candidates from excluded paths
- [ ] Filter applies to all exclusion patterns

---

#### TC-HD-004: File Extension Filtering
**Description**: System excludes file links (PDF, images, etc.).

**Steps**:
1. Provide homepage with links to:
   - `report.pdf`
   - `image.jpg`
   - `download.zip`

**Expected**: All file links excluded.

**Acceptance Criteria**:
- [ ] Zero PDF/image/zip candidates

---

#### TC-HD-005: Tracking Parameter Removal
**Description**: System strips UTM and other tracking params.

**Steps**:
1. Provide links with tracking params:
   - `article?utm_source=homepage&utm_medium=web`
   - `article?fbclid=abc123`

**Expected**: Clean URLs without tracking params.

**Acceptance Criteria**:
- [ ] utm_* params removed
- [ ] fbclid, gclid params removed
- [ ] URLs deduplicated after cleaning

---

#### TC-HD-006: Zero Candidates Warning
**Description**: System logs warning when no candidates found.

**Steps**:
1. Provide homepage with only non-article content
2. Run extraction

**Expected**: Warning logged, run continues.

**Acceptance Criteria**:
- [ ] Warning logged: "No article candidates found from [URL]"
- [ ] No error thrown
- [ ] Run continues to next homepage

---

### 3. Article Processing Tests

#### TC-AP-001: Publish Date - JSON-LD Extraction
**Description**: System extracts date from JSON-LD structured data.

**Steps**:
1. Provide article with JSON-LD containing `datePublished`
2. Run extraction

**Expected**: Date extracted with confidence 0.95.

**Acceptance Criteria**:
- [ ] publish_date matches JSON-LD value
- [ ] publish_date_source = "jsonld_published"
- [ ] publish_date_confidence = 0.95

---

#### TC-AP-002: Publish Date - OpenGraph Extraction
**Description**: System extracts date from OpenGraph meta tag.

**Steps**:
1. Provide article with `<meta property="article:published_time">`
2. No JSON-LD present

**Expected**: Date extracted with confidence 0.90.

**Acceptance Criteria**:
- [ ] Date extracted from og:article:published_time
- [ ] publish_date_source = "opengraph"
- [ ] publish_date_confidence = 0.90

---

#### TC-AP-003: Publish Date - Meta Tag Extraction
**Description**: System extracts date from meta tags.

**Steps**:
1. Provide article with `<meta name="pubdate">` or `<meta name="DC.date">`
2. No JSON-LD or OpenGraph

**Expected**: Date extracted with confidence 0.80.

**Acceptance Criteria**:
- [ ] Date extracted from meta tag
- [ ] publish_date_source = "meta"
- [ ] publish_date_confidence = 0.80

---

#### TC-AP-004: Publish Date - Time Element Extraction
**Description**: System extracts date from `<time>` elements.

**Steps**:
1. Provide article with `<time datetime="2026-01-06T10:30:00Z">`
2. No higher-priority sources

**Expected**: Date extracted with confidence 0.70.

**Acceptance Criteria**:
- [ ] Date extracted from time element
- [ ] publish_date_source = "time_element"
- [ ] publish_date_confidence = 0.70

---

#### TC-AP-005: Publish Date - URL Pattern Extraction
**Description**: System extracts date from URL path as last resort.

**Steps**:
1. Provide article at `/2026/01/06/article-slug`
2. No other date sources

**Expected**: Date extracted with confidence 0.50.

**Acceptance Criteria**:
- [ ] Date extracted as 2026-01-06
- [ ] publish_date_source = "url_pattern"
- [ ] publish_date_confidence = 0.50

---

#### TC-AP-006: Unknown Publish Date - Mandatory Skip
**Description**: System MUST skip articles with unknown publish date.

**Steps**:
1. Provide article with no detectable publish date
2. Run processing

**Expected**: Article skipped with specific reason.

**Acceptance Criteria**:
- [ ] Article not stored in stories table
- [ ] Error logged: "Unknown publish date - MANDATORY SKIP"
- [ ] Skip reason recorded

---

### 4. Time Window Tests

#### TC-TW-001: Article Within 24h Window - Accepted
**Description**: Article published within window is accepted.

**Steps**:
1. Provide article published 12 hours ago
2. Run processing

**Expected**: Article accepted, stored.

**Acceptance Criteria**:
- [ ] Article stored in stories table
- [ ] No window-related skip

---

#### TC-TW-002: Article Before Window - Rejected
**Description**: Article published before window start is rejected.

**Steps**:
1. Provide article published 30 hours ago
2. Run processing

**Expected**: Article skipped.

**Acceptance Criteria**:
- [ ] Error logged: "Outside 24h window"
- [ ] Article not stored

---

#### TC-TW-003: Article After Window - Rejected
**Description**: Article with future date is rejected.

**Steps**:
1. Provide article with publish date tomorrow
2. Run processing

**Expected**: Article skipped.

**Acceptance Criteria**:
- [ ] Error logged: "Outside 24h window"
- [ ] Article not stored

---

#### TC-TW-004: Window Boundary - 07:00 UK
**Description**: Window ends exactly at 07:00 UK time.

**Steps**:
1. Run at 08:00 UK
2. Provide articles:
   - Published 06:59 yesterday UK - should accept
   - Published 07:01 yesterday UK - should accept
   - Published 06:59 two days ago - should reject

**Expected**: Correct boundary enforcement.

**Acceptance Criteria**:
- [ ] Window calculated correctly
- [ ] Boundary respected to the minute

---

### 5. Deduplication Tests

#### TC-DD-001: URL Duplicate Detection
**Description**: Duplicate URLs are detected and merged.

**Steps**:
1. Provide same article URL from two different homepages
2. Run processing

**Expected**: Only one story stored.

**Acceptance Criteria**:
- [ ] Single record in stories table
- [ ] Higher-confidence extraction kept

---

#### TC-DD-002: Title Similarity Detection
**Description**: Articles with very similar titles detected as duplicates.

**Steps**:
1. Provide two articles:
   - Title 1: "Markets rally on positive economic data"
   - Title 2: "Markets rally on positive economic data today"
2. Run processing

**Expected**: Detected as duplicates.

**Acceptance Criteria**:
- [ ] Title normalization applied
- [ ] Similarity threshold triggered
- [ ] One article kept

---

#### TC-DD-003: Content Fingerprint Detection
**Description**: Articles with identical content detected.

**Steps**:
1. Provide two URLs with identical article body
2. Run processing

**Expected**: Detected as duplicates.

**Acceptance Criteria**:
- [ ] Content fingerprint matches
- [ ] One article kept

---

### 6. Paywall Detection Tests

#### TC-PW-001: Paywall CSS Class Detection
**Description**: System detects paywall indicators.

**Steps**:
1. Provide article with `.paywall` class
2. Run processing

**Expected**: Article skipped.

**Acceptance Criteria**:
- [ ] Skip reason: "Paywalled or blocked"
- [ ] Article not stored

---

#### TC-PW-002: Short Content Detection
**Description**: System detects blocked content by length.

**Steps**:
1. Provide article with < 300 chars extracted
2. Run processing

**Expected**: Article skipped as likely paywalled.

**Acceptance Criteria**:
- [ ] Content length check applied
- [ ] Article skipped

---

### 7. LLM Processing Tests

#### TC-LLM-001: Title Polish
**Description**: LLM generates polished, factual title.

**Steps**:
1. Provide article with sensationalist title
2. Run LLM processing

**Expected**: Polished, professional title.

**Acceptance Criteria**:
- [ ] Title factually accurate
- [ ] No sensationalism
- [ ] Readable length

---

#### TC-LLM-002: Summary Generation
**Description**: LLM generates 3-6 sentence summary.

**Steps**:
1. Provide article
2. Run LLM processing

**Expected**: Concise, factual summary.

**Acceptance Criteria**:
- [ ] 3-6 sentences
- [ ] Factual content
- [ ] No invented facts

---

#### TC-LLM-003: Why Matters Generation
**Description**: LLM generates agency-focused analysis.

**Steps**:
1. Provide article
2. Run LLM processing

**Expected**: Max 3 sentences with marketing implication.

**Acceptance Criteria**:
- [ ] Max 3 sentences
- [ ] Agency/marketing focus
- [ ] One practical implication
- [ ] No invented facts

---

#### TC-LLM-004: Relevance Score
**Description**: LLM assigns agency relevance score 1-5.

**Steps**:
1. Provide articles of varying relevance
2. Run LLM processing

**Expected**: Appropriate scores assigned.

**Acceptance Criteria**:
- [ ] Score between 1-5
- [ ] Higher scores for more relevant content
- [ ] Consistent scoring

---

### 8. Capping Tests

#### TC-CAP-001: Genre Cap Enforcement
**Description**: Max 6 stories per genre enforced.

**Steps**:
1. Discover 10 articles in "Financial" genre
2. Run ranking and capping

**Expected**: Only 6 stored for Financial.

**Acceptance Criteria**:
- [ ] Exactly 6 Financial stories
- [ ] Top 6 by relevance score
- [ ] Others not stored

---

#### TC-CAP-002: Daily Cap Enforcement
**Description**: Max 60 stories per day enforced.

**Steps**:
1. Discover 80 articles across genres
2. Run ranking and capping

**Expected**: Only 60 stored total.

**Acceptance Criteria**:
- [ ] Exactly 60 stories max
- [ ] Genre caps still apply
- [ ] Best articles kept

---

#### TC-CAP-003: Top Signals Selection
**Description**: Top 5 stories marked as top signals.

**Steps**:
1. Store 30 articles
2. Run ranking

**Expected**: 5 marked as is_top_signal.

**Acceptance Criteria**:
- [ ] Exactly 5 with is_top_signal = true
- [ ] Highest relevance scores
- [ ] From any genre

---

### 9. Email Tests

#### TC-EM-001: Email Generation - With Stories
**Description**: Email generated with stories.

**Steps**:
1. Complete run with 20 stories
2. Generate email

**Expected**: HTML email with all sections.

**Acceptance Criteria**:
- [ ] Top Signals section present
- [ ] All genres with stories included
- [ ] Genre headers with correct colors
- [ ] Story cards complete

---

#### TC-EM-002: Email Generation - No Stories
**Description**: Email generated for no-news day.

**Steps**:
1. Complete run with 0 stories
2. Generate email

**Expected**: No-news variant email.

**Acceptance Criteria**:
- [ ] No-news message displayed
- [ ] Variant rotates by day
- [ ] Professional tone

---

#### TC-EM-003: Email Delivery - IONOS SMTP
**Description**: Email sent via IONOS SMTP.

**Steps**:
1. Generate email
2. Send via SMTP

**Expected**: Email delivered.

**Acceptance Criteria**:
- [ ] Email received by recipients
- [ ] From address correct
- [ ] Subject line correct
- [ ] HTML renders properly

---

#### TC-EM-004: Mobile Responsive Email
**Description**: Email renders on mobile devices.

**Steps**:
1. View email on iPhone/Android

**Expected**: Readable, properly formatted.

**Acceptance Criteria**:
- [ ] Single column layout
- [ ] Readable text size
- [ ] Touch-friendly links

---

### 10. Database Tests

#### TC-DB-001: Story Upsert Idempotency
**Description**: Re-running doesn't create duplicates.

**Steps**:
1. Run workflow
2. Run workflow again same day

**Expected**: Same stories, updated timestamps.

**Acceptance Criteria**:
- [ ] No duplicate dedupe_keys
- [ ] Updated_at changed on re-run
- [ ] Counts remain same

---

#### TC-DB-002: Run Record Creation
**Description**: Run record tracks execution.

**Steps**:
1. Start workflow
2. Check runs table during execution
3. Check after completion

**Expected**: Status transitions recorded.

**Acceptance Criteria**:
- [ ] Status: pending → running → completed
- [ ] started_at and completed_at set
- [ ] Counts updated

---

#### TC-DB-003: Error Logging
**Description**: Errors logged to errors table.

**Steps**:
1. Introduce error condition
2. Check errors table

**Expected**: Error record created.

**Acceptance Criteria**:
- [ ] Error type recorded
- [ ] Error message clear
- [ ] Stage identified

---

### 11. Multi-Client Tests

#### TC-MC-001: Client Isolation
**Description**: Client data is isolated.

**Steps**:
1. Create two clients
2. Run for both
3. Query stories for each

**Expected**: Stories isolated by client_id.

**Acceptance Criteria**:
- [ ] No cross-client data
- [ ] Correct client_id on all records

---

#### TC-MC-002: Client-Specific Settings
**Description**: Each client uses own settings.

**Steps**:
1. Client A: max 30/day
2. Client B: max 60/day
3. Run for both

**Expected**: Caps applied per client.

**Acceptance Criteria**:
- [ ] Client A has max 30
- [ ] Client B has max 60

---

---

## Acceptance Criteria Summary

### Must Pass (Blocking)

- [ ] All 26 genres accepted
- [ ] Invalid genres rejected with logging
- [ ] Homepage discovery finds article links
- [ ] Excluded paths filtered
- [ ] All 5 publish date extraction tiers work
- [ ] Unknown publish date = mandatory skip
- [ ] 24h window enforced (07:00 to 07:00 UK)
- [ ] Deduplication prevents duplicates
- [ ] Paywall detection skips blocked content
- [ ] LLM generates quality content
- [ ] LLM does NOT classify genres
- [ ] 6/genre cap enforced
- [ ] 60/day cap enforced
- [ ] Top 5 signals identified
- [ ] Email sent via IONOS SMTP
- [ ] No-news email variant rotation
- [ ] Database records created correctly
- [ ] Multi-client isolation

### Should Pass (Important)

- [ ] Pagination support
- [ ] Coverage safeguard logs warnings
- [ ] Admin alerts on failure
- [ ] Mobile responsive email
- [ ] Dashboard displays all stories

---

## Sample Output

### Sample Story Record

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "client_id": "client-uuid-here",
  "run_id": "run-uuid-here",
  "original_url": "https://www.finextra.com/newsarticle/12345",
  "canonical_url": "https://www.finextra.com/newsarticle/12345/digital-banking-trends-2026",
  "genre": "Financial",
  "source_name": "Finextra",
  "original_title": "BREAKING: New Digital Banking Trends Emerge for 2026!!!",
  "polished_title": "Digital Banking Trends for 2026: Key Developments",
  "summary": "Major financial institutions are accelerating their digital transformation initiatives heading into 2026. New research indicates a 40% increase in mobile banking adoption among consumers aged 25-44. Banks are investing heavily in AI-powered customer service and fraud detection systems. The shift toward open banking APIs continues to reshape competitive dynamics in the sector.",
  "why_matters": "Marketing agencies should note the growing importance of digital-first messaging in financial services campaigns. Banks seeking agency partners will prioritize those with demonstrated expertise in fintech positioning and digital customer journey optimization.",
  "published_at": "2026-01-06T08:30:00Z",
  "publish_date_source": "jsonld_published",
  "publish_date_confidence": 0.95,
  "agency_relevance_score": 4,
  "dedupe_key": "a1b2c3d4e5f6789012345678901234567890123456789012345678901234",
  "word_count": 1247,
  "genre_rank": 1,
  "overall_rank": 3,
  "is_top_signal": true,
  "created_at": "2026-01-06T07:15:23Z"
}
```

### Sample Email Output (HTML Structure)

```
44 News Automation
Morning Brief — Monday, 6 January 2026

★ TOP SIGNALS
• Digital Banking Trends for 2026: Key Developments
• Retail Sector Adapts to New Consumer Behaviors
• Healthcare Marketing Shifts to Patient-Centric Approach
• Entertainment Industry Embraces AI Content Creation
• Travel Recovery Accelerates in European Markets

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FINANCIAL (#15803d header)

┌─────────────────────────────────────────┐
│ Digital Banking Trends for 2026        │
│ Finextra                               │
│                                        │
│ Major financial institutions are...    │
│                                        │
│ ┌─────────────────────────────────┐   │
│ │ Why this matters: Marketing     │   │
│ │ agencies should note...         │   │
│ └─────────────────────────────────┘   │
└─────────────────────────────────────────┘

[More stories...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HEALTHCARE (#059669 header)

[Stories...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Footer: Automated by 44 News Automation
```

### Sample Run Record

```json
{
  "id": "run-uuid-here",
  "client_id": "client-uuid",
  "run_date": "2026-01-06",
  "run_number": 1,
  "status": "completed",
  "started_at": "2026-01-06T07:00:05Z",
  "completed_at": "2026-01-06T07:12:34Z",
  "homepages_processed": 45,
  "homepages_failed": 2,
  "candidates_discovered": 312,
  "urls_processed": 287,
  "urls_skipped": 241,
  "stories_created": 46,
  "stories_deduplicated": 8,
  "error_count": 15,
  "email_sent": true,
  "email_sent_at": "2026-01-06T07:12:30Z"
}
```

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | | | |
| Tech Lead | | | |
| QA Lead | | | |
| Client Representative | | | |
