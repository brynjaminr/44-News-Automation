# 44 News Automation - n8n Workflow Specification V2

## Overview

This specification describes the complete n8n workflow for the 44 News Automation system with **homepage discovery** (not direct article URLs). The workflow runs daily at 07:00 UK time.

## Workflow Structure

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                          n8n WORKFLOW: 44 News Automation                        │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  TRIGGER          INIT              DISCOVERY          PROCESSING       OUTPUT   │
│  ───────          ────              ─────────          ──────────       ──────   │
│                                                                                   │
│  ┌──────────┐   ┌──────────────┐   ┌─────────────────────────────────────────┐  │
│  │  Cron    │──▶│ Get Clients  │──▶│        HOMEPAGE DISCOVERY LOOP          │  │
│  │ 07:00 UK │   │ Create Run   │   │  ┌───────────┐  ┌─────────────────────┐ │  │
│  └──────────┘   │ Read Sheet   │   │  │ Fetch     │─▶│ Extract Links       │ │  │
│                 └──────────────┘   │  │ Homepage  │  │ Filter Candidates   │ │  │
│                                     │  └───────────┘  │ Handle Pagination   │ │  │
│                                     │                 └─────────────────────┘ │  │
│                                     └─────────────────────────────────────────┘  │
│                                                        │                         │
│                                     ┌──────────────────┴──────────────────────┐  │
│                                     │       ARTICLE PROCESSING LOOP            │  │
│                                     │  ┌─────────┐ ┌────────┐ ┌────────────┐  │  │
│                                     │  │ Fetch   │▶│Extract │▶│  Validate  │  │  │
│                                     │  │ Article │ │Content │ │  Date/24h  │  │  │
│                                     │  └─────────┘ └────────┘ └────────────┘  │  │
│                                     │       │                                  │  │
│                                     │  ┌────┴─────┐ ┌────────┐ ┌──────────┐  │  │
│                                     │  │ Dedupe   │▶│  LLM   │▶│ Rank&Cap │  │  │
│                                     │  └──────────┘ └────────┘ └──────────┘  │  │
│                                     └──────────────────────────────────────────┘  │
│                                                        │                         │
│                                     ┌──────────────────┴──────────────────────┐  │
│                                     │            OUTPUT STAGE                  │  │
│                                     │  ┌────────────┐  ┌────────────────────┐ │  │
│                                     │  │ Store to   │──│ Generate & Send    │ │  │
│                                     │  │ Postgres   │  │ Email (IONOS SMTP) │ │  │
│                                     │  └────────────┘  └────────────────────┘ │  │
│                                     └──────────────────────────────────────────┘  │
│                                                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Node-by-Node Specification

### Node 1: Schedule Trigger
**Type**: `n8n-nodes-base.scheduleTrigger`
**ID**: `schedule-trigger`
**Name**: `Daily 07:00 UK`

**Purpose**: Trigger workflow at 07:00 Europe/London daily.

**Configuration**:
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

**Output**: Trigger signal

---

### Node 2: Get Active Clients
**Type**: `n8n-nodes-base.postgres`
**ID**: `get-active-clients`
**Name**: `Get Active Clients`

**Purpose**: Fetch all active clients from database.

**Query**:
```sql
SELECT
  id, name, slug, sheet_id, recipients,
  max_stories_per_day, max_stories_per_genre,
  max_pages_per_source, timezone
FROM clients
WHERE is_active = true
```

**Output**: Array of client records

---

### Node 3: Loop Over Clients
**Type**: `n8n-nodes-base.splitInBatches`
**ID**: `loop-clients`
**Name**: `Loop Over Clients`

**Purpose**: Process each client sequentially.

**Configuration**:
```json
{
  "batchSize": 1,
  "options": { "reset": false }
}
```

---

### Node 4: Create Run Record
**Type**: `n8n-nodes-base.postgres`
**ID**: `create-run`
**Name**: `Create Run Record`

**Purpose**: Create a new run record for tracking.

**Query**:
```sql
INSERT INTO runs (client_id, run_date, status, started_at)
VALUES (
  '{{ $json.id }}',
  CURRENT_DATE,
  'running',
  NOW()
)
ON CONFLICT (client_id, run_date, run_number)
DO UPDATE SET status = 'running', started_at = NOW()
RETURNING *
```

---

### Node 5: Read Google Sheet
**Type**: `n8n-nodes-base.googleSheets`
**ID**: `read-sheet`
**Name**: `Read URLs from Sheet`

**Purpose**: Read homepage URLs and genres from Google Sheet.

**Configuration**:
```json
{
  "operation": "read",
  "sheetId": "={{ $('Loop Over Clients').item.json.sheet_id }}",
  "range": "A:B",
  "options": { "headerRow": 1 }
}
```

**Expected columns**:
- Column A: `URL` (homepage/section page URL)
- Column B: `Genre` (from allowed list)

---

### Node 6: Validate Sheet Data
**Type**: `n8n-nodes-base.code`
**ID**: `validate-sheet`
**Name**: `Validate URLs & Genres`

**Purpose**: Validate genres against allowed list, skip invalid rows.

