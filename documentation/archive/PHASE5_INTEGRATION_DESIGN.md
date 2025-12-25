# Phase 5: Integration Design - Showoff Server Architecture

**Version:** 1.0
**Date:** 2025-12-24
**Status:** Design Phase
**Author:** System Architect Agent

---

## Executive Summary

Phase 5 integrates the new modular `Showoff::Server` architecture with the CLI's `serve` command, replacing the monolithic `lib/showoff.rb` (2000+ LOC Sinatra::Application) with a clean, testable Sinatra::Base implementation.

**Key Objectives:**
- Enable `showoff serve` to use new architecture via feature flag
- Maintain 100% backward compatibility during transition
- Provide safe rollback mechanism
- Establish clear deprecation timeline for legacy code

**Success Metrics:**
- All existing presentations work unchanged
- Performance matches or exceeds legacy implementation
- Zero breaking changes to CLI interface
- Test coverage maintained at 100%

---

## 1. Current State Analysis

### 1.1 Architecture Overview

```
Current Architecture (as of Phase 4 completion):

┌─────────────────────────────────────────────────────────────┐
│                     bin/showoff (CLI)                        │
│                    GLI Command Parser                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├─── --dev flag?
                       │
        ┌──────────────┴──────────────┐
        │                             │
        NO (default)                  YES
        │                             │
        ▼                             ▼
┌───────────────┐              ┌──────────────┐
│ lib/showoff.rb│              │showoff_ng.rb │
│ (Monolithic)  │              │ (Modular)    │
└───────────────┘              └──────────────┘
        │                             │
        │                             ├─── static command
        │                             └─── pdf command
        │
        └─── serve command (Sinatra::Application)
             - 2000+ LOC god class
             - Routes, WebSockets, Stats inline
             - Hard to test, hard to maintain
```

### 1.2 New Architecture (Phase 4 Complete)

```
New Modular Architecture (lib/showoff/server.rb):

┌──────────────────────────────────────────────────────────┐
│              Showoff::Server (Sinatra::Base)              │
│                  ~200 LOC orchestrator                    │
└────────────┬─────────────────────────────────────────────┘
             │
             ├─── SessionState      (presenter cookies)
             ├─── StatsManager      (view tracking)
             ├─── FormManager       (form submissions)
             ├─── CacheManager      (content caching)
             ├─── DownloadManager   (file downloads)
             ├─── ExecutionManager  (code execution)
             ├─── WebSocketManager  (real-time sync)
             └─── FeedbackManager   (audience feedback)

Status: ✅ All managers implemented and tested (507 specs, 0 failures)
```

### 1.3 The Integration Challenge

**Problem:** The `serve` command in `bin/showoff` calls:

```ruby
Showoff.run!(options) do |server|
  if options[:ssl]
    server.ssl = true
    server.ssl_options = ssl_options
  end
end
```

This expects:
- `Showoff` to be a Sinatra::Application class
- Class-level `run!` method
- Rack-compatible interface

**But** `Showoff::Server` is:
- A Sinatra::Base subclass
- Instance-based initialization
- Different configuration pattern

**Solution:** Create a compatibility shim that bridges the two architectures.

---

## 2. Architecture Diagrams

### 2.1 Proposed Integration Flow

```
Phase 5 Integration Architecture:

┌─────────────────────────────────────────────────────────────┐
│                     bin/showoff (CLI)                        │
│                    GLI Command Parser                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├─── Check SHOWOFF_USE_NEW_SERVER env var
                       │
        ┌──────────────┴──────────────┐
        │                             │
   LEGACY (default)              NEW (opt-in Phase 5a)
        │                             │
        ▼                             ▼
┌───────────────┐              ┌──────────────────┐
│ lib/showoff.rb│              │ lib/showoff/     │
│ (Monolithic)  │              │ server_adapter.rb│
└───────────────┘              └────────┬─────────┘
        │                               │
        │                               ▼
        │                      ┌──────────────────┐
        │                      │ Showoff::Server  │
        │                      │  (Sinatra::Base) │
        │                      └──────────────────┘
        │                               │
        └───────────────┬───────────────┘
                        │
                        ▼
                 ┌─────────────┐
                 │ Thin Server │
                 │  (Rack)     │
                 └─────────────┘
```

