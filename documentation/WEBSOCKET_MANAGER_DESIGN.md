# WebSocketManager Class Architecture Design

**Version:** 1.0
**Date:** 2025-12-23
**Status:** Design Complete - Ready for Implementation

## Overview

The `WebSocketManager` class is the 8th state manager in the Phase 4 refactoring effort. It extracts WebSocket connection management and message handling from the monolithic `showoff.rb` into a clean, testable, thread-safe component.

## Design Goals

1. **Thread-safe connection management** using Mutex-based locking
2. **Clean message routing** with testable handler methods
3. **EventMachine compatibility** for async broadcasting
4. **Integration** with existing state managers (SessionState, StatsManager)
5. **100% test coverage** using mock WebSocket objects
6. **Gradual migration** via callbacks to avoid breaking changes

## Class Structure

### File Location
```
lib/showoff/server/websocket_manager.rb
spec/unit/showoff/server/websocket_manager_spec.rb
```

### Dependencies
```ruby
require 'thread'
require 'json'
require 'set'
require 'eventmachine'  # Already a dependency via sinatra-websocket
```

### Class Skeleton

```ruby
class Showoff::Server::WebSocketManager
  # Initialize a new WebSocket manager
  #
  # @param session_state [Showoff::Server::SessionState] Session state manager
  # @param stats_manager [Showoff::Server::StatsManager] Statistics manager
  # @param logger [Logger] Logger instance
  # @param current_slide_callback [Proc] Callback for @@current access
  # @param downloads_callback [Proc] Callback for @@downloads access
  def initialize(session_state:, stats_manager:, logger:, current_slide_callback:, downloads_callback:)
    @mutex = Mutex.new
    @session_state = session_state
    @stats_manager = stats_manager
    @logger = logger
    @current_slide_callback = current_slide_callback
    @downloads_callback = downloads_callback

    # Connection tracking
    @connections = {}  # ws => { client_id:, session_id:, is_presenter:, registered_at:, remote_addr: }
    @presenters = Set.new  # Set of ws objects for O(1) lookup

    # Activity tracking (extracted from @@activity)
    @activity = Hash.new { |h, k| h[k] = {} }  # slide_number => { client_id => status }
  end

  # ... public methods ...

  private

  # ... private message handlers ...
end
```

## Data Structures

### Connection Metadata
```ruby
{
  client_id: "abc123",           # From request.cookies['client_id']
  session_id: "session_xyz",     # From session
  is_presenter: false,           # Presenter flag
  registered_at: Time.now,       # Connection timestamp
  remote_addr: "192.168.1.1"    # For logging
}
```

### Activity Tracking
```ruby
{
  5 => {                         # Slide number
    "client_abc" => false,       # Not completed
    "client_xyz" => true         # Completed
  }
}
```

## Public API

### Connection Lifecycle

```ruby
# Add a new WebSocket connection
#
# @param ws [WebSocket] The WebSocket connection object
# @param client_id [String] The client ID from cookies
# @param session_id [String] The session ID
# @param remote_addr [String, nil] Remote address for logging
# @return [void]
def add_connection(ws, client_id, session_id, remote_addr = nil)
  @mutex.synchronize do
    @connections[ws] = {
      client_id: client_id,
      session_id: session_id,
      is_presenter: false,
      registered_at: Time.now,
      remote_addr: remote_addr
    }
    @logger.debug "Added WebSocket connection: #{client_id} from #{remote_addr}"
  end
end

# Remove a WebSocket connection
#
# @param ws [WebSocket] The WebSocket connection object
# @return [void]
def remove_connection(ws)
  @mutex.synchronize do
    info = @connections.delete(ws)
    @presenters.delete(ws)
    @logger.debug "Removed WebSocket connection: #{info[:client_id]}" if info
  end
end

# Register a connection as a presenter
#
# @param ws [WebSocket] The WebSocket connection object
# @return [Boolean] True if successfully registered
def register_presenter(ws)
  @mutex.synchronize do
    if @connections.key?(ws)
      @connections[ws][:is_presenter] = true
      @presenters.add(ws)
      @logger.warn "Registered presenter: #{@connections[ws][:remote_addr]}"
      true
    else
      @logger.error "Attempted to register unknown connection as presenter"
      false
    end
  end
end

# Get connection count
#
# @return [Integer] Number of active connections
def connection_count
  @mutex.synchronize { @connections.size }
end

# Get presenter count
#
# @return [Integer] Number of active presenters
def presenter_count
  @mutex.synchronize { @presenters.size }
end

# Check if a connection is a presenter
#
# @param ws [WebSocket] The WebSocket connection object
# @return [Boolean] True if presenter
def is_presenter?(ws)
  @mutex.synchronize { @presenters.include?(ws) }
end
```

