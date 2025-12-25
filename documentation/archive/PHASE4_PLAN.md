# Showoff Phase 4 Architecture Plan - WebSocket & Advanced Routes

**Date:** December 23, 2025
**Status:** Planning Complete - Ready for Implementation
**Target Duration:** 5-7 days
**Estimated LOC:** ~920 implementation + ~480 tests = ~1,400 total

---

## Executive Summary

Phase 4 will complete the extraction of remaining routes and WebSocket functionality from the monolithic `lib/showoff.rb` (2,019 LOC). This phase focuses on:

1. **WebSocket endpoint migration** (147 LOC, 13 message types)
2. **State manager creation** (4 new managers for WebSocket state)
3. **Route extraction** (6 remaining routes)
4. **Integration testing** (comprehensive WebSocket and route tests)

**Code execution sandboxing is DEFERRED to Phase 5** due to high security risk and complexity.

---

## Complete Route Inventory

### ✅ Already Extracted (Phase 3)

| Route | Method | Description | Status |
|-------|--------|-------------|--------|
| `/form/:id` | POST | Form submission | ✅ Complete |
| `/form/:id` | GET | Form aggregation | ✅ Complete |
| `/stats` | GET | Statistics dashboard | ✅ Complete |
| `/health` | GET | Health check | ✅ Complete |
| `/` | GET | Index/home | ✅ Complete |

### 🔄 To Extract (Phase 4)

| Route | Method | Lines | Complexity | Priority | Estimate |
|-------|--------|-------|------------|----------|----------|
| `/image/*`, `/file/*` | GET | 9 | LOW | HIGH | 3h |
| `/edit/*` | GET | 26 | LOW | LOW | 2h |
| `/presenter` | GET | 11 | MEDIUM | HIGH | 2h |
| `/slides` | GET | 18 | MEDIUM | HIGH | 2h |
| `/onepage`, `/print` | GET | 10 | MEDIUM | MEDIUM | 2h |
| `/download` | GET | 13 | LOW | MEDIUM | 1h |
| `/supplemental/:content` | GET | 7 | LOW | LOW | DEFERRED |
| `/control` (WebSocket) | GET | 147 | **HIGH** | **CRITICAL** | 16h |
| `/execute/:lang` | GET | 30 | HIGH | MEDIUM | DEFERRED |
| Catch-all `/*` | GET | 36 | MEDIUM | HIGH | 5h |

**Total Remaining:** 307 LOC across 10 routes

---

## WebSocket Endpoint Analysis

### Message Types (13 total)

| Message | Lines | Handler | Dependencies | Complexity |
|---------|-------|---------|--------------|------------|
| `update` | 21 | UpdateHandler | @@cookie, @@current, @@downloads | HIGH |
| `register` | 7 | RegisterHandler | @@cookie, settings.presenters | LOW |
| `track` | 24 | TrackHandler | @@counter, client_id | MEDIUM |
| `position` | 2 | PositionHandler | @@current, @@cookie | LOW |
| `activity` | 17 | ActivityHandler | @@activity, @@current | MEDIUM |
| `pace` | 4 | BroadcastHandler | settings.presenters | LOW |
| `question` | 4 | BroadcastHandler | settings.presenters | LOW |
| `cancel` | 4 | BroadcastHandler | settings.presenters | LOW |
| `complete` | 2 | BroadcastHandler | settings.sockets | LOW |
| `answerkey` | 2 | BroadcastHandler | settings.sockets | LOW |
| `annotation` | 2 | BroadcastHandler | settings.sockets - presenters | LOW |
| `annotationConfig` | 2 | BroadcastHandler | settings.sockets - presenters | LOW |
| `feedback` | 21 | FeedbackHandler | settings.statsdir, settings.feedback | MEDIUM |

**Total:** 147 LOC, 8 unique handlers

### Class Variables to Migrate