**Code**:
```javascript
const VALID_GENRES = [
  'Office Equipment & Technology',
  'Food & Drink',
  'Telecommunications & Internet',
  'Healthcare',
  'Education',
  'Tobacco & E-cigarettes',
  'Charity & Nonprofit',
  'Fashion',
  'Retail',
  'Professional & Business Services',
  'Property & Construction',
  'Agencies',
  'Entertainment',
  'Transportation & Logistics',
  'Consumer Electronics',
  'Travel & Tourism',
  'Financial',
  'Utilities & Energy',
  'Leisure & Hospitality',
  'Media & Publishing',
  'Government & Public Sector',
  'Cosmetics & Personal Care',
  'Home & Garden',
  'Automotive',
  'Manufacturing & Industrial',
  'Household Consumer Goods'
];

const client = $('Loop Over Clients').first().json;
const run = $('Create Run Record').first().json;
const results = [];
const errors = [];

for (const item of $input.all()) {
  const url = (item.json.URL || '').trim();
  const genre = (item.json.Genre || '').trim();

  if (!url) {
    errors.push({ url: '', genre, reason: 'Missing URL' });
    continue;
  }

  if (!genre) {
    errors.push({ url, genre: '', reason: 'Missing genre' });
    continue;
  }

  if (!VALID_GENRES.includes(genre)) {
    errors.push({ url, genre, reason: `Invalid genre: ${genre}` });
    continue;
  }

  // Normalize URL
  let normalizedUrl = url;
  try {
    const parsed = new URL(url);
    normalizedUrl = parsed.href;
  } catch (e) {
    errors.push({ url, genre, reason: 'Invalid URL format' });
    continue;
  }

  results.push({
    json: {
      homepage_url: normalizedUrl,
      genre,
      client_id: client.id,
      run_id: run.id,
      client_name: client.name,
      max_pages: client.max_pages_per_source || 3
    }
  });
}

// Store errors for logging
$workflow.setStaticData('validation_errors', errors);

return results.slice(0, 200); // Max 200 homepage URLs
```

---

### Node 7: Log Validation Errors
**Type**: `n8n-nodes-base.postgres`
**ID**: `log-validation-errors`
**Name**: `Log Validation Errors`

**Purpose**: Log any validation errors to database.

**Query** (batch insert):
```sql
INSERT INTO errors (client_id, run_id, url, genre, stage, error_type, error_message)
SELECT * FROM json_to_recordset($1::json) AS x(
  client_id uuid, run_id uuid, url text, genre text,
  stage text, error_type text, error_message text
)
```

---

### Node 8: Loop Homepage Discovery
**Type**: `n8n-nodes-base.splitInBatches`
**ID**: `loop-homepages`
**Name**: `Process Each Homepage`

**Purpose**: Process each homepage URL sequentially for discovery.

**Configuration**:
```json
{
  "batchSize": 1,
  "options": { "reset": false }
}
```

---

### Node 9: Fetch Homepage
**Type**: `n8n-nodes-base.httpRequest`
**ID**: `fetch-homepage`
**Name**: `Fetch Homepage HTML`

**Purpose**: Fetch homepage HTML with browser-like headers.

**Configuration**:
```json
{
  "url": "={{ $json.homepage_url }}",
  "method": "GET",
  "options": {
    "timeout": 30000,
    "redirect": {
      "followRedirects": true,
      "maxRedirects": 5
    }
  },
  "headerParameters": {
    "parameters": [
      {
        "name": "User-Agent",
        "value": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      },
      {
        "name": "Accept",
        "value": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
      },
      {
        "name": "Accept-Language",
        "value": "en-US,en;q=0.9"
      }
    ]
  }
}
```

**Error handling**: Continue on error, log and try next homepage.

---

### Node 10: Extract Article Links
**Type**: `n8n-nodes-base.code`
**ID**: `extract-links`
**Name**: `Extract Article Links`

**Purpose**: Parse homepage HTML, extract all links, filter for article candidates.

