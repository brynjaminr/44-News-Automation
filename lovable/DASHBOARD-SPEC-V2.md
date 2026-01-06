# 44 News Automation - Lovable Dashboard Build Specification V2

> Complete build specification for Lovable.dev to create the production dashboard.

---

## Overview

Build a **44 News Automation Dashboard** that allows agency clients to:
- Browse today's news stories grouped by genre
- Access 30+ days of archive with filtering
- Search across all stories
- View individual story details
- Admin: manage clients, recipients, and settings

**Tech Stack**: React + TypeScript + Tailwind CSS + Supabase (database + auth)

**Backend**: PostgreSQL database, n8n handles automation

---

## Design System

### Brand Colors

```css
/* Primary */
--primary-blue: #003d96;
--primary-gradient: linear-gradient(135deg, #003d96 0%, #0056b3 100%);

/* Background */
--bg-main: #f3feff;
--bg-card: #ffffff;
--bg-section: #f8fafc;

/* Text */
--text-primary: #003d96;
--text-body: #334155;
--text-muted: #64748b;

/* Accents */
--accent-info: #0284c7;
--accent-success: #059669;
--accent-warning: #ca8a04;
--accent-error: #dc2626;

/* Why Matters highlight */
--why-matters-bg: #e0f2fe;
--why-matters-border: #0284c7;
--why-matters-text: #0369a1;
```

### Genre Color Mapping (REQUIRED)

All 26 genres have distinct, readable colors on #f3feff background:

```typescript
export const GENRE_COLORS: Record<string, string> = {
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
  'Household Consumer Goods': '#d97706',
};
```

### Typography

- **Headings**: Inter or System UI, font-weight: 600-700
- **Body**: Inter or System UI, font-weight: 400
- **Monospace** (for URLs): JetBrains Mono or Fira Code

---

## Database Schema (Supabase/PostgreSQL)

### Tables

**clients**
```sql
id: uuid (primary key)
name: varchar(255)
slug: varchar(100) unique
sheet_id: varchar(255)
recipients: jsonb
max_stories_per_day: integer (default 60)
max_stories_per_genre: integer (default 6)
timezone: varchar(50) (default 'Europe/London')
send_time: time (default '07:00:00')
is_active: boolean (default true)
created_at: timestamptz
updated_at: timestamptz
```

**runs**
```sql
id: uuid (primary key)
client_id: uuid (references clients)
run_date: date
run_number: integer
status: varchar(20) -- pending, running, completed, failed
started_at: timestamptz
completed_at: timestamptz
stories_created: integer
error_count: integer
email_sent: boolean
created_at: timestamptz
```

**stories**
```sql
id: uuid (primary key)
client_id: uuid (references clients)
run_id: uuid (references runs)
genre: varchar(100)
canonical_url: text
source_name: varchar(255)
original_title: text
polished_title: text
summary: text
why_matters: text
published_at: timestamptz
agency_relevance_score: integer (1-5)
genre_rank: integer
overall_rank: integer
is_top_signal: boolean
created_at: timestamptz
```

**genres**
```sql
id: serial (primary key)
name: varchar(100) unique
color: varchar(7)
display_order: integer
```

---

## Page Structure

### Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  SIDEBAR (240px)           │  MAIN CONTENT                      │
│  ──────────────            │  ────────────                      │
│                            │                                     │
│  ┌────────────────────┐    │  ┌─────────────────────────────┐   │
│  │ 44 News Automation │    │  │ Page Header + Actions       │   │
│  │ Daily Briefing     │    │  └─────────────────────────────┘   │
│  └────────────────────┘    │                                     │
│                            │  ┌─────────────────────────────┐   │
│  Client Selector ▼         │  │ Page Content                │   │
│                            │  │                             │   │
│  Navigation:               │  │                             │   │
│  • Today                   │  │                             │   │
│  • Archive                 │  │                             │   │
│  • Search                  │  │                             │   │
│  • Admin (if authorized)   │  │                             │   │
│                            │  └─────────────────────────────┘   │
│                            │                                     │
│  ┌────────────────────┐    │                                     │
│  │ Footer             │    │                                     │
│  │ "Stay informed"    │    │                                     │
│  └────────────────────┘    │                                     │
│                            │                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pages

### 1. Today (`/` or `/today`)

**Purpose**: Display today's stories grouped by genre.

**Components**:

#### Header Section
- Title: "Today's Briefing"
- Date: "Monday, 6 January 2026"
- Stats row:
  - Total stories: X
  - Genres covered: Y
  - Sources: Z

