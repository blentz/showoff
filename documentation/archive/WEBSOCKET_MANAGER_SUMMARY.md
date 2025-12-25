# WebSocketManager Design Summary

**Status:** ✅ Design Complete - Ready for Implementation  
**Date:** 2025-12-23  
**Phase:** 4 (State Manager Extraction)

## Quick Reference

### Files Created
- `documentation/WEBSOCKET_MANAGER_DESIGN.md` - Detailed class design
- `documentation/WEBSOCKET_ARCHITECTURE_DIAGRAM.md` - Visual architecture
- `documentation/WEBSOCKET_MANAGER_SUMMARY.md` - This file

### Implementation Files (To Be Created)
- `lib/showoff/server/websocket_manager.rb` - Main class (~400 LOC)
- `spec/unit/showoff/server/websocket_manager_spec.rb` - Tests (~600 LOC)

## Design Highlights

### 1. **Clean Architecture**
```ruby
WebSocketManager
├── Connection Management (add/remove/register)
├── Message Routing (12 message types)
├── Broadcasting (all/presenters/audience)
└── Activity Tracking (completion status)
```

### 2. **Thread Safety**
- Mutex-based protection for shared state
- EventMachine compatibility with EM.next_tick
- Copy-before-iterate pattern for broadcasting

### 3. **Integration Strategy**
- Dependency injection via constructor
- Callbacks for @@current and @@downloads (gradual migration)
- Clean interfaces with SessionState and StatsManager

### 4. **Testing Approach**
- Mock WebSocket objects
- Mock EM.next_tick for synchronous testing
- 100% coverage target
- Test each message handler independently

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Hash + Set for connections | O(1) lookups for presenters |
| Callbacks for @@current/@@downloads | Avoid breaking changes during migration |
| EM.next_tick for broadcasting | Maintain async behavior |
| Private handler methods | Testability and separation of concerns |
| Activity tracking in manager | Consolidate related state |

## Message Type Summary

| Type | Handler | Target | Integration |
|------|---------|--------|-------------|
| update | handle_update | All | @@current, @@downloads |
| register | handle_register | Self | SessionState |
| track | handle_track | Self | StatsManager |
| position | handle_position | Self | @@current |
| activity | handle_activity | Presenters | @activity hash |
| pace | handle_pace | Presenters | None |
| question | handle_question | Presenters | None |
| cancel | handle_cancel | Presenters | None |
| complete | handle_complete | All | None |
| answerkey | handle_answerkey | All | None |
| annotation | handle_annotation | Audience | None |
| annotationConfig | handle_annotation_config | Audience | None |
| feedback | handle_feedback | File | File I/O (future: FeedbackManager) |

## Implementation Checklist

### Phase 1: Core Implementation
- [ ] Create `lib/showoff/server/websocket_manager.rb`
- [ ] Implement constructor with dependency injection
- [ ] Implement connection management methods
- [ ] Implement broadcasting methods
- [ ] Implement message routing
- [ ] Implement all 12 message handlers
- [ ] Add comprehensive error handling
- [ ] Add logging throughout

### Phase 2: Testing
- [ ] Create `spec/unit/showoff/server/websocket_manager_spec.rb`
- [ ] Create MockWebSocket helper
- [ ] Test connection management
- [ ] Test broadcasting (all/presenters/audience)
- [ ] Test all 12 message handlers
- [ ] Test thread safety with concurrent operations
- [ ] Test error handling (JSON parse, send failures)
- [ ] Test integration with SessionState
- [ ] Test integration with StatsManager
- [ ] Verify 100% coverage

### Phase 3: Integration
- [ ] Update `showoff.rb` to initialize WebSocketManager
- [ ] Replace `/control` route WebSocket handling
- [ ] Implement callbacks for @@current and @@downloads
- [ ] Test backward compatibility
- [ ] Update documentation

### Phase 4: Cleanup (Future)
- [ ] Extract FeedbackManager
- [ ] Extract ActivityManager
- [ ] Remove callbacks, use direct manager references

## Code Snippets

### Initialization in showoff.rb
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
```

### WebSocket Route
```ruby
get '/control' do
  if !request.websocket?
    erb :presenter
  else
    request.websocket do |ws|
      ws.onopen do
        @ws_manager.add_connection(ws, request.cookies['client_id'], 
                                   session[:session_id], request.env['REMOTE_ADDR'])
        # Send current slide...
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

### Test Example
```ruby
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
    allow(EM).to receive(:next_tick) { |&block| block.call }
  end
  
  context 'with update message' do
    it 'updates current slide if presenter' do
      session_state.register_presenter('abc123')
      manager.register_presenter(ws)
      
      message = { 'message' => 'update', 'name' => 'slide2', 'slide' => 1, 'increment' => 0 }
      manager.handle_message(ws, message.to_json, request_context)
      
      expect(current_slide[:number]).to eq(1)
      expect(ws.sent_messages).to include(hash_including('message' => 'current'))
    end
  end
end
```

## Estimated Effort

| Task | Lines of Code | Time Estimate |
|------|---------------|---------------|
| Main class implementation | ~400 | 2 days |
| Test implementation | ~600 | 1.5 days |
| Integration with showoff.rb | ~50 | 0.5 days |
| Documentation updates | - | 0.5 days |
| **Total** | **~1050** | **4.5 days** |

## Success Metrics

1. ✅ All 12 message types handled correctly
2. ✅ Thread-safe with Mutex protection
3. ✅ EventMachine compatible
4. ✅ 100% test coverage
5. ✅ No breaking changes
6. ✅ Clean integration with existing managers
7. ✅ Comprehensive error handling

## Next Steps

1. **Review this design** with the team
2. **Begin implementation** with test-first approach
3. **Start with connection management** (simplest part)
4. **Add message handlers** one at a time with tests
5. **Integrate with showoff.rb** after all tests pass
6. **Verify backward compatibility** with manual testing

## Questions to Resolve

1. ✅ Should feedback handling stay in WebSocketManager or extract immediately?
   - **Decision:** Keep in manager for now, extract to FeedbackManager in Phase 4

2. ✅ Should activity tracking stay in WebSocketManager or extract immediately?
   - **Decision:** Keep in manager for now, extract to ActivityManager in Phase 4

3. ✅ How to handle @@current and @@downloads during migration?
   - **Decision:** Use callbacks to avoid breaking changes

4. ✅ Should we mock EM.next_tick or run in reactor for tests?
   - **Decision:** Mock for speed, optionally add integration tests with real reactor

## References

- **Detailed Design:** `WEBSOCKET_MANAGER_DESIGN.md`
- **Architecture Diagrams:** `WEBSOCKET_ARCHITECTURE_DIAGRAM.md`
- **Existing Patterns:** `lib/showoff/server/session_state.rb`, `stats_manager.rb`
- **Current Implementation:** `lib/showoff.rb` lines 1830-1970

---

**Design Status:** ✅ Complete  
**Ready for Implementation:** Yes  
**Estimated Completion:** 4.5 days
