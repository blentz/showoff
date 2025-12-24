# Showoff.rb Dependency Graph & Extraction Plan

**Analysis Date:** 2025-12-22
**File Analyzed:** `lib/showoff.rb` (2019 lines)
**Purpose:** Map dependencies for extracting components from monolith to modular architecture

---

## Executive Summary

The showoff.rb monolith has **NO circular method dependencies** - all entanglement is through **shared class variable state**. This is good news: methods can be extracted without circular import issues. The challenge is **state management**, not call graph cycles.

**Key Metrics:**
- 9 class variables (state)
- 7 routes (6 HTTP + 1 WebSocket)
- 69 helper methods
- ~1070 lines minimum for basic `serve`
- ~900 lines can be removed (WebSocket, forms, stats)

---

## 1. State Dependencies

### Class Variables Overview

| Variable | Purpose | Writers | Readers | Complexity |
|----------|---------|---------|---------|------------|
| `@@forms` | Form submissions | `initialize`, `POST /form/:id`, `self.flush` | `GET /form/:id`, `self.flush` | Low |
| `@@cache` | Rendered slides by locale | `slides()` | `slides()` | Low |
| `@@counter` | Stats (pageviews, user_agents, current) | `initialize`, `GET /control`, `self.flush` | `stats_data()`, `stats()`, `self.flush` | **High** |
| `@@cookie` | Presenter auth token | `manage_client_cookies(true)` | `valid_presenter_cookie?()`, `GET /control` | Low |
| `@@master` | Master presenter client_id | `manage_client_cookies(true)` | `master_presenter?()` | Low |
| `@@activity` | Activity slide completion | `GET /control` | `GET /control` | Medium |
| `@@downloads` | Downloadable files metadata | `update_download_links()` | `download()`, `GET /control` | Medium |
| `@@current` | Current presenter slide | `GET /control` | `stats_data()`, `GET /control` | Medium |
| `@@slide_titles` | Generated slide refs | `process_markdown()` | `stats_data()`, `process_content_for_all_slides()` | Medium |

### State Dependency Graph

```
@@slide_titles ←─── process_markdown()
                    ├─→ stats_data() (reads)
                    └─→ process_content_for_all_slides() (reads)

@@downloads ←─── update_download_links() (called from process_markdown)
                 ├─→ download() (reads)
                 └─→ GET /control (reads/writes)

@@cache[@locale] ←─── slides()
                      └─→ slides() (reads)

@@current ←─── GET /control (writes)
              ├─→ stats_data() (reads)
              ├─→ GET /control (reads)
              └─→ @@counter (dependency)

@@counter ←─── GET /control (writes)
              ├─→ stats_data() (reads)
              ├─→ stats() (reads)
              └─→ self.flush (reads/writes to disk)

@@forms ←─── POST /form/:id (writes)
            ├─→ GET /form/:id (reads)
            └─→ self.flush (reads/writes to disk)

@@activity ←─── GET /control (writes)
               └─→ GET /control (reads)

@@cookie ←─── manage_client_cookies(true)
             └─→ valid_presenter_cookie?()

@@master ←─── manage_client_cookies(true)
             └─→ master_presenter?()
```

### Safe Extraction Order (by State Isolation)

1. **@@forms** - Completely isolated, no dependencies
2. **@@cookie, @@master** - Simple auth tokens, no dependencies
3. **@@cache** - Depends on markdown pipeline
4. **@@downloads** - Populated during markdown, read by views
5. **@@slide_titles** - Populated during markdown, read by stats
6. **@@activity** - WebSocket only
7. **@@current** - WebSocket + stats dependency
8. **@@counter** - WebSocket + stats dependency (most complex)

---

## 2. Method Call Graph

### Markdown Processing Pipeline