**Code**:
```javascript
const cheerio = require('cheerio');

const item = $input.first().json;
const html = item.data || item.body || '';
const homepageUrl = item.homepage_url || $json.homepage_url;
const genre = item.genre || $json.genre;
const clientId = item.client_id || $json.client_id;
const runId = item.run_id || $json.run_id;

if (!html || typeof html !== 'string') {
  return [{
    json: {
      candidates: [],
      homepage_url: homepageUrl,
      genre,
      client_id: clientId,
      run_id: runId,
      error: 'Empty or invalid HTML response'
    }
  }];
}

const $ = cheerio.load(html);
const baseUrl = new URL(homepageUrl);
const baseDomain = baseUrl.hostname.replace('www.', '');

// Excluded path patterns
const EXCLUDED_PATHS = [
  '/tag/', '/tags/', '/author/', '/authors/', '/about/', '/about-us/',
  '/login/', '/signin/', '/signup/', '/subscribe/', '/subscription/',
  '/privacy/', '/privacy-policy/', '/terms/', '/terms-of-service/',
  '/jobs/', '/careers/', '/contact/', '/sitemap/', '/search/',
  '/category/', '/categories/', '/archive/', '/rss/', '/feed/',
  '/account/', '/profile/', '/settings/', '/help/', '/faq/',
  '/advertise/', '/advertising/', '/media-kit/', '/press/',
  '/newsletter/', '/podcasts/', '/videos/', '/webinars/'
];

// Excluded file extensions
const EXCLUDED_EXTENSIONS = [
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  '.jpg', '.jpeg', '.png', '.gif', '.svg', '.webp', '.ico',
  '.zip', '.rar', '.tar', '.gz', '.mp3', '.mp4', '.avi', '.mov'
];

// Tracking params to remove
const TRACKING_PARAMS = [
  'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
  'fbclid', 'gclid', 'msclkid', 'ref', 'source'
];

const candidates = [];
const seenUrls = new Set();

$('a[href]').each((i, el) => {
  try {
    let href = $(el).attr('href');
    if (!href) return;

    // Skip anchors, javascript, mailto
    if (href.startsWith('#') || href.startsWith('javascript:') ||
        href.startsWith('mailto:') || href.startsWith('tel:')) {
      return;
    }

    // Resolve relative URLs
    let fullUrl;
    try {
      fullUrl = new URL(href, homepageUrl);
    } catch (e) {
      return;
    }

    // Same domain check
    const linkDomain = fullUrl.hostname.replace('www.', '');
    if (linkDomain !== baseDomain) {
      return;
    }

    // Check excluded paths
    const path = fullUrl.pathname.toLowerCase();
    for (const excluded of EXCLUDED_PATHS) {
      if (path.includes(excluded)) {
        return;
      }
    }

    // Check excluded extensions
    for (const ext of EXCLUDED_EXTENSIONS) {
      if (path.endsWith(ext)) {
        return;
      }
    }

    // Remove tracking params
    for (const param of TRACKING_PARAMS) {
      fullUrl.searchParams.delete(param);
    }

    const cleanUrl = fullUrl.href;

    // Skip if already seen
    if (seenUrls.has(cleanUrl)) {
      return;
    }
    seenUrls.add(cleanUrl);

    // Skip homepage itself
    if (cleanUrl === homepageUrl || cleanUrl === homepageUrl + '/') {
      return;
    }

    // Article heuristics
    let articleScore = 0;
    let isArticleLike = false;

    // Date pattern in URL: /2026/01/06/ or /2026-01-06/
    const datePattern = /\/(20[0-9]{2})[\/\-](0[1-9]|1[0-2])[\/\-](0[1-9]|[12][0-9]|3[01])/;
    if (datePattern.test(path)) {
      articleScore += 3;
      isArticleLike = true;
    }

    // Path depth >= 2 (e.g., /category/article-slug)
    const pathParts = path.split('/').filter(p => p.length > 0);
    if (pathParts.length >= 2) {
      articleScore += 1;
    }

    // Slug length > 20 chars (article-like slugs are usually descriptive)
    const slug = pathParts[pathParts.length - 1] || '';
    if (slug.length > 20) {
      articleScore += 2;
      isArticleLike = true;
    }

    // Contains common article path patterns
    if (path.includes('/news/') || path.includes('/article/') ||
        path.includes('/story/') || path.includes('/post/') ||
        path.includes('/blog/')) {
      articleScore += 2;
      isArticleLike = true;
    }

    // Get surrounding text context
    const linkText = $(el).text().trim().substring(0, 200);
    const parentText = $(el).parent().text().trim().substring(0, 300);

    // Look for nearby timestamps
    let nearbyTimestamp = null;
    const parent = $(el).parent();
    const timeEl = parent.find('time').first();
    if (timeEl.length) {
      nearbyTimestamp = timeEl.attr('datetime') || timeEl.text();
    }

    // Only include article-like URLs
    if (articleScore >= 2 || isArticleLike) {
      candidates.push({
        url: cleanUrl,
        link_text: linkText,
        article_score: articleScore,
        nearby_timestamp: nearbyTimestamp,
        path_depth: pathParts.length,
        slug_length: slug.length
      });
    }
  } catch (e) {
    // Skip problematic links
  }
});

// Sort by article score descending
candidates.sort((a, b) => b.article_score - a.article_score);

// Detect pagination links
const paginationLinks = [];
$('a[href]').each((i, el) => {
  const href = $(el).attr('href') || '';
  const text = $(el).text().trim().toLowerCase();

  // Common pagination patterns
  if (href.match(/[?&]page=\d+/) || href.match(/\/page\/\d+/) ||
      href.match(/[?&]p=\d+/) || href.match(/[?&]offset=\d+/) ||
      text === 'next' || text === 'older' || text === 'more' ||
      text.match(/^[2-9]$/) || text === '›' || text === '»') {
    try {
      const fullUrl = new URL(href, homepageUrl);
      if (fullUrl.hostname.replace('www.', '') === baseDomain) {
        paginationLinks.push({
          url: fullUrl.href,
          text: text
        });
      }
    } catch (e) {}
  }
});

return [{
  json: {
    candidates: candidates.slice(0, 100), // Max 100 candidates per homepage
    pagination_links: paginationLinks.slice(0, 10),
    homepage_url: homepageUrl,
    genre,
    client_id: clientId,
    run_id: runId,
    total_links_found: seenUrls.size,
    article_candidates_found: candidates.length
  }
}];
```

---

### Node 11: Handle Pagination
**Type**: `n8n-nodes-base.code`
**ID**: `handle-pagination`
**Name**: `Handle Pagination`

**Purpose**: Fetch additional pages if pagination detected.