#### Top Signals Section (if stories exist)
```
┌─────────────────────────────────────────────────────────────┐
│ ★ TOP SIGNALS                                               │
│ ─────────────────────────────────────────────────────────── │
│ • Story title one (link)                                    │
│ • Story title two (link)                                    │
│ • Story title three (link)                                  │
│ • Story title four (link)                                   │
│ • Story title five (link)                                   │
└─────────────────────────────────────────────────────────────┘
```

#### Genre Sections
For each genre with stories:

```
┌─────────────────────────────────────────────────────────────┐
│ ████████████████████████████████████████████████████████████│
│ █  FINANCIAL (green header)                                █│
│ ████████████████████████████████████████████████████████████│
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Story Card                                              ││
│ │ ─────────────────────────────────────────────────────── ││
│ │ **Polished Title Here** (clickable link)               ││
│ │ Source: Financial Times                                 ││
│ │                                                         ││
│ │ Summary text here. This is a 3-6 sentence summary of   ││
│ │ the article content that is factual and professional.  ││
│ │                                                         ││
│ │ ┌───────────────────────────────────────────────────┐  ││
│ │ │ WHY THIS MATTERS: Agency-focused analysis here.  │  ││
│ │ │ One practical marketing implication included.     │  ││
│ │ └───────────────────────────────────────────────────┘  ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ [More story cards...]                                       │
└─────────────────────────────────────────────────────────────┘
```

#### No Stories State
```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  📭 No Stories Today                                        │
│                                                             │
│  Today's scan found no stories meeting our quality          │
│  criteria within the 24-hour window. Check back tomorrow.   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Data Query**:
```typescript
const { data: stories } = await supabase
  .from('stories')
  .select(`
    id, genre, canonical_url, source_name,
    polished_title, summary, why_matters,
    published_at, agency_relevance_score,
    genre_rank, is_top_signal
  `)
  .eq('client_id', selectedClientId)
  .gte('published_at', todayStart)
  .lte('published_at', todayEnd)
  .order('genre')
  .order('genre_rank');
```

---

### 2. Archive (`/archive`)

**Purpose**: Browse historical stories with date and genre filters.

**Components**:

#### Filter Bar
```
┌─────────────────────────────────────────────────────────────┐
│ Date Range: [Jan 1] - [Jan 6]  │  Genre: [All Genres ▼]    │
│                                │                            │
│ [Apply Filters]                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Calendar Navigation
- Show last 30 days as clickable dates
- Highlight dates with stories
- Show story count per date

#### Results Grid
- Display stories in card format
- Group by date OR genre (toggle)
- Pagination: 20 stories per page

**Data Query**:
```typescript
const { data: stories, count } = await supabase
  .from('stories')
  .select('*', { count: 'exact' })
  .eq('client_id', selectedClientId)
  .gte('published_at', dateFrom)
  .lte('published_at', dateTo)
  .eq(genre ? 'genre' : 'client_id', genre || selectedClientId)
  .order('published_at', { ascending: false })
  .range(offset, offset + limit - 1);
```

---

### 3. Search (`/search`)

**Purpose**: Full-text search across all stories.

**Components**:

#### Search Box
```
┌─────────────────────────────────────────────────────────────┐
│  🔍 [Search stories...                              ] [Go]  │
│                                                             │
│  Filters: [Genre ▼] [Date Range ▼] [Source ▼]              │
└─────────────────────────────────────────────────────────────┘
```

#### Search Results
- Show relevance score
- Highlight matching terms
- Display story cards with truncated summary

#### Empty State
```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  🔍 No results found for "your search term"                │
│                                                             │
│  Try:                                                       │
│  • Using different keywords                                 │
│  • Removing filters                                         │
│  • Checking for typos                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Data Query**:
```typescript
const { data: results } = await supabase
  .rpc('search_stories', {
    p_client_id: selectedClientId,
    p_search_term: searchTerm,
    p_genre: selectedGenre,
    p_date_from: dateFrom,
    p_date_to: dateTo,
    p_limit: 50
  });
```

---

### 4. Story Detail (`/story/:id`)

**Purpose**: Full story view with all details.

**Layout**:
```
┌─────────────────────────────────────────────────────────────┐
│ ← Back to Today                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ┌─────────────┐                                             │
│ │ Genre Badge │  Published: Jan 6, 2026 • 09:30 AM         │
│ └─────────────┘                                             │
│                                                             │
│ # Polished Title Here                                       │
│                                                             │
│ Source: Financial Times                                     │
│ Original URL: [Open Article →]                              │
│                                                             │
│ ─────────────────────────────────────────────────────────── │
│                                                             │
│ ## Summary                                                  │
│                                                             │
│ Full summary text displayed here with proper paragraph      │
│ formatting. This contains 3-6 sentences of factual,        │
│ professional content summarizing the article.               │
│                                                             │
│ ─────────────────────────────────────────────────────────── │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ 💡 WHY THIS MATTERS                                     ││
│ │                                                         ││
│ │ Agency-focused analysis explaining the significance.    ││
│ │ Includes one practical marketing implication. Never     ││
│ │ invents facts that weren't in the original article.     ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ ─────────────────────────────────────────────────────────── │
│                                                             │
│ Agency Relevance Score: ★★★★☆ (4/5)                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### 5. Admin (`/admin`) - Protected