### 2.2 Component Interaction

```
Detailed Component Flow:

┌─────────────────────────────────────────────────────────────┐
│                  bin/showoff (serve command)                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │ Feature Flag   │
              │ Check          │
              └────────┬───────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
   use_new_server?              use_legacy?
        │                             │
        ▼                             ▼
┌──────────────────┐          ┌──────────────┐
│ ServerAdapter    │          │ Showoff      │
│ .run!(options)   │          │ .run!(opts)  │
└────────┬─────────┘          └──────────────┘
         │
         ▼
┌──────────────────┐
│ Showoff::Server  │
│ .new(options)    │
└────────┬─────────┘
         │
         ├─── Initialize managers
         ├─── Load presentation
         ├─── Configure routes
         └─── Start Rack server
```

---

## 3. Feature Flag Design

### 3.1 Environment Variable Strategy

**Primary Flag:** `SHOWOFF_USE_NEW_SERVER`

```ruby
# Feature flag evaluation
def use_new_server?
  # Phase 5a: Opt-in (default: false)
  ENV['SHOWOFF_USE_NEW_SERVER'] == 'true'

  # Phase 5b: Opt-out (default: true) - FUTURE
  # ENV['SHOWOFF_USE_LEGACY_SERVER'] != 'true'
end
```

### 3.2 Override Mechanisms

**Priority Order:**
1. Environment variable `SHOWOFF_USE_NEW_SERVER`
2. CLI flag `--new-server` (future enhancement)
3. Config file `showoff.json` setting (future enhancement)

**Example Usage:**

```bash
# Use new server (Phase 5a)
SHOWOFF_USE_NEW_SERVER=true showoff serve

# Use legacy server (default Phase 5a)
showoff serve

# Future: CLI flag override
showoff serve --new-server
```

### 3.3 Deprecation Timeline

| Phase | Default | Override | Timeline |
|-------|---------|----------|----------|
| 5a    | Legacy  | `SHOWOFF_USE_NEW_SERVER=true` | v0.21.0 |
| 5b    | New     | `SHOWOFF_USE_LEGACY_SERVER=true` | v0.22.0 |
| 5c    | New     | Warning on legacy use | v0.23.0 |
| 5d    | New     | Legacy removed | v0.24.0 |

---

## 4. Integration Strategy

### 4.1 ServerAdapter Pattern

Create `lib/showoff/server_adapter.rb` to bridge the two architectures:

```ruby
# lib/showoff/server_adapter.rb
require 'showoff/server'

module Showoff
  # Adapter to make Showoff::Server compatible with legacy CLI expectations.
  # Provides a Sinatra::Application-like interface for Sinatra::Base.
  class ServerAdapter
    # Class method to match legacy Showoff.run! interface
    def self.run!(options = {}, &block)
      # Create server instance
      server = Showoff::Server.new(options)

      # Apply SSL configuration if provided via block
      # (matches legacy pattern: Showoff.run!(opts) { |s| s.ssl = true })
      if block_given?
        # Create a shim object that translates legacy settings
        shim = SSLShim.new(server)
        block.call(shim)
      end

      # Start the Rack server
      server.run!(
        host: options[:bind] || options[:host] || 'localhost',
        port: options[:port] || 9090,
        server: 'thin'
      )
    end

    # Shim to translate legacy SSL settings to new architecture
    class SSLShim
      def initialize(server)
        @server = server
      end

      def ssl=(value)
        @server.class.set :ssl, value
      end

      def ssl_options=(options)
        @server.class.set :ssl_options, options
      end
    end
  end
end
```

### 4.2 CLI Integration Point

Modify `bin/showoff` serve command:

```ruby
# bin/showoff (serve command action block)
c.action do |global_options, options, args|
  # ... existing config parsing ...

  # Feature flag check
  if use_new_server?
    # Use new modular architecture
    require 'showoff/server_adapter'

    Showoff::ServerAdapter.run!(options) do |server|
      if options[:ssl]
        server.ssl = true
        server.ssl_options = ssl_options
      end
    end
  else
    # Use legacy monolithic architecture
    Showoff.run!(options) do |server|
      if options[:ssl]
        server.ssl = true
        server.ssl_options = ssl_options
      end
    end
  end
end

# Helper method
def use_new_server?
  ENV['SHOWOFF_USE_NEW_SERVER'] == 'true'
end
```