**Code**:
```javascript
const input = $input.first().json;
const maxPages = input.max_pages || 3;
let allCandidates = [...(input.candidates || [])];
const paginationLinks = input.pagination_links || [];
const seenUrls = new Set(allCandidates.map(c => c.url));

// Process up to maxPages-1 additional pages (page 1 already processed)
let pagesProcessed = 1;

for (const pageLink of paginationLinks) {
  if (pagesProcessed >= maxPages) break;

  try {
    // Fetch pagination page
    const response = await this.helpers.httpRequest({
      method: 'GET',
      url: pageLink.url,
      timeout: 30000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml'
      }
    });

    if (response && typeof response === 'string') {
      const cheerio = require('cheerio');
      const $ = cheerio.load(response);
      const baseUrl = new URL(input.homepage_url);
      const baseDomain = baseUrl.hostname.replace('www.', '');

      let newCandidatesCount = 0;

      $('a[href]').each((i, el) => {
        const href = $(el).attr('href');
        if (!href) return;

        try {
          const fullUrl = new URL(href, input.homepage_url);
          const linkDomain = fullUrl.hostname.replace('www.', '');

          if (linkDomain !== baseDomain) return;

          const cleanUrl = fullUrl.href;
          if (seenUrls.has(cleanUrl)) return;

          const path = fullUrl.pathname.toLowerCase();
          const pathParts = path.split('/').filter(p => p.length > 0);
          const slug = pathParts[pathParts.length - 1] || '';

          // Article heuristics
          const datePattern = /\/(20[0-9]{2})[\/\-](0[1-9]|1[0-2])[\/\-](0[1-9]|[12][0-9]|3[01])/;
          let articleScore = 0;

          if (datePattern.test(path)) articleScore += 3;
          if (pathParts.length >= 2) articleScore += 1;
          if (slug.length > 20) articleScore += 2;
          if (path.includes('/news/') || path.includes('/article/')) articleScore += 2;

          if (articleScore >= 2) {
            seenUrls.add(cleanUrl);
            allCandidates.push({
              url: cleanUrl,
              link_text: $(el).text().trim().substring(0, 200),
              article_score: articleScore,
              from_page: pagesProcessed + 1
            });
            newCandidatesCount++;
          }
        } catch (e) {}
      });

      pagesProcessed++;

      // Stop if no new candidates found
      if (newCandidatesCount === 0) break;
    }
  } catch (e) {
    // Continue with what we have
    break;
  }
}

return [{
  json: {
    ...input,
    candidates: allCandidates.slice(0, 150), // Max 150 per homepage after pagination
    pages_processed: pagesProcessed,
    total_candidates: allCandidates.length
  }
}];
```

---

### Node 12: Coverage Safeguard
**Type**: `n8n-nodes-base.code`
**ID**: `coverage-safeguard`
**Name**: `Coverage Safeguard`

**Purpose**: If 0 candidates, retry with relaxed heuristics.

**Code**:
```javascript
const input = $input.first().json;

if (input.candidates.length === 0) {
  // Log warning but continue - don't fail the whole run
  return [{
    json: {
      ...input,
      coverage_warning: `No article candidates found from ${input.homepage_url}`,
      candidates: []
    }
  }];
}

// Flatten candidates with source info
const results = input.candidates.map(candidate => ({
  json: {
    article_url: candidate.url,
    article_score: candidate.article_score,
    nearby_timestamp: candidate.nearby_timestamp,
    homepage_url: input.homepage_url,
    genre: input.genre,
    client_id: input.client_id,
    run_id: input.run_id
  }
}));

return results;
```

---

### Node 13: Aggregate All Candidates
**Type**: `n8n-nodes-base.code`
**ID**: `aggregate-candidates`
**Name**: `Aggregate All Candidates`

**Purpose**: Collect all candidates from all homepages.

**Code**:
```javascript
// Collect all candidates from the homepage processing loop
const allCandidates = [];
const items = $input.all();

for (const item of items) {
  if (item.json.article_url) {
    allCandidates.push(item);
  }
}

// Remove exact URL duplicates across homepages
const seenUrls = new Set();
const uniqueCandidates = [];

for (const item of allCandidates) {
  if (!seenUrls.has(item.json.article_url)) {
    seenUrls.add(item.json.article_url);
    uniqueCandidates.push(item);
  }
}

return uniqueCandidates;
```

---

### Node 14: Batch Article Fetching
**Type**: `n8n-nodes-base.splitInBatches`
**ID**: `batch-articles`
**Name**: `Batch Articles (5)`

**Purpose**: Process articles in batches of 5 for controlled concurrency.

**Configuration**:
```json
{
  "batchSize": 5,
  "options": { "reset": false }
}
```

---

### Node 15: Fetch Article
**Type**: `n8n-nodes-base.httpRequest`
**ID**: `fetch-article`
**Name**: `Fetch Article Page`

**Purpose**: Fetch full article page HTML.

**Configuration**:
```json
{
  "url": "={{ $json.article_url }}",
  "method": "GET",
  "options": {
    "timeout": 30000,
    "redirect": {
      "followRedirects": true,
      "maxRedirects": 5
    }
  },
  "headerParameters": {
    "parameters": [
      {
        "name": "User-Agent",
        "value": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
      }
    ]
  }
}
```

**Error handling**: Continue on error output, log failed fetches.

---

### Node 16: Extract Article Content
**Type**: `n8n-nodes-base.code`
**ID**: `extract-content`
**Name**: `Extract Article Content`

**Purpose**: Extract all article metadata, content, and publish date.