### Message Handling

```ruby
# Handle an incoming WebSocket message
#
# @param ws [WebSocket] The WebSocket connection object
# @param message_json [String] The JSON message string
# @param request_context [Hash] Request context with :cookies, :user_agent, :remote_addr
# @return [void]
def handle_message(ws, message_json, request_context)
  @mutex.synchronize do
    begin
      control = JSON.parse(message_json)
      @logger.debug "WebSocket message: #{control.inspect}"

      case control['message']
      when 'update'            then handle_update(ws, control, request_context)
      when 'register'          then handle_register(ws, control, request_context)
      when 'track'             then handle_track(ws, control, request_context)
      when 'position'          then handle_position(ws, control, request_context)
      when 'activity'          then handle_activity(ws, control, request_context)
      when 'pace'              then handle_pace(ws, control, request_context)
      when 'question'          then handle_question(ws, control, request_context)
      when 'cancel'            then handle_cancel(ws, control, request_context)
      when 'complete'          then handle_complete(ws, control, request_context)
      when 'answerkey'         then handle_answerkey(ws, control, request_context)
      when 'annotation'        then handle_annotation(ws, control, request_context)
      when 'annotationConfig'  then handle_annotation_config(ws, control, request_context)
      when 'feedback'          then handle_feedback(ws, control, request_context)
      else
        @logger.warn "Unknown WebSocket message type: #{control['message']}"
        @logger.debug control.inspect
      end

    rescue JSON::ParserError => e
      @logger.error "Failed to parse WebSocket message: #{e.message}"
      @logger.debug "Raw message: #{message_json}"
    rescue StandardError => e
      @logger.error "WebSocket message handling error: #{e.message}"
      @logger.debug e.backtrace.join("\n")
    end
  end
end
```

### Broadcasting

```ruby
# Broadcast a message to all connections
#
# @param message_hash [Hash] The message to broadcast
# @return [void]
def broadcast_to_all(message_hash)
  connections = @mutex.synchronize { @connections.keys.dup }

  EM.next_tick do
    connections.each do |ws|
      send_to_connection(ws, message_hash)
    end
  end
end

# Broadcast a message to presenters only
#
# @param message_hash [Hash] The message to broadcast
# @return [void]
def broadcast_to_presenters(message_hash)
  presenters = @mutex.synchronize { @presenters.to_a.dup }

  EM.next_tick do
    presenters.each do |ws|
      send_to_connection(ws, message_hash)
    end
  end
end

# Broadcast a message to audience only (non-presenters)
#
# @param message_hash [Hash] The message to broadcast
# @return [void]
def broadcast_to_audience(message_hash)
  audience = @mutex.synchronize { (@connections.keys - @presenters.to_a).dup }

  EM.next_tick do
    audience.each do |ws|
      send_to_connection(ws, message_hash)
    end
  end
end

# Send a message to a specific connection
#
# @param ws [WebSocket] The WebSocket connection object
# @param message_hash [Hash] The message to send
# @return [void]
def send_to_connection(ws, message_hash)
  begin
    ws.send(message_hash.to_json)
  rescue StandardError => e
    @logger.error "Failed to send to WebSocket: #{e.message}"
    # Don't raise - connection might be dead
  end
end
```

### Activity Tracking

```ruby
# Get activity completion count for a slide
#
# @param slide_number [Integer] The slide number
# @return [Integer] Number of incomplete activities
def get_activity_count(slide_number)
  @mutex.synchronize do
    activity = @activity[slide_number]
    return 0 unless activity
    activity.select { |_client_id, status| status == false }.size
  end
end

# Clear activity tracking
#
# @param slide_number [Integer, nil] Specific slide or nil for all
# @return [void]
def clear_activity(slide_number = nil)
  @mutex.synchronize do
    if slide_number
      @activity.delete(slide_number)
    else
      @activity.clear
    end
  end
end
```

