# FeedbackManager Class Architecture Design

**Status:** Design Complete - Ready for Implementation
**Date:** 2025-12-23
**Manager #:** 9 of planned state managers

## Executive Summary

The `FeedbackManager` extracts slide feedback collection from the legacy WebSocket handler in `showoff.rb` (lines 1931-1951). It provides thread-safe storage, validation, aggregation, and persistence for user feedback on presentation slides.

## Current State Analysis

### Legacy Implementation (showoff.rb:1931-1951)

```ruby
when 'feedback'
  filename = "#{settings.statsdir}/#{settings.feedback}"
  slide    = control['slide']
  rating   = control['rating']
  feedback = control['feedback']

  begin
    log = JSON.parse(File.read(filename))
  rescue
    # do nothing
  end

  log        ||= Hash.new
  log[slide] ||= Array.new
  log[slide]  << { :rating => rating, :feedback => feedback }

  if settings.verbose then
    File.write(filename, JSON.pretty_generate(log))
  else
    File.write(filename, log.to_json)
  end
```

### Problems Identified

1. **No Session Tracking** - Can't identify who submitted feedback
2. **No Timestamps** - Can't track when feedback was submitted
3. **No Thread Safety** - Direct file writes without locking
4. **No Atomic Writes** - File corruption possible on concurrent access
5. **No Validation** - Rating values not validated (should be 1-5)
6. **Mixed Concerns** - WebSocket handler does persistence logic
7. **Silent Failures** - Empty rescue block swallows errors

### Data Collected

From UI (`views/index.erb`):
- **Rating:** Radio buttons 1-5 (numeric)
- **Feedback Text:** Optional textarea (string)
- **Slide ID:** Automatically included (e.g., "one/slidesA.md#1")

WebSocket message format:
```javascript
{
  message: 'feedback',
  rating: 5,
  feedback: 'Great slide!',
  slide: 'one/slidesA.md#1'
}
```

## Architecture Design

### Class Structure

```ruby
# lib/showoff/server/feedback_manager.rb
require 'thread'
require 'json'
require 'fileutils'
require 'time'

class Showoff
  class Server
    # Thread-safe feedback manager for Showoff server.
    #
    # Replaces legacy feedback handling in showoff.rb (lines 1931-1951).
    #
    # Stores slide feedback with ratings (1-5) and optional text comments.
    # Tracks session IDs and timestamps for analytics.
    #
    # @example
    #   feedback = Showoff::Server::FeedbackManager.new
    #   feedback.submit_feedback('slide1', 'session123', 5, 'Great!')
    #   feedback.get_slide_rating_average('slide1') # => 5.0
    class FeedbackManager
      # Initialize a new feedback manager
      #
      # @param persistence_file [String] Path to JSON file for persistence
      def initialize(persistence_file = 'stats/feedback.json')
        @mutex = Mutex.new
        @persistence_file = persistence_file
        @feedback = Hash.new { |h, k| h[k] = [] }  # slide_id => [entries]

        load_from_disk if File.exist?(@persistence_file)
      end

      # Submit feedback for a slide.
      #
      # @param slide_id [String] The slide identifier
      # @param session_id [String] The session ID
      # @param rating [Integer] Rating from 1-5
      # @param feedback_text [String, nil] Optional text feedback
      # @param timestamp [Time] The submission timestamp (defaults to now)
      # @return [Hash] The stored feedback entry
      # @raise [ArgumentError] If slide_id, session_id nil or rating invalid
      # @thread_safe
      def submit_feedback(slide_id, session_id, rating, feedback_text = nil, timestamp = Time.now)
        # Implementation
      end

      # Get all feedback for a specific slide.
      #
      # @param slide_id [String] The slide identifier
      # @return [Array<Hash>] All feedback entries for this slide
      # @thread_safe
      def get_feedback(slide_id)
        # Implementation
      end

      # Get all feedback across all slides.
      #
      # @return [Hash] Hash of slide_id => [feedback_entries]
      # @thread_safe
      def get_all_feedback
        # Implementation
      end

      # Get aggregated statistics for a slide.
      #
      # @param slide_id [String] The slide identifier
      # @return [Hash] Aggregated stats (average, distribution, count)
      # @thread_safe
      def get_aggregated(slide_id)
        # Implementation
      end

      # Get average rating for a slide.
      #
      # @param slide_id [String] The slide identifier
      # @return [Float, nil] Average rating or nil if no feedback
      # @thread_safe
      def get_slide_rating_average(slide_id)
        # Implementation
      end

      # Get feedback count.
      #
      # @param slide_id [String, nil] Specific slide or nil for total
      # @return [Integer] Number of feedback entries
      # @thread_safe
      def feedback_count(slide_id = nil)
        # Implementation
      end

      # Get all slide IDs with feedback.
      #
      # @return [Array<String>] All slide IDs
      # @thread_safe
      def slide_ids
        # Implementation
      end

      # Export feedback to JSON file.
      #
      # @return [void]
      # @thread_safe
      def export_json
        # Implementation
      end

      # Load feedback from JSON file.
      #
      # @return [void]
      # @thread_safe
      def load_from_disk
        # Implementation
      end

      # Save to disk (alias for export_json).
      #
      # @return [void]
      def save_to_disk
        export_json
      end

      # Clear feedback.
      #
      # @param slide_id [String, nil] Specific slide or nil for all
      # @return [void]
      # @thread_safe
      def clear(slide_id = nil)
        # Implementation
      end

      # Get feedback in legacy format for migration.
      #
      # @return [Hash] Legacy format (slide_id => [{rating:, feedback:}])
      # @thread_safe
      def legacy_format
        # Implementation
      end

      private

      # Calculate average rating (internal, assumes mutex held).
      #
      # @param slide_id [String] The slide identifier
      # @return [Float, nil] Average rating
      def calculate_average_unsafe(slide_id)
        # Implementation
      end

      # Calculate rating distribution (internal, assumes mutex held).
      #
      # @param slide_id [String] The slide identifier
      # @return [Hash] Rating => count
      def calculate_distribution_unsafe(slide_id)
        # Implementation
      end

      # Migrate legacy format data.
      #
      # @param data [Hash] Legacy format data
      # @return [void]
      def migrate_legacy_format(data)
        # Implementation
      end
    end
  end
end
```