### 4.3 Presentation Loading

Fix the TODO in `lib/showoff/server.rb`:

```ruby
# lib/showoff/server.rb (initialize method)
def initialize(options = {})
  @options = {
    pres_dir: Dir.pwd,
    pres_file: 'showoff.json',
    verbose: false,
    execute: false,
    host: 'localhost',
    port: 9090
  }.merge(options)

  super(nil)

  # Set settings that will be accessible in routes
  self.class.set :pres_dir, @options[:pres_dir]
  self.class.set :verbose, @options[:verbose]
  self.class.set :execute, @options[:execute]

  # Initialize state managers
  @sessions = SessionState.new
  @stats = StatsManager.new
  @forms = FormManager.new
  @cache = CacheManager.new
  @download_manager = DownloadManager.new
  @execution_manager = nil # Lazy-initialized when needed

  # Load presentation (FIXED: was stubbed in Phase 4)
  Dir.chdir(@options[:pres_dir]) do
    Showoff::Config.load(@options[:pres_file])
    @presentation = Showoff::Presentation.new(@options)

    # Store config in settings for route access
    self.class.set :showoff_config, Showoff::Config.settings
  end
end
```

---

## 5. Migration Phases

### Phase 5a: Feature Flag (Both Codepaths Coexist)

**Timeline:** v0.21.0
**Default:** Legacy
**Status:** Initial integration

**Objectives:**
- Add `ServerAdapter` compatibility layer
- Implement feature flag in CLI
- Fix presentation loading in `Showoff::Server`
- Validate new architecture with real presentations

**Deliverables:**
- [ ] `lib/showoff/server_adapter.rb` created
- [ ] `bin/showoff` modified with feature flag
- [ ] Presentation loading fixed
- [ ] Integration tests passing
- [ ] Documentation updated

**Testing:**
```bash
# Test legacy (default)
showoff serve
curl http://localhost:9090/

# Test new architecture
SHOWOFF_USE_NEW_SERVER=true showoff serve
curl http://localhost:9090/

# Both should produce identical output
```

**Success Criteria:**
- New architecture serves presentations correctly
- WebSocket connections work
- Presenter mode functions
- Stats tracking operational
- No regressions in legacy mode

---

### Phase 5b: Default to New Architecture

**Timeline:** v0.22.0
**Default:** New
**Status:** Planned

**Objectives:**
- Flip default to new architecture
- Provide legacy escape hatch
- Monitor for issues in production use

**Changes:**
```ruby
def use_new_server?
  # Phase 5b: Default to new, allow legacy opt-out
  ENV['SHOWOFF_USE_LEGACY_SERVER'] != 'true'
end
```

**Deliverables:**
- [ ] Feature flag flipped
- [ ] Release notes with migration guide
- [ ] Known issues documented
- [ ] Performance benchmarks published

**Success Criteria:**
- 95% of users successfully migrate
- No critical bugs reported
- Performance within 5% of legacy

---

### Phase 5c: Deprecate Legacy

**Timeline:** v0.23.0
**Default:** New
**Status:** Planned

**Objectives:**
- Add deprecation warnings for legacy use
- Encourage final migrations
- Prepare for legacy removal

**Changes:**
```ruby
def use_new_server?
  if ENV['SHOWOFF_USE_LEGACY_SERVER'] == 'true'
    warn "WARNING: Legacy server is deprecated and will be removed in v0.24.0"
    warn "Please test with the new architecture and report any issues."
    return false
  end
  true
end
```

**Deliverables:**
- [ ] Deprecation warnings added
- [ ] Migration guide published
- [ ] Community feedback collected

**Success Criteria:**
- <5% of users still on legacy
- No blocking migration issues

---

### Phase 5d: Remove Legacy Code

**Timeline:** v0.24.0
**Default:** New (only option)
**Status:** Planned

**Objectives:**
- Remove `lib/showoff.rb` monolithic code
- Clean up feature flags
- Simplify codebase

**Files to Remove:**
- `lib/showoff.rb` (2000+ LOC)
- Legacy route handlers
- Feature flag code