### Introspection

```ruby
# Get connection information
#
# @param ws [WebSocket] The WebSocket connection object
# @return [Hash, nil] Connection metadata or nil
def get_connection_info(ws)
  @mutex.synchronize { @connections[ws]&.dup }
end

# Get all connections
#
# @return [Array<Hash>] Array of connection metadata
def all_connections
  @mutex.synchronize do
    @connections.map { |ws, info| info.merge(ws: ws) }
  end
end
```

## Private Message Handlers

### update - Presenter slide navigation
```ruby
# Handle 'update' message - presenter navigates to new slide
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_update(ws, control, request_context)
  return unless is_presenter_connection?(ws)

  name = control['name']
  slide = control['slide'].to_i
  increment = control['increment'].to_i rescue 0

  # Enable download if needed
  downloads = @downloads_callback.call(slide)
  if downloads
    @logger.debug "Enabling file download for slide #{name}"
    downloads[0] = true
  end

  # Update current slide
  @logger.debug "Updated current slide to #{name}"
  @current_slide_callback.call(:set, { name: name, number: slide, increment: increment })

  # Broadcast to all clients
  broadcast_to_all({
    'message' => 'current',
    'current' => slide,
    'increment' => increment
  })
end
```

### register - Register as presenter
```ruby
# Handle 'register' message - register connection as presenter
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_register(ws, control, request_context)
  return unless @session_state.valid_presenter_cookie?(request_context[:cookies]['presenter'])

  register_presenter(ws)
end
```

### track - Track slide views
```ruby
# Handle 'track' message - track slide view or current position
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_track(ws, control, request_context)
  info = @connections[ws]
  return unless info

  remote = is_presenter_connection?(ws) ? 'presenter' : info[:client_id]
  slide = control['slide']

  if control.key?('time')
    # Record pageview with elapsed time
    time = control['time'].to_f
    @stats_manager.record_view(slide, remote, Time.now, request_context[:user_agent])
    @logger.debug "Logged #{time}s on slide #{slide} for #{remote}"
  else
    # Record current position
    @stats_manager.record_view(slide, remote, Time.now, request_context[:user_agent])
    @logger.debug "Recorded current slide #{slide} for #{remote}"
  end
end
```

### position - Request current slide
```ruby
# Handle 'position' message - client requests current slide
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_position(ws, control, request_context)
  current = @current_slide_callback.call(:get)
  return if current.nil? || current[:number].nil?

  send_to_connection(ws, {
    'message' => 'current',
    'current' => current[:number]
  })
end
```

### activity - Track activity completion
```ruby
# Handle 'activity' message - track activity slide completion
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_activity(ws, control, request_context)
  return if is_presenter_connection?(ws)

  info = @connections[ws]
  return unless info

  slide = control['slide']
  status = control['status']

  @activity[slide] ||= {}
  @activity[slide][info[:client_id]] = status

  # Get current slide and activity count
  current = @current_slide_callback.call(:get)
  if current && current[:number] == slide
    count = get_activity_count(slide)
    broadcast_to_presenters({
      'message' => 'activity',
      'count' => count
    })
  end
end
```

### pace, question, cancel - Forward to presenters
```ruby
# Handle 'pace', 'question', 'cancel' messages - forward to presenters
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_pace(ws, control, request_context)
  control['id'] = generate_guid
  broadcast_to_presenters(control)
end

def handle_question(ws, control, request_context)
  control['id'] = generate_guid
  broadcast_to_presenters(control)
end

def handle_cancel(ws, control, request_context)
  control['id'] = generate_guid
  broadcast_to_presenters(control)
end
```

### complete, answerkey - Broadcast to all
```ruby
# Handle 'complete', 'answerkey' messages - broadcast to all
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_complete(ws, control, request_context)
  broadcast_to_all(control)
end

def handle_answerkey(ws, control, request_context)
  broadcast_to_all(control)
end
```

### annotation, annotationConfig - Broadcast to audience
```ruby
# Handle 'annotation', 'annotationConfig' messages - broadcast to audience
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_annotation(ws, control, request_context)
  broadcast_to_audience(control)
end

def handle_annotation_config(ws, control, request_context)
  broadcast_to_audience(control)
end
```

