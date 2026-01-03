# 44 News Automation - Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           44 NEWS AUTOMATION                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────────────────────────────────────────┐  │
│  │ Google Sheet │───▶│                 N8N WORKFLOW                      │  │
│  │  (URLs +     │    │  ┌─────────┐  ┌──────────┐  ┌─────────────────┐  │  │
│  │   Genres)    │    │  │ Cron    │─▶│ Sheet    │─▶│ Article Fetcher │  │  │
│  └──────────────┘    │  │ 07:00UK │  │ Reader   │  │ (Concurrency=5) │  │  │
│                      │  └─────────┘  └──────────┘  └────────┬────────┘  │  │
│                      │                                      │           │  │
│                      │  ┌─────────────────────────────────────────────┐ │  │
│                      │  │ Content Pipeline:                           │ │  │
│                      │  │  1. Readability Extraction                  │ │  │
│                      │  │  2. Publish Date Detection (JSON-LD/Meta)   │ │  │
│                      │  │  3. 24h Window Validation                   │ │  │
│                      │  │  4. Deduplication (URL + Title + Content)   │ │  │
│                      │  │  5. LLM Processing (Title/Summary/WhyMatters│ │  │
│                      │  │  6. Ranking (Agency Relevance + Recency)    │ │  │
│                      │  │  7. Cap Enforcement (60/day, 6/genre)       │ │  │
│                      │  └─────────────────────────────────────────────┘ │  │
│                      │                      │                           │  │
│                      │         ┌────────────┴────────────┐              │  │
│                      │         ▼                         ▼              │  │
│                      │  ┌─────────────┐          ┌─────────────┐        │  │
│                      │  │ Postgres    │          │ IONOS SMTP  │        │  │
│                      │  │ Write       │          │ Email Send  │        │  │
│                      │  └─────────────┘          └─────────────┘        │  │
│                      └──────────────────────────────────────────────────┘  │
│                                    │                                       │
│                                    ▼                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         POSTGRESQL DATABASE                           │  │
│  │  ┌─────────┐  ┌──────┐  ┌─────────┐  ┌────────┐  ┌──────────────┐   │  │
│  │  │ clients │  │ runs │  │ stories │  │ errors │  │ email_logs   │   │  │
│  │  └─────────┘  └──────┘  └─────────┘  └────────┘  └──────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                    │                                       │
│                                    ▼                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                       LOVABLE DASHBOARD                               │  │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────────┐ │  │
│  │  │ Today View    │  │ Archive View  │  │ Search/Filter             │ │  │
│  │  │ (By Genre)    │  │ (Calendar)    │  │ (Genre/Source/Date)       │ │  │
│  │  └───────────────┘  └───────────────┘  └───────────────────────────┘ │  │
│  │  ┌───────────────┐  ┌───────────────────────────────────────────────┐│  │
│  │  │ Story Detail  │  │ Admin (Clients/Recipients/Settings)          ││  │
│  │  └───────────────┘  └───────────────────────────────────────────────┘│  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow (Daily Run)

```
07:00 UK ─────────────────────────────────────────────────────────────────────▶

1. TRIGGER          2. INPUT           3. FETCH           4. VALIDATE
   Cron fires ─────▶ Read Sheet ─────▶ HTTP GET ─────────▶ Check publish
   at 07:00 UK       URLs + Genres     each URL            date in 24h
                     (max 200 rows)    (5 concurrent)      window

                                                               │
                    ┌──────────────────────────────────────────┘
                    ▼
5. EXTRACT         6. DEDUPE          7. LLM              8. RANK
   Readability ───▶ By URL, title,   ────▶ Polish title  ────▶ Score by
   extraction       content hash          Summary (3-6)       agency
   + metadata                             Why matters (3)     relevance

                                                               │
                    ┌──────────────────────────────────────────┘
                    ▼
9. CAP             10. STORE          11. EMAIL           12. COMPLETE
   6/genre ───────▶ Write to   ──────▶ Send via  ────────▶ Update run
   60/day max       Postgres           IONOS SMTP          status

```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | Postgres connection string | `postgresql://user:pass@host:5432/news` |
| `SMTP_HOST` | IONOS SMTP server | `smtp.ionos.co.uk` |
| `SMTP_PORT` | SMTP port | `587` |
| `SMTP_USER` | SMTP username | `news@44automationltd.com` |
| `SMTP_PASS` | SMTP password | `***` |
| `SMTP_FROM` | From address | `news@44automationltd.com` |
| `OPENAI_API_KEY` | For LLM processing | `sk-***` |
| `ADMIN_ALERT_EMAIL` | Alert recipient | `admin@44automationltd.com` |
| `GOOGLE_SHEETS_CREDENTIALS` | Service account JSON | `{...}` |

## Key Design Decisions

### Multi-Client Architecture
- All tables include `client_id` foreign key
- Each client has own Google Sheet, recipients, branding
- Dashboard includes client selector dropdown
- Same n8n workflow handles all clients (loop over active clients)

### Deduplication Strategy
1. **Canonical URL match**: Exact match after normalization
2. **Title similarity**: Levenshtein distance < 0.15 on normalized titles
3. **Content fingerprint**: SimHash on article body text

### Publish Date Extraction (Priority Order)
1. JSON-LD `datePublished` / `dateModified`
2. OpenGraph `article:published_time`
3. Meta tags (`pubdate`, `date`, `DC.date`)
4. `<time>` elements with `datetime` attribute
5. URL path date patterns (`/2026/01/03/`)
6. **SKIP if none found** (never guess)

### Rate Limiting & Concurrency
- Max 5 concurrent HTTP requests
- 1 second delay between batches
- 30 second timeout per request
- 3 retries with exponential backoff (2s, 4s, 8s)

### Idempotency
- Each run creates unique `run_id` based on `client_id + date`
- Stories keyed by `client_id + run_id + dedupe_key`
- Re-runs update existing records, don't create duplicates

## Branding Constants

| Property | Value |
|----------|-------|
| Product Name | 44 News Automation |
| Primary Text Color | `#003d96` |
| Background Color | `#f3feff` |
| Genre Colors | See `genre-colors.json` |
