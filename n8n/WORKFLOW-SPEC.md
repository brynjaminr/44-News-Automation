# 44 News Automation - n8n Workflow Specification

## Overview

The workflow runs daily at 07:00 Europe/London to process news URLs from Google Sheets, extract and validate content, generate LLM-enhanced summaries, store in Postgres, and send morning brief emails.

## Node-by-Node Specification

### 1. Daily 07:00 UK (Schedule Trigger)
**Type:** `n8n-nodes-base.scheduleTrigger`
**Purpose:** Trigger workflow daily at 07:00 UK time

**Settings:**
```json
{
  "rule": {
    "interval": [{
      "triggerAtHour": 7,
      "triggerAtMinute": 0
    }]
  }
}
```
**Timezone:** Workflow settings → Europe/London

---

### 2. Get Active Clients (Postgres)
**Type:** `n8n-nodes-base.postgres`
**Purpose:** Fetch all active clients for processing

**Query:**
```sql
SELECT * FROM clients WHERE is_active = true
```

**Output:** Array of client objects with sheet_id, recipients, caps, etc.

---

### 3. Loop Over Clients (Split In Batches)
**Type:** `n8n-nodes-base.splitInBatches`
**Purpose:** Process each client sequentially

**Settings:**
- Batch Size: 1 (process one client at a time)
- Reset: false

---

### 4. Create Run Record (Postgres)
**Type:** `n8n-nodes-base.postgres`
**Purpose:** Create/update run record for idempotency

**Query:**
```sql
INSERT INTO runs (client_id, run_date, status, started_at)
VALUES ('{{ $json.id }}', CURRENT_DATE, 'running', NOW())
ON CONFLICT (client_id, run_date, run_number)
DO UPDATE SET status = 'running', started_at = NOW()
RETURNING *
```

---

### 5. Read URLs from Sheet (Google Sheets)
**Type:** `n8n-nodes-base.googleSheets`
**Purpose:** Read URLs and Genres from client's Google Sheet

**Settings:**
- Operation: read
- Sheet ID: `={{ $('Loop Over Clients').item.json.sheet_id }}`
- Range: A:B (Column A = URL, Column B = Genre)
- Options: headerRow = 1

**Expected columns:**
| URL | Genre |
|-----|-------|
| https://example.com/article | Healthcare |

---

### 6. Validate Genres (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Validate genres against allowed list, filter invalid rows

**Key Logic:**
```javascript
const validGenres = [
  'Office Equipment & Technology',
  'Food & Drink',
  // ... all 26 genres
];

// For each row:
// - Check URL is not empty
// - Check Genre is not empty
// - Check Genre is in validGenres list
// - Skip and log if invalid
// - Limit to 200 URLs max
```

**Output:** Valid items with client_id and run_id attached

---

### 7. Batch URLs (Split In Batches)
**Type:** `n8n-nodes-base.splitInBatches`
**Purpose:** Control concurrency for HTTP requests

**Settings:**
- Batch Size: 5 (5 concurrent requests)
- Reset: false

---

### 8. Fetch Article (HTTP Request)
**Type:** `n8n-nodes-base.httpRequest`
**Purpose:** Fetch HTML content from each URL

**Settings:**
```json
{
  "url": "={{ $json.url }}",
  "options": {
    "timeout": 30000,
    "redirect": {
      "followRedirects": true,
      "maxRedirects": 5
    }
  }
}
```

**Error Handling:**
- onError: continueErrorOutput (route errors to separate output)
- retryOnFail: true
- maxTries: 3
- waitBetweenTries: 2000ms

---

### 9. Extract Content (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Extract article content using Cheerio

**Extraction Logic:**

1. **Canonical URL:**
   ```javascript
   $('link[rel="canonical"]').attr('href') ||
   $('meta[property="og:url"]').attr('content') ||
   originalUrl
   ```

2. **Source Name:**
   ```javascript
   $('meta[property="og:site_name"]').attr('content') ||
   new URL(canonicalUrl).hostname.replace('www.', '')
   ```

3. **Publish Date (Tiered):**
   - Tier 1: JSON-LD `datePublished` (confidence: 0.95)
   - Tier 2: OpenGraph `article:published_time` (confidence: 0.90)
   - Tier 3: Meta tags `pubdate`, `date`, `DC.date` (confidence: 0.80)
   - Tier 4: `<time datetime>` elements (confidence: 0.70)
   - Tier 5: URL patterns `/2026/01/03/` (confidence: 0.50)