### feedback - Write to file
```ruby
# Handle 'feedback' message - write feedback to file
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The message payload
# @param request_context [Hash] Request context
# @return [void]
def handle_feedback(ws, control, request_context)
  # TODO: Extract to FeedbackManager in future refactoring
  # For now, keep file I/O here to maintain compatibility

  filename = "#{settings.statsdir}/#{settings.feedback}"
  slide = control['slide']
  rating = control['rating']
  feedback = control['feedback']

  begin
    log = JSON.parse(File.read(filename))
  rescue
    log = {}
  end

  log[slide] ||= []
  log[slide] << { rating: rating, feedback: feedback }

  if settings.verbose
    File.write(filename, JSON.pretty_generate(log))
  else
    File.write(filename, log.to_json)
  end
end
```

### Helper Methods
```ruby
# Generate a GUID for message deduplication
#
# @return [String] A simple GUID
def generate_guid
  (0..15).to_a.map { |a| rand(16).to_s(16) }.join
end

# Check if a connection is a presenter
#
# @param ws [WebSocket] The WebSocket connection
# @return [Boolean] True if presenter
def is_presenter_connection?(ws)
  @presenters.include?(ws)
end
```

## Integration with showoff.rb

### Initialization
```ruby
# In showoff.rb configure block:
configure do
  # ... existing configuration ...

  @session_state = Showoff::Server::SessionState.new
  @stats_manager = Showoff::Server::StatsManager.new("#{settings.statsdir}/#{settings.viewstats}")

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
    downloads_callback: lambda { |slide_num|
      @@downloads[slide_num]
    }
  )
end
```

### WebSocket Route
```ruby
# Replace lines 1830-1970 in showoff.rb:
get '/control' do
  if !request.websocket?
    erb :presenter
  else
    request.websocket do |ws|
      ws.onopen do
        client_id = request.cookies['client_id']
        session_id = session[:session_id]
        remote_addr = request.env['REMOTE_HOST'] || request.env['REMOTE_ADDR']

        @ws_manager.add_connection(ws, client_id, session_id, remote_addr)

        # Send current slide
        current = @@current
        ws.send({ 'message' => 'current', 'current' => current[:number] }.to_json)

        @logger.warn "Open sockets: #{@ws_manager.connection_count}"
      end

      ws.onmessage do |data|
        request_context = {
          cookies: request.cookies,
          user_agent: request.user_agent,
          remote_addr: request.env['REMOTE_HOST'] || request.env['REMOTE_ADDR']
        }

        @ws_manager.handle_message(ws, data, request_context)
      end

      ws.onclose do
        @logger.warn "WebSocket closed"
        @ws_manager.remove_connection(ws)
      end
    end
  end
end
```

## Thread Safety Strategy

### Critical Sections
All shared state modifications are protected by `@mutex.synchronize`:

1. **@connections hash** - add/remove/modify
2. **@presenters set** - add/remove
3. **@activity hash** - modify/read

### EventMachine Compatibility
- **EM.next_tick** wraps all broadcasting to ensure async execution
- **Mutex** protects state, not EM operations
- **Copy collections** before iterating in EM.next_tick to avoid mutation issues

### Thread Safety Pattern
```ruby
def broadcast_to_all(message_hash)
  # Copy under mutex
  connections = @mutex.synchronize { @connections.keys.dup }

  # Broadcast outside mutex in EM context
  EM.next_tick do
    connections.each do |ws|
      send_to_connection(ws, message_hash)
    end
  end
end
```

## Testing Strategy

### Mock WebSocket Object
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

  def close
    @closed = true
  end

  def closed?
    @closed
  end