```
process_markdown(name, section, content, opts)
├─→ process_content_for_replacements(content)
│   ├─→ settings.showoff_config (reads)
│   └─→ File.read (for ~~~FILE:~~~ tags)
├─→ process_content_for_language(content, locale)
├─→ Tilt[:markdown].render (external)
├─→ build_forms(content, classes)
│   └─→ form_element*(...)  [10+ form helpers]
├─→ update_p_classes(content)
├─→ process_content_for_section_tags(content, name, opts)
│   ├─→ Nokogiri::HTML::DocumentFragment.parse
│   └─→ Tilt[:markdown].render (for personal notes)
├─→ update_special_content(content, seq, name)  [DEPRECATED]
│   ├─→ update_special_content_mark(doc, mark)
│   └─→ update_download_links(doc, seq, name)
│       └─→ @@downloads[seq] = [...]  **SIDE EFFECT**
├─→ update_image_paths(path, slide, opts)
├─→ final_slide_fixup(content)
└─→ update_commandline_code(slide)
    └─→ CommandlineParser.parse

SIDE EFFECTS:
- Line 497: @@slide_titles << ref
- Line 1065: @@downloads[seq] = [...]
```

### Slide Orchestration

```
get_slides_html(opts)
├─→ ShowoffUtils.showoff_sections (external)
├─→ process_markdown(...) for each slide file
│   └─→ [SIDE EFFECTS: @@slide_titles, @@downloads]
└─→ process_content_for_all_slides(content, num_slides, opts)
    ├─→ Build table of contents (if opts[:toc])
    └─→ Build glossary pages

slides(static, merged)
├─→ Check @@cache[@locale]
├─→ ShowoffUtils.update (if settings.url)
├─→ @@slide_titles = []  **RESET**
├─→ get_slides_html(...)
└─→ @@cache[@locale] = content  **CACHE**
```

### No Circular Dependencies Found

Analyzed potential cycles:
- ✅ `process_markdown` → `update_special_content_mark` → `Tilt[:markdown]` (nested rendering, not circular)
- ✅ `get_slides_html` → `@@downloads` → `download()` (shared state, not circular call)
- ✅ `slides()` → `@@slide_titles` → `stats_data()` (shared state, not circular call)
- ✅ `GET /control` → `@@current` → `stats_data()` (shared state, not circular call)

**Conclusion:** Entanglement is through SHARED STATE, not method call cycles.

---

## 3. External Dependencies

### WebSocket & EventMachine

**Location:** GET /control route (lines 1823-1969)

**Dependencies:**
- `require 'sinatra-websocket'` (line 9)
- EventMachine (implicit via sinatra-websocket)
- `settings.sockets` - Array of WebSocket connections
- `settings.presenters` - Subset of sockets (presenter connections)

**Usage:**
```ruby
EM.next_tick { settings.sockets.each{|s| s.send(msg.to_json) } }
```

**Impact:** Only GET /control route requires these. Can be isolated.

### Rack Middleware

**Location:** Line 63
```ruby
use Rack::Locale  # Automatic locale detection from browser headers
```

**Impact:** Used for i18n. Required for multi-language support.

### Markdown Engines

**Location:** Throughout markdown processing
```ruby
Tilt[:markdown].new(nil, nil, @engine_options) { content }.render
```

**Impact:** Abstracted via Tilt. Engine configured in `MarkdownConfig::setup`.

---

## 4. Data Flows

### Flow 1: Slide Content (File → Cache → Response)

```
1. Markdown files on disk (*.md in sections)
2. get_slides_html() reads files
3. process_markdown() for each file
   ├─→ @@slide_titles << ref (side effect)
   └─→ @@downloads[seq] = [...] (side effect)
4. Result cached in @@cache[@locale]
5. Subsequent requests return cached content
6. Cache cleared by params['cache'] == 'clear'
```

**Bottleneck:** Side effects in step 3 prevent pure functional extraction.

### Flow 2: Form Submission (Submission → Storage → Retrieval → Display)

```
1. Client submits form via POST /form/:id
2. Data stored in @@forms[id][client_id]
3. Background thread flushes to stats/forms.json every 30s
4. GET /form/:id aggregates responses across clients
5. Returns JSON with counts per response option
6. Client-side JS displays results
```

**Isolation:** Completely independent of other flows.

### Flow 3: Stats Collection (Collection → Aggregation → UI)

