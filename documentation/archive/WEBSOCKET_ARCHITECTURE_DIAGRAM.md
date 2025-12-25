# WebSocketManager Architecture Diagram

## System Context

```
┌─────────────────────────────────────────────────────────────────┐
│                         Showoff Server                          │
│                                                                 │
│  ┌──────────────┐                                              │
│  │  showoff.rb  │                                              │
│  │  (Sinatra)   │                                              │
│  └──────┬───────┘                                              │
│         │                                                       │
│         │ GET /control                                         │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │           WebSocket Route Handler                        │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐        │ │
│  │  │ ws.onopen  │  │ws.onmessage│  │ ws.onclose │        │ │
│  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘        │ │
│  └────────┼───────────────┼───────────────┼───────────────┘ │
│           │               │               │                   │
│           ▼               ▼               ▼                   │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │              WebSocketManager                            │ │
│  │  ┌────────────────────────────────────────────────────┐ │ │
│  │  │  Connection Management                             │ │ │
│  │  │  • add_connection()                                │ │ │
│  │  │  • remove_connection()                             │ │ │
│  │  │  • register_presenter()                            │ │ │
│  │  └────────────────────────────────────────────────────┘ │ │
│  │  ┌────────────────────────────────────────────────────┐ │ │
│  │  │  Message Routing                                   │ │ │
│  │  │  • handle_message()                                │ │ │
│  │  │  • 12 message type handlers                        │ │ │
│  │  └────────────────────────────────────────────────────┘ │ │
│  │  ┌────────────────────────────────────────────────────┐ │ │
│  │  │  Broadcasting                                      │ │ │
│  │  │  • broadcast_to_all()                              │ │ │
│  │  │  • broadcast_to_presenters()                       │ │ │
│  │  │  • broadcast_to_audience()                         │ │ │
│  │  └────────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────┘ │
│           │               │               │                   │
│           ▼               ▼               ▼                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ SessionState │  │ StatsManager │  │   Callbacks  │       │
│  │              │  │              │  │  @@current   │       │
│  │ • presenter  │  │ • pageviews  │  │  @@downloads │       │
│  │   auth       │  │ • questions  │  └──────────────┘       │
│  └──────────────┘  └──────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

## Component Interaction Flow

### Connection Lifecycle

```
Client Browser                WebSocket Route              WebSocketManager
      │                             │                             │
      │  WebSocket Connect          │                             │
      ├────────────────────────────>│                             │
      │                             │                             │
      │                             │  ws.onopen                  │
      │                             ├────────────────────────────>│
      │                             │                             │
      │                             │  add_connection(ws, ...)    │
      │                             │                             │
      │                             │<────────────────────────────┤
      │                             │  connection added           │
      │                             │                             │
      │  { message: 'current' }     │                             │
      │<────────────────────────────┤                             │
      │                             │                             │
      │  Send message               │                             │
      ├────────────────────────────>│                             │
      │                             │  ws.onmessage               │
      │                             ├────────────────────────────>│
      │                             │  handle_message(ws, data)   │
      │                             │                             │
      │                             │<────────────────────────────┤
      │                             │  message processed          │
      │                             │                             │
      │  Disconnect                 │                             │
      ├────────────────────────────>│                             │
      │                             │  ws.onclose                 │
      │                             ├────────────────────────────>│
      │                             │  remove_connection(ws)      │
      │                             │                             │
