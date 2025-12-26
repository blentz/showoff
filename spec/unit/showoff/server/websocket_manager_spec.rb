require 'spec_helper'
require 'json'
require 'tmpdir'
require 'showoff/server/websocket_manager'

RSpec.describe Showoff::Server::WebSocketManager do
  # Mock WebSocket object
  class MockWebSocket
    attr_reader :sent_messages

    def initialize
      @sent_messages = []
      @closed = false
    end

    def send(message)
      raise 'Socket closed' if @closed
      @sent_messages << message
    end

    def close!
      @closed = true
    end

    def closed?
      @closed
    end
  end

  # Mock EventMachine
  module MockEM
    @blocks = []

    def self.next_tick(&block)
      @blocks << block
    end

    def self.run_pending_ticks
      blocks_to_run = @blocks.dup
      @blocks.clear
      blocks_to_run.each(&:call)
    end

    def self.clear_ticks
      @blocks.clear
    end
  end

  let(:logger) { instance_double('Logger', debug: nil, warn: nil, error: nil) }
  let(:session_state) { instance_double('Showoff::Server::SessionState') }
  let(:stats_manager) { instance_double('Showoff::Server::StatsManager') }

  # Simple current slide store to emulate @@current callback
  let(:current_slide_store) { { name: 'intro', number: 0, increment: 0 } }
  let(:current_slide_callback) do
    lambda do |action, value = nil|
      case action
      when :get
        current_slide_store
      when :set
        current_slide_store.merge!(value)
      else
        raise "unknown action #{action}"
      end
    end
  end

  # Simple downloads store: { slide_num => [enabled, name, files] }
  let(:downloads_store) { Hash.new { |h, k| h[k] = [false, 'Slide', []] } }
  let(:downloads_callback) do
    lambda do |slide_num|
      downloads_store[slide_num]
    end
  end

  subject(:manager) do
    described_class.new(
      session_state: session_state,
      stats_manager: stats_manager,
      logger: logger,
      current_slide_callback: current_slide_callback,
      downloads_callback: downloads_callback
    )
  end

  let(:cookies) { { 'client_id' => 'client-1', 'presenter' => 'presenter-cookie' } }
  let(:request_context) { { cookies: cookies, user_agent: 'RSpec UA', remote_addr: '127.0.0.1' } }

  before(:each) do
    # Stub EventMachine
    stub_const('EM', MockEM)
    MockEM.clear_ticks
  end

  describe 'A. Initialization' do
    it 'initializes with default structures' do
      expect(manager.instance_variable_get(:@connections)).to eq({})
      expect(manager.instance_variable_get(:@presenters)).to be_a(Set)
      expect(manager.instance_variable_get(:@presenters)).to be_empty
      expect(manager.instance_variable_get(:@activity)).to be_a(Hash)
    end

    it 'stores injected dependencies' do
      expect(manager.instance_variable_get(:@session_state)).to eq(session_state)
      expect(manager.instance_variable_get(:@stats_manager)).to eq(stats_manager)
      expect(manager.instance_variable_get(:@logger)).to eq(logger)
    end

    it 'accepts and uses callbacks' do
      expect(current_slide_callback.call(:get)).to include(number: 0)
      current_slide_callback.call(:set, { name: 's1', number: 42, increment: 2 })
      expect(current_slide_callback.call(:get)).to include(number: 42, increment: 2, name: 's1')
    end

    it 'starts with empty connection counts' do
      expect(manager.connection_count).to eq(0)
      expect(manager.presenter_count).to eq(0)
    end

    it 'handles nil downloads callback return' do
      # Replace downloads callback to return nil and ensure no error when update occurs
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      ws = MockWebSocket.new
      manager.add_connection(ws, 'client-1', 'session-1', '1.1.1.1')
      # mark presenter via register
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks

      # Swap downloads callback to nil
      manager.instance_variable_set(:@downloads_callback, ->(_num) { nil })

      expect {
        manager.handle_message(ws, { 'message' => 'update', 'name' => 'slide', 'slide' => 5 }.to_json, request_context)
        MockEM.run_pending_ticks
      }.not_to raise_error
    end
  end

  describe 'B. Connection Management' do
    let(:ws) { MockWebSocket.new }

    it 'adds client connection with metadata' do
      manager.add_connection(ws, 'client-1', 'session-1', '2.2.2.2')
      info = manager.get_connection_info(ws)
      expect(info[:client_id]).to eq('client-1')
      expect(info[:session_id]).to eq('session-1')
      expect(info[:remote_addr]).to eq('2.2.2.2')
      expect(info[:is_presenter]).to be false
      expect(manager.connection_count).to eq(1)
    end

    it 'adds presenter connection and tracks presenter set' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      manager.add_connection(ws, 'client-1', 'session-1', '2.2.2.2')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(manager.is_presenter?(ws)).to be true
      expect(manager.presenter_count).to eq(1)
    end

    it 'removes connection and cleans up presenter set' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      manager.add_connection(ws, 'client-1', 'session-1')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      expect(manager.presenter_count).to eq(1)

      manager.remove_connection(ws)
      expect(manager.connection_count).to eq(0)
      expect(manager.presenter_count).to eq(0)
      expect(manager.get_connection_info(ws)).to be_nil
    end

    it 'removing untracked connection is safe' do
      expect { manager.remove_connection(ws) }.not_to raise_error
    end

    it 'tracks connection metadata and exposes all connections' do
      ws2 = MockWebSocket.new
      manager.add_connection(ws, 'client-1', 'session-1', '1.1.1.1')
      manager.add_connection(ws2, 'client-2', 'session-2', '2.2.2.2')

      all = manager.all_connections
      expect(all.map { |h| h[:client_id] }).to contain_exactly('client-1', 'client-2')
      expect(all.map { |h| h[:session_id] }).to contain_exactly('session-1', 'session-2')
      expect(all.map { |h| h[:ws] }).to contain_exactly(ws, ws2)
    end

    it 'is_presenter? returns false by default' do
      manager.add_connection(ws, 'client-1', 'session-1')
      expect(manager.is_presenter?(ws)).to be false
    end

    it 'get_connection_info returns a duplicate (not mutable)' do
      manager.add_connection(ws, 'client-1', 'session-1')
      info = manager.get_connection_info(ws)
      info[:client_id] = 'mutated'
      expect(manager.get_connection_info(ws)[:client_id]).to eq('client-1')
    end

    it 'cleanup on remove does not log error' do
      manager.add_connection(ws, 'client-1', 'session-1')
      expect { manager.remove_connection(ws) }.not_to raise_error
    end

    it 'lists all sessions via all_connections' do
      ws2 = MockWebSocket.new
      manager.add_connection(ws, 'client-1', 's1')
      manager.add_connection(ws2, 'client-2', 's2')
      expect(manager.all_connections.size).to eq(2)
    end
  end

  describe 'C. Message Routing' do
    let(:ws) { MockWebSocket.new }
    before do
      manager.add_connection(ws, 'client-1', 'session-1', '9.9.9.9')
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      # Register as presenter for update routing tests
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
    end

    it "routes 'update' message" do
      manager.handle_message(ws, { 'message' => 'update', 'name' => 'slide-1', 'slide' => 3, 'increment' => 2 }.to_json, request_context)
      MockEM.run_pending_ticks
      # Broadcast to all
      expect(ws.sent_messages.last).to include('current')
    end

    it "routes 'register' message" do
      ws2 = MockWebSocket.new
      manager.add_connection(ws2, 'client-2', 'session-2')
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      manager.handle_message(ws2, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(manager.is_presenter?(ws2)).to be true
    end

    it "routes 'track' message (time-based)" do
      expect(stats_manager).to receive(:record_view).with(5, anything, kind_of(Time), 'RSpec UA')
      manager.handle_message(ws, { 'message' => 'track', 'slide' => 5, 'time' => 1.5 }.to_json, request_context)
    end

    it "routes 'track' message (position-based)" do
      expect(stats_manager).to receive(:record_view).with(6, anything, kind_of(Time), 'RSpec UA')
      manager.handle_message(ws, { 'message' => 'track', 'slide' => 6 }.to_json, request_context)
    end

    it "routes 'position' message" do
      current_slide_store[:number] = 7
      manager.handle_message(ws, { 'message' => 'position' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'current', 'current' => 7)
    end

    it "routes 'activity' message" do
      # Make ws a non-presenter for activity
      manager.remove_connection(ws)
      manager.add_connection(ws, 'client-1', 'session-1')
      current_slide_store[:number] = 10

      expect {
        manager.handle_message(ws, { 'message' => 'activity', 'slide' => 10, 'status' => false }.to_json, request_context)
        MockEM.run_pending_ticks
      }.not_to raise_error
    end

    it "routes 'pace' message" do
      allow(SecureRandom).to receive(:hex).and_return('deadbeefdeadbeef')
      manager.handle_message(ws, { 'message' => 'pace', 'rating' => 'good' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'pace', 'rating' => 'good', 'id' => 'deadbeefdeadbeef')
    end

    it "routes 'question' message" do
      allow(SecureRandom).to receive(:hex).and_return('cafebabecafebabe')
      manager.handle_message(ws, { 'message' => 'question', 'question' => 'Q?' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'question', 'question' => 'Q?', 'id' => 'cafebabecafebabe')
    end

    it "routes 'cancel' message" do
      allow(SecureRandom).to receive(:hex).and_return('abababababababab')
      manager.handle_message(ws, { 'message' => 'cancel', 'id' => 'orig' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'cancel', 'id' => 'abababababababab')
    end

    it "routes 'complete' message" do
      manager.handle_message(ws, { 'message' => 'complete', 'slide' => 1 }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'complete', 'slide' => 1)
    end

    it "routes 'answerkey' message" do
      manager.handle_message(ws, { 'message' => 'answerkey', 'slide' => 2 }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'answerkey', 'slide' => 2)
    end

    it "routes 'annotation' message" do
      # Add an audience client
      ws2 = MockWebSocket.new
      manager.add_connection(ws2, 'client-2', 'session-2')

      manager.handle_message(ws, { 'message' => 'annotation', 'data' => { 'x' => 1 } }.to_json, request_context)
      MockEM.run_pending_ticks

      # Presenter should not receive audience broadcast; ws2 should
      expect(ws.sent_messages).to be_empty
      expect(JSON.parse(ws2.sent_messages.last)).to include('message' => 'annotation')
    end

    it "routes 'annotationConfig' message" do
      ws2 = MockWebSocket.new
      manager.add_connection(ws2, 'client-2', 'session-2')

      manager.handle_message(ws, { 'message' => 'annotationConfig', 'enabled' => true }.to_json, request_context)
      MockEM.run_pending_ticks

      expect(ws.sent_messages).to be_empty
      expect(JSON.parse(ws2.sent_messages.last)).to include('message' => 'annotationConfig', 'enabled' => true)
    end

    it 'logs warning for unknown message type' do
      expect(logger).to receive(:warn).with(/Unknown WebSocket message type/)
      manager.handle_message(ws, { 'message' => 'wat' }.to_json, request_context)
    end
  end

  describe 'D. Message Handlers' do
    let(:presenter_ws) { MockWebSocket.new }
    let(:audience_ws)  { MockWebSocket.new }

    before do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      manager.add_connection(presenter_ws, 'presenter-1', 'session-1')
      manager.add_connection(audience_ws, 'audience-1', 'session-1')
      manager.handle_message(presenter_ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
    end

    context 'update handler' do
      it 'requires presenter auth (non-presenter ignored)' do
        data = { 'message' => 'update', 'name' => 's', 'slide' => 4, 'increment' => 1 }.to_json
        manager.handle_message(audience_ws, data, request_context)
        MockEM.run_pending_ticks
        # audience should not trigger broadcast; presenter set does
        expect(audience_ws.sent_messages).to be_empty
      end

      it 'updates @@current via callback' do
        manager.handle_message(presenter_ws, { 'message' => 'update', 'name' => 's2', 'slide' => 8, 'increment' => 3 }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(current_slide_store).to include(name: 's2', number: 8, increment: 3)
      end

      it 'enables download via callback when downloads exist' do
        downloads_store[12] = [false, 'Slide 12', %w[a b]]
        manager.handle_message(presenter_ws, { 'message' => 'update', 'name' => 's12', 'slide' => 12, 'increment' => 0 }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(downloads_store[12][0]).to be true
      end

      it 'broadcasts to all clients' do
        manager.handle_message(presenter_ws, { 'message' => 'update', 'name' => 'br', 'slide' => 9, 'increment' => 0 }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(presenter_ws.sent_messages.last)).to include('message' => 'current', 'current' => 9)
        expect(JSON.parse(audience_ws.sent_messages.last)).to include('message' => 'current', 'current' => 9)
      end

      it 'handles missing increment gracefully' do
        manager.handle_message(presenter_ws, { 'message' => 'update', 'name' => 'noinc', 'slide' => 5 }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(audience_ws.sent_messages.last)).to include('increment')
      end
    end

    context 'register handler' do
      it 'requires presenter auth' do
        allow(session_state).to receive(:valid_presenter_cookie?).and_return(false)
        ws3 = MockWebSocket.new
        manager.add_connection(ws3, 'foo', 'bar')
        manager.handle_message(ws3, { 'message' => 'register' }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(manager.is_presenter?(ws3)).to be false
      end

      it 'adds to presenters set' do
        expect(manager.is_presenter?(presenter_ws)).to be true
      end

      it 'logs registration' do
        expect(logger).to receive(:warn).with(/Registered presenter/)
        ws4 = MockWebSocket.new
        manager.add_connection(ws4, 'x', 'y')
        allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
        manager.handle_message(ws4, { 'message' => 'register' }.to_json, request_context)
      end
    end

    context 'track handler' do
      it 'time-based tracking via StatsManager' do
        expect(stats_manager).to receive(:record_view).with(11, anything, kind_of(Time), 'RSpec UA')
        manager.handle_message(audience_ws, { 'message' => 'track', 'slide' => 11, 'time' => 2.1 }.to_json, request_context)
      end

      it 'position tracking via StatsManager' do
        expect(stats_manager).to receive(:record_view).with(12, anything, kind_of(Time), 'RSpec UA')
        manager.handle_message(presenter_ws, { 'message' => 'track', 'slide' => 12 }.to_json, request_context)
      end

      it 'works for audience' do
        expect(stats_manager).to receive(:record_view).with(13, 'audience-1', kind_of(Time), 'RSpec UA')
        manager.handle_message(audience_ws, { 'message' => 'track', 'slide' => 13 }.to_json, request_context)
      end

      it 'works for presenter (remote "presenter")' do
        expect(stats_manager).to receive(:record_view).with(14, 'presenter-1', kind_of(Time), 'RSpec UA')
        manager.handle_message(presenter_ws, { 'message' => 'track', 'slide' => 14 }.to_json, request_context)
      end

      it 'handles missing time field same as position' do
        expect(stats_manager).to receive(:record_view).with(15, anything, kind_of(Time), 'RSpec UA')
        manager.handle_message(audience_ws, { 'message' => 'track', 'slide' => 15 }.to_json, request_context)
      end
    end

    context 'position handler' do
      it 'sends current slide to requester' do
        current_slide_store[:number] = 21
        manager.handle_message(audience_ws, { 'message' => 'position' }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(audience_ws.sent_messages.last)).to include('message' => 'current', 'current' => 21)
      end

      it 'uses @@current callback and ignores when nil' do
        manager.instance_variable_set(:@current_slide_callback, ->(_){ nil })
        expect {
          manager.handle_message(audience_ws, { 'message' => 'position' }.to_json, request_context)
          MockEM.run_pending_ticks
        }.not_to raise_error
        expect(audience_ws.sent_messages).to be_empty
      end
    end

    context 'activity handler' do
      it 'skips if presenter' do
        expect {
          manager.handle_message(presenter_ws, { 'message' => 'activity', 'slide' => 1, 'status' => false }.to_json, request_context)
          MockEM.run_pending_ticks
        }.not_to change { manager.get_activity_count(1) }
      end

      it 'tracks completion status' do
        manager.handle_message(audience_ws, { 'message' => 'activity', 'slide' => 30, 'status' => true }.to_json, request_context)
        MockEM.run_pending_ticks
        # Completed -> incomplete count should be 0
        expect(manager.get_activity_count(30)).to eq(0)
        manager.handle_message(audience_ws, { 'message' => 'activity', 'slide' => 30, 'status' => false }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(manager.get_activity_count(30)).to eq(1)
      end

      it 'broadcasts incomplete count to presenters when slide matches current' do
        current_slide_store[:number] = 40
        expect(presenter_ws.sent_messages).to be_empty
        manager.handle_message(audience_ws, { 'message' => 'activity', 'slide' => 40, 'status' => false }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(presenter_ws.sent_messages.last)).to include('message' => 'activity', 'count' => 1)
      end

      it 'handles empty activity for other slides (no broadcast)' do
        current_slide_store[:number] = 41
        manager.handle_message(audience_ws, { 'message' => 'activity', 'slide' => 42, 'status' => false }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(presenter_ws.sent_messages).to be_empty
      end

      it 'handles no current slide (no errors)' do
        manager.instance_variable_set(:@current_slide_callback, ->(_){ {} })
        expect {
          manager.handle_message(audience_ws, { 'message' => 'activity', 'slide' => 50, 'status' => false }.to_json, request_context)
          MockEM.run_pending_ticks
        }.not_to raise_error
      end
    end

    context 'pace/question/cancel handlers' do
      before do
        allow(SecureRandom).to receive(:hex).and_return('guid-123')
      end

      it 'adds GUID to pace and broadcasts to presenters only' do
        manager.handle_message(audience_ws, { 'message' => 'pace', 'rating' => 'too_fast' }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(presenter_ws.sent_messages.last)).to include('message' => 'pace', 'rating' => 'too_fast', 'id' => 'guid-123')
        expect(audience_ws.sent_messages).to be_empty
      end

      it 'adds GUID to question and preserves original data' do
        manager.handle_message(audience_ws, { 'message' => 'question', 'question' => 'Q?' }.to_json, request_context)
        MockEM.run_pending_ticks
        msg = JSON.parse(presenter_ws.sent_messages.last)
        expect(msg).to include('message' => 'question', 'question' => 'Q?')
        expect(msg['id']).to eq('guid-123')
      end

      it 'adds GUID to cancel messages' do
        manager.handle_message(audience_ws, { 'message' => 'cancel', 'target' => 'something' }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(presenter_ws.sent_messages.last)).to include('message' => 'cancel', 'target' => 'something', 'id' => 'guid-123')
      end
    end

    context 'complete/answerkey handlers' do
      it 'broadcasts to all clients unchanged (complete)' do
        ws3 = MockWebSocket.new
        manager.add_connection(ws3, 'c3', 's1')
        manager.handle_message(audience_ws, { 'message' => 'complete', 'slide' => 99 }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(presenter_ws.sent_messages.last)).to include('message' => 'complete', 'slide' => 99)
        expect(JSON.parse(ws3.sent_messages.last)).to include('message' => 'complete', 'slide' => 99)
      end

      it 'broadcasts to all clients unchanged (answerkey)' do
        ws3 = MockWebSocket.new
        manager.add_connection(ws3, 'c3', 's1')
        manager.handle_message(audience_ws, { 'message' => 'answerkey', 'slide' => 101 }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(JSON.parse(presenter_ws.sent_messages.last)).to include('message' => 'answerkey', 'slide' => 101)
        expect(JSON.parse(ws3.sent_messages.last)).to include('message' => 'answerkey', 'slide' => 101)
      end
    end

    context 'annotation/annotationConfig handlers' do
      it 'broadcasts to audience only and uses EM.next_tick (annotation)' do
        # Ensure there is an audience member besides sender
        ws3 = MockWebSocket.new
        manager.add_connection(ws3, 'aud-2', 's1')
        # sender is audience_ws; presenter should not receive, audience should
        manager.handle_message(audience_ws, { 'message' => 'annotation', 'x' => 1 }.to_json, request_context)
        expect(presenter_ws.sent_messages).to be_empty
        MockEM.run_pending_ticks
        expect(JSON.parse(ws3.sent_messages.last)).to include('message' => 'annotation')
      end

      it 'broadcasts to audience only (annotationConfig)' do
        ws3 = MockWebSocket.new
        manager.add_connection(ws3, 'aud-2', 's1')
        manager.handle_message(audience_ws, { 'message' => 'annotationConfig', 'enabled' => true }.to_json, request_context)
        MockEM.run_pending_ticks
        expect(ws3.sent_messages).not_to be_empty
        expect(JSON.parse(ws3.sent_messages.last)).to include('message' => 'annotationConfig', 'enabled' => true)
      end
    end
  end

  describe 'E. Broadcasting' do
    let(:p1) { MockWebSocket.new }
    let(:p2) { MockWebSocket.new }
    let(:a1) { MockWebSocket.new }

    before do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      manager.add_connection(p1, 'p1', 's')
      manager.add_connection(p2, 'p2', 's')
      manager.add_connection(a1, 'a1', 's')
      manager.handle_message(p1, { 'message' => 'register' }.to_json, request_context)
      manager.handle_message(p2, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
    end

    it 'broadcast to all clients' do
      manager.broadcast_to_all({ 'message' => 'hello' })
      MockEM.run_pending_ticks
      [p1, p2, a1].each do |ws|
        expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'hello')
      end
    end

    it 'broadcast to presenters only' do
      manager.broadcast_to_presenters({ 'message' => 'presenter-only' })
      MockEM.run_pending_ticks
      [p1, p2].each do |ws|
        expect(JSON.parse(ws.sent_messages.last)).to include('message' => 'presenter-only')
      end
      expect(a1.sent_messages).to be_empty
    end

    it 'broadcast to audience only' do
      manager.broadcast_to_audience({ 'message' => 'audience-only' })
      MockEM.run_pending_ticks
      expect(JSON.parse(a1.sent_messages.last)).to include('message' => 'audience-only')
      [p1, p2].each { |ws| expect(ws.sent_messages).to be_empty }
    end

    it 'handle send failures gracefully' do
      a1.close!
      manager.broadcast_to_all({ 'message' => 'boom' })
      expect(logger).to receive(:error).with(/Failed to send to WebSocket/)
      MockEM.run_pending_ticks
    end

    it 'uses EM.next_tick for broadcasts' do
      manager.broadcast_to_all({ 'message' => 'tick' })
      # No messages until ticks run
      [p1, p2, a1].each { |ws| expect(ws.sent_messages).to be_empty }
      MockEM.run_pending_ticks
      expect(p1.sent_messages).not_to be_empty
    end

    it 'executing pending ticks delivers messages' do
      manager.broadcast_to_all({ 'message' => 'tick2' })
      MockEM.run_pending_ticks
      expect(JSON.parse(a1.sent_messages.last)).to include('message' => 'tick2')
    end

    it 'empty socket list is a no-op' do
      m2 = described_class.new(session_state: session_state, stats_manager: stats_manager, logger: logger, current_slide_callback: current_slide_callback, downloads_callback: downloads_callback)
      expect { m2.broadcast_to_all({ 'message' => 'empty' }); MockEM.run_pending_ticks }.not_to raise_error
    end

    it 'empty presenter list is a no-op' do
      m2 = described_class.new(session_state: session_state, stats_manager: stats_manager, logger: logger, current_slide_callback: current_slide_callback, downloads_callback: downloads_callback)
      a = MockWebSocket.new
      m2.add_connection(a, 'a', 's')
      expect { m2.broadcast_to_presenters({ 'message' => 'noop' }); MockEM.run_pending_ticks }.not_to raise_error
      expect(a.sent_messages).to be_empty
    end

    it 'mixed presenter/audience broadcasting honors sets' do
      manager.broadcast_to_presenters({ 'message' => 'presenters' })
      manager.broadcast_to_audience({ 'message' => 'audience' })
      MockEM.run_pending_ticks
      expect(JSON.parse(p1.sent_messages.last)).to include('message' => 'presenters')
      expect(JSON.parse(a1.sent_messages.last)).to include('message' => 'audience')
    end
  end

  describe 'F. Activity Tracking' do
    let(:ws1) { MockWebSocket.new }
    let(:ws2) { MockWebSocket.new }
    before do
      manager.add_connection(ws1, 'c1', 's')
      manager.add_connection(ws2, 'c2', 's')
    end

    it 'tracks activity completion' do
      manager.handle_message(ws1, { 'message' => 'activity', 'slide' => 1, 'status' => false }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(manager.get_activity_count(1)).to eq(1)
      manager.handle_message(ws1, { 'message' => 'activity', 'slide' => 1, 'status' => true }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(manager.get_activity_count(1)).to eq(0)
    end

    it 'gets activity count for slide' do
      manager.handle_message(ws1, { 'message' => 'activity', 'slide' => 2, 'status' => false }.to_json, request_context)
      manager.handle_message(ws2, { 'message' => 'activity', 'slide' => 2, 'status' => false }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(manager.get_activity_count(2)).to eq(2)
    end

    it 'clears activity for slide' do
      manager.handle_message(ws1, { 'message' => 'activity', 'slide' => 3, 'status' => false }.to_json, request_context)
      MockEM.run_pending_ticks
      manager.clear_activity(3)
      expect(manager.get_activity_count(3)).to eq(0)
    end

    it 'handles empty slide gracefully' do
      expect(manager.get_activity_count(999)).to eq(0)
    end

    it 'multiple clients same slide tracked independently' do
      manager.handle_message(ws1, { 'message' => 'activity', 'slide' => 4, 'status' => false }.to_json, request_context)
      manager.handle_message(ws2, { 'message' => 'activity', 'slide' => 4, 'status' => true }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(manager.get_activity_count(4)).to eq(1)
    end

    it 'clear all activities' do
      manager.handle_message(ws1, { 'message' => 'activity', 'slide' => 5, 'status' => false }.to_json, request_context)
      manager.handle_message(ws2, { 'message' => 'activity', 'slide' => 6, 'status' => false }.to_json, request_context)
      MockEM.run_pending_ticks
      manager.clear_activity
      expect(manager.get_activity_count(5)).to eq(0)
      expect(manager.get_activity_count(6)).to eq(0)
    end
  end

  describe 'G. Thread Safety' do
    it 'concurrent add_connection (10 threads, 50 each)' do
      threads = []
      10.times do |i|
        threads << Thread.new do
          50.times do |j|
            manager.add_connection(MockWebSocket.new, "c-#{i}-#{j}", "s-#{i}")
          end
        end
      end
      threads.each(&:join)
      expect(manager.connection_count).to eq(10 * 50)
    end

    it 'concurrent remove_connection' do
      sockets = 100.times.map { MockWebSocket.new }
      sockets.each_with_index { |ws, i| manager.add_connection(ws, "c#{i}", 's') }
      threads = sockets.map { |ws| Thread.new { manager.remove_connection(ws) } }
      threads.each(&:join)
      expect(manager.connection_count).to eq(0)
    end

  it 'concurrent message routing' do
    ws = MockWebSocket.new
    allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
    manager.add_connection(ws, 'cp', 's')
    manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
    MockEM.run_pending_ticks

    # Provide a thread-safe current_slide_callback to avoid Proc stubbing
    mutex = Mutex.new
    safe_callback = lambda do |action, value = nil|
      mutex.synchronize do
        case action
        when :get
          current_slide_store
        when :set
          current_slide_store.merge!(value || {})
        end
      end
    end
    manager.instance_variable_set(:@current_slide_callback, safe_callback)

    threads = []
    50.times do |i|
      threads << Thread.new do
        manager.handle_message(ws, { 'message' => 'update', 'name' => "n#{i}", 'slide' => i }.to_json, request_context)
      end
    end
    threads.each(&:join)
    MockEM.run_pending_ticks
    # We should have at least one broadcast
    expect(ws.sent_messages).not_to be_empty
  end

    it 'concurrent broadcasts' do
      20.times { |i| manager.add_connection(MockWebSocket.new, "c#{i}", 's') }
      threads = []
      10.times do
        threads << Thread.new do
          manager.broadcast_to_all({ 'message' => 'ping' })
        end
      end
      threads.each(&:join)
      MockEM.run_pending_ticks
      # If we got here without exceptions, good enough
      expect(true).to be true
    end

  it 'mixed operations' do
    allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
    allow(stats_manager).to receive(:record_view).with(any_args)
    threads = []

    5.times do |t|
      threads << Thread.new do
        20.times do |i|
          ws = MockWebSocket.new
          manager.add_connection(ws, "c#{t}-#{i}", "s#{t}")
          manager.handle_message(ws, { 'message' => 'track', 'slide' => i }.to_json, request_context)
          manager.handle_message(ws, { 'message' => 'position' }.to_json, request_context)
          manager.remove_connection(ws)
        end
      end
    end

    threads.each(&:join)
    MockEM.run_pending_ticks
    expect(manager.connection_count).to eq(0)
  end
  end

  describe 'H. Integration with Managers' do
    it 'SessionState.valid_presenter_cookie? is called on register' do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      expect(session_state).to receive(:valid_presenter_cookie?).with('presenter-cookie').and_return(true)
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
    end

    it 'StatsManager.record_view is called on track' do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      expect(stats_manager).to receive(:record_view).with(3, 'cid', kind_of(Time), 'RSpec UA')
      manager.handle_message(ws, { 'message' => 'track', 'slide' => 3 }.to_json, request_context)
    end

    it 'Downloads callback is used by update' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
      downloads_store[77] = [false, 'Slide 77', ['a']]
      manager.handle_message(ws, { 'message' => 'update', 'name' => 's77', 'slide' => 77 }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(downloads_store[77][0]).to be true
    end

    it 'Callbacks for @@current are used by position' do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      current_slide_store[:number] = 123
      manager.handle_message(ws, { 'message' => 'position' }.to_json, request_context)
      MockEM.run_pending_ticks
      expect(JSON.parse(ws.sent_messages.last)).to include('current' => 123)
    end

    it 'nil dependency handling: downloads_callback returns nil safely' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
      manager.instance_variable_set(:@downloads_callback, ->(_){ nil })
      expect {
        manager.handle_message(ws, { 'message' => 'update', 'name' => 's', 'slide' => 5 }.to_json, request_context)
        MockEM.run_pending_ticks
      }.not_to raise_error
    end

    it 'error in dependency method is logged (current_slide_callback raises)' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks

      # make callback raise
      manager.instance_variable_set(:@current_slide_callback, ->(*_args) { raise 'boom' })
      expect(logger).to receive(:error).with(/WebSocket message handling error: boom/)
      manager.handle_message(ws, { 'message' => 'update', 'name' => 's', 'slide' => 1 }.to_json, request_context)
    end

    it 'feedback handling writes to file' do
      tmp = Dir.mktmpdir('feedback')
      begin
        # Create a temporary file for feedback
        feedback_file = File.join(tmp, 'feedback.json')
        File.write(feedback_file, '{}')

        # Stub the File methods to verify they're called
        expect(File).to receive(:exist?).with('stats/feedback.json').and_return(true)
        expect(File).to receive(:read).with('stats/feedback.json').and_return('{}')
        expect(File).to receive(:write).with('stats/feedback.json', anything)

        ws = MockWebSocket.new
        manager.add_connection(ws, 'cid', 'sid')
        payload = { 'message' => 'feedback', 'slide' => 2, 'rating' => 5, 'feedback' => 'Nice!' }
        manager.handle_message(ws, payload.to_json, request_context)
      ensure
        FileUtils.remove_entry_secure(tmp)
      end
    end
  end

  describe 'I. Error Handling' do
    it 'invalid JSON message is logged' do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      expect(logger).to receive(:error).with(/Failed to parse WebSocket message/)
      manager.handle_message(ws, '{not json', request_context)
    end

    it "missing 'message' field logs warning as unknown" do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      expect(logger).to receive(:warn).with(/Unknown WebSocket message type/)
      manager.handle_message(ws, { 'foo' => 'bar' }.to_json, request_context)
    end

    it 'exception in handler is logged' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks
      # Force error by stubbing broadcast_to_all to raise
      allow(manager).to receive(:broadcast_to_all).and_raise('kaboom')
      expect(logger).to receive(:error).with(/WebSocket message handling error: kaboom/)
      manager.handle_message(ws, { 'message' => 'update', 'name' => 's', 'slide' => 1 }.to_json, request_context)
    end

    it 'send failure is logged' do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      ws.close!
      expect(logger).to receive(:error).with(/Failed to send to WebSocket/)
      manager.broadcast_to_all({ 'message' => 'X' })
      MockEM.run_pending_ticks
    end

    it 'nil WebSocket object is handled by send_to_connection' do
      expect(logger).to receive(:error).with(/Failed to send to WebSocket/)
      expect { manager.send(:send_to_connection, nil, { 'message' => 'X' }) }.not_to raise_error
    end

    it 'closed WebSocket is handled' do
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      ws.close!
      expect(logger).to receive(:error).with(/Failed to send to WebSocket/)
      manager.send(:send_to_connection, ws, { 'message' => 'X' })
    end

    it 'logs errors appropriately without crashing' do
      allow(session_state).to receive(:valid_presenter_cookie?).and_return(true)
      ws = MockWebSocket.new
      manager.add_connection(ws, 'cid', 'sid')
      manager.handle_message(ws, { 'message' => 'register' }.to_json, request_context)
      MockEM.run_pending_ticks

      # Make downloads callback raise inside handler
      manager.instance_variable_set(:@downloads_callback, ->(_){ raise 'dl oops' })
      expect(logger).to receive(:error).with(/WebSocket message handling error: dl oops/)
      manager.handle_message(ws, { 'message' => 'update', 'name' => 's', 'slide' => 1 }.to_json, request_context)
    end
  end
end
