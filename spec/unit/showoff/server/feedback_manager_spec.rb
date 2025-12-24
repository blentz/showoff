# frozen_string_literal: true

require 'spec_helper'
require 'showoff/server/feedback_manager'
require 'tmpdir'
require 'json'
require 'time'

RSpec.describe Showoff::Server::FeedbackManager do
  # Use a temp directory for any persistence-related specs
  let(:tmp_dir) { Dir.mktmpdir('feedback_mgr_spec') }
  let(:persistence_file) { File.join(tmp_dir, 'feedback.json') }
  let(:manager) { described_class.new(persistence_file) }

  after do
    # Clean up the temp directory if it still exists
    FileUtils.remove_entry_secure(tmp_dir) if File.exist?(tmp_dir)
  end

  describe '#initialize' do
    it 'initializes with default persistence file when none provided' do
      allow(File).to receive(:exist?).and_return(false)
      mgr = described_class.new
      expect(mgr).to be_a(described_class)
      expect(mgr.slide_ids).to eq([])
      expect(mgr.feedback_count).to eq(0)
    end

    it 'initializes with custom persistence file and loads nothing when missing' do
      expect(File.exist?(persistence_file)).to be false
      mgr = described_class.new(persistence_file)
      expect(mgr.slide_ids).to eq([])
      expect(mgr.feedback_count).to eq(0)
    end

    it 'auto-loads data when file exists' do
      payload = {
        'feedback' => {
          'slideA' => [
            { 'session_id' => 's1', 'rating' => 5, 'feedback' => 'great', 'timestamp' => Time.now.iso8601 }
          ]
        },
        'exported_at' => Time.now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))
      mgr = described_class.new(persistence_file)
      expect(mgr.feedback_count('slideA')).to eq(1)
    end

    it 'creates new storage when file does not exist' do
      FileUtils.rm_f(persistence_file)
      mgr = described_class.new(persistence_file)
      expect(mgr.get_feedback('nope')).to eq([])
    end

    it 'handles permission errors on load by warning and clearing state' do
      File.write(persistence_file, '{}')
      # Simulate permission error on read
      allow(File).to receive(:read).and_raise(Errno::EACCES)
      expect(Kernel).to receive(:warn).with(/Failed to load feedback/)
      mgr = described_class.new(persistence_file)
      expect(mgr.feedback_count).to eq(0)
      expect(mgr.slide_ids).to eq([])
    end
  end

  describe '#submit_feedback (submission)' do
    it 'stores a valid submission' do
      ts = Time.now
      entry = manager.submit_feedback('s1', 'session1', 5, 'Great slide', ts)
      expect(entry[:rating]).to eq(5)
      expect(entry[:session_id]).to eq('session1')
      expect(entry[:feedback]).to eq('Great slide')
      expect(entry[:timestamp]).to eq(ts)
    end

    it 'validates rating: 1 is accepted' do
      entry = manager.submit_feedback('s1', 'a', 1, 'ok')
      expect(entry[:rating]).to eq(1)
    end

    it 'validates rating: 5 is accepted' do
      entry = manager.submit_feedback('s1', 'a', 5, 'ok')
      expect(entry[:rating]).to eq(5)
    end

    it 'rejects rating below 1' do
      expect { manager.submit_feedback('s1', 'a', 0, 'no') }.to raise_error(ArgumentError, /rating must be Integer 1-5/)
    end

    it 'rejects rating above 5' do
      expect { manager.submit_feedback('s1', 'a', 6, 'no') }.to raise_error(ArgumentError, /rating must be Integer 1-5/)
    end

    it 'rejects nil slide_id' do
      expect { manager.submit_feedback(nil, 'sess', 3, 'x') }.to raise_error(ArgumentError, /slide_id/)
    end

    it 'rejects nil session_id' do
      expect { manager.submit_feedback('s1', nil, 3, 'x') }.to raise_error(ArgumentError, /session_id/)
    end

    it 'coerces rating type from string when numeric' do
      entry = manager.submit_feedback('s1', 'sess', '3', 'x')
      expect(entry[:rating]).to eq(3)
    end

    it 'rejects non-numeric rating strings' do
      expect { manager.submit_feedback('s1', 'sess', 'abc', 'x') }.to raise_error(ArgumentError, /rating must be Integer 1-5/)
    end

    it 'treats empty feedback text as nil' do
      entry = manager.submit_feedback('s1', 'sess', 4, '')
      expect(entry[:feedback]).to be_nil
    end

    it 'auto-generates timestamp when not provided' do
      entry = manager.submit_feedback('s1', 'sess', 2)
      expect(entry[:timestamp]).to be_a(Time)
    end

    it 'allows multiple submissions for the same slide' do
      3.times { |i| manager.submit_feedback('slideX', "sess-#{i}", 4, "t#{i}") }
      expect(manager.feedback_count('slideX')).to eq(3)
    end

    it 'handles submissions for different slides' do
      manager.submit_feedback('A', 's1', 3)
      manager.submit_feedback('B', 's2', 5)
      expect(manager.slide_ids).to contain_exactly('A', 'B')
    end
  end

  describe 'retrieval' do
    it 'gets feedback for a slide' do
      manager.submit_feedback('r1', 's1', 5, 'x')
      list = manager.get_feedback('r1')
      expect(list.size).to eq(1)
    end

    it 'get_all_feedback returns hash of all slides' do
      manager.submit_feedback('rA', 's1', 4)
      manager.submit_feedback('rB', 's2', 2)
      all = manager.get_all_feedback
      expect(all.keys).to include('rA', 'rB')
    end

    it 'non-existent slide returns empty array' do
      expect(manager.get_feedback('nope')).to eq([])
    end

    it 'returns deep copy to prevent mutation' do
      manager.submit_feedback('deep', 's', 3, 't')
      copy = manager.get_feedback('deep')
      copy.first[:rating] = 1
      orig = manager.get_feedback('deep')
      expect(orig.first[:rating]).to eq(3)
    end

    it 'returns slide IDs list' do
      manager.submit_feedback('id1', 's', 3)
      manager.submit_feedback('id2', 's', 4)
      expect(manager.slide_ids).to contain_exactly('id1', 'id2')
    end

    it 'returns feedback count for slide' do
      2.times { manager.submit_feedback('cnt', 's', 5) }
      expect(manager.feedback_count('cnt')).to eq(2)
    end

    it 'returns total feedback count' do
      manager.submit_feedback('t1', 's', 5)
      manager.submit_feedback('t2', 's', 4)
      expect(manager.feedback_count).to eq(2)
    end

    it 'can filter by rating after retrieval (bonus)' do
      manager.submit_feedback('flt', 's1', 5)
      manager.submit_feedback('flt', 's2', 3)
      only_fives = manager.get_feedback('flt').select { |e| e[:rating] == 5 }
      expect(only_fives.size).to eq(1)
    end

    it 'can filter by session after retrieval (bonus)' do
      manager.submit_feedback('fls', 'A', 4)
      manager.submit_feedback('fls', 'B', 4)
      sess_a = manager.get_feedback('fls').select { |e| e[:session_id] == 'A' }
      expect(sess_a.size).to eq(1)
    end
  end

  describe 'aggregation' do
    it 'calculates average rating' do
      manager.submit_feedback('avg', 's1', 4)
      manager.submit_feedback('avg', 's2', 2)
      expect(manager.get_slide_rating_average('avg')).to eq(3.0)
    end

    it 'returns nil average for slide with no feedback' do
      expect(manager.get_slide_rating_average('empty')).to be_nil
    end

    it 'calculates rating distribution' do
      manager.submit_feedback('dist', 's1', 5)
      manager.submit_feedback('dist', 's2', 5)
      manager.submit_feedback('dist', 's3', 3)
      agg = manager.get_aggregated('dist')
      expect(agg[:distribution][5]).to eq(2)
    end

    it 'returns aggregated count' do
      4.times { |i| manager.submit_feedback('agg', "s#{i}", (i % 5) + 1) }
      expect(manager.get_aggregated('agg')[:count]).to eq(4)
    end

    it 'returns zeros for no feedback' do
      agg = manager.get_aggregated('none')
      expect(agg).to eq({ count: 0, average: nil, distribution: {} })
    end

    it 'handles single feedback entry' do
      manager.submit_feedback('one', 's', 4)
      expect(manager.get_aggregated('one')[:average]).to eq(4.0)
    end

    it 'does not round average (retains float precision)' do
      manager.submit_feedback('round', 's1', 1)
      manager.submit_feedback('round', 's2', 2)
      expect(manager.get_slide_rating_average('round')).to eq(1.5)
    end
  end

  describe 'persistence' do
    it 'exports JSON atomically with expected structure' do
      now = Time.now
      manager.submit_feedback('pA', 's1', 5, 'yay', now)
      manager.submit_feedback('pB', 's2', 3, nil, now - 60)

      # Spy on write/rename to verify atomic behavior
      expect(File).to receive(:write).with(a_string_matching(/feedback\.json\.tmp$/), kind_of(String)).and_call_original
      expect(File).to receive(:rename).with(a_string_matching(/feedback\.json\.tmp$/), persistence_file).and_call_original

      manager.export_json

      expect(File).to exist(persistence_file)
      expect(Dir.glob(File.join(tmp_dir, '*.tmp'))).to be_empty

      raw = File.read(persistence_file)
      json = JSON.parse(raw)

      expect(json.keys).to include('feedback', 'exported_at')
      expect(json['feedback']).to be_a(Hash)
      expect(json['feedback'].keys).to include('pA', 'pB')
      expect(json['feedback']['pA'].first.keys).to include('session_id', 'rating', 'feedback', 'timestamp')
      expect(json['feedback']['pA'].first['timestamp']).to be_a(String)
      expect { Time.parse(json['feedback']['pA'].first['timestamp']) }.not_to raise_error
    end

    it 'saves via save_to_disk alias' do
      manager.submit_feedback('save', 's', 5)
      manager.save_to_disk
      expect(File).to exist(persistence_file)
    end

    it 'loads from JSON file and converts timestamps back to Time' do
      now = Time.now
      payload = {
        'feedback' => {
          'L1' => [
            { 'session_id' => 'aa', 'rating' => 4, 'feedback' => 'ok', 'timestamp' => (now - 120).iso8601 },
            { 'session_id' => 'bb', 'rating' => 5, 'feedback' => nil, 'timestamp' => (now - 60).iso8601 }
          ]
        },
        'exported_at' => now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))

      mgr = described_class.new(persistence_file)
      list = mgr.get_feedback('L1')
      expect(list.first[:timestamp]).to be_a(Time)
    end

    it 'round-trips data save and load' do
      ts = Time.now
      manager.submit_feedback('rt', 's1', 2, 'meh', ts)
      manager.submit_feedback('rt', 's2', 5, nil, ts + 5)
      manager.export_json

      mgr = described_class.new(persistence_file)
      list = mgr.get_feedback('rt')
      expect(list.size).to eq(2)
    end

    it 'handles corrupt JSON gracefully with warning and clears state' do
      File.write(persistence_file, '{not json')
      expect(Kernel).to receive(:warn).with(/Failed to load feedback.*Invalid JSON/)
      mgr = described_class.new(persistence_file)
      expect(mgr.feedback_count).to eq(0)
    end

    it 'handles missing file on load without raising' do
      allow(File).to receive(:exist?).and_return(false)
      expect { manager.load_from_disk }.not_to raise_error
      expect(manager.feedback_count).to eq(0)
    end

    it 'creates parent directory on export if needed' do
      custom_dir = File.join(tmp_dir, 'nested', 'dir')
      custom_file = File.join(custom_dir, 'fb.json')
      mgr = described_class.new(custom_file)
      mgr.submit_feedback('c', 's', 3)
      expect { mgr.export_json }.to change { File.exist?(custom_dir) }.from(false).to(true)
    end

    it 'uses temp file for atomic write (no leftover temp files)' do
      manager.submit_feedback('tmp', 's', 3)
      manager.export_json
      leftovers = Dir.glob(File.join(tmp_dir, '*.tmp'))
      expect(leftovers).to be_empty
    end

    it 'serializes timestamps in ISO8601 format' do
      ts = Time.utc(2025, 1, 2, 3, 4, 5)
      manager.submit_feedback('iso', 's', 5, 'x', ts)
      manager.export_json
      json = JSON.parse(File.read(persistence_file))
      expect(json['feedback']['iso'].first['timestamp']).to eq(ts.iso8601)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent submissions without data loss' do
      threads = 10.times.map do |t|
        Thread.new do
          100.times do |i|
            manager.submit_feedback("slide#{t}", "session#{i}", (i % 5) + 1, "feedback#{i}")
          end
        end
      end
      threads.each(&:join)

      expect(manager.feedback_count('slide0')).to eq(100)
    end

    it 'supports concurrent reads without mutation or errors' do
      200.times { |i| manager.submit_feedback('cr', "s#{i}", (i % 5) + 1, "t#{i}") }
      readers = 10.times.map do
        Thread.new do
          50.times do
            list = manager.get_feedback('cr')
            expect(list).to be_a(Array)
          end
        end
      end
      readers.each(&:join)
      expect(manager.feedback_count('cr')).to eq(200)
    end

    it 'maintains integrity during mixed read/write operations' do
      writer = Thread.new do
        100.times { |i| manager.submit_feedback('mix', "s#{i}", (i % 5) + 1) }
      end
      readers = 5.times.map do
        Thread.new do
          50.times { manager.get_aggregated('mix') }
        end
      end
      (readers + [writer]).each(&:join)
      expect(manager.feedback_count('mix')).to eq(100)
    end

    it 'can save while submissions are ongoing' do
      100.times { |i| manager.submit_feedback('savewhile', "s#{i}", (i % 5) + 1) }
      saver = Thread.new { 3.times { manager.export_json } }
      adder = Thread.new { 100.times { |i| manager.submit_feedback('savewhile', "t#{i}", (i % 5) + 1) } }
      ( [saver, adder] ).each(&:join)
      expect(manager.feedback_count('savewhile')).to eq(200)
      expect(File).to exist(persistence_file)
    end

    it 'can load while reads are happening without raising' do
      50.times { |i| manager.submit_feedback('loadwhile', "s#{i}", (i % 5) + 1) }
      manager.export_json
      reloader = Thread.new { 5.times { manager.load_from_disk } }
      readers = 5.times.map { Thread.new { 50.times { manager.get_feedback('loadwhile') } } }
      (readers + [reloader]).each(&:join)
      expect(manager.feedback_count('loadwhile')).to be >= 50
    end
  end

  describe 'edge cases' do
    it 'handles empty manager with no feedback' do
      expect(manager.slide_ids).to eq([])
      expect(manager.get_all_feedback).to eq({})
    end

    it 'clears feedback for a specific slide' do
      manager.submit_feedback('clr1', 's', 5)
      manager.submit_feedback('clr2', 's', 5)
      manager.clear('clr1')
      expect(manager.slide_ids).to eq(['clr2'])
    end

    it 'clears all slides when no slide_id provided' do
      manager.submit_feedback('c1', 's', 5)
      manager.submit_feedback('c2', 's', 4)
      manager.clear
      expect(manager.slide_ids).to eq([])
    end

    it 'handles very long feedback text' do
      long = 'x' * 10_000
      entry = manager.submit_feedback('long', 's', 4, long)
      expect(entry[:feedback].length).to eq(10_000)
    end

    it 'handles special characters in slide ID' do
      sid = 'weird/slide#1?x=1&y=2'
      manager.submit_feedback(sid, 's', 3, 'ok')
      expect(manager.slide_ids).to include(sid)
    end

    it 'supports unicode in feedback text' do
      txt = "😅 — why doesn’t slide render <b>bold</b>? & more"
      entry = manager.submit_feedback('uni', 's', 4, txt)
      expect(entry[:feedback]).to eq(txt)
    end

    it 'handles very large number of submissions for distribution' do
      1000.times { |i| manager.submit_feedback('big', "s#{i}", (i % 5) + 1) }
      agg = manager.get_aggregated('big')
      expect(agg[:distribution].values.sum).to eq(1000)
    end

    it 'preserves timestamps across save/load' do
      ts = Time.utc(2025, 12, 24, 1, 2, 3)
      manager.submit_feedback('ts', 's', 5, 'x', ts)
      manager.export_json
      mgr = described_class.new(persistence_file)
      loaded = mgr.get_feedback('ts').first
      expect(loaded[:timestamp]).to eq(ts)
    end
  end

  describe 'legacy compatibility' do
    it 'detects legacy format and migrates on load' do
      legacy = {
        'slide1' => [ { 'rating' => 5, 'feedback' => 'great' } ],
        'slide2' => [ { 'rating' => 2, 'feedback' => nil } ]
      }
      File.write(persistence_file, JSON.generate(legacy))
      expect(Kernel).to receive(:warn).with(/Migrated legacy feedback format/)
      mgr = described_class.new(persistence_file)
      expect(mgr.slide_ids).to contain_exactly('slide1', 'slide2')
    end

    it 'preserves ratings and feedback text during migration' do
      legacy = { 's' => [ { 'rating' => 4, 'feedback' => 'ok' } ] }
      File.write(persistence_file, JSON.generate(legacy))
      mgr = described_class.new(persistence_file)
      rec = mgr.get_feedback('s').first
      expect(rec[:rating]).to eq(4)
    end

    it 'sets session_id to "unknown" during migration' do
      legacy = { 's2' => [ { 'rating' => 3, 'feedback' => 'meh' } ] }
      File.write(persistence_file, JSON.generate(legacy))
      mgr = described_class.new(persistence_file)
      rec = mgr.get_feedback('s2').first
      expect(rec[:session_id]).to eq('unknown')
    end
  end
end