```

### Message Handling Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    handle_message(ws, json)                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
                    ┌────────────────┐
                    │  Parse JSON    │
                    └────────┬───────┘
                             │
                             ▼
                    ┌────────────────┐
                    │ Route by type  │
                    └────────┬───────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐         ┌─────────┐        ┌─────────┐
    │ update  │         │  track  │        │activity │
    └────┬────┘         └────┬────┘        └────┬────┘
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐         ┌─────────┐        ┌─────────┐
    │Check    │         │Record   │        │Update   │
    │presenter│         │stats    │        │activity │
    └────┬────┘         └────┬────┘        └────┬────┘
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐         ┌─────────┐        ┌─────────┐
    │Update   │         │Log view │        │Broadcast│
    │@@current│         │         │        │to       │
    └────┬────┘         └─────────┘        │presenter│
         │                                  └────┬────┘
         ▼                                       │
    ┌─────────┐                                 │
    │Broadcast│                                 │
    │to all   │                                 │
    └─────────┘                                 │
         │                                      │
         └──────────────┬───────────────────────┘
                        │
                        ▼
               ┌────────────────┐
               │  EM.next_tick  │
               └────────┬───────┘
                        │
                        ▼
               ┌────────────────┐
               │  ws.send(json) │
               └────────────────┘
```

## Data Structure Relationships

```
WebSocketManager
├── @connections: Hash
│   ├── ws1 => { client_id: "abc", session_id: "s1", is_presenter: false, ... }
│   ├── ws2 => { client_id: "def", session_id: "s2", is_presenter: true,  ... }
│   └── ws3 => { client_id: "ghi", session_id: "s3", is_presenter: false, ... }
│
├── @presenters: Set
│   └── [ws2]
│
└── @activity: Hash
    ├── 5 => { "abc" => false, "def" => true }
    └── 7 => { "ghi" => false }
```

## Message Type Routing

```
┌──────────────────────────────────────────────────────────────┐
│                     Message Types (12)                       │
└──────────────────────────────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Presenter Only  │  │  Audience Only  │  │   Broadcast     │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ • update        │  │ • track         │  │ • complete      │
│ • register      │  │ • activity      │  │ • answerkey     │
│                 │  │ • pace          │  │                 │
│                 │  │ • question      │  │                 │
│                 │  │ • cancel        │  │                 │
│                 │  │ • feedback      │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Check presenter │  │ Forward to      │  │ Send to all     │
│ cookie          │  │ presenters      │  │ connections     │
└─────────────────┘  └─────────────────┘  └─────────────────┘

┌─────────────────┐  ┌─────────────────┐
│ Special Cases   │  │ Audience Bcast  │
├─────────────────┤  ├─────────────────┤
│ • position      │  │ • annotation    │
│   (send current)│  │ • annotationCfg │
└─────────────────┘  └─────────────────┘
         │                   │
         ▼                   ▼
┌─────────────────┐  ┌─────────────────┐
│ Send to         │  │ Send to         │
│ requester only  │  │ non-presenters  │
└─────────────────┘  └─────────────────┘
```

## Thread Safety Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Thread Safety Zones                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  MUTEX PROTECTED (Shared State)                             │
├─────────────────────────────────────────────────────────────┤
│  • @connections hash (add/remove/modify)                    │
│  • @presenters set (add/remove)                             │
│  • @activity hash (read/write)                              │
│                                                              │
│  Pattern:                                                    │
│    @mutex.synchronize do                                     │
│      # modify shared state                                   │
│      connections = @connections.keys.dup  # copy for EM      │
│    end                                                       │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  EVENTMACHINE ZONE (Single-threaded)                        │
├─────────────────────────────────────────────────────────────┤
│  • ws.send() operations                                      │
│  • JSON serialization                                        │
│  • Iteration over copied collections                         │
│                                                              │
│  Pattern:                                                    │
│    EM.next_tick do                                           │
│      connections.each { |ws| ws.send(...) }                  │
│    end                                                       │
└─────────────────────────────────────────────────────────────┘
```

## Integration Points

```
┌─────────────────────────────────────────────────────────────┐
│                   WebSocketManager                          │
└─────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ SessionState │ │ StatsManager │ │ @@current    │ │ @@downloads  │
│              │ │              │ │  (callback)  │ │  (callback)  │
├──────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤
│ • valid_     │ │ • record_    │ │ • get        │ │ • [slide] => │
│   presenter_ │ │   view()     │ │ • set        │ │   [enabled,  │
│   cookie?()  │ │ • record_    │ │              │ │    name,     │
│              │ │   question() │ │              │ │    files]    │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

