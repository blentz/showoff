require 'spec_helper'
require 'showoff/server/session_state'

RSpec.describe Showoff::Server::SessionState do
  let(:sessions) { described_class.new }

  describe '#initialize' do
    it 'initializes with no sessions' do
      expect(sessions.count).to eq(0)
    end

    it 'has no presenter token' do
      expect(sessions.presenter_token).to be_nil
    end

    it 'has no master presenter' do
      expect(sessions.master_presenter).to be_nil
    end
  end

  describe '#set_presenter_token and #is_presenter?' do
    it 'sets and checks presenter token' do
      sessions.set_presenter_token('token123')
      expect(sessions.is_presenter?('token123')).to be true
      expect(sessions.is_presenter?('wrong')).to be false
    end

    it 'returns the presenter token' do
      sessions.set_presenter_token('token123')
      expect(sessions.presenter_token).to eq('token123')
    end
  end

  describe '#set_master_presenter and #is_master_presenter?' do
    it 'sets and checks master presenter' do
      sessions.set_master_presenter('client-abc')
      expect(sessions.is_master_presenter?('client-abc')).to be true
      expect(sessions.is_master_presenter?('client-xyz')).to be false
    end

    it 'returns the master presenter ID' do
      sessions.set_master_presenter('client-abc')
      expect(sessions.master_presenter).to eq('client-abc')
    end
  end

  describe '#set_current_slide and #get_current_slide' do
    it 'sets and retrieves current slide' do
      sessions.set_current_slide('session1', 5)
      expect(sessions.get_current_slide('session1')).to eq(5)
    end

    it 'returns nil for non-existent session' do
      expect(sessions.get_current_slide('nonexistent')).to be_nil
    end

    it 'converts slide number to integer' do
      sessions.set_current_slide('session1', '10')
      expect(sessions.get_current_slide('session1')).to eq(10)
    end

    it 'handles multiple sessions independently' do
      sessions.set_current_slide('session1', 5)
      sessions.set_current_slide('session2', 10)
      expect(sessions.get_current_slide('session1')).to eq(5)
      expect(sessions.get_current_slide('session2')).to eq(10)
    end
  end

  describe '#set_follow_mode and #following?' do
    it 'sets and checks follow mode' do
      sessions.set_follow_mode('session1', true)
      expect(sessions.following?('session1')).to be true
    end

    it 'defaults to false for new sessions' do
      expect(sessions.following?('session1')).to be false
    end

    it 'can disable follow mode' do
      sessions.set_follow_mode('session1', true)
      sessions.set_follow_mode('session1', false)
      expect(sessions.following?('session1')).to be false
    end

    it 'coerces value to boolean' do
      sessions.set_follow_mode('session1', 'yes')
      expect(sessions.following?('session1')).to be true
    end
  end

  describe '#get_session' do
    it 'returns session data' do
      sessions.set_current_slide('session1', 5)
      sessions.set_follow_mode('session1', true)

      data = sessions.get_session('session1')
      expect(data[:current_slide]).to eq(5)
      expect(data[:follow_mode]).to be true
    end

    it 'returns nil for non-existent session' do
      expect(sessions.get_session('nonexistent')).to be_nil
    end

    it 'returns a copy of session data' do
      sessions.set_current_slide('session1', 5)
      data = sessions.get_session('session1')
      data[:current_slide] = 10

      expect(sessions.get_current_slide('session1')).to eq(5)
    end
  end

  describe '#clear_session' do
    it 'clears a specific session' do
      sessions.set_current_slide('session1', 5)
      sessions.set_current_slide('session2', 10)

      sessions.clear_session('session1')

      expect(sessions.get_current_slide('session1')).to be_nil
      expect(sessions.get_current_slide('session2')).to eq(10)
    end
  end

  describe '#clear_all' do
    it 'clears all sessions and state' do
      sessions.set_presenter_token('token123')
      sessions.set_master_presenter('client-abc')
      sessions.set_current_slide('session1', 5)
      sessions.set_current_slide('session2', 10)

      sessions.clear_all

      expect(sessions.count).to eq(0)
      expect(sessions.presenter_token).to be_nil
      expect(sessions.master_presenter).to be_nil
    end
  end

  describe '#count' do
    it 'returns count of active sessions' do
      expect(sessions.count).to eq(0)
      sessions.set_current_slide('session1', 5)
      expect(sessions.count).to eq(1)
      sessions.set_current_slide('session2', 10)
      expect(sessions.count).to eq(2)
    end
  end

  describe '#all_session_ids' do
    it 'returns all session IDs' do
      sessions.set_current_slide('session1', 5)
      sessions.set_current_slide('session2', 10)

      ids = sessions.all_session_ids
      expect(ids).to contain_exactly('session1', 'session2')
    end

    it 'returns empty array when no sessions' do
      expect(sessions.all_session_ids).to eq([])
    end

    it 'returns a copy of session IDs' do
      sessions.set_current_slide('session1', 5)
      ids = sessions.all_session_ids
      ids << 'session2'

      expect(sessions.count).to eq(1)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent access safely' do
      threads = []

      # Spawn 10 threads that each set slides for 10 sessions
      10.times do |i|
        threads << Thread.new do
          10.times do |j|
            session_id = "session_#{i}_#{j}"
            sessions.set_current_slide(session_id, i * 10 + j)
            sessions.set_follow_mode(session_id, j.even?)
          end
        end
      end

      threads.each(&:join)

      # Verify all 100 sessions were created
      expect(sessions.count).to eq(100)

      # Spot check some values
      expect(sessions.get_current_slide('session_5_7')).to eq(57)
      expect(sessions.following?('session_3_4')).to be true
      expect(sessions.following?('session_3_5')).to be false
    end

    it 'handles concurrent presenter token updates' do
      threads = []

      100.times do |i|
        threads << Thread.new do
          sessions.set_presenter_token("token#{i}")
        end
      end

      threads.each(&:join)

      # Should have one of the tokens set
      expect(sessions.presenter_token).to match(/^token\d+$/)
    end
  end
end
