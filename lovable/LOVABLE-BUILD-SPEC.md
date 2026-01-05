# 44 News Automation - Lovable Dashboard Build Specification

> Build prompt for Lovable.dev to create the user dashboard that replicates the Base44 app functionality.

---

## Overview

Build a **News Digest Dashboard** that allows users to:
- Manage news sources (add, edit, delete, toggle)
- Preview upcoming digest before sending
- Configure delivery settings, article limits, and AI tone
- View digest history and stats
- Trigger manual digest runs

**Tech Stack**: React + TypeScript + Tailwind CSS + Supabase (auth & database)

**Backend**: n8n webhooks handle article fetching, AI processing, and email sending

---

## Design System

### Colors
```
Primary Blue: #003d96
Primary Gradient: linear-gradient(135deg, #003d96, #0056b3)
Background: #f3feff (light cyan tint)
Card Background: white
Text Primary: #1f2937
Text Secondary: #6b7280
Success: #10b981
```

### Genre Badge Colors
```javascript
const genreColors = {
  'Office Equipment & Technology': '#2563eb',
  'Food & Drink': '#dc2626',
  'Telecommunications & Internet': '#7c3aed',
  'Healthcare': '#059669',
  'Education': '#0891b2',
  'Tobacco & E-cigarettes': '#78716c',
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
  'Manufacturing & Industrial': '#64748b',
  'Household Consumer Goods': '#f59e0b'
};
```

### Typography
- Headings: Inter/System UI, semibold
- Body: Inter/System UI, regular
- Monospace for URLs: JetBrains Mono or similar

---

## Database Schema (Supabase)

### Tables

**sources**
```sql
id: uuid (primary key)
user_id: uuid (references auth.users)
name: varchar(255)
url: text
genre: varchar(100)
is_active: boolean (default true)
created_at: timestamptz
updated_at: timestamptz
```

**user_settings**
```sql
id: uuid (primary key)
user_id: uuid (unique, references auth.users)
recipient_email: varchar(255)
send_time: time (default '07:00:00')
timezone: varchar(50) (default 'Europe/London')
max_per_source: integer (default 15)
max_total_articles: integer (default 200)
skip_empty_digests: boolean (default false)
email_greeting: text
email_footer: text
summary_tone: varchar(50) (default 'Professional')
why_matters_focus: varchar(50) (default 'Business Focus')
created_at: timestamptz
updated_at: timestamptz
```

**digests**
```sql
id: uuid (primary key)
user_id: uuid (references auth.users)
article_count: integer
source_count: integer
status: varchar(20) ('pending', 'processing', 'sent', 'failed')
sent_at: timestamptz
error_message: text
created_at: timestamptz
```

**articles**
```sql
id: uuid (primary key)
digest_id: uuid (references digests)
source_id: uuid (references sources)
user_id: uuid (references auth.users)
url: text
headline: text
source_name: varchar(255)
genre: varchar(100)
summary: text
why_matters: text
published_at: timestamptz
created_at: timestamptz
```

---

## Pages

### 1. Dashboard (`/dashboard`)

**Layout**:
- Header: "News Digest" logo + "Daily Briefing" subtitle
- Sidebar navigation: Dashboard, Sources, Preview, Settings
- Main content area

**Components**:

#### Stats Cards (3 columns)
1. **Active Sources**
   - Large number (count of active sources)
   - Subtitle: "{total} total sources"
   - Icon: RSS/signal icon (teal)

2. **Last Digest**
   - Large number (article count from most recent sent digest)
   - Subtitle: "articles included"
   - Icon: Document icon (teal)

3. **Total Digests**
   - Large number (count of sent digests)
   - Subtitle: "sent to date"
   - Icon: Stack/papers icon (teal)

#### Next Digest Card (dark blue/navy background)
- Clock icon + "Next Digest" label
- Large date/time: "Tuesday, Jan 6 at 7:00 AM"
- Timezone label: "Europe/London"
- **"Run Today's Digest Now"** button (white, full width within card)
  - On click: POST to n8n webhook `/run-digest` with `{ user_id }`
  - Show loading spinner during execution
  - Show success toast with article count on completion

#### Recent Activity Panel
- Header: "Recent Activity"
- List of recent digests:
  - "{X} articles from {Y} sources"
  - Date/time
  - Status badge ("Sent" in teal)
- Scrollable, max 5-7 items

---

### 2. Sources (`/sources`)