```
1. WebSocket 'track' messages from clients
2. Data stored in @@counter['pageviews'][slide][client_id]
3. User agents stored in @@counter['user_agents'][client_id]
4. Current slide stored in @@counter['current'][client_id]
5. Background thread flushes to stats/viewstats.json every 30s
6. stats_data() aggregates for visualization
7. stats() view renders charts
```

**Dependency:** Requires @@slide_titles for iteration.

### Flow 4: Presenter Sync (Action → Broadcast → Update)

```
1. Presenter navigates to slide, sends 'update' message
2. WebSocket handler validates presenter cookie
3. Updates @@current = { :name, :number, :increment }
4. Enables download link if @@downloads[slide] exists
5. EM.next_tick broadcasts to all settings.sockets
6. Audience clients receive 'current' message and navigate
```

**Complexity:** Touches 4 class variables (@@current, @@downloads, @@cookie, settings.sockets).

---

## 5. Critical Paths

### Minimum Code for Basic `serve`

**Required Components:**
1. Sinatra app initialization (~100 lines)
2. Route: GET / (index view) (~50 lines)
3. Route: GET /slides (slide content) (~50 lines)
4. Route: GET /(?:image|file)/(.*) (static assets) (~10 lines)
5. Markdown processing pipeline (~800 lines)
6. ERB view rendering (external files)
7. Settings configuration (~100 lines)

**Total:** ~1070 lines (vs 2019 current)

**Can Be Removed:**
- WebSocket (/control route) - ~200 lines
- Forms (POST/GET /form/:id) - ~250 lines
- Stats (@@counter, stats_data, stats) - ~150 lines
- Code execution (GET /execute/:lang) - ~50 lines
- PDF generation (pdf method) - ~50 lines
- Downloads (@@downloads) - ~50 lines
- Activity tracking (@@activity) - ~50 lines
- Presenter mode (presenter view, @@cookie, @@master) - ~100 lines
- Authentication (protected!, locked!) - ~55 lines

**Total Removable:** ~955 lines

### Independently Extractable Features

**Easy Wins (No dependencies):**
1. File serving - 10 lines
2. Editor integration - 30 lines
3. Authentication helpers - 55 lines
4. Pure markdown helpers - ~400 lines
5. Form HTML generators - ~150 lines

**Total Easy:** ~645 lines can be extracted immediately.

---

## 6. Extraction Order Recommendation

### Phase 1: Isolated Features (Low Risk)

**Target:** 300 lines extracted

1. **Forms Subsystem**
   - Routes: `POST /form/:id`, `GET /form/:id`
   - State: `@@forms`
   - Helpers: `build_forms()`, `form_element*()`
   - New module: `Showoff::Forms`
   - Rationale: Completely isolated, no dependencies

2. **File Serving**
   - Route: `GET /(?:image|file)/(.*)`
   - New module: `Showoff::FileServer`
   - Rationale: Pure utility, no state

3. **Editor Integration**
   - Route: `GET /edit/*`
   - New module: `Showoff::Editor`
   - Rationale: Standalone utility

4. **Authentication**
   - Methods: `protected!`, `locked!`, `authorized?`, `unlocked?`, `localhost?`, `authenticate`
   - New module: `Showoff::Auth`
   - Rationale: Pure functions, reads config only

### Phase 2: Markdown Pipeline (Medium Risk)

**Target:** 800 lines extracted

5. **Pure Markdown Helpers**
   - Methods: `process_content_for_language`, `process_content_for_replacements`,
     `update_p_classes`, `update_image_paths`, `update_commandline_code`,
     `process_content_for_section_tags`, `final_slide_fixup`
   - New module: `Showoff::Compiler::Transforms`
   - Rationale: No state mutations, safe to extract

6. **Markdown Orchestration (REFACTOR FIRST)**
   - Methods: `process_markdown`, `get_slides_html`, `process_content_for_all_slides`
   - **BLOCKER:** Side effects (@@slide_titles, @@downloads)
   - **Refactor:** Return `{html, slide_titles, downloads}` instead of mutating globals
   - New module: `Showoff::Compiler`
   - Rationale: After refactoring, can extract cleanly