**Code**:
```javascript
const cheerio = require('cheerio');
const crypto = require('crypto');

const item = $input.first();
const html = item.json.data || item.json.body || '';
const articleUrl = item.json.article_url;
const genre = item.json.genre;
const clientId = item.json.client_id;
const runId = item.json.run_id;

if (!html || typeof html !== 'string' || html.length < 500) {
  return [{
    json: {
      skip: true,
      skip_reason: 'Empty or too short response',
      url: articleUrl,
      genre,
      client_id: clientId,
      run_id: runId
    }
  }];
}

const $ = cheerio.load(html);

// ========================================
// CANONICAL URL
// ========================================
let canonicalUrl = $('link[rel="canonical"]').attr('href') ||
                   $('meta[property="og:url"]').attr('content') ||
                   articleUrl;

if (canonicalUrl && !canonicalUrl.startsWith('http')) {
  try {
    canonicalUrl = new URL(canonicalUrl, articleUrl).href;
  } catch (e) {
    canonicalUrl = articleUrl;
  }
}

// ========================================
// SOURCE NAME
// ========================================
const sourceName = $('meta[property="og:site_name"]').attr('content') ||
                   $('meta[name="application-name"]').attr('content') ||
                   new URL(canonicalUrl).hostname.replace('www.', '');

// ========================================
// TITLE
// ========================================
const title = $('meta[property="og:title"]').attr('content') ||
              $('meta[name="title"]').attr('content') ||
              $('title').text().trim().split('|')[0].trim() ||
              $('h1').first().text().trim();

// ========================================
// PAYWALL DETECTION
// ========================================
const paywallSelectors = [
  '.paywall', '.subscription-required', '[data-paywall]',
  '.premium-content', '.subscriber-only', '.locked-content',
  '.gate', '.regwall', '[data-piano-region]'
];

let isPaywalled = false;
for (const selector of paywallSelectors) {
  if ($(selector).length > 0) {
    isPaywalled = true;
    break;
  }
}

// ========================================
// PUBLISH DATE EXTRACTION (Tiered)
// ========================================
let publishDate = null;
let publishDateSource = null;
let confidence = 0;

// Tier 1: JSON-LD (highest confidence)
$('script[type="application/ld+json"]').each((i, el) => {
  if (publishDate) return;
  try {
    const data = JSON.parse($(el).html());
    const items = Array.isArray(data) ? data : [data];
    for (const item of items) {
      if (item['@type'] === 'NewsArticle' || item['@type'] === 'Article' ||
          item['@type'] === 'BlogPosting' || item['@type'] === 'WebPage') {
        if (item.datePublished) {
          publishDate = item.datePublished;
          publishDateSource = 'jsonld_published';
          confidence = 0.95;
          break;
        }
        if (item.dateModified) {
          publishDate = item.dateModified;
          publishDateSource = 'jsonld_modified';
          confidence = 0.85;
          break;
        }
      }
    }
  } catch (e) {}
});

// Tier 2: OpenGraph
if (!publishDate) {
  const ogDate = $('meta[property="article:published_time"]').attr('content');
  if (ogDate) {
    publishDate = ogDate;
    publishDateSource = 'opengraph';
    confidence = 0.90;
  }
}

// Tier 3: Meta tags
if (!publishDate) {
  const metaSelectors = [
    'meta[name="pubdate"]',
    'meta[name="date"]',
    'meta[name="DC.date"]',
    'meta[name="DC.date.issued"]',
    'meta[itemprop="datePublished"]',
    'meta[name="article:published"]',
    'meta[name="publish-date"]',
    'meta[name="cXenseParse:recs:publishtime"]'
  ];

  for (const selector of metaSelectors) {
    const val = $(selector).attr('content');
    if (val) {
      publishDate = val;
      publishDateSource = 'meta';
      confidence = 0.80;
      break;
    }
  }
}

// Tier 4: <time> elements
if (!publishDate) {
  const timeEl = $('time[datetime]').first();
  if (timeEl.length) {
    publishDate = timeEl.attr('datetime');
    publishDateSource = 'time_element';
    confidence = 0.70;
  }
}

// Tier 5: URL date pattern (last resort)
if (!publishDate) {
  const urlDateMatch = canonicalUrl.match(/\/(20[0-9]{2})\/(0[1-9]|1[0-2])\/(0[1-9]|[12][0-9]|3[01])/);
  if (urlDateMatch) {
    publishDate = `${urlDateMatch[1]}-${urlDateMatch[2]}-${urlDateMatch[3]}`;
    publishDateSource = 'url_pattern';
    confidence = 0.50;
  }
}

// ========================================
// CONTENT EXTRACTION
// ========================================
// Remove noise
$('script, style, nav, header, footer, aside, .ad, .advertisement, .social-share, .related-articles, .comments, .sidebar, noscript').remove();

let articleBody = '';
const contentSelectors = [
  'article',
  '[itemprop="articleBody"]',
  '.article-body',
  '.article-content',
  '.post-content',
  '.entry-content',
  '.story-body',
  '.story-content',
  '[data-article-body]',
  'main article',
  'main',
  '.content'
];

for (const selector of contentSelectors) {
  const content = $(selector).first();
  if (content.length && content.text().trim().length > 300) {
    articleBody = content.text().trim();
    break;
  }
}

// Fallback: concatenate paragraphs
if (!articleBody || articleBody.length < 300) {
  const paragraphs = [];
  $('p').each((i, el) => {
    const text = $(el).text().trim();
    if (text.length > 40) {
      paragraphs.push(text);
    }
  });
  articleBody = paragraphs.join('\n\n');
}

// Check if content too short (likely paywalled/blocked)
if (articleBody.length < 300) {
  isPaywalled = true;
}

// ========================================
// DEDUPLICATION KEYS
// ========================================
const dedupeKey = crypto.createHash('sha256').update(canonicalUrl).digest('hex').substring(0, 64);
const titleNormalized = title ? title.toLowerCase().replace(/[^a-z0-9\s]/g, '').replace(/\s+/g, ' ').trim() : '';
const contentFingerprint = crypto.createHash('sha256').update(articleBody.substring(0, 1000)).digest('hex').substring(0, 64);

return [{
  json: {
    url: articleUrl,
    canonical_url: canonicalUrl,
    genre,
    client_id: clientId,
    run_id: runId,
    source_name: sourceName,
    original_title: title,
    article_body: articleBody,
    word_count: articleBody.split(/\s+/).length,
    publish_date: publishDate,
    publish_date_source: publishDateSource,
    publish_date_confidence: confidence,
    is_paywalled: isPaywalled,
    dedupe_key: dedupeKey,
    title_normalized: titleNormalized,
    content_fingerprint: contentFingerprint,
    skip: false
  }
}];
```

---

### Node 17: Validate Publish Date & 24h Window
**Type**: `n8n-nodes-base.code`
**ID**: `validate-date`
**Name**: `Validate Publish Date`