4. **Article Body:**
   - Try selectors: article, [itemprop="articleBody"], .article-body, etc.
   - Fallback: concatenate all paragraphs > 50 chars

5. **Paywall Detection:**
   - Check for .paywall, .subscription-required selectors
   - Flag if content < 300 chars

6. **Deduplication Keys:**
   - `dedupe_key`: SHA256 of canonical URL
   - `title_normalized`: lowercase, alphanumeric only
   - `content_fingerprint`: SHA256 of first 1000 chars

---

### 10. Validate Publish Date (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Ensure article is within 24h window

**Logic:**
```javascript
// Calculate window (07:00 yesterday to 07:00 today UK)
const windowEnd = // 07:00 today UK
const windowStart = // 07:00 yesterday UK

// Skip if:
// - No publish date found
// - Parse error
// - Outside window
// - Paywalled
```

---

### 11. Filter Skipped (IF)
**Type:** `n8n-nodes-base.if`
**Purpose:** Route valid vs skipped items

**Condition:**
- `$json.skip === false` → Continue to Deduplicate
- `$json.skip === true` → Route to Log Skipped

---

### 12. Log Skipped (Postgres)
**Type:** `n8n-nodes-base.postgres`
**Purpose:** Record skipped URLs for debugging

**Query:**
```sql
INSERT INTO errors (client_id, run_id, url, genre, stage, error_type, error_message)
VALUES (..., 'validation', 'skipped', '{{ $json.skip_reason }}')
```

---

### 13. Deduplicate (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Remove duplicate articles

**Logic:**
```javascript
// Sort by publish_date_confidence (prefer higher)
// Check each item against seen items:
// 1. Exact dedupe_key match
// 2. Exact title_normalized match (if > 20 chars)
// 3. Exact content_fingerprint match
// Keep first (highest quality) version
```

---

### 14. LLM Process (OpenAI)
**Type:** `@n8n/n8n-nodes-langchain.openAi`
**Purpose:** Generate polished content

**Model:** gpt-4o-mini
**Temperature:** 0.3

**System Prompt:**
```
You are a professional news editor for a marketing agency newsletter called '44 News Automation'. Your task is to:

1. Polish the article title - keep it faithful and factual, no sensationalism
2. Write a summary (3-6 sentences max) - factual, professional, concise
3. Write 'Why this matters' (max 3 sentences) - formal, agency-focused, include 1 practical implication for marketing agencies, never invent facts
4. Score agency relevance (1-5) based on practical marketing implications

Rules:
- Never add facts not in the article
- If uncertain, briefly signal uncertainty
- Keep language concise and professional
- Tone should read like a professional agency newsletter

Respond in JSON format:
{
  "polished_title": "...",
  "summary": "...",
  "why_matters": "...",
  "agency_relevance_score": 1-5
}
```

**User Prompt:**
```
Genre: {{ $json.genre }}

Original Title: {{ $json.original_title }}

Source: {{ $json.source_name }}

Article Content:
{{ $json.article_body.substring(0, 4000) }}
```

---

### 15. Parse LLM Response (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Parse JSON from LLM and merge with original data

**Fallback values if parsing fails:**
- polished_title: original_title
- summary: "Summary unavailable."
- why_matters: "Analysis unavailable."
- agency_relevance_score: 3

---

### 16. Rank & Cap (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Apply ranking and enforce caps

**Logic:**
```javascript
// Group by genre
// Sort within each genre by:
//   1. agency_relevance_score DESC
//   2. published_at DESC (recency)
// Take top 6 per genre
// Take top 60 total
// Mark top 5 overall as is_top_signal = true
// Assign genre_rank and overall_rank
```

---

### 17. Store Story (Postgres)
**Type:** `n8n-nodes-base.postgres`
**Purpose:** Persist stories with upsert

**Query:** INSERT ... ON CONFLICT DO UPDATE
- Conflict key: (client_id, run_id, dedupe_key)
- Update: polished fields, ranks, timestamps

---

### 18. Aggregate for Email (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Prepare data for email generation