## Broadcasting Patterns

```
┌─────────────────────────────────────────────────────────────┐
│                    Broadcasting Strategy                     │
└─────────────────────────────────────────────────────────────┘

broadcast_to_all(msg)
  │
  ├─> @mutex.synchronize { @connections.keys.dup }
  │
  └─> EM.next_tick do
        connections.each { |ws| ws.send(msg.to_json) }
      end

broadcast_to_presenters(msg)
  │
  ├─> @mutex.synchronize { @presenters.to_a.dup }
  │
  └─> EM.next_tick do
        presenters.each { |ws| ws.send(msg.to_json) }
      end

broadcast_to_audience(msg)
  │
  ├─> @mutex.synchronize { (@connections.keys - @presenters.to_a).dup }
  │
  └─> EM.next_tick do
        audience.each { |ws| ws.send(msg.to_json) }
      end
```

## Error Handling Flow

```
handle_message(ws, json, context)
  │
  ├─> JSON.parse(json)
  │     │
  │     ├─> Success ──> route_message()
  │     │
  │     └─> JSON::ParserError
  │           │
  │           └─> @logger.error("Failed to parse...")
  │               return (graceful degradation)
  │
  └─> route_message()
        │
        ├─> Known type ──> handle_xxx()
        │                    │
        │                    ├─> Success
        │                    │
        │                    └─> StandardError
        │                          │
        │                          └─> @logger.error(...)
        │                              return
        │
        └─> Unknown type
              │
              └─> @logger.warn("Unknown message type...")
                  return
```

## Testing Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Test Structure                          │
└─────────────────────────────────────────────────────────────┘

RSpec Tests
  │
  ├─> Unit Tests (WebSocketManager)
  │     │
  │     ├─> Connection Management
  │     │     ├─> add_connection
  │     │     ├─> remove_connection
  │     │     └─> register_presenter
  │     │
  │     ├─> Message Handling (12 types)
  │     │     ├─> update
  │     │     ├─> register
  │     │     ├─> track
  │     │     ├─> position
  │     │     ├─> activity
  │     │     ├─> pace
  │     │     ├─> question
  │     │     ├─> cancel
  │     │     ├─> complete
  │     │     ├─> answerkey
  │     │     ├─> annotation
  │     │     ├─> annotationConfig
  │     │     └─> feedback
  │     │
  │     ├─> Broadcasting
  │     │     ├─> broadcast_to_all
  │     │     ├─> broadcast_to_presenters
  │     │     └─> broadcast_to_audience
  │     │
  │     ├─> Thread Safety
  │     │     ├─> concurrent add/remove
  │     │     └─> concurrent broadcasting
  │     │
  │     └─> Error Handling
  │           ├─> JSON parse errors
  │           ├─> send failures
  │           └─> unknown message types
  │
  └─> Integration Tests (with SessionState, StatsManager)
        │
        ├─> Presenter authentication
        ├─> Stats recording
        └─> Callback integration

Mocks
  │
  ├─> MockWebSocket
  │     ├─> send(message)
  │     ├─> close()
  │     └─> sent_messages[]
  │
  ├─> Mock EM.next_tick
  │     └─> Execute block immediately
  │
  └─> Mock Logger
        ├─> debug()
        ├─> warn()
        └─> error()
```

## Migration Path

```
Phase 1: Create WebSocketManager
  │
  ├─> Implement class
  ├─> Write tests (100% coverage)
  └─> Verify in isolation

Phase 2: Integrate with showoff.rb
  │
  ├─> Replace /control route
  ├─> Use callbacks for @@current, @@downloads
  └─> Verify backward compatibility

Phase 3: Extract Feedback
  │
  ├─> Create FeedbackManager
  ├─> Move file I/O
  └─> Update handle_feedback

Phase 4: Extract Activity
  │
  ├─> Create ActivityManager
  ├─> Move @activity hash
  └─> Update handle_activity
```

---

**Diagram Version:** 1.0
**Last Updated:** 2025-12-23
