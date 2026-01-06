# 44 News Automation - Production Architecture V2

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           44 NEWS AUTOMATION - V2 ARCHITECTURE                       │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   INPUT                    DISCOVERY                  PROCESSING         OUTPUT      │
│   ─────                    ─────────                  ──────────         ──────      │
│                                                                                      │
│  ┌────────────┐       ┌─────────────────────────────────────────────────────────┐   │
│  │ Google     │       │          HOMEPAGE DISCOVERY PIPELINE                     │   │
│  │ Sheet      │──────▶│  ┌─────────┐  ┌────────────┐  ┌──────────────────────┐  │   │
│  │ ─────────  │       │  │ Fetch   │  │ Link       │  │ Article Candidate    │  │   │
│  │ URL|Genre  │       │  │ Homepage│─▶│ Extraction │─▶│ Heuristics           │  │   │
│  │ (homepages)│       │  │ HTML    │  │ (all <a>)  │  │ (path/slug/OG check) │  │   │
│  └────────────┘       │  └─────────┘  └────────────┘  └──────────────────────┘  │   │
│                       │       │                               │                  │   │
│                       │       ▼                               ▼                  │   │
│                       │  ┌─────────────────────────────────────────────────────┐│   │
│                       │  │ PAGINATION SUPPORT                                   ││   │
│                       │  │ • /page/2, ?page=2                                  ││   │
│                       │  │ • Load-more detection                               ││   │
│                       │  │ • Max 3 pages per source                            ││   │
│                       │  │ • Stop if articles outside window                   ││   │
│                       │  └─────────────────────────────────────────────────────┘│   │
│                       └─────────────────────────────────────────────────────────┘   │
│                                           │                                          │
│                                           ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────────────────┐   │
│  │                    ARTICLE PROCESSING PIPELINE                                │   │
│  │  ┌───────────────┐  ┌───────────────────┐  ┌─────────────────────────────┐   │   │
│  │  │ Fetch Article │  │ Extract Content   │  │ Publish Date Validation     │   │   │
│  │  │ (full page)   │─▶│ • Readability     │─▶│ • JSON-LD (0.95 conf)       │   │   │
│  │  │               │  │ • JSON-LD         │  │ • OpenGraph (0.90)          │   │   │
│  │  │               │  │ • OpenGraph       │  │ • Meta tags (0.80)          │   │   │
│  │  │               │  │ • Canonical URL   │  │ • <time> (0.70)             │   │   │
│  │  └───────────────┘  └───────────────────┘  │ • URL pattern (0.50)        │   │   │
│  │                                             │ • Unknown → SKIP           │   │   │
│  │                                             └─────────────────────────────┘   │   │
│  │                           │                                                   │   │
│  │                           ▼                                                   │   │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐ │   │
│  │  │ 24-HOUR WINDOW VALIDATION (07:00 UK → 07:00 UK)                         │ │   │
│  │  │ • Calculate window based on current time                                 │ │   │
│  │  │ • Outside window → SKIP                                                  │ │   │
│  │  │ • Unknown date → SKIP (MANDATORY)                                        │ │   │
│  │  └─────────────────────────────────────────────────────────────────────────┘ │   │
│  │                           │                                                   │   │
│  │                           ▼                                                   │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │ Paywall      │  │ Dedupe       │  │ LLM Process │  │ Rank & Cap      │   │   │
│  │  │ Detection    │─▶│ • URL hash   │─▶│ • Title     │─▶│ • 6/genre max   │   │   │
│  │  │ (skip if     │  │ • Title sim  │  │ • Summary   │  │ • 60/day max    │   │   │
│  │  │ blocked)     │  │ • Content fp │  │ • WhyMatters│  │ • Top 5 signals │   │   │
│  │  └──────────────┘  └──────────────┘  │ • Score 1-5 │  └─────────────────┘   │   │
│  │                                       └─────────────┘                         │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                           │                                          │
│                                           ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────────────────┐   │
│  │                              OUTPUT LAYER                                     │   │
│  │                                                                               │   │
│  │  ┌────────────────────┐           ┌────────────────────────────────────────┐ │   │
│  │  │ POSTGRESQL         │           │ EMAIL (07:00 UK)                       │ │   │
│  │  │ ──────────────     │           │ ────────────────                       │ │   │
│  │  │ • clients          │           │ • Top Signals (5)                      │ │   │
│  │  │ • sources          │           │ • Genre sections (color-coded)         │ │   │
│  │  │ • runs             │           │ • Mobile-friendly HTML                 │ │   │
│  │  │ • discovered_urls  │           │ • No-news variant (7 rotating)         │ │   │
│  │  │ • stories          │           │ • IONOS SMTP                           │ │   │
│  │  │ • errors           │           └────────────────────────────────────────┘ │   │
│  │  │ • email_logs       │                                                      │   │
│  │  └────────────────────┘           ┌────────────────────────────────────────┐ │   │
│  │                                    │ LOVABLE DASHBOARD                      │ │   │
│  │                                    │ ──────────────────                     │ │   │
│  │                                    │ • Today view (by genre)                │ │   │
│  │                                    │ • Archive (30+ days)                   │ │   │
│  │                                    │ • Search/Filter                        │ │   │
│  │                                    │ • Admin (clients, recipients)          │ │   │
│  │                                    └────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Sequence

