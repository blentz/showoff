# Showoff Server Architecture Decision Records (ADRs)

## ADR-001: Use Sinatra::Base Modular Style

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

The current Showoff server inherits from `Sinatra::Application` (classic style), which:
- Pollutes global namespace with DSL methods
- Allows only one application instance per Ruby process
- Uses implicit configuration (magic settings)
- Makes testing difficult due to global state

### Decision

Migrate to `Sinatra::Base` modular style.

### Rationale

**Pros:**
- Explicit configuration (no magic)
- Multiple instances per process (can run multiple presentations)
- Testable in isolation (dependency injection)
- Composable as Rack middleware
- Follows showoff_ng patterns
- Industry best practice for reusable components

**Cons:**
- More boilerplate (must explicitly enable features)
- Different defaults than classic style
- Requires understanding of Rack middleware

**Alternatives Considered:**
1. **Keep Sinatra::Application** - Rejected: Doesn't solve testability or multi-instance issues
2. **Switch to Rails** - Rejected: Massive overkill for presentation server
3. **Switch to Roda** - Rejected: Breaking change, team unfamiliarity

### Consequences

- All routes must be defined in `Sinatra::Base` subclasses
- Settings must be explicitly configured
- Middleware must be explicitly mounted
- Tests can inject mock dependencies
- Can run multiple presentations in same process

---

## ADR-002: Replace Class Variables with Thread-Safe State Managers

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Current implementation uses class variables for shared state:
```ruby
@@counter = {}      # Stats tracking
@@forms = {}        # Form responses
@@current = {}      # Current slide state
@@cache = {}        # Slide content cache
```