| Variable | Purpose | New Manager | Complexity |
|----------|---------|-------------|------------|
| `@@cookie` | Presenter auth token | SessionState | LOW |
| `@@master` | Master presenter ID | SessionState | LOW |
| `@@current` | Current slide state | SessionState | MEDIUM |
| `@@downloads` | Download availability | DownloadManager | LOW |
| `@@activity` | Activity completion | ActivityManager | LOW |
| `@@counter` | Pageview stats | StatsManager | ✅ Done (Phase 3) |
| `@@forms` | Form responses | FormManager | ✅ Done (Phase 3) |

---

## Recommended Architecture

### Directory Structure

```
lib/showoff/server/
├── websocket/
│   ├── adapter.rb               # EventMachine abstraction
│   ├── connection_manager.rb    # Connection lifecycle
│   ├── message_handler.rb       # Message routing
│   └── handlers/
│       ├── update_handler.rb    # Presenter navigation
│       ├── track_handler.rb     # Pageview tracking
│       ├── activity_handler.rb  # Activity completion
│       ├── feedback_handler.rb  # Slide feedback
│       ├── broadcast_handler.rb # Generic broadcasts
│       ├── position_handler.rb  # Current slide request
│       └── register_handler.rb  # Presenter registration
├── routes/
│   ├── assets.rb                # GET /image/*, /file/*
│   ├── editor.rb                # GET /edit/*
│   ├── presenter.rb             # GET /presenter
│   ├── slides.rb                # GET /slides
│   ├── print.rb                 # GET /onepage, /print
│   └── download.rb              # GET /download
├── session_state.rb             # @@cookie, @@master, @@current
├── download_manager.rb          # @@downloads
└── activity_manager.rb          # @@activity
```

### Key Design Decisions

#### 1. WebSocket Abstraction Layer

**Pattern:** Adapter pattern to hide EventMachine details

```ruby
module Showoff::Server::WebSocket
  class Adapter
    def connect(ws)
      # EventMachine-specific connection setup
    end

    def disconnect(ws)
      # Cleanup
    end

    def send(ws, message)
      # Send to single client
    end

    def broadcast(message, exclude: [])
      # Send to all clients
    end
  end
end
```

**Benefits:**
- Allows future migration to Async, ActionCable, or Faye
- Testable without EventMachine
- Isolates EventMachine Ruby 3.x compatibility issues

#### 2. Message Handler Pattern

**Pattern:** Strategy pattern with handler registry

```ruby
module Showoff::Server::WebSocket
  class MessageHandler
    def initialize(handlers = {})
      @handlers = handlers
    end

    def handle(message, context)
      type = message['message']
      handler = @handlers[type]
      handler.call(message, context) if handler
    end
  end
end
```

**Benefits:**
- Each message type is isolated
- Easy to test handlers independently
- Clear separation of concerns

#### 3. Route Modules

**Pattern:** Sinatra extensions

```ruby
module Showoff::Server::Routes
  module Assets
    def self.registered(app)
      app.get %r{/(?:image|file)/(.*)} do |path|
        # Implementation
      end
    end
  end
end

# In server.rb
register Showoff::Server::Routes::Assets
```

**Benefits:**
- Routes are modular and testable
- Can be registered selectively
- Clear file organization

---

## Phase 4 Task Breakdown

### Day 1: State Managers (8 hours)

**Tasks:**
1. Create `SessionState` manager (3h)
   - Store @@cookie, @@master, @@current
   - Thread-safe operations
   - Persistence to disk
   - Tests: 15 unit tests

2. Create `DownloadManager` (1h)
   - Track downloadable files per slide
   - Enable/disable downloads
   - Tests: 8 unit tests

3. Create `ActivityManager` (1h)
   - Track activity completion per session
   - Count incomplete activities
   - Tests: 8 unit tests

4. Integration testing (3h)
   - Test state manager interactions
   - Persistence validation
   - Concurrent access tests