end
```

### Test Structure
```ruby
describe Showoff::Server::WebSocketManager do
  let(:session_state) { Showoff::Server::SessionState.new }
  let(:stats_manager) { Showoff::Server::StatsManager.new('test_stats.json') }
  let(:logger) { double('logger', warn: nil, debug: nil, error: nil) }
  let(:current_slide) { { name: 'slide1', number: 0, increment: 0 } }
  let(:current_slide_callback) do
    lambda { |action, value = nil|
      case action
      when :get then current_slide
      when :set then current_slide.merge!(value)
      end
    }
  end
  let(:downloads_callback) { lambda { |slide_num| nil } }

  subject(:manager) do
    described_class.new(
      session_state: session_state,
      stats_manager: stats_manager,
      logger: logger,
      current_slide_callback: current_slide_callback,
      downloads_callback: downloads_callback
    )
  end

  # Mock EM.next_tick to execute immediately
  before do
    allow(EM).to receive(:next_tick) { |&block| block.call }
  end

  describe '#add_connection' do
    it 'adds a connection with metadata'
    it 'is thread-safe with concurrent adds'
  end

  describe '#remove_connection' do
    it 'removes a connection'
    it 'removes from presenters set if presenter'
  end

  describe '#register_presenter' do
    it 'adds connection to presenters set'
    it 'returns false for unknown connection'
  end

  describe '#broadcast_to_all' do
    it 'sends message to all connections'
    it 'handles send failures gracefully'
  end

  describe '#broadcast_to_presenters' do
    it 'sends only to presenters'
  end

  describe '#broadcast_to_audience' do
    it 'sends only to non-presenters'
  end

  describe '#handle_message' do
    let(:ws) { MockWebSocket.new }
    let(:request_context) do
      {
        cookies: { 'client_id' => 'abc123', 'presenter' => 'valid_cookie' },
        user_agent: 'Test Browser',
        remote_addr: '127.0.0.1'
      }
    end

    before do
      manager.add_connection(ws, 'abc123', 'session123', '127.0.0.1')
    end

    context 'with update message' do
      it 'updates current slide if presenter'
      it 'ignores if not presenter'
      it 'broadcasts to all clients'
    end

    context 'with track message' do
      it 'records pageview via StatsManager'
      it 'includes elapsed time'
    end

    context 'with activity message' do
      it 'tracks completion status'
      it 'broadcasts count to presenters'
      it 'ignores presenter submissions'
    end

    context 'with invalid JSON' do
      it 'logs error and continues'
    end

    context 'with unknown message type' do
      it 'logs warning'
    end
  end

  describe 'thread safety' do
    it 'handles concurrent add/remove'
    it 'handles concurrent broadcasting'
  end
end
```

### Test Coverage Target
- **100% line coverage**
- **All 12 message types** tested
- **Thread safety** verified with concurrent operations
- **Error handling** for JSON parse errors, send failures
- **Integration** with SessionState and StatsManager

## Error Handling

### Graceful Degradation
- **JSON parse errors** - log and continue
- **Send failures** - log but don't crash
- **Unknown message types** - log warning
- **Missing connections** - return early

### Logging Levels
- **DEBUG** - Message content, state changes
- **WARN** - Connection events, unknown messages
- **ERROR** - Parse failures, send failures

## Migration Path

### Phase 1: Create WebSocketManager (This Design)
- Implement class with full test coverage
- Keep as separate component

### Phase 2: Integrate with showoff.rb
- Replace `/control` route WebSocket handling
- Use callbacks for @@current and @@downloads
- Verify backward compatibility

### Phase 3: Extract Feedback Handling
- Create FeedbackManager
- Move feedback file I/O out of WebSocketManager
- Update handle_feedback to use FeedbackManager

### Phase 4: Extract Activity Tracking
- Create ActivityManager
- Move @activity hash to ActivityManager
- Update handle_activity to use ActivityManager

## Estimated Complexity

- **Main class:** ~400 lines
- **Tests:** ~600 lines
- **Total:** ~1000 lines
- **Implementation time:** 2-3 days
- **Testing time:** 1-2 days

## Success Criteria

1. ✅ All 12 message types handled correctly
2. ✅ Thread-safe with Mutex protection
3. ✅ EventMachine compatible with EM.next_tick
4. ✅ 100% test coverage
5. ✅ No breaking changes to existing functionality
6. ✅ Clean integration with SessionState and StatsManager
7. ✅ Comprehensive error handling and logging

## Future Enhancements

1. **FeedbackManager** - Extract feedback file I/O
2. **ActivityManager** - Extract activity tracking
3. **Connection pooling** - Limit max connections
4. **Heartbeat/ping** - Detect dead connections
5. **Message queuing** - Handle backpressure
6. **Metrics** - Track message rates, latencies

---

**Design Status:** ✅ Complete and ready for implementation
**Next Step:** Begin implementation with test-first approach
