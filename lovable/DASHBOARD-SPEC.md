# 44 News Automation - Lovable Dashboard Specification

## Overview

A multi-client news dashboard for marketing agencies to browse daily news briefings by date, genre, and search. Built with Lovable (React + Supabase/Postgres).

## Design System

### Brand Colors
```css
:root {
  --primary: #003d96;
  --background: #f3feff;
  --surface: #ffffff;
  --text-primary: #003d96;
  --text-secondary: #64748b;
  --border: #e2e8f0;
  --success: #059669;
  --error: #dc2626;
}
```

### Typography
- Font family: Inter, system-ui, sans-serif
- Headings: Bold, #003d96
- Body: Regular, #334155
- Captions: 12px, #64748b

### Component Styling
- Cards: White background, soft shadow, rounded corners (8px)
- Buttons: Primary (#003d96), rounded (6px)
- Inputs: Border (#e2e8f0), rounded (6px), focus ring (#003d96)

---

## Genre Color Mapping

Import from `/config/genre-colors.json` and use for:
- Genre badges/pills in story cards
- Genre section headers
- Filter chips

```typescript
const genreColors: Record<string, { color: string; textColor: string }> = {
  'Office Equipment & Technology': { color: '#2563eb', textColor: '#fff' },
  'Food & Drink': { color: '#dc2626', textColor: '#fff' },
  'Telecommunications & Internet': { color: '#7c3aed', textColor: '#fff' },
  'Healthcare': { color: '#059669', textColor: '#fff' },
  'Education': { color: '#0891b2', textColor: '#fff' },
  'Tobacco & E-cigarettes': { color: '#57534e', textColor: '#fff' },
  'Charity & Nonprofit': { color: '#db2777', textColor: '#fff' },
  'Fashion': { color: '#c026d3', textColor: '#fff' },
  'Retail': { color: '#ea580c', textColor: '#fff' },
  'Professional & Business Services': { color: '#4f46e5', textColor: '#fff' },
  'Property & Construction': { color: '#ca8a04', textColor: '#fff' },
  'Agencies': { color: '#0d9488', textColor: '#fff' },
  'Entertainment': { color: '#e11d48', textColor: '#fff' },
  'Transportation & Logistics': { color: '#1d4ed8', textColor: '#fff' },
  'Consumer Electronics': { color: '#6366f1', textColor: '#fff' },
  'Travel & Tourism': { color: '#0284c7', textColor: '#fff' },
  'Financial': { color: '#15803d', textColor: '#fff' },
  'Utilities & Energy': { color: '#a16207', textColor: '#fff' },
  'Leisure & Hospitality': { color: '#be185d', textColor: '#fff' },
  'Media & Publishing': { color: '#9333ea', textColor: '#fff' },
  'Government & Public Sector': { color: '#1e40af', textColor: '#fff' },
  'Cosmetics & Personal Care': { color: '#ec4899', textColor: '#fff' },
  'Home & Garden': { color: '#65a30d', textColor: '#fff' },
  'Automotive': { color: '#b91c1c', textColor: '#fff' },
  'Manufacturing & Industrial': { color: '#475569', textColor: '#fff' },
  'Household Consumer Goods': { color: '#d97706', textColor: '#fff' },
};
```

---

## Pages

### 1. Today (Default - `/`)

**Purpose:** Display today's news briefing grouped by genre

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  [Logo] 44 News Automation     [Client Dropdown ▼]     │
├─────────────────────────────────────────────────────────┤
│  Today  │  Archive  │  Search  │  Admin                │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Friday, 3 January 2026                    [Refresh]   │
│  42 stories from 18 sources                             │
│                                                         │
│  ┌─ Healthcare ─────────────────────────────────────┐  │
│  │  [Story Card]  [Story Card]  [Story Card]        │  │
│  │  [Story Card]  [Story Card]  [Story Card]        │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ Financial ──────────────────────────────────────┐  │
│  │  [Story Card]  [Story Card]  [Story Card]        │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ... more genres ...                                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Components:**
- `Header` with logo, client selector
- `Navigation` tabs
- `DateDisplay` showing current date and story count
- `GenreSection` for each genre with stories
- `StoryCard` grid (3 columns desktop, 1 mobile)

**Data Query:**
```sql
SELECT s.*, g.color as genre_color
FROM stories s
JOIN runs r ON s.run_id = r.id
JOIN genres g ON s.genre = g.name
WHERE r.run_date = CURRENT_DATE
  AND r.client_id = :clientId
ORDER BY s.genre, s.genre_rank
```

---

### 2. Archive (`/archive`)

**Purpose:** Browse past briefings by date

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  Header + Navigation                                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─ Calendar ───────────────────────────────────────┐  │
│  │  < January 2026 >                                │  │
│  │  Su Mo Tu We Th Fr Sa                            │  │
│  │     [•] [•] [3] ... (dots = has data)            │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Selected: Thursday, 2 January 2026                    │
│  38 stories                                             │
│                                                         │
│  [Same genre sections as Today view]                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Components:**
- `CalendarPicker` with dots indicating dates with data
- `DateHeader` for selected date
- Same `GenreSection` and `StoryCard` components

**Data Query:**
```sql
-- Get dates with data for calendar
SELECT DISTINCT run_date, COUNT(s.id) as story_count
FROM runs r
LEFT JOIN stories s ON s.run_id = r.id
WHERE r.client_id = :clientId
  AND r.run_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY r.run_date
ORDER BY r.run_date DESC

-- Get stories for selected date
SELECT s.*, g.color as genre_color
FROM stories s
JOIN runs r ON s.run_id = r.id
JOIN genres g ON s.genre = g.name
WHERE r.run_date = :selectedDate
  AND r.client_id = :clientId
ORDER BY s.genre, s.genre_rank
```

---

### 3. Search/Filter (`/search`)

**Purpose:** Find stories by genre, source, date, or text search

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  Header + Navigation                                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─ Filters ────────────────────────────────────────┐  │
│  │  [🔍 Search stories...                         ] │  │
│  │                                                   │  │
│  │  Genre:  [All ▼]         Source: [All ▼]        │  │
│  │  Date:   [From] - [To]   Confidence: [0.5+]     │  │
│  │                                                   │  │
│  │  [Reset Filters]                                 │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Showing 127 results                                    │
│                                                         │
│  [Story Card]                                           │
│  [Story Card]                                           │
│  [Story Card]                                           │
│  ...                                                    │
│                                                         │
│  [Load More]                                            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Components:**
- `SearchInput` with debounced text search
- `FilterDropdown` for genre (multiselect)
- `FilterDropdown` for source
- `DateRangePicker` for date filtering
- `ConfidenceSlider` for publish date confidence filter
- `StoryList` with pagination

**Data Query:**
```sql
SELECT s.*, g.color as genre_color
FROM stories s
JOIN runs r ON s.run_id = r.id
JOIN genres g ON s.genre = g.name
WHERE r.client_id = :clientId
  AND (:searchTerm IS NULL OR
       s.polished_title ILIKE '%' || :searchTerm || '%' OR
       s.summary ILIKE '%' || :searchTerm || '%')
  AND (:genre IS NULL OR s.genre = :genre)
  AND (:source IS NULL OR s.source_name = :source)
  AND (:dateFrom IS NULL OR r.run_date >= :dateFrom)
  AND (:dateTo IS NULL OR r.run_date <= :dateTo)
  AND (:minConfidence IS NULL OR s.publish_date_confidence >= :minConfidence)
ORDER BY s.published_at DESC
LIMIT 20 OFFSET :offset
```

---

### 4. Story Detail (`/story/:id`)

**Purpose:** Full story view with all metadata

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  Header + Navigation                                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ← Back to Today                                        │
│                                                         │
│  ┌─ Story ──────────────────────────────────────────┐  │
│  │  [Genre Badge: Healthcare]                        │  │
│  │                                                   │  │
│  │  Major Hospital Network Announces AI             │  │
│  │  Diagnostic Partnership                          │  │
│  │                                                   │  │
│  │  Source: BBC News                                │  │
│  │  Published: 2 January 2026, 14:32 UTC            │  │
│  │  Confidence: 95%                                 │  │
│  │  Agency Relevance: ★★★★☆                         │  │
│  │                                                   │  │
│  │  ─────────────────────────────────────────────── │  │
│  │                                                   │  │
│  │  Summary:                                        │  │
│  │  [3-6 sentence summary]                          │  │
│  │                                                   │  │
│  │  ─────────────────────────────────────────────── │  │
│  │                                                   │  │
│  │  Why This Matters:                               │  │
│  │  [Max 3 sentences, agency-focused]               │  │
│  │                                                   │  │
│  │  ─────────────────────────────────────────────── │  │
│  │                                                   │  │
│  │  [Read Original Article →]                       │  │
│  │                                                   │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ Extraction Notes ───────────────────────────────┐  │
│  │  Method: readability                             │  │
│  │  Date Source: jsonld                             │  │
│  │  Word Count: 847                                 │  │
│  │  Canonical URL: https://...                      │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Components:**
- `BackButton`
- `GenreBadge` with genre color
- `StoryHeader` with title, source, date
- `ConfidenceIndicator` visual bar
- `RelevanceStars` (1-5 rating)
- `SummarySection`
- `WhyMattersSection` with highlight styling
- `ExternalLink` button
- `MetadataCard` collapsible with extraction details

**Data Query:**
```sql
SELECT s.*, g.color as genre_color, c.name as client_name
FROM stories s
JOIN genres g ON s.genre = g.name
JOIN clients c ON s.client_id = c.id
WHERE s.id = :storyId
```

---

### 5. Admin (`/admin`)

**Purpose:** Manage clients, recipients, settings

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  Header + Navigation                                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─ Tabs ───────────────────────────────────────────┐  │
│  │  [Clients] [Runs] [Settings]                     │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  == Clients Tab ==                                      │
│                                                         │
│  [+ Add Client]                                         │
│                                                         │
│  ┌─ Client Row ─────────────────────────────────────┐  │
│  │  44 Automation Ltd        Active    [Edit] [⚙]  │  │
│  │  Recipients: 3  |  Sheet: ...ABC123              │  │
│  │  Last run: 3 Jan 2026, 42 stories, 0 errors     │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  == Edit Client Modal ==                                │
│                                                         │
│  Name: [44 Automation Ltd        ]                     │
│  Timezone: [Europe/London ▼]                           │
│  Send Time: [07:00]                                    │
│  Sheet ID: [1ABC123...                  ]              │
│  Max Stories/Day: [60]                                 │
│  Max Stories/Genre: [6]                                │
│  Active: [✓]                                           │
│                                                         │
│  Recipients:                                            │
│  [john@example.com                 ] [×]               │
│  [jane@example.com                 ] [×]               │
│  [+ Add Recipient]                                     │
│                                                         │
│  [Cancel] [Save]                                       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Sub-tabs:**

#### Clients
- List all clients with status
- Edit client settings inline or modal
- Add/remove recipients
- Toggle active status

#### Runs
- Table of recent runs with status, counts, errors
- Filter by client, status, date
- Click to view run details/errors

#### Settings
- Global settings (read-only display of environment config)
- Test email button
- System health check

---

## Components Library

### Core Components

```typescript
// StoryCard.tsx
interface StoryCardProps {
  story: Story;
  showGenreBadge?: boolean;
  onClick?: () => void;
}

// GenreSection.tsx
interface GenreSectionProps {
  genre: string;
  color: string;
  stories: Story[];
}

// GenreBadge.tsx
interface GenreBadgeProps {
  genre: string;
  size?: 'sm' | 'md' | 'lg';
}

// ClientSelector.tsx
interface ClientSelectorProps {
  clients: Client[];
  selectedId: string;
  onChange: (clientId: string) => void;
}

// DatePicker.tsx
interface DatePickerProps {
  value: Date;
  onChange: (date: Date) => void;
  availableDates?: Date[];
}

// ConfidenceIndicator.tsx
interface ConfidenceIndicatorProps {
  value: number; // 0-1
}

// RelevanceStars.tsx
interface RelevanceStarsProps {
  score: number; // 1-5
}
```

### Layout Components

```typescript
// Header.tsx
// - Logo, client selector, user menu

// Navigation.tsx
// - Tabs: Today, Archive, Search, Admin

// PageLayout.tsx
// - Standard page wrapper with header and nav

// Card.tsx
// - Generic card with shadow, rounded corners

// Modal.tsx
// - Overlay modal for editing
```

---

## API / Data Access

### Using Supabase Client

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_ANON_KEY!
);

// Fetch today's stories
const { data: stories } = await supabase
  .from('stories')
  .select(`
    *,
    runs!inner(run_date, client_id),
    genres!inner(color)
  `)
  .eq('runs.run_date', today)
  .eq('runs.client_id', clientId)
  .order('genre')
  .order('genre_rank');
```

### API Routes (if using API layer)

```
GET /api/clients
GET /api/clients/:id
PUT /api/clients/:id
POST /api/clients

GET /api/runs?clientId=&status=&date=
GET /api/runs/:id

GET /api/stories?clientId=&date=&genre=&search=
GET /api/stories/:id

GET /api/genres
```

---

## State Management

Use React Context for:
- Current client selection
- User authentication (if needed)

Use React Query/SWR for:
- Story data fetching with caching
- Automatic refetch on focus
- Optimistic updates for admin actions

---

## Responsive Design

### Breakpoints
```css
/* Mobile first */
@media (min-width: 640px) { /* sm */ }
@media (min-width: 768px) { /* md */ }
@media (min-width: 1024px) { /* lg */ }
@media (min-width: 1280px) { /* xl */ }
```

### Mobile Adaptations
- Single column story cards
- Collapsible genre sections
- Bottom navigation on mobile
- Slide-out filters panel
- Full-screen story detail

---

## Sample Story Card Component

```tsx
import { Story } from '@/types';
import { genreColors } from '@/config/genre-colors';

interface StoryCardProps {
  story: Story;
  showGenreBadge?: boolean;
}

export function StoryCard({ story, showGenreBadge = false }: StoryCardProps) {
  const genreColor = genreColors[story.genre]?.color || '#003d96';

  return (
    <div
      className="bg-white rounded-lg p-5 shadow-sm border border-gray-100 hover:shadow-md transition-shadow"
      style={{ borderLeftColor: genreColor, borderLeftWidth: '4px' }}
    >
      {showGenreBadge && (
        <span
          className="inline-block px-2 py-1 text-xs font-medium text-white rounded mb-2"
          style={{ backgroundColor: genreColor }}
        >
          {story.genre}
        </span>
      )}

      <h3 className="text-lg font-semibold text-primary mb-2 line-clamp-2">
        <a
          href={story.canonical_url}
          target="_blank"
          rel="noopener noreferrer"
          className="hover:underline"
        >
          {story.polished_title}
        </a>
      </h3>

      <p className="text-xs text-secondary mb-2">
        {story.source_name}
      </p>

      <p className="text-sm text-gray-700 mb-3 line-clamp-3">
        {story.summary}
      </p>

      <div className="bg-sky-50 border-l-2 border-sky-500 p-3 rounded-r">
        <p className="text-xs text-gray-600">
          <strong className="text-sky-700">Why this matters:</strong>{' '}
          {story.why_matters}
        </p>
      </div>
    </div>
  );
}
```

---

## Deployment Checklist

1. [ ] Configure Supabase project with Postgres schema
2. [ ] Set environment variables (DATABASE_URL, etc.)
3. [ ] Configure RLS policies for multi-client access
4. [ ] Set up authentication (if required)
5. [ ] Deploy to Vercel/Netlify
6. [ ] Configure custom domain
7. [ ] Test all pages and queries
8. [ ] Verify mobile responsiveness
