# Showoff Server Architecture

**Version:** 2.0
**Date:** 2025-12-24
**Status:** Implemented (v0.24.0)

## Overview

Showoff uses a modular server architecture built on Sinatra::Base. This document describes the current architecture and its key components.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Showoff::Server                         │
│                   (Sinatra::Base)                           │
├─────────────────────────────────────────────────────────────┤
│ - presentation: Presentation                                │
│ - session_state: SessionState                               │
│ - stats_manager: StatsManager                               │
│ - form_manager: FormManager                                 │
│ - websocket_manager: WebSocketManager                       │
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
│ HTTP Routes  │        │ State        │
│              │        │ Managers     │
├──────────────┤        ├──────────────┤
│ GET /        │        │ SessionState │
│ GET /presenter│       │ StatsManager │
│ GET /slides  │        │ FormManager  │
│ GET /print   │        │ CacheManager │
│ POST /form/* │        │ ActivityMgr  │
│ GET /stats   │        │ DownloadMgr  │
│ GET /control │        │ FeedbackMgr  │
│ GET /execute │        └──────────────┘
└──────────────┘
        │
        ▼
┌──────────────────────┐
│ WebSocketManager     │
├──────────────────────┤
│ + register(ws)       │
│ + broadcast(msg)     │
│ + unregister(ws)     │
│ + handle_message()   │
└──────────────────────┘
```

## Core Components

### Showoff::Server

The main Sinatra::Base application class. Handles HTTP routing and coordinates all server components.

**Key Design Decisions:**
- Uses Sinatra::Base (modular style) instead of Sinatra::Application
- Explicit configuration with no magic globals
- Testable in isolation via dependency injection
- Thread-safe by design

### State Managers

All state managers use Mutex-based synchronization for thread safety.

#### SessionState
Manages presenter/audience sessions, current slide position, and follow-mode state.

```ruby
session_state = Showoff::Server::SessionState.new
session_state.update_current_slide(name: 'intro', number: 1)
session_state.current_slide  # => { name: 'intro', number: 1, increment: 0 }
```

#### StatsManager
Tracks slide views, questions, and pace feedback with JSON persistence.

```ruby
stats_manager = Showoff::Server::StatsManager.new('/path/to/stats')
stats_manager.record_view('slide_1', user_agent: 'Mozilla/5.0...')
stats_manager.flush  # Persists to disk
```

#### FormManager
Stores form responses with validation and aggregation for quizzes/surveys.

```ruby
form_manager = Showoff::Server::FormManager.new('/path/to/stats')
form_manager.save_response('quiz_1', { answer: 'A' })
form_manager.get_responses('quiz_1')  # => [{ answer: 'A' }]
```

#### CacheManager
LRU cache for compiled slide content with configurable size limits.

```ruby
cache_manager = Showoff::Server::CacheManager.new(max_size: 100)
cache_manager.fetch('slide_key') { expensive_computation }
```

#### WebSocketManager
Handles real-time communication for slide synchronization.

```ruby
websocket_manager = Showoff::Server::WebSocketManager.new(session_state, stats_manager)
websocket_manager.register(ws, presenter: true)
websocket_manager.broadcast({ message: 'update', slide: 5 })
```

### ServerAdapter

CLI compatibility layer that bridges the GLI command-line interface with the Sinatra server.

```ruby
# Used by bin/showoff
Showoff::ServerAdapter.run!(options) do |server|
  server.ssl = true if options[:ssl]
end
```

## Route Structure

| Route | Method | Description |
|-------|--------|-------------|
| `/` | GET | Main presentation view |
| `/presenter` | GET | Presenter view with notes |
| `/slides` | GET | AJAX slide content |
| `/print/:notes?` | GET | Printable version |
| `/onepage` | GET | Single-page view |
| `/supplemental/:type` | GET | Supplemental materials |
| `/stats` | GET | Viewing statistics |
| `/download` | GET | Downloadable files |
| `/form/:id` | GET/POST | Form submission/retrieval |
| `/execute/:lang` | GET | Code execution |
| `/edit/*` | GET | Local file editing |
| `/image/*`, `/file/*` | GET | Asset serving |
| `/control` | GET | WebSocket endpoint |
| `/health` | GET | Health check |

## WebSocket Messages

The WebSocket endpoint (`/control`) handles these message types:

| Message | Direction | Description |
|---------|-----------|-------------|
| `register` | Client→Server | Register as presenter |
| `update` | Client→Server | Update current slide |
| `current` | Server→Client | Broadcast current slide |
| `track` | Client→Server | Track viewer position |
| `pace` | Client→Server | Pace feedback |
| `question` | Client→Server | Ask question |
| `feedback` | Client→Server | Slide feedback |
| `activity` | Bidirectional | Activity completion |
| `annotation` | Bidirectional | Slide annotations |

## Testing

The architecture is designed for testability:

```ruby
# Unit test example
RSpec.describe Showoff::Server::SessionState do
  subject(:state) { described_class.new }

  it 'updates slide atomically' do
    state.update_current_slide(name: 'intro', number: 1)
    expect(state.current_slide[:number]).to eq(1)
  end
end

# Integration test example
RSpec.describe 'Routes' do
  include Rack::Test::Methods

  def app
    Showoff::Server.new(nil, pres_dir: fixture_path)
  end

  it 'serves the index' do
    get '/'
    expect(last_response).to be_ok
  end
end
```

## File Structure

```
lib/showoff/
├── server.rb                    # Main Server class
├── server_adapter.rb            # CLI compatibility layer
└── server/
    ├── session_state.rb         # Session management
    ├── stats_manager.rb         # Statistics tracking
    ├── form_manager.rb          # Form responses
    ├── cache_manager.rb         # LRU cache
    ├── download_manager.rb      # Download tracking
    ├── activity_manager.rb      # Activity completion
    ├── execution_manager.rb     # Code execution
    ├── websocket_manager.rb     # Real-time sync
    └── feedback_manager.rb      # Audience feedback
```

## Performance Considerations

- **Caching**: Compiled slides are cached per locale
- **Thread Safety**: All state managers use Mutex synchronization
- **WebSocket**: EventMachine handles concurrent connections
- **Persistence**: Stats and forms use atomic JSON writes

## Configuration

Server configuration is loaded from `showoff.json`:

```json
{
  "name": "My Presentation",
  "sections": ["intro", "main", "conclusion"],
  "protected": ["presenter"],
  "password": "secret"
}
```

CLI options override configuration file settings.