### Data Structures

#### Internal Storage

```ruby
@feedback = {
  "one/slidesA.md#1" => [
    {
      session_id: "abc123",
      rating: 5,
      feedback: "Great slide!",
      timestamp: Time.parse("2025-12-23T15:30:00Z")
    },
    {
      session_id: "def456",
      rating: 4,
      feedback: nil,
      timestamp: Time.parse("2025-12-23T15:31:00Z")
    }
  ],
  "two/slidesA.md#3" => [...]
}
```

#### JSON Persistence Format

```json
{
  "feedback": {
    "one/slidesA.md#1": [
      {
        "session_id": "abc123",
        "rating": 5,
        "feedback": "Great slide!",
        "timestamp": "2025-12-23T15:30:00Z"
      }
    ]
  },
  "exported_at": "2025-12-23T15:35:00Z"
}
```

#### Legacy Format (Backward Compatibility)

```json
{
  "one/slidesA.md#1": [
    {"rating": 5, "feedback": "text"}
  ]
}
```

**Migration Strategy:** If no "feedback" key at root level, assume legacy format. Add:
- `session_id: "unknown"`
- `timestamp: File.mtime(@persistence_file)` (file modification time)

### Public API Methods

| Method | Purpose | Thread-Safe | Returns |
|--------|---------|-------------|---------|
| `submit_feedback(slide_id, session_id, rating, feedback_text, timestamp)` | Store feedback | ✅ | Hash (entry) |
| `get_feedback(slide_id)` | Get slide feedback | ✅ | Array |
| `get_all_feedback` | Get all feedback | ✅ | Hash |
| `get_aggregated(slide_id)` | Get statistics | ✅ | Hash |
| `get_slide_rating_average(slide_id)` | Get average rating | ✅ | Float/nil |
| `feedback_count(slide_id)` | Get count | ✅ | Integer |
| `slide_ids` | Get all slide IDs | ✅ | Array |
| `export_json` | Save to disk | ✅ | void |
| `load_from_disk` | Load from disk | ✅ | void |
| `save_to_disk` | Alias for export_json | ✅ | void |
| `clear(slide_id)` | Clear feedback | ✅ | void |
| `legacy_format` | Legacy format | ✅ | Hash |

### Validation Rules

```ruby
# In submit_feedback:
raise ArgumentError, "slide_id cannot be nil" if slide_id.nil?
raise ArgumentError, "session_id cannot be nil" if session_id.nil?
raise ArgumentError, "rating must be Integer 1-5" unless (1..5).include?(rating.to_i)

# Convert rating to integer
rating = rating.to_i

# Allow nil or empty feedback_text
feedback_text = feedback_text.to_s.empty? ? nil : feedback_text
```