**Purpose**: Manage clients, recipients, and settings.

**Tabs**:

#### Clients Tab
- List all clients with status
- Add/Edit client form:
  - Name
  - Slug (auto-generated)
  - Google Sheet ID
  - Recipients (tag input)
  - Max stories per day
  - Max stories per genre
  - Timezone
  - Send time
  - Active toggle

#### Recipients Tab
- View/edit recipient list per client
- Add single or bulk recipients
- Remove recipients

#### Runs Tab
- View run history
- Status badges (completed, failed, running)
- Story counts
- Error counts
- Manual trigger button (POST to n8n webhook)

#### Settings Tab
- Global configuration
- Admin email for alerts
- Default caps

---

## Components Library

### GenreBadge
```tsx
interface GenreBadgeProps {
  genre: string;
  size?: 'sm' | 'md' | 'lg';
}

function GenreBadge({ genre, size = 'md' }: GenreBadgeProps) {
  const color = GENRE_COLORS[genre] || '#003d96';
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full font-medium text-white',
        size === 'sm' && 'px-2 py-0.5 text-xs',
        size === 'md' && 'px-3 py-1 text-sm',
        size === 'lg' && 'px-4 py-1.5 text-base'
      )}
      style={{ backgroundColor: color }}
    >
      {genre}
    </span>
  );
}
```

### StoryCard
```tsx
interface StoryCardProps {
  story: Story;
  showGenre?: boolean;
  compact?: boolean;
}

function StoryCard({ story, showGenre = true, compact = false }: StoryCardProps) {
  return (
    <div className="bg-white rounded-lg p-5 shadow-sm border-l-4 border-gray-200 hover:border-[#003d96] transition-colors">
      {showGenre && <GenreBadge genre={story.genre} size="sm" />}

      <h3 className="mt-2 text-lg font-semibold">
        <a
          href={story.canonical_url}
          target="_blank"
          rel="noopener noreferrer"
          className="text-[#003d96] hover:underline"
        >
          {story.polished_title}
        </a>
      </h3>

      <p className="text-sm text-gray-500 mt-1">
        {story.source_name} • {formatDate(story.published_at)}
      </p>

      {!compact && (
        <>
          <p className="mt-3 text-gray-700">{story.summary}</p>

          <div className="mt-4 bg-[#e0f2fe] border-l-3 border-[#0284c7] rounded-r-md p-3">
            <p className="text-sm text-[#0369a1]">
              <strong>Why this matters:</strong> {story.why_matters}
            </p>
          </div>
        </>
      )}
    </div>
  );
}
```

### GenreSection
```tsx
interface GenreSectionProps {
  genre: string;
  stories: Story[];
}

function GenreSection({ genre, stories }: GenreSectionProps) {
  const color = GENRE_COLORS[genre] || '#003d96';

  return (
    <section className="mb-8">
      <div
        className="text-white font-semibold px-5 py-3 rounded-lg mb-4"
        style={{ backgroundColor: color }}
      >
        {genre}
      </div>

      <div className="space-y-4">
        {stories.map((story) => (
          <StoryCard key={story.id} story={story} showGenre={false} />
        ))}
      </div>
    </section>
  );
}
```

### TopSignals
```tsx
interface TopSignalsProps {
  stories: Story[];
}

function TopSignals({ stories }: TopSignalsProps) {
  if (stories.length === 0) return null;

  return (
    <div className="bg-[#f8fafc] border-l-4 border-[#003d96] rounded-r-lg p-5 mb-8">
      <h2 className="text-lg font-semibold text-[#003d96] mb-3">
        ★ Top Signals
      </h2>
      <ul className="space-y-2">
        {stories.map((story) => (
          <li key={story.id}>
            <a
              href={story.canonical_url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-[#003d96] hover:underline"
            >
              {story.polished_title}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}
```

### ClientSelector
```tsx
function ClientSelector() {
  const { clients, selectedClient, setSelectedClient } = useClientContext();

  return (
    <select
      value={selectedClient?.id || ''}
      onChange={(e) => {
        const client = clients.find(c => c.id === e.target.value);
        setSelectedClient(client);
      }}
      className="w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:ring-[#003d96] focus:border-[#003d96]"
    >
      {clients.map((client) => (
        <option key={client.id} value={client.id}>
          {client.name}
        </option>
      ))}
    </select>
  );
}
```

