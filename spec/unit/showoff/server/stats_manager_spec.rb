require 'spec_helper'
require 'showoff/server/stats_manager'
require 'tmpdir'
require 'json'
require 'time'

RSpec.describe Showoff::Server::StatsManager do
  # Use a temp directory for any persistence-related specs
  let(:tmp_dir) { Dir.mktmpdir('stats_mgr_spec') }
  let(:persistence_file) { File.join(tmp_dir, 'stats.json') }
  let(:stats) { described_class.new(persistence_file) }

  after do
    # Clean up the temp directory if it still exists
    FileUtils.remove_entry_secure(tmp_dir) if File.exist?(tmp_dir)
  end

  describe '#initialize' do
    it 'initializes with default persistence file when none provided' do
      # Do not let it try to load from disk
      allow(File).to receive(:exist?).and_return(false)
      mgr = described_class.new

      expect(mgr).to be_a(described_class)
      expect(mgr.get_stats).to include(
        views: {},
        total_views: 0,
        questions_count: 0,
        pace: {}
      )
    end

    it 'initializes with custom persistence file and loads nothing when missing' do
      expect(File.exist?(persistence_file)).to be false
      mgr = described_class.new(persistence_file)

      expect(mgr.get_stats[:total_views]).to eq(0)
      expect(mgr.get_questions).to eq([])
      expect(mgr.get_stats[:pace]).to eq({})
    end

    it 'loads from JSON when file exists' do
      # Prepare a persisted file with one view, one question, and pace
      payload = {
        views: {
          '3' => [
            { session_id: 's1', timestamp: Time.now.iso8601 }
          ]
        },
        questions: [
          { session_id: 's2', question: 'Hello?', timestamp: (Time.now - 10).iso8601 }
        ],
        pace: { too_fast: 2, good: 1, too_slow: 0 },
        exported_at: Time.now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))

      mgr = described_class.new(persistence_file)

      expect(mgr.get_view_count(3)).to eq(1)
      expect(mgr.get_questions.size).to eq(1)
      expect(mgr.get_stats[:pace]).to include(too_fast: 2, good: 1, too_slow: 0)
    end
  end

  describe 'recording events' do
    it 'records view events and increments counts' do
      expect(stats.get_view_count(1)).to eq(0)

      now = Time.now
      stats.record_view(1, 'sess-1', now)
      stats.record_view(1, 'sess-2', now + 1)
      stats.record_view(2, 'sess-3', now + 2)

      expect(stats.get_view_count(1)).to eq(2)
      expect(stats.get_view_count(2)).to eq(1)
      expect(stats.get_stats[:total_views]).to eq(3)

      # Multiple views of the same slide aggregate correctly
      3.times { |i| stats.record_view(1, "sess-#{i+4}", now + 3 + i) }
      expect(stats.get_view_count(1)).to eq(5)
    end

    it 'records question submissions including special characters' do
      ts = Time.now
      txt = "WTF 😅 — why doesn’t slide #2 render <b>bold</b>? & can we fix it?"
      stats.record_question('abc', txt, ts)

      qs = stats.get_questions
      expect(qs.size).to eq(1)
      expect(qs.first[:session_id]).to eq('abc')
      expect(qs.first[:question]).to eq(txt)
      expect(qs.first[:timestamp]).to be_a(Time)
    end

    it 'records valid pace feedback and rejects invalid ones' do
      stats.record_pace('s1', :good)
      stats.record_pace('s2', 'too_fast')
      stats.record_pace('s3', :too_slow)
      stats.record_pace('s4', 'good')

      pace = stats.get_stats[:pace]
      expect(pace[:good]).to eq(2)
      expect(pace[:too_fast]).to eq(1)
      expect(pace[:too_slow]).to eq(1)

      expect { stats.record_pace('sX', :bananas) }.to raise_error(ArgumentError, /Invalid pace rating/)
      expect { stats.record_pace('sX', 'FAST') }.to raise_error(ArgumentError)
    end
  end

  describe '#get_stats aggregation' do
    it 'returns aggregated stats including most/least viewed slides' do
      # views: slide 1 => 3, slide 2 => 1, slide 3 => 2
      t0 = Time.now
      3.times { |i| stats.record_view(1, "s#{i}", t0 + i) }
      1.times { |i| stats.record_view(2, "t#{i}", t0 + 100 + i) }
      2.times { |i| stats.record_view(3, "u#{i}", t0 + 200 + i) }

      stats.record_pace('p1', :good)
      stats.record_pace('p2', :too_fast)
      stats.record_pace('p3', :good)

      agg = stats.get_stats
      expect(agg[:views]).to include(1 => 3, 2 => 1, 3 => 2)
      expect(agg[:total_views]).to eq(6)
      expect(agg[:questions_count]).to eq(0)
      expect(agg[:pace]).to include(good: 2, too_fast: 1)

      most = agg[:most_viewed_slides]
      least = agg[:least_viewed_slides]

      expect(most.first).to eq([1, 3])
      expect(least.first).to eq([2, 1])
      # Contains all slides (limit defaults to 5)
      expect(most.map(&:first)).to contain_exactly(1, 3, 2)
      expect(least.map(&:first)).to contain_exactly(2, 3, 1)
    end

    it 'handles empty stats gracefully' do
      agg = stats.get_stats
      expect(agg[:views]).to eq({})
      expect(agg[:total_views]).to eq(0)
      expect(agg[:questions_count]).to eq(0)
      expect(agg[:pace]).to eq({})
      expect(agg[:most_viewed_slides]).to eq([])
      expect(agg[:least_viewed_slides]).to eq([])
    end
  end

  describe 'legacy counter compatibility methods' do
    before do
      @t0 = Time.now
      # Record views with elapsed time
      stats.record_view(1, 'user1', @t0)
      stats.record_view(2, 'user1', @t0 + 60) # 60 seconds on slide 1
      stats.record_view(1, 'user2', @t0 + 30)
      stats.record_view(3, 'user2', @t0 + 90) # 60 seconds on slide 1

      # Record user agents
      stats.record_user_agent('user1', 'Mozilla/5.0 Test Agent 1')
      stats.record_user_agent('user2', 'Mozilla/5.0 Test Agent 2')
    end

    describe '#pageviews' do
      it 'returns data in the legacy @@counter["pageviews"] format' do
        result = stats.pageviews

        expect(result).to be_a(Hash)
        expect(result.keys).to include('1', '2', '3')

        # Check slide 1 data
        expect(result['1']).to have_key('user1')
        expect(result['1']).to have_key('user2')
        expect(result['1']['user1']).to be_an(Array)
        expect(result['1']['user1'].first).to have_key('elapsed')

        # Check elapsed time values
        expect(result['2']['user1'].first['elapsed']).to be_within(0.1).of(60)
        expect(result['3']['user2'].first['elapsed']).to be_within(0.1).of(60)
      end
    end

    describe '#current_viewers' do
      it 'returns data in the legacy @@counter["current"] format' do
        result = stats.current_viewers

        expect(result).to be_a(Hash)
        expect(result).to have_key('user1')
        expect(result).to have_key('user2')

        # Check format: [slide_number, timestamp]
        expect(result['user1']).to be_an(Array)
        expect(result['user1'][0]).to eq(2) # Last slide viewed
        expect(result['user1'][1]).to be_a(Integer) # Timestamp

        expect(result['user2'][0]).to eq(3) # Last slide viewed
      end
    end

    describe '#user_agents' do
      it 'returns data in the legacy @@counter["user_agents"] format' do
        result = stats.user_agents

        expect(result).to be_a(Hash)
        expect(result['user1']).to eq('Mozilla/5.0 Test Agent 1')
        expect(result['user2']).to eq('Mozilla/5.0 Test Agent 2')
      end
    end

    describe '#elapsed_time_per_slide' do
      it 'calculates total elapsed time per slide' do
        result = stats.elapsed_time_per_slide

        expect(result).to be_a(Hash)
        expect(result.keys).to include('1', '2', '3')

        # Both users spent 60 seconds each on slide 1
        expect(result['1']).to be_within(0.1).of(120)
        expect(result['2']).to be_within(0.1).of(60)
        expect(result['3']).to be_within(0.1).of(60)
      end
    end

    describe '#legacy_counter' do
      it 'returns the full legacy @@counter structure' do
        result = stats.legacy_counter

        expect(result).to be_a(Hash)
        expect(result.keys).to contain_exactly('pageviews', 'current', 'user_agents')

        # Check that each component has the expected structure
        expect(result['pageviews']).to eq(stats.pageviews)
        expect(result['current']).to eq(stats.current_viewers)
        expect(result['user_agents']).to eq(stats.user_agents)
      end
    end

    describe '#record_user_agent' do
      it 'stores user agent strings' do
        stats.record_user_agent('new_user', 'New Test Agent')

        expect(stats.user_agents['new_user']).to eq('New Test Agent')
      end

      it 'updates existing user agent strings' do
        stats.record_user_agent('user1', 'Updated Agent')

        expect(stats.user_agents['user1']).to eq('Updated Agent')
      end
    end
  end

  describe 'persistence' do
    it 'exports JSON atomically (tmp file then rename) with expected structure' do
      # Create some data to persist
      now = Time.now
      stats.record_view(10, 's1', now)
      stats.record_question('s2', 'How are you?', now - 60)
      stats.record_pace('s3', :good)
      stats.record_user_agent('s1', 'Test Agent')

      # Spy on write/rename to verify atomic behavior
      expect(File).to receive(:write).with(a_string_matching(/\.json\.tmp$/), kind_of(String)).and_call_original
      expect(File).to receive(:rename).with(a_string_matching(/\.json\.tmp$/), persistence_file).and_call_original

      stats.export_json

      expect(File).to exist(persistence_file)
      tmp_candidates = Dir.glob(File.join(tmp_dir, '*.tmp'))
      expect(tmp_candidates).to be_empty

      raw = File.read(persistence_file)
      json = JSON.parse(raw)

      # Structure assertions
      expect(json.keys).to include('views', 'questions', 'pace', 'exported_at', 'session_data')
      expect(json['views']).to be_a(Hash)
      expect(json['questions']).to be_a(Array)
      expect(json['pace']).to be_a(Hash)
      expect(json['session_data']).to be_a(Hash)

      # Legacy expectations: slide keys as strings, timestamps as ISO8601 strings
      expect(json['views'].keys).to include('10')
      expect(json['views']['10']).to all(include('session_id', 'timestamp', 'elapsed'))
      expect(json['views']['10'].first['timestamp']).to be_a(String)
      expect { Time.parse(json['views']['10'].first['timestamp']) }.not_to raise_error

      # Check session data
      expect(json['session_data']).to have_key('s1')
      expect(json['session_data']['s1']).to include('user_agent' => 'Test Agent')
      expect(json['session_data']['s1']).to have_key('last_slide')
      expect(json['session_data']['s1']).to have_key('last_timestamp')

      q = json['questions'].first
      expect(q['session_id']).to eq('s2')
      expect(q['question']).to eq('How are you?')
      expect(q['timestamp']).to be_a(String)
      expect { Time.parse(q['timestamp']) }.not_to raise_error
    end

    it 'loads from JSON file and converts timestamps back to Time' do
      now = Time.now
      payload = {
        views: {
          '2' => [
            { session_id: 'aa', timestamp: (now - 3600).iso8601, elapsed: 30 },
            { session_id: 'bb', timestamp: (now - 1800).iso8601, elapsed: 45 }
          ]
        },
        questions: [
          { session_id: 'cc', question: 'Q1', timestamp: (now - 120).iso8601 }
        ],
        pace: { good: 3, too_fast: 1 },
        session_data: {
          'aa' => {
            last_slide: 2,
            last_timestamp: now.iso8601,
            user_agent: 'Test Agent AA'
          },
          'bb' => {
            last_slide: 2,
            last_timestamp: now.iso8601,
            user_agent: 'Test Agent BB'
          }
        },
        exported_at: now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))

      mgr = described_class.new(persistence_file)

      expect(mgr.get_view_count(2)).to eq(2)

      # Verify timestamps are Time instances after load
      views = mgr.instance_eval { @views[2] } # internal access for validation only
      expect(views.first[:timestamp]).to be_a(Time)
      expect(views.first[:elapsed]).to eq(30)

      # Verify session data loaded correctly
      session_data = mgr.instance_eval { @session_data }
      expect(session_data['aa'][:user_agent]).to eq('Test Agent AA')
      expect(session_data['aa'][:last_slide]).to eq(2)
      expect(session_data['aa'][:last_timestamp]).to be_a(Time)

      # Verify legacy counter methods work with loaded data
      expect(mgr.user_agents['aa']).to eq('Test Agent AA')
      expect(mgr.current_viewers['aa'][0]).to eq(2)
      expect(mgr.elapsed_time_per_slide['2']).to eq(75) # 30 + 45

      qs = mgr.get_questions
      expect(qs.first[:timestamp]).to be_a(Time)
      expect(qs.first[:question]).to eq('Q1')
    end

    it 'handles missing files gracefully' do
      allow(File).to receive(:exist?).and_return(false)
      mgr = described_class.new(persistence_file)
      expect { mgr.load_from_disk }.not_to raise_error
      expect(mgr.get_stats[:total_views]).to eq(0)
    end

    it 'handles corrupt JSON files without raising and warns' do
      File.write(persistence_file, '{not json')
      mgr = described_class.new(persistence_file)

      # Force reload to trigger parse error again
      expect(Kernel).to receive(:warn).at_least(:once)
      expect { mgr.load_from_disk }.not_to raise_error

      # Remains empty after failed load
      expect(mgr.get_stats[:total_views]).to eq(0)
      expect(mgr.get_questions).to eq([])
    end

    it 'handles time parsing edge cases by rescuing and warning' do
      payload = {
        views: { '1' => [ { session_id: 'x', timestamp: 'not-a-time' } ] },
        questions: [ { session_id: 'y', question: 'Z', timestamp: '---' } ],
        pace: { good: 1 }
      }
      File.write(persistence_file, JSON.generate(payload))
      mgr = described_class.new(persistence_file)

      # Trigger another load to hit rescue path
      expect(Kernel).to receive(:warn).at_least(:once)
      expect { mgr.load_from_disk }.not_to raise_error

      # Since load failed, state should be empty
      expect(mgr.get_stats[:views]).to eq({})
      expect(mgr.get_questions).to eq([])
    end

    it 'handles loading files without session_data' do
      # Create a file with the old format (no session_data)
      payload = {
        views: {
          '1' => [
            { session_id: 'aa', timestamp: Time.now.iso8601 }
          ]
        },
        questions: [],
        pace: {},
        exported_at: Time.now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))

      # Should load without errors
      mgr = described_class.new(persistence_file)
      expect(mgr.get_view_count(1)).to eq(1)

      # Session data should be empty but initialized
      session_data = mgr.instance_eval { @session_data }
      expect(session_data).to be_a(Hash)
      expect(session_data).to be_empty
    end
  end

  describe 'thread safety' do
    it 'handles concurrent view recording without data loss' do
      threads = []
      per_thread = 50
      slides = [1, 2, 3]

      10.times do |i|
        threads << Thread.new do
          per_thread.times do |j|
            slide = slides[(i + j) % slides.size]
            stats.record_view(slide, "s-#{i}-#{j}")
          end
        end
      end

      threads.each(&:join)

      total = stats.get_stats[:total_views]
      expect(total).to eq(10 * per_thread)
      # Ensure each slide saw some views
      slides.each do |s|
        expect(stats.get_view_count(s)).to be > 0
      end
    end

    it 'handles concurrent question submissions' do
      threads = []
      per_thread = 25

      10.times do |i|
        threads << Thread.new do
          per_thread.times do |j|
            stats.record_question("sess-#{i}", "q-#{j} ?!")
          end
        end
      end

      threads.each(&:join)

      expect(stats.get_questions.size).to eq(10 * per_thread)
    end

    it 'handles concurrent pace feedback' do
      threads = []
      per_thread = 20
      ratings = [:good, :too_fast, :too_slow]

      12.times do |i|
        threads << Thread.new do
          per_thread.times do |j|
            stats.record_pace("p-#{i}", ratings[(i + j) % ratings.size])
          end
        end
      end

      threads.each(&:join)

      pace = stats.get_stats[:pace]
      expect(pace.values.sum).to eq(12 * per_thread)
      expect(pace.keys).to include(:good, :too_fast, :too_slow)
    end

    it 'handles concurrent user agent recording' do
      threads = []
      per_thread = 15

      8.times do |i|
        threads << Thread.new do
          per_thread.times do |j|
            stats.record_user_agent("sess-#{i}", "agent-#{j}")
          end
        end
      end

      threads.each(&:join)

      agents = stats.user_agents
      expect(agents.size).to eq(8) # One entry per session
      expect(agents["sess-0"]).to eq("agent-#{per_thread-1}") # Last one wins
    end
  end

  describe '#clear' do
    it 'clears all statistics including session data' do
      # Add some data
      stats.record_view(1, 'user1', Time.now)
      stats.record_question('user1', 'Test question')
      stats.record_pace('user1', :good)
      stats.record_user_agent('user1', 'Test Agent')

      # Verify data exists
      expect(stats.get_view_count(1)).to eq(1)
      expect(stats.get_questions.size).to eq(1)
      expect(stats.get_stats[:pace][:good]).to eq(1)
      expect(stats.user_agents['user1']).to eq('Test Agent')

      # Clear all data
      stats.clear

      # Verify all data is cleared
      expect(stats.get_view_count(1)).to eq(0)
      expect(stats.get_questions).to be_empty
      expect(stats.get_stats[:pace]).to be_empty
      expect(stats.user_agents).to be_empty
      expect(stats.current_viewers).to be_empty
      expect(stats.elapsed_time_per_slide).to be_empty
    end
  end
end
