# Showoff Server Architecture Design

**Version:** 1.0
**Date:** 2025-12-22
**Status:** Proposed

## Executive Summary

This document defines the target architecture for refactoring the monolithic `Showoff` Sinatra application (2018 LOC) into a modular, testable, and thread-safe server following the patterns established in `showoff_ng.rb`.

**Key Architectural Decisions:**
- **Modular Sinatra::Base** instead of classic Sinatra::Application
- **Thread-safe state management** replacing class variables
- **Dependency injection** for testability
- **Concern-based modules** for route organization
- **Keep EventMachine** (minimal usage, stable, works)

---

## 1. Current State Analysis

### Problems with Monolithic Architecture

```ruby
class Showoff < Sinatra::Application
  # 2018 lines of god-class anti-patterns

  # PROBLEM 1: Thread-unsafe class variables
  @@counter = {}      # Stats tracking
  @@forms = {}        # Form responses
  @@downloads = {}    # Download tracking
  @@cookie = nil      # Presenter auth
  @@master = nil      # Master presenter ID
  @@current = {}      # Current slide state
  @@cache = {}        # Slide content cache
  @@activity = []     # Activity tracking
  @@slide_titles = [] # Cross-reference index

  # PROBLEM 2: Mixed concerns in single class
  # - HTTP routing
  # - WebSocket handling
  # - Markdown compilation
  # - Stats persistence
  # - Form processing
  # - Session management
  # - Code execution

  # PROBLEM 3: Untestable design
  # - No dependency injection
  # - Direct file I/O in routes
  # - Global state mutations
  # - Tight coupling to Sinatra framework
end
```

### Current Route Structure (8 routes)

```
POST /form/:id          # Form submission
GET  /form/:id          # Form retrieval
GET  /execute/:lang     # Code execution
GET  /edit/*            # Edit mode
GET  /image|file/*      # Asset serving
GET  /control           # WebSocket endpoint
GET  /:page?/:subpage?  # Catch-all presentation route
```

---

## 2. Target Architecture

### 2.1 Showoff::Server Class

**Decision: Use Sinatra::Base modular style**

**Rationale:**
- Explicit configuration (no magic globals)
- Testable in isolation
- Composable as Rack middleware
- Multiple instances per process
- Clear dependency boundaries

```ruby
# lib/showoff/server.rb
module Showoff
  class Server < Sinatra::Base
    # Configuration
    set :views, File.join(GEMROOT, 'views')
    set :public_folder, File.join(GEMROOT, 'public')
    set :server, 'thin'  # Required for EventMachine

    # Disable classic-style defaults
    set :logging, false  # We use our own logger
    set :static, true

    # Thread safety
    set :lock, false  # We handle our own thread safety

    # Dependencies (injected via initialize)
    attr_reader :presentation, :session_state, :stats_manager,
                :form_manager, :websocket_hub, :logger

    def initialize(app = nil, options = {})
      super(app)

      # Dependency injection
      @presentation   = options[:presentation]   || build_presentation
      @session_state  = options[:session_state]  || SessionState.new
      @stats_manager  = options[:stats_manager]  || StatsManager.new(settings.statsdir)
      @form_manager   = options[:form_manager]   || FormManager.new(settings.statsdir)
      @websocket_hub  = options[:websocket_hub]  || WebSocketHub.new
      @logger         = options[:logger]         || build_logger

      # Load configuration
      load_showoff_config!
    end

    # Route modules (mixed in)
    use Routes::Assets
    use Routes::Forms
    use Routes::Execution
    use Routes::Presentation
    use Routes::WebSocket

    # Middleware stack
    use Rack::Locale
    use Rack::Session::Cookie, secret: session_secret

    private

    def build_presentation
      Showoff::Presentation.new(
        root: settings.pres_dir,
        config_file: settings.pres_file
      )
    end

    def build_logger
      logger = Logger.new(STDERR)
      logger.level = settings.verbose ? Logger::DEBUG : Logger::WARN
      logger.formatter = proc { |severity, datetime, progname, msg|
        "#{progname} #{msg}\n"
      }
      logger
    end

    def session_secret
      ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
    end

    def load_showoff_config!
      config_path = File.join(settings.pres_dir, settings.pres_file)
      return unless File.exist?(config_path)

      config = Showoff::Config.load(config_path)
      settings.showoff_config = config
    end
  end
end
```