**Purpose**: Check publish date exists and is within 24h window.

**Code**:
```javascript
const item = $input.first().json;

// Already marked for skip
if (item.skip) {
  return [{ json: item }];
}

// Paywall check
if (item.is_paywalled) {
  return [{
    json: {
      ...item,
      skip: true,
      skip_reason: 'Paywalled or blocked content'
    }
  }];
}

// MANDATORY: Must have publish date
if (!item.publish_date) {
  return [{
    json: {
      ...item,
      skip: true,
      skip_reason: 'Unknown publish date - MANDATORY SKIP'
    }
  }];
}

// Parse publish date
let pubDate;
try {
  pubDate = new Date(item.publish_date);
  if (isNaN(pubDate.getTime())) {
    throw new Error('Invalid date');
  }
} catch (e) {
  return [{
    json: {
      ...item,
      skip: true,
      skip_reason: `Invalid publish date format: ${item.publish_date}`
    }
  }];
}

// Calculate 24h window (07:00 UK yesterday to 07:00 UK today)
const now = new Date();

// Get current hour in UK timezone
const ukTime = new Date(now.toLocaleString('en-US', { timeZone: 'Europe/London' }));
const ukHour = ukTime.getHours();

// Window end: 07:00 today UK (or yesterday if before 7am)
let windowEnd = new Date(ukTime);
windowEnd.setHours(7, 0, 0, 0);

if (ukHour < 7) {
  // Before 7am UK, use yesterday's 7am as window end
  windowEnd.setDate(windowEnd.getDate() - 1);
}

// Window start: 24 hours before end
const windowStart = new Date(windowEnd);
windowStart.setDate(windowStart.getDate() - 1);

// Check if publish date is in window
const pubTime = pubDate.getTime();
const startTime = windowStart.getTime();
const endTime = windowEnd.getTime();

if (pubTime < startTime || pubTime > endTime) {
  return [{
    json: {
      ...item,
      skip: true,
      skip_reason: `Outside 24h window. Published: ${pubDate.toISOString()}, Window: ${windowStart.toISOString()} to ${windowEnd.toISOString()}`
    }
  }];
}

// Valid article - pass through
return [{
  json: {
    ...item,
    published_at: pubDate.toISOString(),
    window_start: windowStart.toISOString(),
    window_end: windowEnd.toISOString()
  }
}];
```

---

### Node 18: Filter Skipped
**Type**: `n8n-nodes-base.if`
**ID**: `filter-skipped`
**Name**: `Filter Skipped Articles`

**Purpose**: Route valid articles vs skipped articles.

**Condition**: `{{ $json.skip }}` equals `false`

---

### Node 19: Log Skipped Articles
**Type**: `n8n-nodes-base.postgres`
**ID**: `log-skipped`
**Name**: `Log Skipped Articles`

**Purpose**: Log skipped articles to errors table.

**Query**:
```sql
INSERT INTO errors (client_id, run_id, url, genre, stage, error_type, error_message)
VALUES (
  '{{ $json.client_id }}',
  '{{ $json.run_id }}',
  '{{ $json.url }}',
  '{{ $json.genre }}',
  'article_validation',
  'skipped',
  '{{ $json.skip_reason }}'
)
```

---

### Node 20: Deduplicate Articles
**Type**: `n8n-nodes-base.code`
**ID**: `deduplicate`
**Name**: `Deduplicate Articles`

**Purpose**: Remove duplicate articles by URL, title, and content.

**Code**:
```javascript
const items = $input.all().filter(item => !item.json.skip);
const seen = new Map();
const results = [];
const duplicates = [];

// Sort by confidence (prefer higher confidence)
items.sort((a, b) => (b.json.publish_date_confidence || 0) - (a.json.publish_date_confidence || 0));

for (const item of items) {
  const key = item.json.dedupe_key;
  const titleNorm = item.json.title_normalized;
  const contentFp = item.json.content_fingerprint;

  // Check exact URL duplicate
  if (seen.has(key)) {
    duplicates.push({ url: item.json.url, type: 'url' });
    continue;
  }

  // Check title similarity
  let isDupe = false;
  for (const [existingKey, existing] of seen.entries()) {
    // Exact title match
    if (existing.title_normalized === titleNorm && titleNorm.length > 20) {
      duplicates.push({ url: item.json.url, type: 'title' });
      isDupe = true;
      break;
    }
    // Content fingerprint match
    if (existing.content_fingerprint === contentFp && contentFp) {
      duplicates.push({ url: item.json.url, type: 'content' });
      isDupe = true;
      break;
    }
  }

  if (!isDupe) {
    seen.set(key, item.json);
    results.push(item);
  }
}

return results;
```

---

### Node 21: LLM Process
**Type**: `@n8n/n8n-nodes-langchain.openAi`
**ID**: `llm-process`
**Name**: `LLM Process Article`

**Purpose**: Generate polished title, summary, why matters, and score.

**Configuration**:
```json
{
  "model": "gpt-4o-mini",
  "messages": {
    "values": [
      {
        "role": "system",
        "content": "You are a professional news editor for '44 News Automation', a marketing agency newsletter.\n\nTask:\n1. Polish the article title - faithful, factual, no sensationalism\n2. Write summary (3-6 sentences) - factual, professional, concise\n3. Write 'Why this matters' (max 3 sentences) - formal, agency-focused, include 1 practical marketing implication, never invent facts, flag uncertainty if needed\n4. Score agency relevance (1-5)\n\nRules:\n- Never add facts not in the article\n- Never invent or assume information\n- Keep language professional\n- Signal uncertainty briefly if needed\n\nRespond in JSON:\n{\n  \"polished_title\": \"...\",\n  \"summary\": \"...\",\n  \"why_matters\": \"...\",\n  \"agency_relevance_score\": 1-5\n}"
      },
      {
        "role": "user",
        "content": "Genre: {{ $json.genre }}\n\nOriginal Title: {{ $json.original_title }}\n\nSource: {{ $json.source_name }}\n\nArticle:\n{{ $json.article_body.substring(0, 4000) }}"
      }
    ]
  },
  "options": {
    "temperature": 0.3,
    "responseFormat": "json_object"
  }
}
```