### Phase 3: Caching & Views (Medium-High Risk)

**Target:** 200 lines extracted

7. **Slide Caching**
   - Method: `slides()`
   - State: `@@cache`
   - Dependencies: Markdown pipeline (Phase 2)
   - New module: `Showoff::Cache`
   - Rationale: After markdown extraction, wrap in cache layer

8. **View Methods (Non-interactive)**
   - Methods: `index(static)`, `print`, `supplemental`, `pdf`, `download`
   - Dependencies: Markdown pipeline, @@downloads
   - New module: `Showoff::Views`
   - Rationale: After markdown + cache extraction

### Phase 4: Stats & Tracking (High Risk)

**Target:** 200 lines extracted

9. **Stats Subsystem**
   - Methods: `stats_data`, `stats`
   - State: `@@counter`, `@@current`, `@@slide_titles`
   - Dependencies: WebSocket for data collection
   - New module: `Showoff::Stats`
   - Rationale: Tightly coupled to WebSocket, extract after WebSocket

### Phase 5: Real-time Features (Highest Risk)

**Target:** 200 lines extracted

10. **WebSocket & Real-time Sync**
    - Route: `GET /control`
    - State: `@@current`, `@@counter`, `@@activity`, `@@cookie`, `@@downloads`, `settings.sockets`, `settings.presenters`
    - Dependencies: EventMachine, sinatra-websocket, ALL state
    - New module: `Showoff::Realtime`
    - Rationale: Most complex, extract LAST after all state is abstracted

**Extraction Strategy:**
1. Create `Showoff::Realtime::State` class to wrap all class variables
2. Create `Showoff::Realtime::MessageHandler` for message dispatch
3. Create `Showoff::Realtime::Broadcaster` for EM.next_tick logic
4. Create `Showoff::Realtime::Connection` to wrap WebSocket
5. Extract route to `Showoff::Realtime` module
6. Inject state object instead of using class variables

**Estimated Effort:** 2-3 days

---

## 7. Entangled Components (Must Move Together)

### Group 1: Forms Subsystem
- `POST /form/:id`, `GET /form/:id`
- `@@forms`
- `build_forms()`, `form_element*()` helpers
- **Rationale:** Tightly coupled, but isolated from rest of system

### Group 2: Markdown Processing Core
- `process_markdown()`
- `process_content_for_language()`
- `process_content_for_replacements()`
- `update_p_classes()`
- `update_commandline_code()`
- `update_image_paths()`
- `process_content_for_section_tags()`
- `final_slide_fixup()`
- **Rationale:** Call chain dependencies, must move as unit

### Group 3: Markdown Orchestration + State
- `get_slides_html()`
- `process_content_for_all_slides()`
- `update_download_links()`
- `@@slide_titles` (mutated during processing)
- `@@downloads` (mutated during processing)
- **Rationale:** State mutations happen during orchestration

### Group 4: Caching Layer
- `slides()`
- `@@cache`
- **Depends on:** Group 3
- **Rationale:** Wraps markdown orchestration with caching

### Group 5: Stats & Analytics
- `stats_data()`
- `stats()`
- `@@counter` (all sub-hashes)
- `@@current`
- **Depends on:** `@@slide_titles` from Group 3
- **Rationale:** Stats depend on slide metadata

### Group 6: WebSocket Real-time
- `GET /control` route
- `@@current`, `@@counter`, `@@activity`, `@@cookie`, `@@master`
- `settings.sockets`, `settings.presenters`
- `manage_client_cookies()`, `valid_presenter_cookie?()`, `master_presenter?()`
- **Depends on:** Group 5 (stats), Group 3 (@@downloads)
- **Rationale:** Deeply entangled with all state

### Group 7: View Rendering
- `index()`, `presenter()`, `print()`, `supplemental()`, `pdf()`, `download()`
- **Depends on:** Group 4 (caching), Group 6 (cookies)
- **Rationale:** Views depend on cached content and auth