**Problems:**
- Thread-unsafe (race conditions, lost updates)
- Global mutable state
- Untestable (can't isolate tests)
- Violates single responsibility principle

### Decision

Create separate state manager classes with Mutex-based thread safety:
- `SessionState` - Session/slide state
- `StatsManager` - Stats tracking with disk persistence
- `FormManager` - Form responses with disk persistence
- `CacheManager` - Slide content cache

### Rationale

**Pros:**
- Thread-safe (Mutex protection)
- Testable (can mock in tests)
- Clear ownership (each manager owns its data)
- Encapsulated persistence logic
- Follows single responsibility principle

**Cons:**
- More classes to maintain
- Mutex overhead (minimal for our use case)
- Must pass managers to routes

**Alternatives Considered:**
1. **concurrent-ruby gem** - Rejected: New dependency, overkill for simple use case
2. **Thread-local storage** - Rejected: Doesn't solve shared state problem
3. **Immutable data structures** - Rejected: Requires functional programming paradigm shift

### Consequences

- Each state manager uses `Mutex.synchronize` for thread safety
- State managers injected via `Server#initialize` for testability
- Disk persistence handled by managers (not routes)
- Can swap implementations for testing (e.g., in-memory vs. Redis)

---

## ADR-003: Organize Routes as Rack Middleware

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Current monolithic server has all routes in one 2000+ LOC class. Need to separate concerns while maintaining cohesion.

### Decision

Organize routes into separate Rack middleware classes:
- `Routes::Presentation` - Main presentation routes
- `Routes::Forms` - Form submission/retrieval
- `Routes::Execution` - Code execution
- `Routes::WebSocket` - WebSocket handling
- `Routes::Assets` - Static asset serving

Each route module inherits from `Routes::Base` which provides shared helpers.

### Rationale

**Pros:**
- Clear separation of concerns
- Independently testable
- Can mount conditionally (e.g., disable code execution)
- Explicit middleware ordering
- Follows Rack best practices

**Cons:**
- More files to navigate
- Must understand Rack middleware pattern
- Shared helpers in base class

**Alternatives Considered:**
1. **Module mixins** - Rejected: Pollutes Server namespace, harder to test
2. **Single routes file with namespaces** - Rejected: Still monolithic
3. **Separate Sinatra apps** - Rejected: Overkill, complicates shared state

### Consequences

- Each route module is a `Sinatra::Base` subclass
- Routes mounted via `use Routes::ClassName`
- Shared helpers in `Routes::Base`
- Can test routes in isolation with mocked dependencies

---

## ADR-004: Keep EventMachine with Abstraction Layer

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Current WebSocket implementation uses EventMachine via `sinatra-websocket` gem. EventMachine is:
- Unmaintained (last release 2015)
- Has Ruby 3.x compatibility issues
- Single-threaded reactor model

However, usage is minimal (only `EM.next_tick` for broadcasts).

### Decision

Keep EventMachine for v1, but abstract behind `WebSocketHub` interface to enable future migration.

### Rationale

**Pros:**
- Works today (stable, battle-tested)
- Minimal usage (only broadcast scheduling)
- Migration risk > benefit for v1
- Abstraction allows future swap

**Cons:**
- Technical debt (unmaintained dependency)
- Potential Ruby 3.x issues
- Single-threaded reactor

**Alternatives Considered:**
1. **Async gem** - Rejected: Breaking change, ecosystem immature, steep learning curve
2. **Falcon server** - Rejected: Requires Async, not Rack-compatible
3. **Plain threads** - Rejected: Loses async broadcast semantics

### Consequences

- `WebSocketHub#schedule_broadcast` abstracts EM.next_tick
- Can swap to Async/Fiber in v2 without changing routes
- Must continue using Thin server (EventMachine-based)
- Add feature flag for async backend in future

### Migration Path (v2)

```ruby
# lib/showoff/websocket/hub.rb
def schedule_broadcast(recipients, message)
  case ENV['WEBSOCKET_BACKEND']
  when 'async'
    Async { send_to_all(recipients, message) }
  when 'eventmachine'
    EM.next_tick { send_to_all(recipients, message) }
  else
    send_to_all(recipients, message)  # Synchronous fallback
  end
end
```

---

## ADR-005: Use Mutex for Thread Safety (Not concurrent-ruby)

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Need thread-safe state management. Options:
1. Stdlib `Mutex`
2. `concurrent-ruby` gem (lock-free data structures)
3. Thread-local storage
4. Immutable data structures

### Decision

Use stdlib `Mutex` for all state managers.

### Rationale

**Pros:**
- No new dependencies (stdlib only)
- Simple, well-understood
- Sufficient for our use case (short critical sections)
- Predictable performance
- Ruby 2.7+ has GVL improvements

**Cons:**
- Potential contention under high load
- Not lock-free (can block threads)

**Alternatives Considered:**
1. **concurrent-ruby** - Rejected: New dependency, overkill for simple use case
2. **Thread-local storage** - Rejected: Doesn't solve shared state problem
3. **Immutable data** - Rejected: Requires functional paradigm shift

### Consequences

- All state managers use `@mutex.synchronize { ... }`
- Critical sections kept minimal (< 1ms)
- Can upgrade to concurrent-ruby if profiling shows contention
- Must avoid nested locks (deadlock risk)

### When to Reconsider

- If profiling shows Mutex contention
- If critical sections exceed 10ms
- If we add background job processing
- If we need lock-free data structures

---

## ADR-006: Dependency Injection via initialize()

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Current server creates dependencies inline (untestable):
```ruby
def initialize
  @presentation = Showoff::Presentation.new
  @stats = load_stats_from_disk
end
```

### Decision

Inject all dependencies via `initialize(options)` with sensible defaults:

```ruby
def initialize(app = nil, options = {})
  @presentation   = options[:presentation]   || build_presentation
  @session_state  = options[:session_state]  || SessionState.new
  @stats_manager  = options[:stats_manager]  || StatsManager.new
  # ...
end
```

### Rationale

**Pros:**
- Testable (can inject mocks)
- Flexible (can swap implementations)
- Explicit dependencies
- Follows SOLID principles

**Cons:**
- More verbose initialization
- Must maintain default builders

**Alternatives Considered:**
1. **Service locator pattern** - Rejected: Global state, hard to test
2. **Setter injection** - Rejected: Mutable dependencies, order-dependent
3. **No injection (inline creation)** - Rejected: Untestable

### Consequences

- Tests inject mock dependencies
- Production uses default builders
- Dependencies explicit in constructor
- Can swap implementations (e.g., Redis for stats)

---

## ADR-007: Maintain Backwards Compatibility

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Refactoring must not break existing presentations or workflows.

### Decision

Maintain 100% backwards compatibility:
- CLI commands unchanged
- `showoff.json` format unchanged
- HTTP routes return same responses
- WebSocket messages unchanged
- Session cookies compatible
- Stats file format unchanged

### Rationale

**Pros:**
- Zero migration effort for users
- Can run both servers in parallel
- Gradual rollout possible
- Reduces risk

**Cons:**
- Constrains design choices
- Must support legacy quirks
- Slower migration

**Alternatives Considered:**
1. **Breaking changes** - Rejected: Too risky, user backlash
2. **Versioned API** - Rejected: Overkill for internal tool

### Consequences

- Feature flag: `SHOWOFF_USE_NEW_SERVER=1`
- Both servers run in parallel during migration
- Gradual rollout (10% → 50% → 100%)
- Can rollback instantly
- Deprecate old server after 6 months

---

## ADR-008: Target 80% Test Coverage

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Current server has minimal tests. Need to define coverage target.

### Decision

Target 80% test coverage with focus on:
- 100% coverage for state managers (critical)
- 80% coverage for routes (integration tests)
- 50% coverage for helpers (unit tests)
- Optional system tests (full stack)

### Rationale

**Pros:**
- Catches regressions
- Documents behavior
- Enables refactoring
- Realistic target (not 100%)

**Cons:**
- Time investment
- Maintenance burden

**Alternatives Considered:**
1. **100% coverage** - Rejected: Diminishing returns, unrealistic
2. **No coverage target** - Rejected: Insufficient quality bar
3. **50% coverage** - Rejected: Too low for critical refactor

### Consequences

- State managers: 100% coverage (critical path)
- Routes: 80% coverage (integration tests)
- Helpers: 50% coverage (unit tests)
- System tests: Optional (expensive, flaky)

### Testing Strategy

```
System Tests (5 tests)
    ↑
Integration Tests (30 tests)
    ↑
Unit Tests (80 tests)
```

---

## ADR-009: Phased Migration Over 6 Weeks

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Cannot do big-bang rewrite. Need incremental migration strategy.

### Decision

6-week phased migration:
1. **Week 1:** Foundation (state managers, tests)
2. **Week 2-3:** Route migration
3. **Week 4:** Feature parity
4. **Week 5:** Testing & validation
5. **Week 6:** Gradual cutover

### Rationale

**Pros:**
- Reduces risk (incremental)
- Allows validation at each phase
- Can pause/rollback
- Maintains velocity

**Cons:**
- Longer timeline
- Must maintain both codebases
- Coordination overhead

**Alternatives Considered:**
1. **Big-bang rewrite** - Rejected: Too risky
2. **3-month migration** - Rejected: Too slow
3. **2-week sprint** - Rejected: Insufficient testing

### Consequences

- Both servers run in parallel for 6 weeks
- Feature flag controls which server handles requests
- Can rollback at any phase
- Old server deprecated after 6 months

---

## ADR-010: No Redis/Database in v1

**Status:** Accepted
**Date:** 2025-12-22
**Deciders:** System Architect

### Context

Current implementation uses JSON files for persistence. Could migrate to Redis/SQLite for:
- Shared state across instances
- Better concurrency
- Query capabilities

### Decision

Keep JSON file persistence in v1. Reconsider if:
- > 1000 form responses
- > 10,000 pageviews
- Concurrent write contention
- Need horizontal scaling

### Rationale

**Pros:**
- No new dependencies
- Simple deployment
- Sufficient for current scale
- Can migrate later

**Cons:**
- File I/O slower than in-memory
- No ACID guarantees
- Can't scale horizontally

**Alternatives Considered:**
1. **Redis** - Rejected: New dependency, overkill for v1
2. **SQLite** - Rejected: Adds complexity, not needed yet
3. **PostgreSQL** - Rejected: Way overkill

### Consequences

- Stats/forms persist to JSON files
- Mutex protects file writes
- Flush on shutdown (graceful)
- Can migrate to Redis in v2 if needed

### Migration Path (v2)

```ruby
# Abstract persistence behind interface
class StatsManager
  def initialize(backend: :file)
    @backend = case backend
    when :file then FileBackend.new
    when :redis then RedisBackend.new
    when :sqlite then SqliteBackend.new
    end
  end
end
```

---

## Summary of Key Decisions

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| Sinatra::Base | Testability, multi-instance | More boilerplate |
| State Managers | Thread safety, SRP | More classes |
| Rack Middleware Routes | Separation of concerns | More files |
| Keep EventMachine | Works today, minimal usage | Technical debt |
| Mutex (not concurrent-ruby) | Stdlib, simple | Potential contention |
| Dependency Injection | Testability | Verbose initialization |
| Backwards Compatible | Zero migration effort | Constrains design |
| 80% Test Coverage | Quality bar | Time investment |
| 6-Week Migration | Reduces risk | Longer timeline |
| No Redis in v1 | Simple deployment | Can't scale horizontally |

---

## Open Questions for Review

1. **Should we add Prometheus metrics?**
   - Pro: Observability, performance monitoring
   - Con: New dependency, complexity
   - **Recommendation:** Add in v2 if needed

2. **Should we support multiple presentations per instance?**
   - Pro: Resource efficiency
   - Con: Complicates state management
   - **Recommendation:** Not in v1, add if requested

3. **Should we add rate limiting?**
   - Pro: Prevents abuse
   - Con: Adds complexity
   - **Recommendation:** Not needed for internal tool

4. **Should we add GraphQL for stats API?**
   - Pro: Flexible querying
   - Con: Overkill for simple stats
   - **Recommendation:** REST is sufficient

---

**Next Steps:**
1. Team review of ADRs
2. Prototype Phase 1 (state managers)
3. Validate assumptions with benchmarks
4. Adjust timeline based on findings