**Files to Keep:**
- `lib/showoff_ng.rb` (static/pdf commands)
- `lib/showoff/server.rb` (new architecture)
- All manager classes

**Deliverables:**
- [ ] Legacy code removed
- [ ] Tests updated
- [ ] Documentation cleaned
- [ ] Codebase size reduced by ~40%

**Success Criteria:**
- All tests pass
- No legacy references remain
- Clean git history

---

## 6. Implementation Plan

### 6.1 File Changes Required

**New Files:**
```
lib/showoff/server_adapter.rb    (Compatibility shim)
spec/integration/server_adapter_spec.rb  (Integration tests)
```

**Modified Files:**
```
bin/showoff                      (Add feature flag logic)
lib/showoff/server.rb            (Fix presentation loading)
lib/showoff_ng.rb                (Require server_adapter)
documentation/PHASE5_INTEGRATION_DESIGN.md  (This file)
```

### 6.2 Step-by-Step Implementation

**Step 1: Create ServerAdapter**
```bash
# Create the adapter
touch lib/showoff/server_adapter.rb

# Implement compatibility layer (see section 4.1)
```

**Step 2: Fix Presentation Loading**
```bash
# Edit lib/showoff/server.rb
# Uncomment and fix the presentation loading code (see section 4.3)
```

**Step 3: Modify CLI**
```bash
# Edit bin/showoff
# Add feature flag check to serve command (see section 4.2)
```

**Step 4: Add Integration Tests**
```bash
# Create integration test
touch spec/integration/server_adapter_spec.rb

# Test both legacy and new paths
```

**Step 5: Test with Real Presentations**
```bash
# Test with example presentations
cd example/one
SHOWOFF_USE_NEW_SERVER=true showoff serve

# Verify:
# - Presentation loads
# - Slides render
# - WebSocket connects
# - Presenter mode works
# - Stats track
```

**Step 6: Documentation**
```bash
# Update docs
# - README.md (add feature flag info)
# - CHANGELOG.txt (note Phase 5a completion)
# - ARCHITECTURE_DECISIONS.md (document adapter pattern)
```

### 6.3 Code Review Checklist

- [ ] ServerAdapter implements full Sinatra::Application interface
- [ ] SSL configuration works in both modes
- [ ] Presentation loading handles all edge cases
- [ ] Feature flag has clear documentation
- [ ] Tests cover both legacy and new paths
- [ ] No breaking changes to CLI interface
- [ ] Error messages are helpful
- [ ] Logging indicates which mode is active

---

## 7. Risk Analysis & Mitigation

### 7.1 High-Risk Areas

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Presentation loading fails** | High | Medium | Extensive testing with diverse presentations; fallback to legacy |
| **WebSocket incompatibility** | High | Low | Already tested in Phase 4; integration tests |
| **SSL configuration breaks** | Medium | Low | SSLShim tested separately; manual SSL testing |
| **Performance regression** | Medium | Medium | Benchmark tests; profiling before release |
| **User confusion** | Low | High | Clear documentation; helpful error messages |

### 7.2 Rollback Strategy

**If critical issues found:**

1. **Immediate:** Document workaround using legacy mode
   ```bash
   # Workaround for issue #XXX
   unset SHOWOFF_USE_NEW_SERVER
   showoff serve
   ```

2. **Short-term:** Fix issue in new architecture
   - Create hotfix branch
   - Fix and test
   - Release patch version

3. **Long-term:** If unfixable, delay phase transition
   - Keep legacy as default longer
   - Reassess architecture decisions
   - Consider alternative approaches

### 7.3 Monitoring & Detection

**Early Warning Signs:**
- Integration tests failing
- User reports of broken presentations
- Performance benchmarks showing regression
- WebSocket connection failures

**Detection Mechanisms:**
- Automated test suite (507 specs)
- Manual testing with example presentations
- Beta testing with community
- Performance profiling

---

## 8. Testing Strategy

### 8.1 Unit Tests

**Existing Coverage:**
- ✅ All managers tested (Phase 4)
- ✅ 507 examples, 0 failures
- ✅ 100% coverage of new code

