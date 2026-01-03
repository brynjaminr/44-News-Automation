# 44 News Automation - Test Plan & Acceptance Criteria

## Test Categories

1. [Data Pipeline Tests](#1-data-pipeline-tests)
2. [Publish Date Validation Tests](#2-publish-date-validation-tests)
3. [Deduplication Tests](#3-deduplication-tests)
4. [LLM Processing Tests](#4-llm-processing-tests)
5. [Email Generation Tests](#5-email-generation-tests)
6. [Dashboard Tests](#6-dashboard-tests)
7. [Multi-Client Tests](#7-multi-client-tests)
8. [Error Handling Tests](#8-error-handling-tests)
9. [Performance Tests](#9-performance-tests)
10. [End-to-End Tests](#10-end-to-end-tests)

---

## 1. Data Pipeline Tests

### 1.1 Google Sheets Input
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DP-001 | Read sheet with 50 valid URLs | All 50 URLs processed |
| DP-002 | Read sheet with empty rows | Empty rows skipped |
| DP-003 | Read sheet with missing Genre column | URLs with missing genre logged as errors |
| DP-004 | Read sheet with invalid Genre | Invalid genre logged, URL skipped |
| DP-005 | Read sheet with 250 URLs | Only first 200 processed (cap enforced) |

### 1.2 HTTP Fetching
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DP-006 | Fetch valid article URL | HTML content returned |
| DP-007 | Fetch 404 URL | Error logged, URL skipped |
| DP-008 | Fetch timeout (>30s) | Timeout error logged, URL skipped |
| DP-009 | Fetch with redirect | Final URL followed, content retrieved |
| DP-010 | Concurrent fetch (5 URLs) | All fetched in parallel, no blocking |

### Acceptance Criteria
- [ ] All valid genres from list are accepted
- [ ] Invalid genres are logged and skipped
- [ ] HTTP errors are retried 3 times before failing
- [ ] Concurrency is limited to 5 simultaneous requests

---

## 2. Publish Date Validation Tests

### 2.1 Date Extraction Tiers
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| PD-001 | Article with JSON-LD datePublished | Date extracted, confidence 0.95 |
| PD-002 | Article with OG:published_time only | Date extracted, confidence 0.90 |
| PD-003 | Article with meta pubdate only | Date extracted, confidence 0.80 |
| PD-004 | Article with <time datetime> only | Date extracted, confidence 0.70 |
| PD-005 | Article with URL date pattern only | Date extracted, confidence 0.50 |
| PD-006 | Article with no date indicators | URL skipped, logged as "no publish date" |

### 2.2 Time Window Validation
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| PD-007 | Article published 2 hours ago | Included in output |
| PD-008 | Article published 23 hours ago | Included in output |
| PD-009 | Article published 25 hours ago | Excluded, logged as "outside window" |
| PD-010 | Article published 1 week ago | Excluded, logged as "outside window" |
| PD-011 | Article published 1 hour in future | Excluded, logged as "future date" |

### 2.3 Timezone Handling
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| PD-012 | Date in UTC format | Correctly parsed and compared |
| PD-013 | Date in ISO 8601 with offset | Correctly parsed with timezone |
| PD-014 | Date without timezone | Assumed UTC, processed correctly |
| PD-015 | Run at 06:59 UK time | Uses previous day's 07:00 as window end |
| PD-016 | Run at 07:01 UK time | Uses today's 07:00 as window end |

### Acceptance Criteria
- [ ] All 5 extraction tiers work correctly
- [ ] Stories outside 24h window are excluded
- [ ] Confidence scores are assigned based on source
- [ ] UK timezone is respected for window calculation

---

## 3. Deduplication Tests

### 3.1 URL Deduplication
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DD-001 | Same URL submitted twice | Second occurrence removed |
| DD-002 | URL with different query params | Canonical URL used, duplicate detected |
| DD-003 | http vs https versions | Canonical URL normalizes, duplicate detected |

### 3.2 Title Deduplication
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DD-004 | Identical titles from different URLs | Second story removed |
| DD-005 | Titles differing only in punctuation | Both kept (different normalized) |
| DD-006 | Short identical titles (<20 chars) | Both kept (too short for comparison) |

### 3.3 Content Deduplication
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DD-007 | Syndicated article on 2 sites | Duplicate detected by content hash |
| DD-008 | Similar articles with different content | Both kept (different fingerprint) |

### 3.4 Quality Selection
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DD-009 | Duplicate with different confidence | Higher confidence version kept |
| DD-010 | Duplicate with same confidence | First encountered kept |

### Acceptance Criteria
- [ ] Canonical URL deduplication works
- [ ] Title similarity detection works for titles > 20 chars
- [ ] Content fingerprint catches syndicated content
- [ ] Higher quality version is always preserved

---

## 4. LLM Processing Tests

### 4.1 Content Generation
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| LM-001 | Generate summary for tech article | 3-6 sentences, factual, no hallucination |
| LM-002 | Generate "why matters" for agency | Max 3 sentences, marketing focus |
| LM-003 | Polish sensationalist title | Neutral, factual title returned |
| LM-004 | Score agency relevance | Score 1-5 based on practical implications |

### 4.2 Content Rules
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| LM-005 | Article with uncertain facts | Summary includes "reportedly" or similar |
| LM-006 | Article with statistics | Statistics reproduced accurately |
| LM-007 | Empty article body | Fallback summary used |
| LM-008 | Very long article (>10k words) | Truncated input, valid output |

### 4.3 Error Handling
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| LM-009 | LLM API timeout | Fallback values used, error logged |
| LM-010 | Invalid JSON response | Fallback values used, error logged |
| LM-011 | Rate limit error | Retry with backoff |

### Acceptance Criteria
- [ ] Summary is 3-6 sentences maximum
- [ ] "Why matters" is max 3 sentences, agency-focused
- [ ] No facts are invented
- [ ] Uncertainty is signaled when appropriate
- [ ] Fallback values work on error

---

## 5. Email Generation Tests

### 5.1 Email Structure
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EM-001 | Email with 42 stories | Header + Top Signals + Genre sections |
| EM-002 | Email with 0 stories | No-news variant message shown |
| EM-003 | Consecutive no-news days | Different variant each day (rotating) |

### 5.2 Content Accuracy
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EM-004 | Top 5 signals section | Correct 5 highest-scored stories |
| EM-005 | Genre section headers | Correct color for each genre |
| EM-006 | Story card content | Title linked, summary, why matters shown |

### 5.3 Formatting
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EM-007 | View on desktop client | Renders correctly |
| EM-008 | View on mobile | Responsive layout works |
| EM-009 | View in Outlook | Compatible HTML rendering |
| EM-010 | Special characters in content | Properly encoded |

### 5.4 Delivery
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EM-011 | Send via IONOS SMTP | Email delivered |
| EM-012 | Multiple recipients | All receive email |
| EM-013 | Invalid recipient | Error logged, others still receive |

### Acceptance Criteria
- [ ] Email matches template specification
- [ ] Genre colors are correctly applied
- [ ] Mobile-friendly responsive design
- [ ] No-news variants rotate correctly
- [ ] SMTP delivery succeeds

---

## 6. Dashboard Tests

### 6.1 Today View
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DB-001 | Load today's stories | Grouped by genre, max 6 per genre |
| DB-002 | Story card displays | Title, source, summary, why matters |
| DB-003 | Click story card | Navigates to detail view |
| DB-004 | Genre header colors | Match color mapping |

### 6.2 Archive View
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DB-005 | Calendar shows data indicators | Dots on dates with stories |
| DB-006 | Select past date | Stories for that date displayed |
| DB-007 | Select date with no data | "No stories" message |

### 6.3 Search View
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DB-008 | Text search "AI healthcare" | Matching stories returned |
| DB-009 | Filter by genre | Only that genre shown |
| DB-010 | Filter by date range | Stories within range shown |
| DB-011 | Combined filters | Intersection of all filters |
| DB-012 | Pagination | 20 per page, load more works |

### 6.4 Story Detail
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DB-013 | Display all metadata | Title, source, date, confidence, score |
| DB-014 | External link | Opens original article |
| DB-015 | Extraction notes | Shows method, date source, word count |

### 6.5 Admin
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| DB-016 | List clients | All clients shown with status |
| DB-017 | Edit client | Changes saved, reflected in list |
| DB-018 | Add recipient | Recipient added to list |
| DB-019 | View run history | Runs shown with counts |

### Acceptance Criteria
- [ ] All 5 pages function correctly
- [ ] Genre colors consistent throughout
- [ ] Search and filters work
- [ ] Admin can manage clients
- [ ] Responsive on mobile

---

## 7. Multi-Client Tests

### 7.1 Client Isolation
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| MC-001 | Client A stories | Only Client A data visible |
| MC-002 | Client selector switch | Data updates to new client |
| MC-003 | Run for Client A only | Client B unaffected |

### 7.2 Configuration
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| MC-004 | Different sheet per client | Each reads own sheet |
| MC-005 | Different recipients per client | Emails sent to correct lists |
| MC-006 | Different caps per client | Caps respected per client |

### 7.3 Concurrent Runs
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| MC-007 | Run 2 clients simultaneously | Both complete without conflict |
| MC-008 | One client fails, other succeeds | Failure isolated to one client |

### Acceptance Criteria
- [ ] Data is isolated per client
- [ ] Configuration is independent
- [ ] Failures don't cascade

---

## 8. Error Handling Tests

### 8.1 Recoverable Errors
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EH-001 | Transient network error | Retry succeeds, story processed |
| EH-002 | Temporary API rate limit | Backoff and retry succeeds |

### 8.2 Logged Errors
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EH-003 | 404 page | Error logged with URL, stage "fetch" |
| EH-004 | Paywall detected | Error logged, reason "paywalled" |
| EH-005 | No publish date | Error logged, reason "no publish date" |
| EH-006 | Invalid genre | Error logged, reason "invalid genre" |

### 8.3 Critical Errors
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EH-007 | Database connection lost | Admin alert sent |
| EH-008 | LLM API completely down | Fallback used, alert sent |
| EH-009 | SMTP failure | Alert sent via backup channel |

### 8.4 Idempotency
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| EH-010 | Re-run same day | No duplicate stories created |
| EH-011 | Partial failure, re-run | Picks up where it left off |

### Acceptance Criteria
- [ ] All errors are logged with context
- [ ] Transient errors are retried
- [ ] Critical failures trigger alerts
- [ ] Re-runs are idempotent

---

## 9. Performance Tests

### 9.1 Throughput
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| PF-001 | Process 200 URLs | Completes within 15 minutes |
| PF-002 | Fetch 50 URLs concurrently | No rate limiting issues |
| PF-003 | Store 60 stories | Database writes < 10 seconds |

### 9.2 Scalability
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| PF-004 | Dashboard with 30 days data | Page loads < 3 seconds |
| PF-005 | Search across 1000+ stories | Results return < 2 seconds |
| PF-006 | 10 clients daily runs | All complete before 07:00 |

### Acceptance Criteria
- [ ] Daily run completes well before deadline
- [ ] Dashboard is responsive
- [ ] No timeout issues

---

## 10. End-to-End Tests

### 10.1 Full Daily Run
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| E2E-001 | Complete run from cron trigger | All stages complete, email sent |
| E2E-002 | Verify email content | Matches stories in database |
| E2E-003 | Verify dashboard content | Matches email content |

### 10.2 Real-World Scenarios
| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| E2E-004 | Mix of valid/invalid URLs | Valid processed, invalid logged |
| E2E-005 | Mix of in/out of window | Only in-window included |
| E2E-006 | Genre cap reached | Exactly 6 per genre in output |

---

## Sample Output Example

### Input (Google Sheet)
```
| URL                                           | Genre           |
|-----------------------------------------------|-----------------|
| https://bbc.co.uk/news/health-12345          | Healthcare      |
| https://theguardian.com/tech/ai-breakthrough | Healthcare      |
| https://ft.com/content/banking-reform        | Financial       |
| https://invalid-url.xyz                      | Healthcare      |
| https://paywalled-site.com/article           | Healthcare      |
```

### Processing Results
```
URL: https://bbc.co.uk/news/health-12345
Status: ✓ Processed
  - Published: 2026-01-02T14:32:00Z (within window)
  - Confidence: 0.95 (JSON-LD)
  - Genre: Healthcare (valid)
  - Agency Relevance: 4/5

URL: https://theguardian.com/tech/ai-breakthrough
Status: ✓ Processed
  - Published: 2026-01-02T18:45:00Z (within window)
  - Confidence: 0.90 (OpenGraph)
  - Genre: Healthcare (valid)
  - Agency Relevance: 5/5

URL: https://ft.com/content/banking-reform
Status: ✓ Processed
  - Published: 2026-01-03T06:00:00Z (within window)
  - Confidence: 0.95 (JSON-LD)
  - Genre: Financial (valid)
  - Agency Relevance: 3/5

URL: https://invalid-url.xyz
Status: ✗ Skipped
  - Reason: HTTP 404 - Page not found

URL: https://paywalled-site.com/article
Status: ✗ Skipped
  - Reason: Paywall detected (content < 300 chars)
```

### Email Output
```
Subject: 44 News Automation — Morning Brief — Friday, 3 January 2026

Top Signals:
• Major AI Breakthrough Promises to Transform Healthcare Diagnostics
• NHS Announces Partnership with Tech Giants for Digital Health

Healthcare (2 stories)
━━━━━━━━━━━━━━━━━━━━━

Major AI Breakthrough Promises to Transform Healthcare Diagnostics
The Guardian | 2 Jan 2026

Researchers at Cambridge University have developed a new AI system capable of
detecting early-stage cancers with 95% accuracy, significantly outperforming
current diagnostic methods. The technology uses deep learning algorithms...

Why this matters: Healthcare marketing agencies should prepare for increased
client interest in AI-driven diagnostic solutions. This development may accelerate
digital health budgets across the NHS and private sector.

[Read more →]

---

NHS Announces Partnership with Tech Giants for Digital Health
BBC News | 2 Jan 2026

The National Health Service has signed a landmark agreement with major technology
companies to accelerate digital transformation across hospitals...

Why this matters: Agencies with healthcare clients should anticipate RFPs for
digital health communications as NHS trusts implement new technology partnerships.

[Read more →]

Financial (1 story)
━━━━━━━━━━━━━━━━━━

[Story cards continue...]
```

### Database Records

#### runs table
```json
{
  "id": "run-uuid-123",
  "client_id": "client-uuid-456",
  "run_date": "2026-01-03",
  "status": "completed",
  "started_at": "2026-01-03T07:00:02Z",
  "completed_at": "2026-01-03T07:08:45Z",
  "urls_processed": 5,
  "urls_skipped": 2,
  "stories_created": 3,
  "email_sent": true
}
```

#### stories table
```json
{
  "id": "story-uuid-789",
  "client_id": "client-uuid-456",
  "run_id": "run-uuid-123",
  "genre": "Healthcare",
  "polished_title": "Major AI Breakthrough Promises to Transform Healthcare Diagnostics",
  "summary": "Researchers at Cambridge University have developed...",
  "why_matters": "Healthcare marketing agencies should prepare...",
  "source_name": "The Guardian",
  "published_at": "2026-01-02T18:45:00Z",
  "publish_date_confidence": 0.90,
  "agency_relevance_score": 5,
  "genre_rank": 1,
  "is_top_signal": true
}
```

#### errors table
```json
{
  "id": "error-uuid-abc",
  "client_id": "client-uuid-456",
  "run_id": "run-uuid-123",
  "url": "https://invalid-url.xyz",
  "stage": "fetch",
  "error_type": "http_404",
  "error_message": "HTTP 404 - Page not found"
}
```

---

## Sign-Off Checklist

### Before Production Launch
- [ ] All test categories pass
- [ ] Manual end-to-end test completed
- [ ] Email renders correctly in major clients
- [ ] Dashboard tested on mobile
- [ ] Admin can manage clients
- [ ] Alerts working for critical errors
- [ ] Performance within acceptable limits
- [ ] Documentation reviewed
- [ ] Credentials secured (env vars)
- [ ] Backup/recovery tested