**Header**:
- Title: "Sources"
- Subtitle: "Manage your news sources and RSS feeds"
- **"+ Add Source"** button (dark blue, top right)

**Search Bar**:
- Placeholder: "Search sources..."
- Filters list in real-time

**Source List**:
Each source card shows:
- RSS icon (left)
- **Name** (bold)
- URL (gray, smaller, with external link icon)
- **Genre badge** (colored pill matching genre)
- **Toggle switch** (on/off for is_active)
- **Edit icon** (pencil)
- **Delete icon** (trash)

**Add/Edit Source Modal**:
- Name field (text input)
- URL field (text input with URL validation)
- Genre dropdown (26 options from genreColors)
- Save / Cancel buttons

**Delete Confirmation**:
- "Are you sure you want to delete {source name}?"
- Confirm / Cancel buttons

---

### 3. Preview (`/preview`)

**Header**:
- Title: "Preview"
- Subtitle: "See what your next digest will look like"
- **"Generate Preview"** button (outline style)
- **"Send Test Email"** button (solid dark blue)

**Tabs**:
- "Article Cards" (default)
- "Email Preview"

#### Article Cards View
Display each article as a card:
- **Headline** (link to original article, external icon)
- **Genre badge** (colored)
- "from {source_name}" (gray)
- **SUMMARY** section
- **WHY THIS MATTERS** section (light blue background)

#### Email Preview View
- Render the actual HTML email in an iframe or sanitized HTML
- Shows exactly what recipient will receive

**Generate Preview Logic**:
- POST to n8n webhook `/generate-preview` with `{ user_id }`
- Returns array of articles with headline, summary, why_matters, genre, source_name, url
- Display in Article Cards format

**Send Test Email Logic**:
- POST to n8n webhook `/send-test-email` with `{ user_id }`
- Shows success toast: "Test email sent to {email}"

---

### 4. Settings (`/settings`)

**Header**:
- Title: "Settings"
- Subtitle: "Configure your daily digest preferences"
- **"Save Settings"** button (dark blue, top right)

**Sections**:

#### Delivery Settings
- **Recipient Email** (text input, required)
  - Note: "Locked to your account email" or allow business email
- **Send Time** (time picker, default 07:00)
- **Timezone** dropdown:
  - Europe/London (default)
  - America/New_York
  - America/Los_Angeles
  - Europe/Paris
  - etc.

#### Article Limits
- **Max per Source** (number input, default 15)
  - Helper: "Maximum articles from each source"
- **Max Total Articles** (number input, default 200)
  - Helper: "Maximum articles in entire digest"
- **Skip Empty Digests** (toggle)
  - Helper: "Don't send email if no articles found"

#### Email Content
- **Email Greeting** (textarea)
  - Default: "Good morning! Here's your daily 44 Automation news digest."
- **Email Footer** (textarea)
  - Default: "Please stay tuned for tomorrow's instalment to stay informed. Have a great day!"

#### Tone & Style
- **Summary Tone** (dropdown)
  - Options: Professional, Casual, Formal, Technical
  - Helper: "How summaries are written"
- **Why-It-Matters Focus** (dropdown)
  - Options: Business Focus, Industry Trends, Consumer Impact, General Interest
  - Helper: "Perspective for relevance explanations"

**Save Logic**:
- UPSERT to user_settings table
- Show success toast: "Settings saved successfully"

---

## API Integration (n8n Webhooks)

Configure these webhook URLs in environment variables:

```env
VITE_N8N_WEBHOOK_URL=https://your-n8n-instance.app.n8n.cloud/webhook
```

### Endpoints

#### Run Digest
```javascript
POST ${WEBHOOK_URL}/run-digest
Body: { user_id: string }
Response: { success: boolean, digest_id: string, articles: number }
```

#### Generate Preview
```javascript
POST ${WEBHOOK_URL}/generate-preview
Body: { user_id: string }
Response: {
  success: boolean,
  articles: [
    { headline, summary, why_matters, source_name, genre, genre_color, url }
  ],
  count: number
}
```

#### Send Test Email
```javascript
POST ${WEBHOOK_URL}/send-test-email
Body: { user_id: string }
Response: { success: boolean, sent_to: string, article_count: number }
```

---

## Authentication

Use Supabase Auth:
- Email/password sign up and login
- Magic link option
- Password reset flow