**New Tests Needed:**
```ruby
# spec/unit/showoff/server_adapter_spec.rb
RSpec.describe Showoff::ServerAdapter do
  describe '.run!' do
    it 'creates a Showoff::Server instance'
    it 'passes options to server'
    it 'applies SSL configuration via block'
    it 'starts Rack server with correct settings'
  end

  describe Showoff::ServerAdapter::SSLShim do
    it 'translates ssl= to server settings'
    it 'translates ssl_options= to server settings'
  end
end
```

### 8.2 Integration Tests

**Test Scenarios:**

```ruby
# spec/integration/server_integration_spec.rb
RSpec.describe 'Server Integration' do
  context 'with legacy mode' do
    before { ENV.delete('SHOWOFF_USE_NEW_SERVER') }

    it 'serves presentations'
    it 'handles WebSocket connections'
    it 'tracks stats'
  end

  context 'with new architecture' do
    before { ENV['SHOWOFF_USE_NEW_SERVER'] = 'true' }

    it 'serves presentations'
    it 'handles WebSocket connections'
    it 'tracks stats'
    it 'produces identical output to legacy'
  end
end
```

### 8.3 End-to-End Tests

**Manual Test Plan:**

1. **Basic Presentation**
   ```bash
   cd example/one
   SHOWOFF_USE_NEW_SERVER=true showoff serve
   ```
   - [ ] Presentation loads
   - [ ] Slides render correctly
   - [ ] Navigation works
   - [ ] Images display

2. **Presenter Mode**
   ```bash
   # Open http://localhost:9090/presenter
   ```
   - [ ] Presenter view loads
   - [ ] Slide sync works
   - [ ] Notes display
   - [ ] Audience view syncs

3. **WebSocket Features**
   - [ ] Real-time slide sync
   - [ ] Presenter registration
   - [ ] Audience following
   - [ ] Stats updates

4. **Code Execution**
   ```bash
   SHOWOFF_USE_NEW_SERVER=true showoff serve -x
   ```
   - [ ] Code blocks execute
   - [ ] Results display
   - [ ] Security restrictions work

5. **Forms & Feedback**
   - [ ] Forms render
   - [ ] Submissions save
   - [ ] Feedback displays

### 8.4 Performance Tests

**Benchmarks to Run:**

```ruby
# benchmark/server_performance.rb
require 'benchmark'

def benchmark_server(mode)
  ENV['SHOWOFF_USE_NEW_SERVER'] = mode

  Benchmark.measure do
    # Start server
    # Load 100 slides
    # Simulate 50 concurrent users
    # Measure response times
  end
end

legacy_time = benchmark_server('false')
new_time = benchmark_server('true')

puts "Legacy: #{legacy_time}"
puts "New: #{new_time}"
puts "Difference: #{((new_time - legacy_time) / legacy_time * 100).round(2)}%"
```

**Acceptance Criteria:**
- New architecture within 5% of legacy performance
- No memory leaks
- WebSocket latency <100ms

---

## 9. Compatibility Matrix

### 9.1 Feature Compatibility

| Feature | Legacy | New (5a) | Status |
|---------|--------|----------|--------|
| Basic slides | ✅ | ✅ | Complete |
| Presenter mode | ✅ | ✅ | Complete |
| WebSocket sync | ✅ | ✅ | Complete |
| Stats tracking | ✅ | ✅ | Complete |
| Forms | ✅ | ✅ | Complete |
| Feedback | ✅ | ✅ | Complete |
| Code execution | ✅ | ⚠️ | Needs testing |
| PDF export | ✅ | ✅ | Via showoff_ng |
| Static export | ✅ | ✅ | Via showoff_ng |
| SSL support | ✅ | ⚠️ | Needs testing |
| i18n | ✅ | ⚠️ | Needs testing |

**Legend:**
- ✅ Fully compatible
- ⚠️ Needs validation
- ❌ Not compatible

### 9.2 Configuration Compatibility

| Config Option | Legacy | New | Notes |
|---------------|--------|-----|-------|
| `pres_dir` | ✅ | ✅ | |
| `pres_file` | ✅ | ✅ | |
| `host` | ✅ | ✅ | |
| `port` | ✅ | ✅ | |
| `ssl` | ✅ | ✅ | Via SSLShim |
| `ssl_certificate` | ✅ | ✅ | Via SSLShim |
| `ssl_private_key` | ✅ | ✅ | Via SSLShim |
| `verbose` | ✅ | ✅ | |
| `execute` | ✅ | ✅ | |
| `standalone` | ✅ | ⚠️ | Needs implementation |
| `nocache` | ✅ | ⚠️ | Needs implementation |