---

## State Management

### Client Context
```tsx
interface ClientContextType {
  clients: Client[];
  selectedClient: Client | null;
  setSelectedClient: (client: Client) => void;
  isLoading: boolean;
}

const ClientContext = createContext<ClientContextType | undefined>(undefined);

function ClientProvider({ children }: { children: React.ReactNode }) {
  const [clients, setClients] = useState<Client[]>([]);
  const [selectedClient, setSelectedClient] = useState<Client | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function loadClients() {
      const { data } = await supabase
        .from('clients')
        .select('*')
        .eq('is_active', true)
        .order('name');

      if (data) {
        setClients(data);
        setSelectedClient(data[0] || null);
      }
      setIsLoading(false);
    }
    loadClients();
  }, []);

  return (
    <ClientContext.Provider value={{ clients, selectedClient, setSelectedClient, isLoading }}>
      {children}
    </ClientContext.Provider>
  );
}
```

---

## API Hooks

### useStories
```typescript
function useStories(clientId: string, date?: Date) {
  return useQuery({
    queryKey: ['stories', clientId, date?.toISOString()],
    queryFn: async () => {
      const startOfDay = date
        ? new Date(date.setHours(0, 0, 0, 0))
        : new Date(new Date().setHours(0, 0, 0, 0));
      const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);

      const { data, error } = await supabase
        .from('stories')
        .select('*')
        .eq('client_id', clientId)
        .gte('published_at', startOfDay.toISOString())
        .lt('published_at', endOfDay.toISOString())
        .order('genre')
        .order('genre_rank');

      if (error) throw error;
      return data;
    },
    enabled: !!clientId,
  });
}
```

### useGenreStats
```typescript
function useGenreStats(clientId: string) {
  return useQuery({
    queryKey: ['genre-stats', clientId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_genre_distribution')
        .select('*')
        .eq('client_id', clientId);

      if (error) throw error;
      return data;
    },
    enabled: !!clientId,
  });
}
```

---

## Responsive Design

### Breakpoints
- **Mobile**: < 640px
- **Tablet**: 640px - 1024px
- **Desktop**: > 1024px

### Mobile Adaptations
- Sidebar collapses to bottom navigation
- Single column layout
- Stacked filter controls
- Larger touch targets

---

## Loading States

- Skeleton loaders for story cards
- Spinner for search results
- Optimistic UI updates where possible
- Toast notifications for actions

---

## Error Handling

- Error boundaries for components
- Toast notifications for API errors
- Retry buttons on failed loads
- Graceful degradation

---

## Build Prompt for Lovable

Copy this into Lovable:

```
Build a "44 News Automation" dashboard for marketing agencies to browse daily news briefings.

Tech: React + TypeScript + Tailwind CSS + Supabase

Brand Colors:
- Primary: #003d96 (dark blue)
- Background: #f3feff (light cyan)
- Cards: white with subtle shadows

Pages:
1. Today (/) - Display today's news stories grouped by genre. Include "Top Signals" section at top with 5 best stories. Each genre has colored header matching genre color. Story cards show: title (link), source, summary, and "Why this matters" in light blue highlight box.

2. Archive (/archive) - Calendar view to browse past 30 days. Filter by date range and genre. Paginated story list.

3. Search (/search) - Full-text search with filters for genre and date. Show relevance-sorted results.

4. Story Detail (/story/:id) - Full view of single story with all metadata.

5. Admin (/admin) - Manage clients and recipients. View run history. Protected route.

Key Features:
- Multi-client support with client selector in sidebar
- 26 genre types each with distinct color
- Story cards with "Why this matters" section highlighted
- Mobile responsive with collapsible sidebar
- Connect to Supabase PostgreSQL database

Database tables: clients, runs, stories, genres (schemas attached)

Navigation: Sidebar with logo "44 News Automation - Daily Briefing", client selector dropdown, and nav links.
```

---

## Acceptance Criteria

- [ ] Today page displays stories grouped by genre
- [ ] Genre headers use correct colors from mapping
- [ ] Top Signals section shows top 5 stories
- [ ] Story cards display title, source, summary, why matters
- [ ] Why matters section has light blue background
- [ ] Archive allows filtering by date and genre
- [ ] Search returns relevant results
- [ ] Story detail page shows full content
- [ ] Admin can manage clients and recipients
- [ ] Client selector switches data context
- [ ] Mobile layout works on phones
- [ ] Loading states for all data fetches
- [ ] Error handling for API failures