**Output:**
```javascript
{
  client,
  run,
  dateStr,  // "Friday, 3 January 2026"
  storyCount,
  topSignals,  // Array of top 5 stories
  storiesByGenre,  // { "Healthcare": [...], ... }
  genreColors,  // Mapping
  recipients
}
```

---

### 19. Generate Email HTML (Code)
**Type:** `n8n-nodes-base.code`
**Purpose:** Build responsive HTML email

**Features:**
- Mobile-friendly design
- Header with branding
- Top Signals section (5 bullets)
- Genre sections with color headers
- Story cards with title, source, summary, why matters
- No-news variant rotation (7 messages)

---

### 20. Send Email (Email Send)
**Type:** `n8n-nodes-base.emailSend`
**Purpose:** Send via IONOS SMTP

**Settings:**
```json
{
  "fromEmail": "={{ $env.SMTP_FROM }}",
  "toEmail": "={{ $json.recipients.join(', ') }}",
  "subject": "={{ $json.emailSubject }}",
  "emailType": "html",
  "message": "={{ $json.emailHtml }}"
}
```

**Credentials:** SMTP with env vars (SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS)

---

### 21. Log Email Sent (Postgres)
**Type:** `n8n-nodes-base.postgres`
**Purpose:** Record email in email_logs table

---

### 22. Complete Run (Postgres)
**Type:** `n8n-nodes-base.postgres`
**Purpose:** Update run status to 'completed'

**Query:**
```sql
UPDATE runs SET
  status = 'completed',
  completed_at = NOW(),
  stories_created = (SELECT COUNT(*) FROM stories WHERE run_id = '...'),
  error_count = (SELECT COUNT(*) FROM errors WHERE run_id = '...'),
  email_sent = true,
  email_sent_at = NOW()
WHERE id = '...'
```

---

### 23. Alert Admin (Email Send - Error Path)
**Type:** `n8n-nodes-base.emailSend`
**Purpose:** Send alert on critical failures

**Settings:**
```json
{
  "toEmail": "={{ $env.ADMIN_ALERT_EMAIL }}",
  "subject": "[ALERT] 44 News Automation - Run Failed",
  "emailType": "text"
}
```

---

## Required Credentials

### 1. Postgres
```
Name: Postgres
Host: (your postgres host)
Database: news_automation
User: (your user)
Password: (your password)
SSL: Required for production
```

### 2. Google Sheets OAuth2
```
Name: Google Sheets
Client ID: (from Google Cloud Console)
Client Secret: (from Google Cloud Console)
```

### 3. IONOS SMTP
```
Name: IONOS SMTP
Host: {{ $env.SMTP_HOST }}
Port: {{ $env.SMTP_PORT }}
User: {{ $env.SMTP_USER }}
Password: {{ $env.SMTP_PASS }}
SSL/TLS: STARTTLS
```

### 4. OpenAI API
```
Name: OpenAI
API Key: (your OpenAI API key)
```

---

## Environment Variables Required

| Variable | Description | Example |
|----------|-------------|---------|
| DATABASE_URL | Postgres connection | postgresql://... |
| SMTP_HOST | IONOS SMTP server | smtp.ionos.co.uk |
| SMTP_PORT | SMTP port | 587 |
| SMTP_USER | SMTP username | news@44automationltd.com |
| SMTP_PASS | SMTP password | *** |
| SMTP_FROM | From address | news@44automationltd.com |
| OPENAI_API_KEY | OpenAI key | sk-*** |
| ADMIN_ALERT_EMAIL | Alert recipient | admin@44automationltd.com |

---

## Workflow Settings

```json
{
  "executionOrder": "v1",
  "saveManualExecutions": true,
  "timezone": "Europe/London"
}
```

---

## Error Handling Strategy

1. **HTTP Fetch Errors:** Retry 3 times with 2s backoff, then route to error log
2. **Parse Errors:** Use fallback values, continue processing
3. **LLM Errors:** Use fallback summary text
4. **Database Errors:** Route to admin alert
5. **Email Errors:** Route to admin alert

---

## Idempotency

- Run records use UPSERT on (client_id, run_date, run_number)
- Stories use UPSERT on (client_id, run_id, dedupe_key)
- Re-running same day updates existing records, doesn't duplicate