### 9.3 Presentation Format Compatibility

All existing presentation formats should work:
- ✅ Markdown files
- ✅ showoff.json config
- ✅ Custom CSS/JS
- ✅ Image embedding
- ✅ Code blocks
- ✅ Speaker notes
- ✅ Incremental bullets
- ✅ Forms
- ✅ Glossary

---

## 10. Success Criteria

### 10.1 Phase 5a Success Metrics

**Technical:**
- [ ] All 507 existing tests pass
- [ ] New integration tests pass
- [ ] Example presentations work in both modes
- [ ] WebSocket connections stable
- [ ] No memory leaks detected

**Functional:**
- [ ] Feature flag works correctly
- [ ] ServerAdapter provides full compatibility
- [ ] Presentation loading works
- [ ] SSL configuration works
- [ ] Error messages are helpful

**Performance:**
- [ ] Response times within 5% of legacy
- [ ] WebSocket latency <100ms
- [ ] Memory usage comparable
- [ ] No CPU spikes

**Documentation:**
- [ ] Integration design documented (this file)
- [ ] README updated with feature flag info
- [ ] CHANGELOG updated
- [ ] Migration guide created

### 10.2 Long-Term Success Metrics

**Phase 5b (v0.22.0):**
- [ ] 95% of users migrate successfully
- [ ] No critical bugs reported
- [ ] Performance validated in production

**Phase 5c (v0.23.0):**
- [ ] <5% of users still on legacy
- [ ] Deprecation warnings visible
- [ ] Migration blockers resolved

**Phase 5d (v0.24.0):**
- [ ] Legacy code removed
- [ ] Codebase size reduced by ~40%
- [ ] All tests pass
- [ ] Clean architecture achieved

---

## 11. Next Steps

### Immediate Actions (Phase 5a)

1. **Create ServerAdapter** (2-4 hours)
   - Implement compatibility shim
   - Add SSL translation
   - Write unit tests

2. **Fix Presentation Loading** (1-2 hours)
   - Uncomment code in server.rb
   - Test with example presentations
   - Handle edge cases

3. **Modify CLI** (1 hour)
   - Add feature flag check
   - Update help text
   - Test both paths

4. **Integration Testing** (4-6 hours)
   - Write integration tests
   - Manual testing with examples
   - SSL testing
   - Performance benchmarking

5. **Documentation** (2-3 hours)
   - Update README
   - Write migration guide
   - Update CHANGELOG
   - Create release notes

**Total Estimated Effort:** 10-16 hours

### Future Phases

- **Phase 5b** (v0.22.0): 2-4 weeks after 5a
- **Phase 5c** (v0.23.0): 1-2 months after 5b
- **Phase 5d** (v0.24.0): 1-2 months after 5c

---

## Appendix A: Code Examples

### A.1 Complete ServerAdapter Implementation

```ruby
# lib/showoff/server_adapter.rb
require 'showoff/server'

module Showoff
  # Adapter to make Showoff::Server compatible with legacy CLI expectations.
  #
  # This adapter bridges the gap between:
  # - Legacy: Showoff (Sinatra::Application) with class-level run!
  # - New: Showoff::Server (Sinatra::Base) with instance-level initialization
  #
  # @example
  #   Showoff::ServerAdapter.run!(pres_dir: '.', port: 9090) do |server|
  #     server.ssl = true
  #     server.ssl_options = { cert_chain_file: 'cert.pem' }
  #   end
  class ServerAdapter
    # Run the server with legacy-compatible interface
    #
    # @param options [Hash] Server configuration options
    # @option options [String] :pres_dir Presentation directory
    # @option options [String] :pres_file Config file (default: showoff.json)
    # @option options [String] :host Bind host
    # @option options [Integer] :port Port number
    # @option options [Boolean] :verbose Enable verbose logging
    # @option options [Boolean] :execute Enable code execution
    # @yield [shim] Optional block for SSL configuration
    # @yieldparam shim [SSLShim] Object that translates legacy SSL settings
    def self.run!(options = {}, &block)
      # Create server instance
      server = Showoff::Server.new(options)

      # Apply SSL configuration if provided via block
      if block_given?
        shim = SSLShim.new(server)
        block.call(shim)
      end

      # Start the Rack server
      server.run!(
        host: options[:bind] || options[:host] || 'localhost',
        port: options[:port] || 9090,
        server: 'thin'
      )
    end

    # Shim to translate legacy SSL settings to Sinatra::Base settings
    class SSLShim
      def initialize(server)
        @server = server
      end

      # Set SSL enabled flag
      # @param value [Boolean] Enable SSL
      def ssl=(value)
        @server.class.set :ssl, value
      end

      # Set SSL options
      # @param options [Hash] SSL configuration
      # @option options [String] :cert_chain_file Path to certificate
      # @option options [String] :private_key_file Path to private key
      # @option options [Boolean] :verify_peer Verify peer certificates
      def ssl_options=(options)
        @server.class.set :ssl_options, options
      end
    end
  end
end
```