---

### Node 22: Parse LLM Response
**Type**: `n8n-nodes-base.code`
**ID**: `parse-llm`
**Name**: `Parse LLM Response`

**Purpose**: Parse JSON response and merge with article data.

**Code**:
```javascript
const item = $input.first().json;

let llmData;
try {
  const content = item.message?.content || item.text || item.output || '{}';
  llmData = JSON.parse(content);
} catch (e) {
  llmData = {
    polished_title: item.original_title,
    summary: 'Summary unavailable.',
    why_matters: 'Analysis unavailable.',
    agency_relevance_score: 3
  };
}

return [{
  json: {
    ...item,
    polished_title: llmData.polished_title || item.original_title,
    summary: llmData.summary || 'Summary unavailable.',
    why_matters: llmData.why_matters || 'Analysis unavailable.',
    agency_relevance_score: parseInt(llmData.agency_relevance_score) || 3
  }
}];
```

---

### Node 23: Rank and Cap
**Type**: `n8n-nodes-base.code`
**ID**: `rank-cap`
**Name**: `Rank & Cap Stories`

**Purpose**: Apply 6/genre and 60/day caps, mark top 5 signals.

**Code**:
```javascript
const items = $input.all();
const MAX_PER_GENRE = 6;
const MAX_TOTAL = 60;

// Group by genre
const byGenre = {};
for (const item of items) {
  const genre = item.json.genre;
  if (!byGenre[genre]) byGenre[genre] = [];
  byGenre[genre].push(item);
}

// Sort each genre by score then recency
for (const genre in byGenre) {
  byGenre[genre].sort((a, b) => {
    const scoreA = a.json.agency_relevance_score || 0;
    const scoreB = b.json.agency_relevance_score || 0;
    if (scoreB !== scoreA) return scoreB - scoreA;

    const dateA = new Date(a.json.published_at || 0);
    const dateB = new Date(b.json.published_at || 0);
    return dateB - dateA;
  });
}

// Apply caps
const results = [];
let overallRank = 0;

for (const genre in byGenre) {
  const genreStories = byGenre[genre].slice(0, MAX_PER_GENRE);
  genreStories.forEach((item, idx) => {
    overallRank++;
    if (overallRank <= MAX_TOTAL) {
      results.push({
        json: {
          ...item.json,
          genre_rank: idx + 1,
          overall_rank: overallRank,
          is_top_signal: false
        }
      });
    }
  });
}

// Mark top 5 as signals
results.sort((a, b) => {
  const scoreA = a.json.agency_relevance_score || 0;
  const scoreB = b.json.agency_relevance_score || 0;
  if (scoreB !== scoreA) return scoreB - scoreA;
  return new Date(b.json.published_at) - new Date(a.json.published_at);
});

results.slice(0, 5).forEach(item => {
  item.json.is_top_signal = true;
});

// Re-sort by genre for output
results.sort((a, b) => {
  if (a.json.genre < b.json.genre) return -1;
  if (a.json.genre > b.json.genre) return 1;
  return a.json.genre_rank - b.json.genre_rank;
});

return results;
```

---

### Node 24: Store Stories
**Type**: `n8n-nodes-base.postgres`
**ID**: `store-stories`
**Name**: `Store Stories to Postgres`

**Purpose**: Insert/upsert stories to database.

**Query**:
```sql
INSERT INTO stories (
  client_id, run_id, original_url, canonical_url, genre, source_name,
  original_title, polished_title, summary, why_matters, article_body,
  published_at, publish_date_source, publish_date_confidence,
  agency_relevance_score, dedupe_key, title_normalized, content_fingerprint,
  word_count, genre_rank, overall_rank, is_top_signal
) VALUES (
  '{{ $json.client_id }}',
  '{{ $json.run_id }}',
  '{{ $json.url.replace(/'/g, "''") }}',
  '{{ $json.canonical_url.replace(/'/g, "''") }}',
  '{{ $json.genre }}',
  '{{ ($json.source_name || "").replace(/'/g, "''") }}',
  '{{ ($json.original_title || "").replace(/'/g, "''").substring(0, 500) }}',
  '{{ ($json.polished_title || "").replace(/'/g, "''").substring(0, 500) }}',
  '{{ ($json.summary || "").replace(/'/g, "''") }}',
  '{{ ($json.why_matters || "").replace(/'/g, "''") }}',
  '{{ ($json.article_body || "").replace(/'/g, "''").substring(0, 10000) }}',
  '{{ $json.published_at }}',
  '{{ $json.publish_date_source }}',
  {{ $json.publish_date_confidence || 0 }},
  {{ $json.agency_relevance_score || 3 }},
  '{{ $json.dedupe_key }}',
  '{{ ($json.title_normalized || "").replace(/'/g, "''").substring(0, 500) }}',
  '{{ $json.content_fingerprint }}',
  {{ $json.word_count || 0 }},
  {{ $json.genre_rank || 0 }},
  {{ $json.overall_rank || 0 }},
  {{ $json.is_top_signal || false }}
)
ON CONFLICT (client_id, run_id, dedupe_key) DO UPDATE SET
  polished_title = EXCLUDED.polished_title,
  summary = EXCLUDED.summary,
  why_matters = EXCLUDED.why_matters,
  agency_relevance_score = EXCLUDED.agency_relevance_score,
  genre_rank = EXCLUDED.genre_rank,
  overall_rank = EXCLUDED.overall_rank,
  is_top_signal = EXCLUDED.is_top_signal,
  updated_at = NOW()
```