## Thread Safety Strategy

### Mutex Protection

All public methods use `@mutex.synchronize`:

```ruby
def submit_feedback(slide_id, session_id, rating, feedback_text = nil, timestamp = Time.now)
  @mutex.synchronize do
    # Validation
    raise ArgumentError, "slide_id cannot be nil" if slide_id.nil?
    raise ArgumentError, "session_id cannot be nil" if session_id.nil?
    raise ArgumentError, "rating must be Integer 1-5" unless (1..5).include?(rating.to_i)

    # Store entry
    entry = {
      session_id: session_id,
      rating: rating.to_i,
      feedback: feedback_text,
      timestamp: timestamp
    }

    @feedback[slide_id] << entry
    entry
  end
end
```

### Deep Copy on Reads

Prevent external mutation:

```ruby
def get_feedback(slide_id)
  @mutex.synchronize do
    @feedback[slide_id].map(&:dup)
  end
end

def get_all_feedback
  @mutex.synchronize do
    result = {}
    @feedback.each do |slide_id, entries|
      result[slide_id] = entries.map(&:dup)
    end
    result
  end
end
```

### Private Unsafe Methods

Methods ending in `_unsafe` assume mutex is already held:

```ruby
private

def calculate_average_unsafe(slide_id)
  entries = @feedback[slide_id]
  return nil if entries.empty?

  sum = entries.sum { |e| e[:rating] }
  sum.to_f / entries.size
end

def calculate_distribution_unsafe(slide_id)
  distribution = Hash.new(0)
  @feedback[slide_id].each do |entry|
    distribution[entry[:rating]] += 1
  end
  distribution
end
```

## Persistence Strategy

### Atomic Write Pattern

Following `StatsManager`:

```ruby
def export_json
  @mutex.synchronize do
    FileUtils.mkdir_p(File.dirname(@persistence_file))

    # Serialize Time objects to ISO8601
    serialized_feedback = {}
    @feedback.each do |slide_id, entries|
      serialized_feedback[slide_id] = entries.map do |e|
        {
          'session_id' => e[:session_id],
          'rating' => e[:rating],
          'feedback' => e[:feedback],
          'timestamp' => e[:timestamp].iso8601
        }
      end
    end

    data = {
      'feedback' => serialized_feedback,
      'exported_at' => Time.now.iso8601
    }

    # Atomic write: temp file + rename
    temp_file = "#{@persistence_file}.tmp"
    File.write(temp_file, JSON.pretty_generate(data))
    File.rename(temp_file, @persistence_file)
  end
end
```

### Load with Error Handling

```ruby
def load_from_disk
  @mutex.synchronize do
    return unless File.exist?(@persistence_file)

    begin
      data = JSON.parse(File.read(@persistence_file))

      # Reset
      @feedback = Hash.new { |h, k| h[k] = [] }

      # Check for legacy format
      if data['feedback']
        # New format
        data['feedback'].each do |slide_id, entries|
          @feedback[slide_id] = entries.map do |e|
            {
              session_id: e['session_id'],
              rating: e['rating'].to_i,
              feedback: e['feedback'],
              timestamp: Time.parse(e['timestamp'].to_s)
            }
          end
        end
      else
        # Legacy format - migrate
        migrate_legacy_format(data)
      end

    rescue JSON::ParserError => e
      Kernel.warn "Failed to load feedback from #{@persistence_file}: Invalid JSON - #{e.message}"
      @feedback.clear
    rescue StandardError => e
      Kernel.warn "Failed to load feedback from #{@persistence_file}: #{e.message}"
      @feedback.clear
    end
  end
end

private

def migrate_legacy_format(data)
  file_mtime = File.mtime(@persistence_file)

  data.each do |slide_id, entries|
    @feedback[slide_id] = entries.map do |e|
      {
        session_id: 'unknown',
        rating: e['rating'].to_i,
        feedback: e['feedback'],
        timestamp: file_mtime
      }
    end
  end

  Kernel.warn "Migrated legacy feedback format from #{@persistence_file}"
end
```

## Integration with WebSocketManager

### Dependency Injection

In `showoff.rb`:

```ruby
# Initialize managers
@feedback_manager = Showoff::Server::FeedbackManager.new('stats/feedback.json')

@ws_manager = Showoff::Server::WebSocketManager.new(
  session_state: @session_state,
  stats_manager: @stats_manager,
  feedback_manager: @feedback_manager,  # NEW
  # ... other dependencies
)
```