---

## 8. Pure vs Stateful Components

### Pure Functions (Safe to Extract Immediately)

**No state, no side effects:**
- `process_content_for_language(content, locale)`
- `process_content_for_replacements(content)`
- `update_p_classes(content)`
- `update_image_paths(path, slide, opts)`
- `update_commandline_code(slide)`
- `process_content_for_section_tags(content, name, opts)`
- `final_slide_fixup(text)`
- `form_element*()` - all form HTML generators
- `form_classes(modifier)`, `form_checked?(modifier)`
- `clean_link(href)`
- `inline_css(csses, pre)`, `inline_js(jses, pre)`
- `with_locale(locale)`, `get_language_name(locale)`, `get_locale_dir(prefix, locale)`
- `protected!()`, `locked!()`, `authorized?()`, `unlocked?()`, `localhost?()`, `authenticate()`
- `guid()`

**Total:** ~20 pure functions, ~500 lines

### Stateful Components (Read-Only)

**Read state but don't mutate:**
- `build_forms()` - reads `I18n.t`
- `get_translations()` - reads `I18n.backend`
- `user_translations()` - reads `@locale`
- `language_names()` - reads filesystem + I18n
- `locale(user_locale)` - reads `I18n.locale`
- `css_files()`, `js_files()`, `preshow_files()` - read settings + filesystem

**Total:** ~6 methods, ~100 lines

### Stateful Components (Mutating)

**Write to class variables:**
- `process_markdown()` - WRITES `@@slide_titles`, `@@downloads`
- `get_slides_html()` - calls `process_markdown` (indirect mutation)
- `process_content_for_all_slides()` - READS `@@slide_titles`
- `update_download_links()` - WRITES `@@downloads`
- `slides()` - WRITES `@@cache`, `@@slide_titles` (reset)
- `stats_data()` - READS `@@counter`, `@@current`, `@@slide_titles`
- `stats()` - READS `@@counter`
- `manage_client_cookies()` - WRITES `@@cookie`, `@@master`
- `valid_presenter_cookie?()` - READS `@@cookie`
- `master_presenter?()` - READS `@@master`
- `GET /control` - READS/WRITES `@@current`, `@@counter`, `@@activity`, `@@downloads`
- `POST /form/:id` - WRITES `@@forms`
- `GET /form/:id` - READS `@@forms`
- `self.flush` - READS/WRITES `@@counter`, `@@forms` (to disk)

**Total:** ~15 methods, ~1000 lines

**Critical Insight:** The markdown processing pipeline SHOULD be pure but has side effects.

**Refactoring Strategy:** Make `process_markdown` return `{html, slide_titles, downloads}` instead of mutating globals.

---

## 9. Dependency Graph (Mermaid)

```mermaid
graph TD
    %% State Variables
    Forms[@@forms]
    Cache[@@cache]
    Counter[@@counter]
    Cookie[@@cookie]
    Master[@@master]
    Activity[@@activity]
    Downloads[@@downloads]
    Current[@@current]
    SlideTitles[@@slide_titles]

    %% Routes
    PostForm[POST /form/:id]
    GetForm[GET /form/:id]
    GetControl[GET /control WebSocket]
    GetFile[GET /file/*]
    GetEdit[GET /edit/*]
    GetExecute[GET /execute/:lang]
    GetCatchAll[GET /* Dispatcher]

    %% Core Methods
    ProcessMD[process_markdown]
    GetSlides[get_slides_html]
    Slides[slides]
    StatsData[stats_data]
    Stats[stats]
    Index[index]
    Presenter[presenter]
    Download[download]

    %% Dependencies
    PostForm -->|writes| Forms
    GetForm -->|reads| Forms

    ProcessMD -->|writes| SlideTitles
    ProcessMD -->|writes| Downloads

    GetSlides -->|calls| ProcessMD
    Slides -->|calls| GetSlides
    Slides -->|writes| Cache
    Slides -->|reads| Cache
    Slides -->|resets| SlideTitles

    GetControl -->|writes| Current
    GetControl -->|writes| Counter
    GetControl -->|writes| Activity
    GetControl -->|reads| Cookie
    GetControl -->|reads| Downloads

    StatsData -->|reads| Counter
    StatsData -->|reads| Current
    StatsData -->|reads| SlideTitles

    Stats -->|reads| Counter

    Download -->|reads| Downloads

    Index -->|calls| Slides
    Presenter -->|writes| Cookie
    Presenter -->|writes| Master

    GetCatchAll -->|dispatches to| Index
    GetCatchAll -->|dispatches to| Presenter
    GetCatchAll -->|dispatches to| Stats
    GetCatchAll -->|dispatches to| Download

    %% Styling
    classDef stateVar fill:#f9f,stroke:#333,stroke-width:2px
    classDef route fill:#bbf,stroke:#333,stroke-width:2px
    classDef method fill:#bfb,stroke:#333,stroke-width:2px

    class Forms,Cache,Counter,Cookie,Master,Activity,Downloads,Current,SlideTitles stateVar
    class PostForm,GetForm,GetControl,GetFile,GetEdit,GetExecute,GetCatchAll route
    class ProcessMD,GetSlides,Slides,StatsData,Stats,Index,Presenter,Download method
```