**Deliverables:**
- `lib/showoff/server/session_state.rb` (~120 LOC)
- `lib/showoff/server/download_manager.rb` (~80 LOC)
- `lib/showoff/server/activity_manager.rb` (~80 LOC)
- Tests: 31 unit tests (~250 LOC)

---

### Day 2: Simple Routes (8 hours)

**Tasks:**
1. Extract assets route (2h)
   - `GET /image/*` and `GET /file/*`
   - File serving with `send_file`
   - Path validation (prevent traversal)
   - MIME type detection
   - CacheManager integration
   - Tests: 6 integration tests

2. Extract editor route (1h)
   - `GET /edit/*`
   - Platform detection (darwin/linux/windows)
   - Localhost-only security
   - File existence validation
   - Tests: 4 integration tests

3. Refactor helper methods (3h)
   - Extract `presenter()`, `slides()`, `print()`, `download()` helpers
   - Integrate with Presentation model
   - Prepare for route extraction

4. Integration testing (2h)
   - Test with real presentation files
   - Security validation (path traversal, localhost)

**Deliverables:**
- `lib/showoff/server/routes/assets.rb` (~50 LOC)
- `lib/showoff/server/routes/editor.rb` (~40 LOC)
- Tests: 10 integration tests (~120 LOC)

---

### Day 3: Helper Method Routes (8 hours)

**Tasks:**
1. Extract presenter route (2h)
   - `GET /presenter`
   - ERB rendering
   - Cookie management
   - Presenter registration
   - Tests: 5 integration tests

2. Extract slides route (2h)
   - `GET /slides`
   - Slide content generation
   - Caching with CacheManager
   - Locale support
   - Tests: 8 integration tests

3. Extract print routes (2h)
   - `GET /onepage` and `GET /print`
   - Print-optimized rendering
   - Section filtering
   - TOC generation
   - Tests: 6 integration tests

4. Extract download route (1h)
   - `GET /download`
   - Download page rendering
   - File listing
   - Tests: 3 integration tests

5. Integration testing (1h)
   - Test all routes together
   - Validate ERB rendering

**Deliverables:**
- `lib/showoff/server/routes/presenter.rb` (~60 LOC)
- `lib/showoff/server/routes/slides.rb` (~80 LOC)
- `lib/showoff/server/routes/print.rb` (~70 LOC)
- `lib/showoff/server/routes/download.rb` (~50 LOC)
- Tests: 22 integration tests (~200 LOC)

---

### Day 4: Catch-All Route (8 hours)

**Tasks:**
1. Extract dynamic routing logic (3h)
   - `GET %r{/([^/]*)/?([^/]*)}`
   - Route pattern matching
   - Method dispatch
   - Tests: 8 integration tests

2. Implement authentication/locking (2h)
   - `protected!` and `locked!` methods
   - Password and key validation
   - Localhost detection
   - Tests: 5 integration tests

3. Integration with route modules (2h)
   - Ensure all routes accessible
   - Test navigation patterns
   - Validate authentication flow

4. Bug fixes and refinement (1h)
   - Address any issues found
   - Improve error handling

**Deliverables:**
- Catch-all route in `lib/showoff/server.rb` (~80 LOC)
- Authentication helpers (~40 LOC)
- Tests: 13 integration tests (~150 LOC)

---

### Day 5: WebSocket Infrastructure (8 hours)

**Tasks:**
1. Create EventMachine adapter (2h)
   - Abstract WebSocket interface
   - Connection lifecycle management
   - Message send/broadcast
   - Tests: 10 unit tests

2. Create ConnectionManager (3h)
   - Track all connections
   - Presenter vs audience separation
   - Heartbeat/ping-pong
   - Connection cleanup
   - Tests: 12 unit tests

3. Create MessageHandler (2h)
   - Route messages to handlers
   - Error handling
   - Logging
   - Tests: 8 unit tests

4. Integration testing (1h)
   - Multi-client scenarios
   - Connection lifecycle
   - Message flow validation