### WebSocketManager Handler

Add to `WebSocketManager#handle_message`:

```ruby
when 'feedback'
  handle_feedback(ws, control, request_context)
```

New handler method:

```ruby
# Handle feedback submission.
#
# @param ws [WebSocket] The WebSocket connection
# @param control [Hash] The control message
# @param request_context [Hash] The request context
# @return [void]
# @private
def handle_feedback(ws, control, request_context)
  slide_id = control['slide']
  rating = control['rating']
  feedback_text = control['feedback']

  # Get session_id from connection metadata
  connection = @connections[ws]
  session_id = connection[:session_id]

  # Delegate to FeedbackManager
  @feedback_manager.submit_feedback(
    slide_id,
    session_id,
    rating.to_i,
    feedback_text
  )

  # Auto-save after submission
  @feedback_manager.export_json

  # No broadcast - feedback is private data

rescue ArgumentError => e
  @logger.error "Invalid feedback submission: #{e.message}"
end
```

### Key Differences from Other Handlers

1. **No Broadcasting** - Feedback is private, not shared with other clients
2. **Auto-save** - Persists immediately after each submission
3. **Session Tracking** - Uses connection metadata for session_id

## Testing Strategy (100% Coverage)

### Test File Structure

```ruby
# spec/unit/showoff/server/feedback_manager_spec.rb
require 'spec_helper'
require 'showoff/server/feedback_manager'

RSpec.describe Showoff::Server::FeedbackManager do
  let(:temp_file) { 'spec/tmp/feedback_test.json' }
  let(:manager) { described_class.new(temp_file) }

  before do
    FileUtils.mkdir_p(File.dirname(temp_file))
  end

  after do
    FileUtils.rm_f(temp_file)
    FileUtils.rm_f("#{temp_file}.tmp")
  end

  describe '#initialize' do
    # Tests
  end

  describe '#submit_feedback' do
    # Tests
  end

  # ... more describe blocks
end
```

### Test Categories

#### 1. Initialization Tests (5 tests)

```ruby
it 'creates empty feedback hash'
it 'sets persistence file path'
it 'loads from disk if file exists'
it 'handles missing file gracefully'
it 'initializes with default path'
```

#### 2. Submission Tests (10 tests)

```ruby
it 'stores valid feedback with rating 1-5'
it 'rejects rating 0'
it 'rejects rating 6'
it 'rejects nil rating'
it 'rejects string rating'
it 'raises ArgumentError for nil slide_id'
it 'raises ArgumentError for nil session_id'
it 'accepts nil feedback text'
it 'accepts empty feedback text'
it 'defaults timestamp to Time.now'
it 'returns stored entry'
```

#### 3. Retrieval Tests (8 tests)

```ruby
it 'gets feedback for slide with entries'
it 'gets empty array for slide with no entries'
it 'gets all feedback across multiple slides'
it 'returns deep copy (mutation safe)'
it 'handles special characters in slide_id'
it 'handles unicode in feedback text'
it 'gets feedback count for specific slide'
it 'gets total feedback count'
```

#### 4. Aggregation Tests (7 tests)

```ruby
it 'calculates average rating correctly'
it 'returns nil average for empty slide'
it 'calculates rating distribution'
it 'aggregates multiple entries correctly'
it 'handles single entry'
it 'handles all same rating'
it 'handles all different ratings'
```

#### 5. Persistence Tests (10 tests)

```ruby
it 'exports to JSON with atomic write'
it 'loads from JSON correctly'
it 'converts timestamps to/from ISO8601'
it 'migrates legacy format'
it 'handles corrupt JSON gracefully'
it 'handles missing file'
it 'creates directory if needed'
it 'uses temp file for atomic write'
it 'warns on parse error'
it 'clears data on error'
```

#### 6. Thread Safety Tests (5 tests)

```ruby
it 'handles concurrent submissions'
it 'handles concurrent reads during write'
it 'prevents race conditions'
it 'maintains data integrity under load'
it 'synchronizes export_json calls'
```

#### 7. Edge Cases (8 tests)

```ruby
it 'handles very long feedback text'
it 'handles empty string vs nil feedback'
it 'handles slide IDs with slashes'
it 'handles slide IDs with special chars'
it 'handles unicode in slide_id'
it 'handles multiple submissions same session'
it 'handles clear specific slide'
it 'handles clear all slides'
```

#### 8. Legacy Compatibility (3 tests)

```ruby
it 'returns legacy format correctly'
it 'migrates legacy format on load'
it 'warns when migrating legacy format'
```