---

### Node 25: Aggregate for Email
**Type**: `n8n-nodes-base.code`
**ID**: `aggregate-email`
**Name**: `Aggregate for Email`

**Purpose**: Prepare data structure for email generation.

**Code**:
```javascript
const allStories = $input.all().map(item => item.json);
const client = $('Loop Over Clients').first().json;
const run = $('Create Run Record').first().json;

const GENRE_COLORS = {
  'Office Equipment & Technology': '#2563eb',
  'Food & Drink': '#dc2626',
  'Telecommunications & Internet': '#7c3aed',
  'Healthcare': '#059669',
  'Education': '#0891b2',
  'Tobacco & E-cigarettes': '#57534e',
  'Charity & Nonprofit': '#db2777',
  'Fashion': '#c026d3',
  'Retail': '#ea580c',
  'Professional & Business Services': '#4f46e5',
  'Property & Construction': '#ca8a04',
  'Agencies': '#0d9488',
  'Entertainment': '#e11d48',
  'Transportation & Logistics': '#1d4ed8',
  'Consumer Electronics': '#6366f1',
  'Travel & Tourism': '#0284c7',
  'Financial': '#15803d',
  'Utilities & Energy': '#a16207',
  'Leisure & Hospitality': '#be185d',
  'Media & Publishing': '#9333ea',
  'Government & Public Sector': '#1e40af',
  'Cosmetics & Personal Care': '#ec4899',
  'Home & Garden': '#65a30d',
  'Automotive': '#b91c1c',
  'Manufacturing & Industrial': '#475569',
  'Household Consumer Goods': '#d97706'
};

const topSignals = allStories.filter(s => s.is_top_signal).slice(0, 5);

const byGenre = {};
for (const story of allStories) {
  if (!byGenre[story.genre]) byGenre[story.genre] = [];
  byGenre[story.genre].push(story);
}

const today = new Date();
const dateStr = today.toLocaleDateString('en-GB', {
  weekday: 'long',
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  timeZone: 'Europe/London'
});

return [{
  json: {
    client,
    run,
    dateStr,
    storyCount: allStories.length,
    topSignals,
    storiesByGenre: byGenre,
    genreColors: GENRE_COLORS,
    recipients: client.recipients || []
  }
}];
```

---

### Node 26: Generate Email HTML
**Type**: `n8n-nodes-base.code`
**ID**: `generate-email`
**Name**: `Generate Email HTML`

**Purpose**: Build the complete HTML email.

*(Full code in workflow JSON - generates HTML with Top Signals, genre sections, and no-news variants)*

---

### Node 27: Send Email
**Type**: `n8n-nodes-base.emailSend`
**ID**: `send-email`
**Name**: `Send Email via IONOS`

**Configuration**:
```json
{
  "fromEmail": "={{ $env.SMTP_FROM }}",
  "toEmail": "={{ $json.recipients.join(', ') }}",
  "subject": "={{ $json.emailSubject }}",
  "emailType": "html",
  "message": "={{ $json.emailHtml }}"
}
```

**Credentials**: IONOS SMTP

---

### Node 28: Log Email
**Type**: `n8n-nodes-base.postgres`
**ID**: `log-email`
**Name**: `Log Email Sent`

**Query**:
```sql
INSERT INTO email_logs (
  client_id, run_id, subject, recipients, story_count,
  top_signals, genres_included, status, sent_at,
  is_no_news_email, no_news_variant
) VALUES (...)
```

---

### Node 29: Complete Run
**Type**: `n8n-nodes-base.postgres`
**ID**: `complete-run`
**Name**: `Complete Run Record`

**Query**:
```sql
UPDATE runs
SET
  status = 'completed',
  completed_at = NOW(),
  stories_created = (SELECT COUNT(*) FROM stories WHERE run_id = '{{ $json.run.id }}'),
  error_count = (SELECT COUNT(*) FROM errors WHERE run_id = '{{ $json.run.id }}'),
  email_sent = true,
  email_sent_at = NOW()
WHERE id = '{{ $json.run.id }}'
```

---

### Node 30: Error Handler / Admin Alert
**Type**: `n8n-nodes-base.emailSend`
**ID**: `admin-alert`
**Name**: `Alert Admin on Failure`

**Purpose**: Send alert email if workflow fails.

**Trigger**: On workflow error

---

## Connection Map

```
[Schedule Trigger]
    → [Get Active Clients]
    → [Loop Over Clients]
        → [Create Run Record]
        → [Read Google Sheet]
        → [Validate Sheet Data]
        → [Loop Homepage Discovery]
            → [Fetch Homepage]
            → [Extract Article Links]
            → [Handle Pagination]
            → [Coverage Safeguard]
        → [Aggregate All Candidates]
        → [Batch Article Fetching]
            → [Fetch Article]
            → [Extract Article Content]
            → [Validate Publish Date]
            → [Filter Skipped]
                → (true) [Deduplicate]
                → (false) [Log Skipped]
            → [LLM Process]
            → [Parse LLM Response]
        → [Rank & Cap]
        → [Store Stories]
        → [Aggregate for Email]
        → [Generate Email HTML]
        → [Send Email]
        → [Log Email]
        → [Complete Run]
        → (back to Loop Over Clients)

[Error Handler] → [Admin Alert]
```