On sign up, create default user_settings record:
```javascript
await supabase.from('user_settings').insert({
  user_id: user.id,
  recipient_email: user.email,
  send_time: '07:00:00',
  timezone: 'Europe/London',
  max_per_source: 15,
  max_total_articles: 200,
  email_greeting: "Good morning! Here's your daily 44 Automation news digest.",
  email_footer: "Please stay tuned for tomorrow's instalment. Have a great day!",
  summary_tone: 'Professional',
  why_matters_focus: 'Business Focus'
});
```

---

## Sidebar Navigation

```jsx
<Sidebar>
  <Logo>
    <Icon type="newspaper" />
    <div>
      <h1>News Digest</h1>
      <span>Daily Briefing</span>
    </div>
  </Logo>

  <NavItem icon="grid" to="/dashboard" active>Dashboard</NavItem>
  <NavItem icon="rss" to="/sources">Sources</NavItem>
  <NavItem icon="eye" to="/preview">Preview</NavItem>
  <NavItem icon="settings" to="/settings">Settings</NavItem>

  <Footer>
    <span>Stay informed, daily</span>
  </Footer>
</Sidebar>
```

---

## Responsive Design

- **Desktop**: Sidebar always visible, 3-column stats
- **Tablet**: Collapsible sidebar, 2-column stats
- **Mobile**: Bottom navigation, single column, stacked cards

---

## Loading States

- Skeleton loaders for stats cards
- Spinner overlay for "Run Digest Now" and "Generate Preview"
- Disabled buttons during API calls
- Toast notifications for success/error

---

## Error Handling

- Show error toasts for failed API calls
- Validate URLs in source form (must start with http:// or https://)
- Validate email format in settings
- Show inline validation errors

---

## Sample Data for Development

```javascript
// Sample sources
const sampleSources = [
  { name: 'Finextra', url: 'https://www.finextra.com/', genre: 'Financial', is_active: true },
  { name: 'Travel Pulse', url: 'https://www.travelpulse.com/news/', genre: 'Travel & Tourism', is_active: true },
  { name: 'Drapers Online', url: 'https://www.drapersonline.com/', genre: 'Fashion', is_active: true },
  { name: 'Corp Comms Magazine', url: 'https://www.corpcommsmagazine.co.uk/', genre: 'Media & Publishing', is_active: true },
];

// Sample preview articles
const sampleArticles = [
  {
    headline: "Do we trust the BBC? Or do we just trust it in some areas and not others?",
    genre: "Media & Publishing",
    source_name: "Corp Comms Magazine",
    summary: "This article examines public trust in the BBC, exploring whether trust varies across different areas of its operations and content.",
    why_matters: "Understanding public trust in media organizations is crucial for businesses to navigate media relations and public perception effectively."
  }
];
```

---

## Build Checklist

- [ ] Set up Supabase project with auth and database
- [ ] Create all database tables with RLS policies
- [ ] Build sidebar navigation component
- [ ] Build Dashboard page with stats and activity
- [ ] Build Sources page with CRUD operations
- [ ] Build Preview page with Generate/Test Email
- [ ] Build Settings page with all configuration options
- [ ] Connect to n8n webhooks
- [ ] Add loading states and error handling
- [ ] Test full flow end-to-end
- [ ] Deploy to production

---

## Prompt for Lovable

Copy this into Lovable:

```
Build a "News Digest" dashboard application with Supabase authentication.

Features:
1. Dashboard page showing: Active Sources count, Last Digest article count, Total Digests sent, Next Digest scheduled time with "Run Today's Digest Now" button, Recent Activity list
2. Sources page: Add/edit/delete news sources with name, URL, and genre (26 genre options with color coding). Each source has a toggle switch to enable/disable.
3. Preview page: "Generate Preview" button to see upcoming articles, "Send Test Email" button. Show articles as cards with headline, genre badge, source name, summary, and "Why This Matters" section.
4. Settings page: Recipient email, send time (default 07:00), timezone, max articles per source, max total articles, skip empty digests toggle, email greeting text, email footer text, summary tone dropdown (Professional/Casual/Formal), why-it-matters focus dropdown (Business Focus/Industry Trends/Consumer Impact).

Design:
- Primary color: #003d96 (dark blue)
- Background: #f3feff (light cyan)
- Sidebar navigation with "News Digest - Daily Briefing" branding
- Clean, professional UI similar to modern SaaS dashboards

Database tables: sources, user_settings, digests, articles (schemas provided)

The backend is handled by n8n webhooks - just need buttons that POST to webhook URLs with user_id.
```