**Deliverables:**
- `lib/showoff/server/websocket/adapter.rb` (~80 LOC)
- `lib/showoff/server/websocket/connection_manager.rb` (~120 LOC)
- `lib/showoff/server/websocket/message_handler.rb` (~60 LOC)
- Tests: 30 unit tests (~250 LOC)

---

### Day 6: WebSocket Message Handlers (8 hours)

**Tasks:**
1. Create UpdateHandler (2h)
   - Validate presenter cookie
   - Update current slide
   - Enable downloads
   - Broadcast to clients
   - Tests: 8 unit tests

2. Create TrackHandler (1.5h)
   - Record slide views
   - Calculate elapsed time
   - Store user agent
   - Tests: 6 unit tests

3. Create ActivityHandler (1h)
   - Track completion status
   - Count incomplete
   - Broadcast to presenters
   - Tests: 5 unit tests

4. Create FeedbackHandler (1h)
   - Save to JSON file
   - Validate input
   - Tests: 4 unit tests

5. Create BroadcastHandler (1.5h)
   - Handle pace, question, cancel
   - Handle complete, answerkey
   - Handle annotation, annotationConfig
   - Tests: 9 unit tests

6. Create remaining handlers (1h)
   - PositionHandler (3 tests)
   - RegisterHandler (3 tests)

**Deliverables:**
- `lib/showoff/server/websocket/handlers/update_handler.rb` (~60 LOC)
- `lib/showoff/server/websocket/handlers/track_handler.rb` (~50 LOC)
- `lib/showoff/server/websocket/handlers/activity_handler.rb` (~40 LOC)
- `lib/showoff/server/websocket/handlers/feedback_handler.rb` (~40 LOC)
- `lib/showoff/server/websocket/handlers/broadcast_handler.rb` (~50 LOC)
- `lib/showoff/server/websocket/handlers/position_handler.rb` (~20 LOC)
- `lib/showoff/server/websocket/handlers/register_handler.rb` (~20 LOC)
- Tests: 38 unit tests (~300 LOC)

---

### Day 7: Integration & Testing (8 hours)

**Tasks:**
1. WebSocket integration tests (3h)
   - End-to-end message flow
   - Multi-presenter scenarios
   - Audience sync validation
   - Tests: 15 integration tests

2. Full stack testing (2h)
   - Test with example presentations
   - Validate all routes work together
   - Test presenter/audience interaction
   - Tests: 8 e2e tests

3. Bug fixes and refinement (2h)
   - Address any issues found
   - Performance optimization
   - Error handling improvements

4. Documentation (1h)
   - Update PHASE4_COMPLETION.md
   - Update SERVER_ARCHITECTURE.md
   - Update REFACTOR_PROGRESS.md

**Deliverables:**
- Integration tests: 23 tests (~280 LOC)
- Documentation: 3 files updated
- Bug fixes and improvements

---

## Testing Strategy

### Unit Tests (~155 tests)

**State Managers (31 tests):**
- SessionState: 15 tests
- DownloadManager: 8 tests
- ActivityManager: 8 tests

**WebSocket Infrastructure (30 tests):**
- Adapter: 10 tests
- ConnectionManager: 12 tests
- MessageHandler: 8 tests

**WebSocket Handlers (38 tests):**
- UpdateHandler: 8 tests
- TrackHandler: 6 tests
- ActivityHandler: 5 tests
- FeedbackHandler: 4 tests
- BroadcastHandler: 9 tests
- PositionHandler: 3 tests
- RegisterHandler: 3 tests

**Route Modules (56 tests):**
- Assets: 6 tests
- Editor: 4 tests
- Presenter: 5 tests
- Slides: 8 tests
- Print: 6 tests
- Download: 3 tests
- Catch-all: 13 tests
- Authentication: 5 tests
- Helper methods: 6 tests

### Integration Tests (~38 tests)

**Route Integration (22 tests):**
- Simple routes: 10 tests
- Helper method routes: 22 tests
- Catch-all route: 13 tests
- Authentication flow: 5 tests