### A.2 CLI Integration

```ruby
# bin/showoff (serve command modification)
command :serve do |c|
  # ... existing flag definitions ...

  c.action do |global_options, options, args|
    # ... existing config parsing ...

    # Feature flag check
    if use_new_server?
      puts "Using new modular server architecture"
      require 'showoff/server_adapter'

      Showoff::ServerAdapter.run!(options) do |server|
        if options[:ssl]
          server.ssl = true
          server.ssl_options = ssl_options
        end
      end
    else
      puts "Using legacy server (set SHOWOFF_USE_NEW_SERVER=true to test new architecture)"
      Showoff.run!(options) do |server|
        if options[:ssl]
          server.ssl = true
          server.ssl_options = ssl_options
        end
      end
    end
  end
end

# Helper method
def use_new_server?
  ENV['SHOWOFF_USE_NEW_SERVER'] == 'true'
end
```

---

## Appendix B: Testing Examples

### B.1 Integration Test

```ruby
# spec/integration/server_adapter_spec.rb
require 'spec_helper'
require 'showoff/server_adapter'
require 'rack/test'

RSpec.describe 'Server Integration', type: :integration do
  include Rack::Test::Methods

  let(:pres_dir) { File.join(FIXTURES_DIR, 'simple') }
  let(:options) { { pres_dir: pres_dir, port: 9091 } }

  context 'with new architecture' do
    before { ENV['SHOWOFF_USE_NEW_SERVER'] = 'true' }
    after { ENV.delete('SHOWOFF_USE_NEW_SERVER') }

    it 'serves the presentation index' do
      # Start server in background thread
      thread = Thread.new { Showoff::ServerAdapter.run!(options) }
      sleep 1 # Wait for server to start

      response = Net::HTTP.get(URI('http://localhost:9091/'))
      expect(response).to include('<title>')

      thread.kill
    end
  end
end
```

---

## Appendix C: Migration Guide

### For Users

**Testing the New Architecture:**

```bash
# 1. Backup your presentation
cp -r my_presentation my_presentation.backup

# 2. Test with new architecture
cd my_presentation
SHOWOFF_USE_NEW_SERVER=true showoff serve

# 3. Verify functionality:
#    - Open http://localhost:9090/
#    - Navigate through slides
#    - Test presenter mode
#    - Check WebSocket sync

# 4. If issues found:
#    - Report to GitHub issues
#    - Use legacy mode: unset SHOWOFF_USE_NEW_SERVER
```

**Reporting Issues:**

Include:
- Showoff version
- Presentation structure (showoff.json)
- Error messages
- Steps to reproduce

### For Developers

**Contributing to Phase 5:**

1. Fork repository
2. Create feature branch: `git checkout -b phase5-fix-xyz`
3. Make changes
4. Run tests: `rake spec`
5. Test both modes:
   ```bash
   showoff serve  # Legacy
   SHOWOFF_USE_NEW_SERVER=true showoff serve  # New
   ```
6. Submit PR with:
   - Description of changes
   - Test coverage
   - Compatibility notes

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-24 | System Architect | Initial design document |

---

**End of Phase 5 Integration Design Document**