```
07:00 UK DAILY TRIGGER
═══════════════════════════════════════════════════════════════════════════════════════

PHASE 1: INITIALIZATION
───────────────────────
   Cron (07:00 UK)
         │
         ▼
   ┌─────────────────────┐
   │ Get Active Clients  │──▶ SELECT * FROM clients WHERE is_active = true
   └─────────────────────┘
         │
         ▼
   ┌─────────────────────┐
   │ Create Run Record   │──▶ INSERT INTO runs (client_id, run_date, status='running')
   └─────────────────────┘
         │
         ▼
   ┌─────────────────────┐
   │ Read Google Sheet   │──▶ Columns A (URL) and B (Genre)
   └─────────────────────┘
         │
         ▼
   ┌─────────────────────┐
   │ Validate Genres     │──▶ Check against 26 allowed genres
   └─────────────────────┘    Invalid → skip + log error


PHASE 2: HOMEPAGE DISCOVERY (CRITICAL - NO RSS)
───────────────────────────────────────────────
   For each (homepage_url, genre) from sheet:
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ FETCH HOMEPAGE                                                   │
   │ • User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)...      │
   │ • Timeout: 30s                                                   │
   │ • Follow redirects: max 5                                        │
   │ • If JS-rendered: fall back to headless render                   │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ EXTRACT ALL LINKS                                                │
   │ • All <a href="..."> elements                                    │
   │ • Surrounding text context                                       │
   │ • Visible timestamps near links                                  │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ CANDIDATE FILTERING (Rule-based, NO LLM)                         │
   │                                                                  │
   │ KEEP if:                                                         │
   │   ✓ Same domain as homepage                                      │
   │   ✓ Not excluded path:                                           │
   │     /tag/, /author/, /about/, /login/, /subscribe/,              │
   │     /privacy/, /jobs/, /contact/, /terms/, /careers/,            │
   │     /sitemap/, /search/, /category/                              │
   │   ✓ Not a file: .pdf, .jpg, .png, .gif, .zip, .doc               │
   │   ✓ Tracking params removed: utm_*, fbclid, gclid                │
   │                                                                  │
   │ Mark as ARTICLE-LIKE if:                                         │
   │   • URL contains date pattern: /2026/01/06/ or /2026-01-06/      │
   │   • Path depth >= 2 AND slug length > 20 chars                   │
   │   • OpenGraph og:type = "article"                                │
   │   • JSON-LD @type = "NewsArticle" or "Article"                   │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ LISTING PAGE TIMESTAMP (Fast Pre-filter)                         │
   │ • Extract timestamps near links if visible                       │
   │ • If timestamp < 24h window start → skip early                   │
   │ • If no timestamp → mark as low confidence, continue             │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ PAGINATION (MANDATORY)                                           │
   │                                                                  │
   │ Detect pagination patterns:                                      │
   │   • /page/2, /page/3                                             │
   │   • ?page=2, ?page=3                                             │
   │   • ?p=2, ?offset=20                                             │
   │   • "Load More" button (headless click)                          │
   │   • Infinite scroll (headless scroll)                            │
   │                                                                  │
   │ Settings:                                                        │
   │   • Max pages per source: 3 (configurable)                       │
   │   • Stop early if articles fall outside 24h window               │
   │   • Stop if 0 new candidates found                               │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   Output: List of article candidate URLs with genre inherited


PHASE 3: ARTICLE PROCESSING
───────────────────────────
   For each discovered article URL (concurrency: 5):
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ FETCH ARTICLE PAGE                                               │
   │ • Full HTML fetch                                                │
   │ • Timeout: 30s                                                   │
   │ • Retries: 3 with exponential backoff (2s, 4s, 8s)              │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ PAYWALL / BLOCK DETECTION                                        │
   │                                                                  │
   │ Skip if:                                                         │
   │   • .paywall, .subscription-required, [data-paywall]            │
   │   • .premium-content, .subscriber-only                          │
   │   • Article body < 300 characters                                │
   │   • HTTP 402, 403, or requires login                            │
   │                                                                  │
   │ Log reason and continue to next article.                         │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ CONTENT EXTRACTION                                               │
   │                                                                  │
   │ Extract:                                                         │
   │   • Canonical URL: <link rel="canonical"> or og:url              │
   │   • Title: og:title > meta title > <title> > h1                  │
   │   • Source name: og:site_name > meta application-name > domain   │
   │   • Article body: Readability-like extraction                    │
   │     - article, [itemprop="articleBody"], .article-body           │
   │     - .article-content, .post-content, .entry-content            │
   │     - main, .content, concatenated <p> tags                      │
   │   • Word count                                                   │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ PUBLISH DATE EXTRACTION (Tiered Confidence)                      │
   │                                                                  │
   │ Priority order:                                                  │
   │   1. JSON-LD datePublished (conf: 0.95)                         │
   │   2. JSON-LD dateModified (conf: 0.85)                          │
   │   3. OpenGraph article:published_time (conf: 0.90)              │
   │   4. Meta tags: pubdate, date, DC.date (conf: 0.80)             │
   │   5. <time datetime="..."> (conf: 0.70)                         │
   │   6. URL date pattern /YYYY/MM/DD/ (conf: 0.50)                 │
   │   7. UNKNOWN → MANDATORY SKIP                                    │
   │                                                                  │
   │ Parse to UTC, validate format, store source + confidence.        │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ 24-HOUR WINDOW VALIDATION                                        │
   │                                                                  │
   │ Window calculation:                                              │
   │   • End: 07:00 today UK (or 07:00 yesterday if before 7am)      │
   │   • Start: 24 hours before end                                   │
   │                                                                  │
   │ Article must be: start <= published_at <= end                    │
   │   • Outside window → SKIP                                        │
   │   • Unknown date → SKIP (already handled above)                  │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ DEDUPLICATION                                                    │
   │                                                                  │
   │ Check in order:                                                  │
   │   1. Canonical URL hash (SHA256, 64 chars)                      │
   │   2. Title normalized similarity (Levenshtein < 0.15)           │
   │   3. Content fingerprint (SimHash of first 1000 chars)          │
   │                                                                  │
   │ If duplicate: keep extraction with higher confidence date.       │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ LLM PROCESSING (OpenAI GPT-4o-mini)                             │
   │                                                                  │
   │ Input: genre (from sheet), original_title, source_name,         │
   │        article_body (truncated to 4000 chars)                   │
   │                                                                  │
   │ LLM generates (JSON response, temp=0.3):                        │
   │   • polished_title: Faithful, factual, no sensationalism        │
   │   • summary: 3-6 sentences, factual, concise                    │
   │   • why_matters: Max 3 sentences, formal, agency-focused,       │
   │                  1 marketing implication, no invented facts     │
   │   • agency_relevance_score: 1-5                                 │
   │                                                                  │
   │ LLM is NEVER used for:                                          │
   │   ✗ Genre classification (genre from sheet only)                │
   │   ✗ Link discovery                                              │
   │   ✗ Date extraction                                             │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ RANKING & CAPPING                                                │
   │                                                                  │
   │ Sort by:                                                         │
   │   1. agency_relevance_score (desc)                              │
   │   2. published_at (desc, newer first)                           │
   │                                                                  │
   │ Apply caps:                                                      │
   │   • Max 6 stories per genre                                     │
   │   • Max 60 stories per day total                                │
   │                                                                  │
   │ Mark top 5 as is_top_signal = true for email header.            │
   └─────────────────────────────────────────────────────────────────┘


PHASE 4: OUTPUT
───────────────
   ┌─────────────────────────────────────────────────────────────────┐
   │ POSTGRES STORAGE                                                 │
   │                                                                  │
   │ INSERT stories with:                                             │
   │   • Upsert on (client_id, run_id, dedupe_key)                   │
   │   • All extracted fields                                         │
   │   • Ranking fields (genre_rank, overall_rank, is_top_signal)    │
   │                                                                  │
   │ UPDATE runs with:                                                │
   │   • stories_created count                                        │
   │   • error_count                                                  │
   │   • status = 'completed'                                        │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ EMAIL GENERATION                                                 │
   │                                                                  │
   │ If stories > 0:                                                  │
   │   • Top Signals section (top 5 by relevance)                    │
   │   • Genre sections sorted alphabetically                         │
   │   • Each story: title link, source, summary, why_matters         │
   │   • Genre headers with distinct colors                           │
   │                                                                  │
   │ If stories == 0:                                                 │
   │   • "No qualifying stories" message                             │
   │   • Rotate 7 variants based on day of year                      │
   │   • Progressive wording for repeated no-news days               │
   │                                                                  │
   │ Send via IONOS SMTP to client recipients.                       │
   └─────────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │ ADMIN ALERTS (on failure)                                        │
   │                                                                  │
   │ If any critical error:                                           │
   │   • Send alert to ADMIN_ALERT_EMAIL                             │
   │   • Include client name, run_id, error details                  │
   │   • Update run status = 'failed'                                │
   └─────────────────────────────────────────────────────────────────┘


COVERAGE SAFEGUARD
──────────────────
If homepage yields 0 article candidates:
   1. Retry with relaxed heuristics
   2. Check for JavaScript rendering → use headless
   3. Check for alternative pagination
   4. If still 0 → log as "no qualifying stories from [source]"
   5. Continue to next homepage
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | Postgres connection string | `postgresql://user:pass@host:5432/news_automation` |
| `SMTP_HOST` | IONOS SMTP server | `smtp.ionos.co.uk` |
| `SMTP_PORT` | SMTP port (TLS) | `587` |
| `SMTP_USER` | SMTP username | `news@44automationltd.com` |
| `SMTP_PASS` | SMTP password | `***` |
| `SMTP_FROM` | From address | `news@44automationltd.com` |
| `OPENAI_API_KEY` | OpenAI API key for LLM | `sk-***` |
| `ADMIN_ALERT_EMAIL` | Alert recipient on failures | `admin@44automationltd.com` |
| `GOOGLE_SHEETS_CREDENTIALS` | Service account JSON | `{...}` |
| `MAX_PAGES_PER_SOURCE` | Pagination depth | `3` |
| `CONCURRENCY_LIMIT` | Parallel HTTP requests | `5` |
| `REQUEST_TIMEOUT_MS` | HTTP timeout | `30000` |