**Why NOT Sinatra::Application?**
- Classic style pollutes global namespace
- Single instance per process (can't run multiple presentations)
- Implicit configuration makes testing harder
- Violates showoff_ng patterns

---

### 2.2 State Management Architecture

**Decision: Separate state managers per concern with thread-safe implementations**

#### Problem with Current Approach

```ruby
# THREAD-UNSAFE: Multiple requests mutate shared class variables
@@current = { name: 'slide1', number: 1 }  # Race condition!
@@counter['pageviews'][slide_id] += 1      # Lost updates!
```

#### Solution: Concern-Specific State Managers

```ruby
# lib/showoff/state/session_state.rb
module Showoff
  class SessionState
    def initialize
      @mutex = Mutex.new
      @current_slide = { name: nil, number: 0, increment: 0 }
      @presenter_cookie = nil
      @master_presenter = nil
    end

    # Thread-safe accessors
    def current_slide
      @mutex.synchronize { @current_slide.dup }
    end

    def update_current_slide(name:, number:, increment: 0)
      @mutex.synchronize do
        @current_slide = { name: name, number: number, increment: increment }
      end
    end

    def presenter_cookie
      @mutex.synchronize { @presenter_cookie }
    end

    def set_presenter_cookie(cookie)
      @mutex.synchronize { @presenter_cookie = cookie }
    end

    def master_presenter
      @mutex.synchronize { @master_presenter }
    end

    def set_master_presenter(client_id)
      @mutex.synchronize { @master_presenter = client_id }
    end
  end
end
```

```ruby
# lib/showoff/state/stats_manager.rb
module Showoff
  class StatsManager
    def initialize(stats_dir)
      @stats_dir = stats_dir
      @mutex = Mutex.new
      @data = load_stats
    end

    def increment_pageview(slide_id, user_agent: nil)
      @mutex.synchronize do
        @data['pageviews'][slide_id] ||= 0
        @data['pageviews'][slide_id] += 1

        if user_agent
          @data['user_agents'][user_agent] ||= 0
          @data['user_agents'][user_agent] += 1
        end
      end
    end

    def current_viewers
      @mutex.synchronize { @data['current'].dup }
    end

    def flush
      @mutex.synchronize do
        File.write(stats_file, JSON.pretty_generate(@data))
      end
    end

    private

    def load_stats
      return default_stats unless File.exist?(stats_file)
      JSON.parse(File.read(stats_file))
    rescue JSON::ParserError
      default_stats
    end

    def default_stats
      { 'pageviews' => {}, 'user_agents' => {}, 'current' => {} }
    end

    def stats_file
      File.join(@stats_dir, 'viewstats.json')
    end
  end
end
```

```ruby
# lib/showoff/state/form_manager.rb
module Showoff
  class FormManager
    def initialize(stats_dir)
      @stats_dir = stats_dir
      @mutex = Mutex.new
      @forms = load_forms
    end

    def save_response(form_id, response_data)
      @mutex.synchronize do
        @forms[form_id] ||= []
        @forms[form_id] << response_data
      end
    end

    def get_responses(form_id)
      @mutex.synchronize { @forms[form_id]&.dup || [] }
    end

    def flush
      @mutex.synchronize do
        File.write(forms_file, JSON.pretty_generate(@forms))
      end
    end

    private

    def load_forms
      return {} unless File.exist?(forms_file)
      JSON.parse(File.read(forms_file))
    rescue JSON::ParserError
      {}
    end

    def forms_file
      File.join(@stats_dir, 'forms.json')
    end
  end
end
```

```ruby
# lib/showoff/state/cache_manager.rb
module Showoff
  class CacheManager
    def initialize
      @mutex = Mutex.new
      @cache = {}
    end

    def fetch(key)
      @mutex.synchronize { @cache[key] }
    end

    def store(key, value)
      @mutex.synchronize { @cache[key] = value }
    end

    def clear
      @mutex.synchronize { @cache.clear }
    end

    # Cache with block (like Rails.cache.fetch)
    def fetch_or_compute(key)
      @mutex.synchronize do
        return @cache[key] if @cache.key?(key)
        @cache[key] = yield
      end
    end
  end
end
```

**Why Mutex instead of concurrent-ruby?**
- Stdlib only (no new dependencies)
- Simple use case (short critical sections)
- Predictable performance
- Ruby 2.7+ has GVL improvements

**When to use concurrent-ruby:**
- If we need lock-free data structures
- If critical sections become bottlenecks
- If we add background job processing

---

### 2.3 Route Organization

**Decision: Rack middleware pattern for route groups**

**Rationale:**
- Clear separation of concerns
- Independent testing
- Conditional mounting (e.g., disable code execution)
- Explicit middleware ordering

```ruby
# lib/showoff/routes/base.rb
module Showoff
  module Routes
    class Base < Sinatra::Base
      # Shared helpers available to all route modules
      helpers do
        def presentation
          settings.server.presentation
        end

        def session_state
          settings.server.session_state
        end

        def stats_manager
          settings.server.stats_manager
        end

        def form_manager
          settings.server.form_manager
        end

        def websocket_hub
          settings.server.websocket_hub
        end

        def logger
          settings.server.logger
        end

        def valid_presenter?
          session[:presenter_cookie] == session_state.presenter_cookie
        end
      end
    end
  end
end
```

```ruby
# lib/showoff/routes/presentation.rb
module Showoff
  module Routes
    class Presentation < Base
      # Main presentation route
      get '/:page?/:subpage?' do |page, subpage|
        page ||= 'index'

        # Track pageview
        stats_manager.increment_pageview(
          params[:page],
          user_agent: request.user_agent
        )

        # Render presentation
        erb :index, locals: {
          presentation: presentation,
          current_slide: session_state.current_slide,
          is_presenter: valid_presenter?
        }
      end

      # Presenter mode
      get '/presenter' do
        halt 403 unless valid_presenter?
        erb :presenter
      end
    end
  end
end
```

```ruby
# lib/showoff/routes/forms.rb
module Showoff
  module Routes
    class Forms < Base
      post '/form/:id' do |id|
        form_manager.save_response(id, params)
        form_manager.flush

        content_type :json
        { success: true }.to_json
      end

      get '/form/:id' do |id|
        halt 403 unless valid_presenter?

        content_type :json
        form_manager.get_responses(id).to_json
      end
    end
  end
end
```

```ruby
# lib/showoff/routes/execution.rb
module Showoff
  module Routes
    class Execution < Base
      # Only mount if execution is enabled
      configure do
        halt 404 unless settings.execute
      end

      get '/execute/:lang' do |lang|
        halt 403 unless settings.execute
        halt 403 unless valid_presenter?

        code = params[:code]
        executor = CodeExecutor.new(lang)

        content_type :json
        executor.run(code).to_json
      end
    end
  end
end
```

**Alternative Considered: Module mixins**

```ruby
# REJECTED: Pollutes Server namespace, harder to test
class Server < Sinatra::Base
  include Routes::Presentation
  include Routes::Forms
end
```

**Why middleware pattern wins:**
- Routes are Rack apps (testable in isolation)
- Explicit mounting order
- Can wrap with middleware per route group
- Follows Sinatra best practices

---

### 2.4 WebSocket Architecture

**Decision: Keep EventMachine with abstraction layer**

**Rationale:**
- EventMachine works (stable since 2009)
- Minimal usage (only EM.next_tick for broadcasts)
- Migration risk > benefit
- Abstraction allows future swap

```ruby
# lib/showoff/websocket/hub.rb
module Showoff
  class WebSocketHub
    def initialize
      @mutex = Mutex.new
      @connections = []
      @presenters = []
    end

    def register(ws, presenter: false)
      @mutex.synchronize do
        @connections << ws
        @presenters << ws if presenter
      end
    end

    def unregister(ws)
      @mutex.synchronize do
        @connections.delete(ws)
        @presenters.delete(ws)
      end
    end

    def broadcast(message, to: :all)
      recipients = case to
      when :all then @connections.dup
      when :presenters then @presenters.dup
      when :viewers then (@connections - @presenters).dup
      else raise ArgumentError, "Invalid recipient: #{to}"
      end

      # EventMachine abstraction
      schedule_broadcast(recipients, message)
    end

    def connection_count
      @mutex.synchronize { @connections.size }
    end

    private

    def schedule_broadcast(recipients, message)
      # Abstraction point: Can swap EventMachine for Async, Fiber, etc.
      if defined?(EM) && EM.reactor_running?
        EM.next_tick { send_to_all(recipients, message) }
      else
        send_to_all(recipients, message)
      end
    end

    def send_to_all(recipients, message)
      json = message.to_json
      recipients.each do |ws|
        ws.send(json) rescue nil  # Ignore closed connections
      end
    end
  end
end
```

```ruby
# lib/showoff/routes/websocket.rb
module Showoff
  module Routes
    class WebSocket < Base
      get '/control' do
        halt 404 unless request.websocket?

        request.websocket do |ws|
          ws.onopen do
            # Send current state
            ws.send({
              message: 'current',
              current: session_state.current_slide[:number]
            }.to_json)

            # Register connection
            websocket_hub.register(ws, presenter: valid_presenter?)
            logger.info "WebSocket opened (total: #{websocket_hub.connection_count})"
          end

          ws.onmessage do |data|
            handle_message(ws, data)
          end

          ws.onclose do
            websocket_hub.unregister(ws)
            logger.info "WebSocket closed (total: #{websocket_hub.connection_count})"
          end
        end
      end

      private

      def handle_message(ws, data)
        message = JSON.parse(data)

        case message['message']
        when 'update'
          handle_slide_update(message) if valid_presenter?
        when 'register'
          handle_presenter_registration(ws) if valid_presenter?
        when 'execute'
          handle_code_execution(message) if valid_presenter?
        else
          logger.warn "Unknown message type: #{message['message']}"
        end
      rescue JSON::ParserError => e
        logger.error "Invalid JSON: #{e.message}"
      end

      def handle_slide_update(message)
        session_state.update_current_slide(
          name: message['name'],
          number: message['slide'].to_i,
          increment: message['increment'].to_i
        )

        websocket_hub.broadcast({
          message: 'current',
          current: session_state.current_slide[:number],
          increment: session_state.current_slide[:increment]
        })
      end

      def handle_presenter_registration(ws)
        websocket_hub.register(ws, presenter: true)
        logger.info "Presenter registered from #{request.ip}"
      end
    end
  end
end
```

**EventMachine Alternatives Considered:**

| Library | Pros | Cons | Decision |
|---------|------|------|----------|
| **EventMachine** | Battle-tested, works now | Unmaintained, Ruby 3.x issues | **KEEP** (with abstraction) |
| **Async** | Modern, fiber-based | Breaking change, learning curve | Future migration path |
| **Falcon** | Fast, HTTP/2 | Requires Async ecosystem | Future option |
| **Iodine** | Fast, simple | Less mature | Monitor |

**Migration Strategy:**
1. Abstract EM.next_tick behind WebSocketHub
2. Add feature flag for async backend
3. Implement Async adapter when Ruby 3.2+ is baseline
4. A/B test in production
5. Deprecate EventMachine

---

## 3. Testing Strategy

### 3.1 Unit Testing State Managers

```ruby
# spec/unit/showoff/state/session_state_spec.rb
RSpec.describe Showoff::SessionState do
  subject(:state) { described_class.new }

  describe '#update_current_slide' do
    it 'updates slide atomically' do
      state.update_current_slide(name: 'intro', number: 1)
      expect(state.current_slide).to eq(name: 'intro', number: 1, increment: 0)
    end

    it 'is thread-safe' do
      threads = 10.times.map do |i|
        Thread.new { state.update_current_slide(name: "slide#{i}", number: i) }
      end
      threads.each(&:join)

      # Should not raise, should have valid state
      expect(state.current_slide[:number]).to be_between(0, 9)
    end
  end
end
```

### 3.2 Integration Testing Routes

```ruby
# spec/integration/showoff/routes/presentation_spec.rb
RSpec.describe Showoff::Routes::Presentation do
  include Rack::Test::Methods

  let(:presentation) { instance_double(Showoff::Presentation) }
  let(:stats_manager) { instance_double(Showoff::StatsManager) }
  let(:session_state) { Showoff::SessionState.new }

  def app
    Showoff::Server.new(
      presentation: presentation,
      stats_manager: stats_manager,
      session_state: session_state
    )
  end

  describe 'GET /' do
    before do
      allow(stats_manager).to receive(:increment_pageview)
    end

    it 'renders the presentation' do
      get '/'
      expect(last_response).to be_ok
      expect(last_response.body).to include('showoff')
    end

    it 'tracks pageview' do
      get '/intro'
      expect(stats_manager).to have_received(:increment_pageview)
        .with('intro', user_agent: anything)
    end
  end
end
```

### 3.3 WebSocket Testing

```ruby
# spec/integration/showoff/routes/websocket_spec.rb
RSpec.describe Showoff::Routes::WebSocket do
  include Rack::Test::Methods

  let(:websocket_hub) { Showoff::WebSocketHub.new }
  let(:session_state) { Showoff::SessionState.new }

  def app
    Showoff::Server.new(
      websocket_hub: websocket_hub,
      session_state: session_state
    )
  end

  describe 'WebSocket connection' do
    it 'registers connection on open' do
      # Mock WebSocket connection
      ws = instance_double(Faye::WebSocket)
      allow(ws).to receive(:send)

      expect {
        websocket_hub.register(ws)
      }.to change { websocket_hub.connection_count }.by(1)
    end

    it 'broadcasts slide updates' do
      ws1 = instance_double(Faye::WebSocket)
      ws2 = instance_double(Faye::WebSocket)

      allow(ws1).to receive(:send)
      allow(ws2).to receive(:send)

      websocket_hub.register(ws1)
      websocket_hub.register(ws2)

      websocket_hub.broadcast({ message: 'test' })

      expect(ws1).to have_received(:send).with(/"message":"test"/)
      expect(ws2).to have_received(:send).with(/"message":"test"/)
    end
  end
end
```

**Testing Philosophy:**
- **Unit tests:** State managers, helpers (no Sinatra)
- **Integration tests:** Routes with mocked dependencies
- **System tests:** Full stack with real WebSockets (optional)

---

## 4. Migration Strategy

### 4.1 Phased Rollout

**Phase 1: Foundation (Week 1)**
- [ ] Create `Showoff::Server` skeleton
- [ ] Implement state managers (SessionState, StatsManager, FormManager)
- [ ] Write unit tests for state managers
- [ ] Add integration test harness

**Phase 2: Route Migration (Week 2-3)**
- [ ] Migrate `/form/:id` routes → `Routes::Forms`
- [ ] Migrate `/execute/:lang` → `Routes::Execution`
- [ ] Migrate asset routes → `Routes::Assets`
- [ ] Migrate WebSocket → `Routes::WebSocket`
- [ ] Migrate presentation routes → `Routes::Presentation`

**Phase 3: Feature Parity (Week 4)**
- [ ] Implement all helper methods
- [ ] Port markdown compilation logic
- [ ] Port stats tracking
- [ ] Port presenter authentication
- [ ] Port code execution

**Phase 4: Testing & Validation (Week 5)**
- [ ] Achieve 80% test coverage
- [ ] Manual QA of all features
- [ ] Performance benchmarking
- [ ] Load testing WebSockets

**Phase 5: Cutover (Week 6)**
- [ ] Feature flag: `SHOWOFF_USE_NEW_SERVER=1`
- [ ] Run both servers in parallel
- [ ] Monitor error rates
- [ ] Gradual rollout (10% → 50% → 100%)
- [ ] Deprecate old server

### 4.2 Backwards Compatibility

**CLI Compatibility:**
```bash
# Must continue to work
showoff serve
showoff serve -p 9090
showoff serve -x  # Enable code execution
```

**Configuration Compatibility:**
```json
// showoff.json must work unchanged
{
  "name": "My Presentation",
  "sections": [...],
  "templates": {...}
}
```

**API Compatibility:**
- All HTTP routes return same responses
- WebSocket message format unchanged
- Session cookies compatible
- Stats file format unchanged

### 4.3 Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| WebSocket breakage | Medium | High | Extensive integration tests, gradual rollout |
| Performance regression | Low | Medium | Benchmarking, profiling |
| State corruption | Low | High | Atomic operations, flush on shutdown |
| Thread deadlocks | Low | High | Mutex timeouts, deadlock detection |
| Session loss | Medium | Low | Cookie compatibility layer |

---

## 5. Performance Considerations

### 5.1 Concurrency Model

**Current:** Single-threaded EventMachine reactor
**Target:** Multi-threaded with thread-safe state

**Benchmark Target:**
- 100 concurrent WebSocket connections
- < 10ms p95 latency for slide updates
- < 100ms p95 for page renders
- No memory leaks over 24h

### 5.2 Caching Strategy

```ruby
# Cache compiled slides
cache_manager.fetch_or_compute("slide:#{slide_id}") do
  presentation.compile_slide(slide_id)
end

# Invalidate on file change (development mode)
if settings.development?
  before do
    cache_manager.clear if presentation.modified?
  end
end
```

### 5.3 Database Considerations

**Current:** JSON files on disk
**Future:** Consider SQLite for stats/forms if:
- > 1000 form responses
- > 10,000 pageviews
- Concurrent write contention

---

## 6. Deployment Architecture

### 6.1 Process Model

```
┌─────────────────────────────────────┐
│  Reverse Proxy (nginx/Caddy)       │
│  - SSL termination                  │
│  - Static asset serving             │
│  - WebSocket upgrade                │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Showoff::Server (Thin)             │
│  - EventMachine reactor             │
│  - Thread pool (5-10 threads)       │
│  - WebSocket connections            │
└─────────────────────────────────────┘
```

### 6.2 Scaling Strategy

**Single Instance (< 50 viewers):**
- One Thin process
- EventMachine handles concurrency
- State in-memory

**Multi-Instance (> 50 viewers):**
- Multiple Thin processes behind load balancer
- Sticky sessions for WebSockets
- Shared state via Redis (future)

---

## 7. Open Questions

1. **Should we add Redis for shared state?**
   - Pro: Enables horizontal scaling
   - Con: New dependency, complexity
   - **Decision:** Not in v1, add if needed

2. **Should we migrate to Async/Falcon?**
   - Pro: Modern, maintained
   - Con: Breaking change, ecosystem immature
   - **Decision:** Abstract EM, migrate in v2

3. **Should we add GraphQL for stats API?**
   - Pro: Flexible querying
   - Con: Overkill for simple stats
   - **Decision:** REST is sufficient

---

## 8. Success Metrics

- [ ] 100% feature parity with legacy server
- [ ] 80%+ test coverage
- [ ] Zero regressions in manual QA
- [ ] < 5% performance degradation
- [ ] All existing presentations work unchanged
- [ ] Clean separation of concerns (< 200 LOC per module)

---

## Appendix A: Class Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Showoff::Server                         │
│                   (Sinatra::Base)                           │
├─────────────────────────────────────────────────────────────┤
│ - presentation: Presentation                                │
│ - session_state: SessionState                               │
│ - stats_manager: StatsManager                               │
│ - form_manager: FormManager                                 │
│ - websocket_hub: WebSocketHub                               │
│ - cache_manager: CacheManager                               │
│ - logger: Logger                                            │
├─────────────────────────────────────────────────────────────┤
│ + initialize(app, options)                                  │
│ + call(env)                                                 │
└───────────────────┬─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
┌──────────────┐        ┌──────────────┐
│ Routes::     │        │ State        │
│ Presentation │        │ Managers     │
├──────────────┤        ├──────────────┤
│ Routes::     │        │ SessionState │
│ Forms        │        │ StatsManager │
├──────────────┤        │ FormManager  │
│ Routes::     │        │ CacheManager │
│ Execution    │        └──────────────┘
├──────────────┤
│ Routes::     │        ┌──────────────┐
│ WebSocket    │───────▶│ WebSocketHub │
├──────────────┤        ├──────────────┤
│ Routes::     │        │ + register   │
│ Assets       │        │ + broadcast  │
└──────────────┘        │ + unregister │
                        └──────────────┘
```

---

## Appendix B: File Structure

```
lib/showoff/
├── server.rb                    # Main Server class
├── routes/
│   ├── base.rb                  # Shared helpers
│   ├── presentation.rb          # Presentation routes
│   ├── forms.rb                 # Form routes
│   ├── execution.rb             # Code execution routes
│   ├── websocket.rb             # WebSocket routes
│   └── assets.rb                # Asset serving routes
├── state/
│   ├── session_state.rb         # Session/slide state
│   ├── stats_manager.rb         # Stats tracking
│   ├── form_manager.rb          # Form responses
│   └── cache_manager.rb         # Slide cache
├── websocket/
│   ├── hub.rb                   # WebSocket connection hub
│   └── message_handler.rb       # Message routing
└── middleware/
    ├── presenter_auth.rb        # Presenter authentication
    └── stats_tracker.rb         # Request tracking

spec/
├── unit/
│   └── showoff/
│       ├── state/
│       │   ├── session_state_spec.rb
│       │   ├── stats_manager_spec.rb
│       │   └── form_manager_spec.rb
│       └── websocket/
│           └── hub_spec.rb
└── integration/
    └── showoff/
        ├── routes/
        │   ├── presentation_spec.rb
        │   ├── forms_spec.rb
        │   └── websocket_spec.rb
        └── server_spec.rb
```

---

## Appendix C: References

- [Sinatra Modular Style](https://sinatrarb.com/intro.html#Sinatra::Base%20-%20Middleware,%20Libraries,%20and%20Modular%20Apps)
- [Rack Middleware](https://github.com/rack/rack/wiki/List-of-Middleware)
- [Thread Safety in Ruby](https://www.jstorimer.com/blogs/workingwithcode/8085491-nobody-understands-the-gil)
- [EventMachine Best Practices](https://github.com/eventmachine/eventmachine/wiki/General-Introduction)
- [Sinatra Testing with Rack::Test](https://github.com/rack/rack-test)

---

**Document Status:** Ready for review
**Next Steps:** Team review → Prototype Phase 1 → Validate assumptions