**WebSocket Integration (15 tests):**
- Message flow: 8 tests
- Multi-presenter: 4 tests
- Audience sync: 3 tests

### End-to-End Tests (~11 tests)

**Full Presentation Flow (5 tests):**
- Load presentation
- Navigate slides
- Submit forms
- View stats
- Download files

**Multi-Presenter Sync (3 tests):**
- Multiple presenters connect
- Slide navigation sync
- Master presenter control

**Form Submission + Stats (3 tests):**
- Submit form responses
- Aggregate results
- View statistics

### Load Tests (4 scenarios)

1. **100 concurrent WebSocket connections**
   - Validate connection stability
   - Check memory usage
   - Measure message latency

2. **1000 requests/sec to /slides endpoint**
   - Test caching effectiveness
   - Measure response times
   - Check for memory leaks

3. **50 concurrent code executions**
   - DEFERRED to Phase 5

4. **24-hour soak test**
   - Memory leak detection
   - Connection cleanup validation
   - Long-running stability

### Security Tests (4 scenarios)

1. **Path traversal in /file/* route**
   - Attempt `../../../etc/passwd`
   - Validate path sanitization

2. **XSS in form submissions**
   - Submit malicious HTML/JS
   - Validate output escaping

3. **CSRF in presenter actions**
   - Test without presenter cookie
   - Validate authentication

4. **Code execution escape attempts**
   - DEFERRED to Phase 5

---

## Risk Assessment

### ✅ Mitigated Risks (Phase 3)

- **Route Extraction Complexity** - RESOLVED
- **State Manager Thread Safety** - RESOLVED
- **Persistence Corruption** - RESOLVED
- **Test Isolation** - RESOLVED

### ⚠️ Active Risks (Phase 4)

#### 1. EventMachine Ruby 3.x Compatibility - MEDIUM RISK

**Risk:** EventMachine has known issues with Ruby 3.x fiber scheduler. WebSocket functionality may break or have performance issues.

**Mitigation:**
- Abstract EventMachine behind adapter interface
- Plan migration path to Async or ActionCable
- Test thoroughly on Ruby 3.2 (current target)
- Consider using em-websocket directly instead of sinatra-websocket
- Document known issues and workarounds

**Contingency:** If EventMachine proves unstable, switch to Async gem (requires 1-2 days additional work)

---

#### 2. State Migration Complexity - MEDIUM RISK

**Risk:** Class variables (@@cookie, @@current, @@downloads, @@activity) must migrate to state managers. Breaking presenter/audience sync or losing download state would be critical failures.

**Mitigation:**
- Create SessionState manager for @@cookie, @@master, @@current
- Extend StatsManager for @@counter (already done in Phase 3)
- Create DownloadManager for @@downloads
- Create ActivityManager for @@activity
- Comprehensive integration tests for state transitions
- Backward compatibility tests with existing presentations

**Contingency:** If state migration fails, rollback to class variables with deprecation warnings

---

#### 3. WebSocket Connection Lifecycle - MEDIUM RISK

**Risk:** onopen, onmessage, onclose events must be handled correctly. Memory leaks from unclosed connections or lost messages would degrade performance.

**Mitigation:**
- Connection registry with automatic cleanup
- Heartbeat/ping-pong for dead connection detection
- Graceful degradation if WebSocket unavailable
- Test with 100+ concurrent connections
- Monitor memory usage during load tests

**Contingency:** Implement connection timeout and forced cleanup after 5 minutes of inactivity

---

#### 4. Backward Compatibility - LOW RISK

**Risk:** Existing presentations must work without changes. Breaking slide navigation, forms, or stats would be unacceptable.

**Mitigation:**
- Feature flag for gradual rollout (`SHOWOFF_USE_NEW_SERVER=1`)
- Comprehensive regression tests
- Test with all example presentations in repo
- Maintain 100% test pass rate throughout

**Contingency:** Keep legacy `showoff.rb` available as fallback

---

### 🔴 Deferred Risks (Phase 5)

#### 1. Code Execution Security - CRITICAL RISK

**Risk:** Arbitrary code execution is inherently dangerous. Current implementation uses Tempfile + shell execution with no sandboxing or resource limits. Potential for remote code execution, DoS attacks, or data exfiltration.

**Deferred Because:**
- High complexity (2-3 days work)
- Requires Docker/Podman integration
- Needs security audit
- Not blocking other Phase 4 work

**Phase 5 Mitigation Plan:**
- MUST use Docker/Podman containers for isolation
- Network isolation (no internet access)
- Filesystem isolation (read-only mounts)
- CPU/memory limits (cgroups)
- Timeout enforcement (30s max)
- Input sanitization (no shell injection)
- Disable execution by default (--executecode flag)
- Security audit before production use

---

## Success Criteria

### Functional Requirements

- [ ] All routes extracted from `showoff.rb`
- [ ] WebSocket endpoint functional with all 13 message types
- [ ] Presenter/audience sync working correctly
- [ ] Form submissions and stats tracking operational
- [ ] Download management functional
- [ ] Activity tracking working
- [ ] All example presentations render correctly

### Quality Requirements

- [ ] 100% test pass rate maintained (229/229 tests)
- [ ] 95%+ code coverage on new code
- [ ] No breaking changes to existing presentations
- [ ] No memory leaks detected in load tests
- [ ] WebSocket connections stable under load (100+ clients)
- [ ] Response times < 10ms p95 for routes
- [ ] Documentation updated and complete

### Technical Requirements

- [ ] State managers implemented and tested
- [ ] WebSocket abstraction layer complete
- [ ] Route modules registered and functional
- [ ] Integration tests passing
- [ ] Load tests passing
- [ ] Security tests passing
- [ ] Container builds successfully

---

## Deferred to Phase 5

### Code Execution Sandbox (2-3 days)

**Reason:** High security risk, requires Docker/Podman integration, not blocking other work.

**Tasks:**
- Docker/Podman container design
- Language-specific runners (Ruby, Python, Shell, Puppet, Perl)
- Input sanitization and validation
- Timeout and resource limit enforcement
- Security audit
- Integration tests
- Documentation

**Estimate:** 2-3 days

---

### Supplemental Route (0.5 days)

**Reason:** Low usage, not critical for core functionality.

**Tasks:**
- Extract `GET /supplemental/:content` route
- Supplemental material filtering
- Static rendering
- Integration tests

**Estimate:** 0.5 days

---

### Performance Optimization (1 day)

**Reason:** Not blocking, can be done after functional completion.

**Tasks:**
- Profile route performance
- Optimize slow queries
- Improve caching
- Reduce memory usage
- Benchmark improvements

**Estimate:** 1 day

---

### Load Testing (1 day)

**Reason:** Requires complete implementation first.

**Tasks:**
- 100+ concurrent WebSocket connections
- 1000 req/sec to /slides endpoint
- 24-hour soak test
- Memory leak detection
- Performance regression testing

**Estimate:** 1 day

---

### Security Audit (1 day)

**Reason:** Requires complete implementation first.

**Tasks:**
- Path traversal testing
- XSS testing
- CSRF testing
- Authentication bypass attempts
- Code execution escape attempts (Phase 5)
- Penetration testing
- Security documentation

**Estimate:** 1 day

---

## Estimated LOC Breakdown

### Implementation

| Component | Files | LOC | Complexity |
|-----------|-------|-----|------------|
| **State Managers** | 3 | 280 | LOW-MEDIUM |
| **Route Modules** | 6 | 330 | LOW-MEDIUM |
| **WebSocket Infrastructure** | 3 | 260 | MEDIUM-HIGH |
| **WebSocket Handlers** | 7 | 280 | MEDIUM |
| **Authentication** | 1 | 40 | LOW |
| **Catch-All Route** | 1 | 80 | MEDIUM |
| **Total** | **21** | **~920** | **MEDIUM** |

### Tests

| Test Type | Files | Tests | LOC | Coverage |
|-----------|-------|-------|-----|----------|
| **Unit Tests** | 15 | 155 | ~1,250 | 95%+ |
| **Integration Tests** | 3 | 38 | ~460 | 100% |
| **E2E Tests** | 1 | 11 | ~150 | N/A |
| **Total** | **19** | **204** | **~1,860** | **95%+** |

### Documentation

| Document | Lines | Status |
|----------|-------|--------|
| PHASE4_PLAN.md | 800+ | ✅ Complete |
| PHASE4_COMPLETION.md | TBD | ⏳ Pending |
| SERVER_ARCHITECTURE.md | +200 | ⏳ To Update |
| REFACTOR_PROGRESS.md | +100 | ⏳ To Update |
| **Total** | **~1,100** | **In Progress** |

---

## Dependencies

### External Gems (No New Dependencies)

All required gems are already in `Gemfile`:
- `sinatra` (~> 2.1) - Web framework
- `sinatra-websocket` - WebSocket support
- `eventmachine` - Async I/O (via sinatra-websocket)
- `thin` - EventMachine-based server
- `rack` - HTTP interface
- `nokogiri` - HTML parsing
- `json` - JSON serialization

### Internal Dependencies

- `Showoff::Presentation` - Presentation model (Phase 1)
- `Showoff::Compiler` - Markdown compilation (Phase 1)
- `Showoff::Server::CacheManager` - Caching (Phase 2)
- `Showoff::Server::StatsManager` - Statistics (Phase 3)
- `Showoff::Server::FormManager` - Forms (Phase 3)
- `Showoff::Server::SessionState` - Session state (Phase 4)

---

## Timeline

### Phase 4: WebSocket & Advanced Routes (7 days)

| Day | Focus | Deliverables |
|-----|-------|--------------|
| **1** | State Managers | SessionState, DownloadManager, ActivityManager + tests |
| **2** | Simple Routes | Assets, Editor routes + tests |
| **3** | Helper Routes | Presenter, Slides, Print, Download routes + tests |
| **4** | Catch-All Route | Dynamic routing, authentication + tests |
| **5** | WebSocket Infrastructure | Adapter, ConnectionManager, MessageHandler + tests |
| **6** | WebSocket Handlers | 7 message handlers + tests |
| **7** | Integration & Testing | Full stack tests, bug fixes, documentation |

### Phase 5: Integration & Validation (5 days)

| Day | Focus | Deliverables |
|-----|-------|--------------|
| **1** | Code Execution Sandbox | Docker/Podman integration, language runners |
| **2** | Security Audit | Penetration testing, vulnerability fixes |
| **3** | Performance Optimization | Profiling, caching improvements |
| **4** | Load Testing | Concurrent connections, soak tests |
| **5** | Documentation & Release | Final docs, release notes, migration guide |

**Total Estimated Duration:** 12 days (7 + 5)

---

## Next Steps

1. **Review and approve this plan** with stakeholders
2. **Create Phase 4 branch** (`git checkout -b phase4-websocket`)
3. **Start Day 1 tasks** (State Managers)
4. **Daily check-ins** to track progress and adjust plan
5. **Continuous testing** to maintain 100% pass rate
6. **Documentation updates** as work progresses

---

## Questions for Review

1. **EventMachine concerns:** Should we plan for Async migration now or defer?
2. **Code execution:** Confirm deferral to Phase 5 is acceptable?
3. **Testing scope:** Is 204 tests sufficient or should we add more?
4. **Timeline:** Is 7 days realistic or should we extend to 10 days?
5. **Security:** Should we do security audit before or after Phase 4?

---

**Report prepared by:** System Architect Agent
**Last updated:** 2025-12-23
**Next review:** Phase 4 Day 1 kickoff