---

## 10. Recommendations

### Immediate Actions (Week 1)

1. **Extract Pure Functions**
   - Move 20 pure functions to `Showoff::Compiler::Transforms`
   - No risk, immediate code organization benefit
   - Estimated: 1 day

2. **Extract Forms Subsystem**
   - Create `Showoff::Forms` module
   - Wrap `@@forms` in `Showoff::Forms::Store` class
   - Estimated: 1 day

3. **Extract File Serving & Editor**
   - Create `Showoff::FileServer` and `Showoff::Editor` modules
   - Estimated: 2 hours

### Medium-term Actions (Week 2-3)

4. **Refactor Markdown Pipeline**
   - Change `process_markdown` to return `{html, metadata}` instead of mutating globals
   - Update callers to handle returned metadata
   - **CRITICAL:** This unblocks all downstream extractions
   - Estimated: 2-3 days

5. **Extract Markdown Orchestration**
   - Move to `Showoff::Compiler` module
   - Estimated: 1 day (after refactoring)

6. **Extract Caching**
   - Create `Showoff::Cache` module
   - Estimated: 1 day

### Long-term Actions (Week 4+)

7. **Extract Stats**
   - Create `Showoff::Stats` module
   - Wrap `@@counter` in state class
   - Estimated: 2 days

8. **Extract WebSocket**
   - Create `Showoff::Realtime` module with sub-classes
   - Most complex extraction
   - Estimated: 3-4 days

### Testing Strategy

- **Unit tests:** Test extracted modules in isolation
- **Integration tests:** Ensure `serve` command still works
- **Regression tests:** Run existing RSpec suite after each extraction
- **Manual testing:** Test presenter mode, forms, stats after WebSocket extraction

### Success Metrics

- [ ] Reduce showoff.rb from 2019 to <1000 lines
- [ ] Extract 5+ independent modules
- [ ] All tests passing after each extraction
- [ ] No circular dependencies introduced
- [ ] Maintain backward compatibility for `serve` command

---

## Appendix: Route Handler Dependencies

| Route | State Read | State Write | External Deps | Complexity |
|-------|-----------|-------------|---------------|------------|
| `POST /form/:id` | - | `@@forms` | - | Low |
| `GET /form/:id` | `@@forms` | - | - | Low |
| `GET /execute/:lang` | - | - | Tempfile, Open3 | Medium |
| `GET /edit/*` | - | - | Platform detection | Low |
| `GET /(?:image|file)/(.*)` | - | - | - | Low |
| `GET /control` | `@@current`, `@@counter`, `@@activity`, `@@cookie`, `@@downloads` | `@@current`, `@@counter`, `@@activity` | EventMachine, sinatra-websocket | **Very High** |
| `GET /([^/]*)/?([^/]*)` | All state | - | - | High (dispatcher) |

---

**End of Analysis**