### Total: 56 tests for 100% coverage

### Example Test Implementation

```ruby
describe '#submit_feedback' do
  it 'stores valid feedback with rating 1-5' do
    entry = manager.submit_feedback('slide1', 'session1', 5, 'Great!')

    expect(entry[:session_id]).to eq('session1')
    expect(entry[:rating]).to eq(5)
    expect(entry[:feedback]).to eq('Great!')
    expect(entry[:timestamp]).to be_a(Time)

    feedback = manager.get_feedback('slide1')
    expect(feedback.size).to eq(1)
    expect(feedback.first[:rating]).to eq(5)
  end

  it 'rejects invalid rating' do
    expect {
      manager.submit_feedback('slide1', 'session1', 0, 'Bad')
    }.to raise_error(ArgumentError, /rating must be Integer 1-5/)

    expect {
      manager.submit_feedback('slide1', 'session1', 6, 'Bad')
    }.to raise_error(ArgumentError, /rating must be Integer 1-5/)
  end

  it 'raises ArgumentError for nil slide_id' do
    expect {
      manager.submit_feedback(nil, 'session1', 5, 'text')
    }.to raise_error(ArgumentError, /slide_id cannot be nil/)
  end

  it 'accepts nil feedback text' do
    entry = manager.submit_feedback('slide1', 'session1', 5, nil)
    expect(entry[:feedback]).to be_nil
  end
end

describe 'thread safety' do
  it 'handles concurrent submissions' do
    threads = 10.times.map do |i|
      Thread.new do
        100.times do |j|
          manager.submit_feedback("slide#{i % 3}", "session#{i}", (j % 5) + 1, "text#{j}")
        end
      end
    end

    threads.each(&:join)

    total = manager.feedback_count
    expect(total).to eq(1000)
  end
end
```

## Implementation Checklist

- [ ] Create `lib/showoff/server/feedback_manager.rb`
- [ ] Implement all public methods
- [ ] Implement private helper methods
- [ ] Add comprehensive RDoc comments
- [ ] Create `spec/unit/showoff/server/feedback_manager_spec.rb`
- [ ] Write all 56 tests
- [ ] Achieve 100% code coverage
- [ ] Add to `WebSocketManager` initialization
- [ ] Implement `handle_feedback` in `WebSocketManager`
- [ ] Update `showoff.rb` to initialize `FeedbackManager`
- [ ] Test integration with WebSocket flow
- [ ] Verify backward compatibility with legacy format
- [ ] Document migration path in CHANGELOG

## Migration Notes

### For Existing Presentations

1. **Legacy Format Support:** Old `feedback.json` files will be automatically migrated on first load
2. **Session IDs:** Legacy entries will have `session_id: "unknown"`
3. **Timestamps:** Legacy entries will use file modification time
4. **No Data Loss:** All existing feedback preserved

### Breaking Changes

None - fully backward compatible.

## Performance Considerations

1. **Memory:** O(n) where n = total feedback entries across all slides
2. **Disk I/O:** Atomic write on each submission (like StatsManager)
3. **Lock Contention:** Minimal - submissions are fast operations
4. **Aggregation:** O(m) where m = entries for specific slide

## Security Considerations

1. **Input Validation:** Rating constrained to 1-5
2. **XSS Prevention:** Feedback text should be sanitized when displayed (not manager's responsibility)
3. **File Permissions:** JSON file should have appropriate permissions (644)
4. **Path Traversal:** Persistence file path should be validated by caller

## Future Enhancements

1. **Slide Comparison:** Compare feedback across slides
2. **Trend Analysis:** Track feedback over time
3. **Sentiment Analysis:** Analyze feedback text sentiment
4. **Export Formats:** CSV, Excel export for analysis
5. **Feedback Moderation:** Flag/hide inappropriate feedback
6. **Anonymous Mode:** Option to not track session IDs

## References

- **Pattern Source:** `lib/showoff/server/stats_manager.rb`
- **Test Pattern:** `spec/unit/showoff/server/stats_manager_spec.rb`
- **Legacy Code:** `lib/showoff.rb:1931-1951`
- **UI Integration:** `views/index.erb` (feedback form)
- **WebSocket Protocol:** `public/js/showoff.js` (sendFeedback function)

---

**Design Status:** ✅ Complete - Ready for Implementation
**Estimated LOC:** ~250 (class) + ~400 (tests) = ~650 total
**Complexity:** Medium (similar to FormManager)
**Risk Level:** Low (well-established patterns)