## Configuration (No Code Changes Required)

All caps and limits are configurable per client in the `clients` table:
- `max_stories_per_day` (default: 60)
- `max_stories_per_genre` (default: 6)
- `max_pages_per_source` (default: 3)
- `concurrency_limit` (default: 5)
- `request_timeout_ms` (default: 30000)

## Multi-Client Architecture

- All tables include `client_id` foreign key
- Each client has:
  - Own Google Sheet
  - Own recipients list
  - Own scheduling preferences
  - Own caps/limits
- Same n8n workflow processes all active clients sequentially
- Dashboard includes client selector
- Data is fully isolated per client

## Key Design Decisions

### 1. Homepage Discovery (Not Article-Direct)
The Google Sheet URLs are **homepages/section pages**, not article URLs. The system MUST discover articles from these pages using link extraction, heuristics, and pagination. This is critical for complete coverage.

### 2. No RSS Feeds
RSS is explicitly forbidden. Discovery uses direct HTML parsing with:
- Standard HTTP fetching
- Headless rendering fallback for JS sites
- Multi-page pagination support

### 3. Genre from Sheet Only
Genre is assigned in the Google Sheet column B. The LLM is NEVER used for genre classification. Invalid genres are skipped with error logging.

### 4. Strict Date Requirements
- Unknown publish date = mandatory skip
- Outside 24-hour window = skip
- Multiple extraction methods with confidence scoring
- Window is 07:00 UK to 07:00 UK (rolling)

### 5. Deduplication Strategy
Three-tier deduplication:
1. Canonical URL hash (exact match)
2. Normalized title similarity (Levenshtein)
3. Content fingerprint (first 1000 chars)

### 6. Rate Limiting
- 5 concurrent HTTP requests
- 30 second timeout
- 3 retries with exponential backoff
- 1 second delay between batches

### 7. Idempotent Reruns
- Unique `run_id` per (client_id, run_date, run_number)
- Upsert on duplicate key
- Safe to rerun without creating duplicates

## Branding

| Property | Value |
|----------|-------|
| Product Name | 44 News Automation |
| Primary Text Color | `#003d96` |
| Background Color | `#f3feff` |
| Genre Colors | See `config/genre-colors.json` |
