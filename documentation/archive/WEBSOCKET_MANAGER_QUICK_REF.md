# WebSocketManager Quick Reference Card

## Class Signature
```ruby
class Showoff::Server::WebSocketManager
  def initialize(
    session_state:,           # SessionState instance
    stats_manager:,           # StatsManager instance
    logger:,                  # Logger instance
    current_slide_callback:,  # Proc for @@current access
    downloads_callback:       # Proc for @@downloads access
  )
end
```

## Public Methods

### Connection Management
```ruby
add_connection(ws, client_id, session_id, remote_addr = nil)
remove_connection(ws)
register_presenter(ws)
connection_count  # => Integer
presenter_count   # => Integer
is_presenter?(ws) # => Boolean
```

### Message Handling
```ruby
handle_message(ws, message_json, request_context)
# request_context = { cookies:, user_agent:, remote_addr: }
```

### Broadcasting
```ruby
broadcast_to_all(message_hash)
broadcast_to_presenters(message_hash)
broadcast_to_audience(message_hash)
send_to_connection(ws, message_hash)
```

### Activity Tracking
```ruby
get_activity_count(slide_number) # => Integer
clear_activity(slide_number = nil)
```

### Introspection
```ruby
get_connection_info(ws)  # => Hash or nil
all_connections          # => Array<Hash>
```

## Message Types

| Type | Direction | Target | Auth Required |
|------|-----------|--------|---------------|
| update | Client → Server | All | Presenter |
| register | Client → Server | Self | Presenter |
| track | Client → Server | Self | No |
| position | Client → Server | Self | No |
| activity | Client → Server | Presenters | No |
| pace | Client → Server | Presenters | No |
| question | Client → Server | Presenters | No |
| cancel | Client → Server | Presenters | No |
| complete | Client → Server | All | No |
| answerkey | Client → Server | All | No |
| annotation | Client → Server | Audience | No |
| annotationConfig | Client → Server | Audience | No |
| feedback | Client → Server | File | No |

## Data Structures

### Connection Metadata
```ruby
{
  client_id: "abc123",
  session_id: "session_xyz",
  is_presenter: false,
  registered_at: Time.now,
  remote_addr: "192.168.1.1"
}
```

### Activity Tracking
```ruby
{
  5 => { "client_abc" => false, "client_xyz" => true },
  7 => { "client_ghi" => false }
}
```

## Thread Safety

### Pattern
```ruby
# Always copy collections before EM.next_tick
connections = @mutex.synchronize { @connections.keys.dup }

EM.next_tick do
  connections.each { |ws| ws.send(...) }
end
```

### Critical Sections
- `@connections` hash modifications
- `@presenters` set modifications
- `@activity` hash modifications

## Error Handling

### Graceful Degradation
```ruby
begin
  # operation
rescue JSON::ParserError => e
  @logger.error "Parse error: #{e.message}"
  # continue
rescue StandardError => e
  @logger.error "Error: #{e.message}"
  # continue
end
```

### Logging Levels
- **DEBUG:** Message content, state changes
- **WARN:** Connection events, unknown messages
- **ERROR:** Parse failures, send failures

## Testing

### Mock WebSocket
```ruby
class MockWebSocket
  attr_reader :sent_messages
  
  def initialize
    @sent_messages = []
    @closed = false
  end
  
  def send(message)
    raise "Cannot send to closed socket" if @closed
    @sent_messages << message
  end
end
```

### Mock EventMachine
```ruby
before do
  allow(EM).to receive(:next_tick) { |&block| block.call }
end
```

### Test Structure
```ruby
describe Showoff::Server::WebSocketManager do
  let(:session_state) { Showoff::Server::SessionState.new }
  let(:stats_manager) { Showoff::Server::StatsManager.new('test.json') }
  let(:logger) { double('logger', warn: nil, debug: nil, error: nil) }
  let(:current_slide) { { name: 'slide1', number: 0, increment: 0 } }
  let(:current_slide_callback) { ... }
  let(:downloads_callback) { ... }
  
  subject(:manager) { described_class.new(...) }
  
  # Tests...
end
```

## Integration Example

### In showoff.rb
```ruby
configure do
  @ws_manager = Showoff::Server::WebSocketManager.new(
    session_state: @session_state,
    stats_manager: @stats_manager,
    logger: @logger,
    current_slide_callback: lambda { |action, value = nil|
      case action
      when :get then @@current
      when :set then @@current = value
      end
    },
    downloads_callback: lambda { |slide_num| @@downloads[slide_num] }
  )
end

get '/control' do
  if !request.websocket?
    erb :presenter
  else
    request.websocket do |ws|
      ws.onopen do
        @ws_manager.add_connection(
          ws,
          request.cookies['client_id'],
          session[:session_id],
          request.env['REMOTE_ADDR']
        )
      end
      
      ws.onmessage do |data|
        @ws_manager.handle_message(ws, data, {
          cookies: request.cookies,
          user_agent: request.user_agent,
          remote_addr: request.env['REMOTE_ADDR']
        })
      end
      
      ws.onclose do
        @ws_manager.remove_connection(ws)
      end
    end
  end
end
```

## Common Patterns

### Check Presenter
```ruby
return unless is_presenter_connection?(ws)
```

### Broadcast Pattern
```ruby
broadcast_to_all({
  'message' => 'current',
  'current' => slide_number,
  'increment' => increment
})
```

### Forward with Debounce
```ruby
control['id'] = generate_guid
broadcast_to_presenters(control)
```

## Debugging

### Enable Debug Logging
```ruby
@logger.level = Logger::DEBUG
```

### Inspect Connections
```ruby
manager.all_connections.each do |conn|
  puts "#{conn[:client_id]}: presenter=#{conn[:is_presenter]}"
end
```

### Check Activity
```ruby
count = manager.get_activity_count(slide_number)
puts "Incomplete activities: #{count}"
```

## Performance Notes

- **O(1)** presenter lookup (Set)
- **O(n)** broadcasting (unavoidable)
- **Mutex contention** minimal (copy-before-iterate)
- **EM.next_tick** prevents blocking

## Common Pitfalls

1. ❌ **Don't iterate @connections without copying**
   ```ruby
   # BAD
   @connections.each { |ws, info| ws.send(...) }
   
   # GOOD
   connections = @mutex.synchronize { @connections.keys.dup }
   connections.each { |ws| ws.send(...) }
   ```

2. ❌ **Don't call ws.send outside EM.next_tick**
   ```ruby
   # BAD
   ws.send(message.to_json)
   
   # GOOD
   EM.next_tick { ws.send(message.to_json) }
   ```

3. ❌ **Don't forget to remove connections on close**
   ```ruby
   # BAD
   ws.onclose { }
   
   # GOOD
   ws.onclose { @ws_manager.remove_connection(ws) }
   ```

## File Locations

- **Implementation:** `lib/showoff/server/websocket_manager.rb`
- **Tests:** `spec/unit/showoff/server/websocket_manager_spec.rb`
- **Design:** `documentation/WEBSOCKET_MANAGER_DESIGN.md`
- **Diagrams:** `documentation/WEBSOCKET_ARCHITECTURE_DIAGRAM.md`

---

**Quick Ref Version:** 1.0  
**Last Updated:** 2025-12-23
