require 'spec_helper'
require 'showoff/server/form_manager'
require 'tmpdir'
require 'json'
require 'time'

RSpec.describe Showoff::Server::FormManager do
  let(:tmp_dir) { Dir.mktmpdir('form_mgr_spec') }
  let(:persistence_file) { File.join(tmp_dir, 'responses.json') }
  let(:forms) { described_class.new(persistence_file) }

  after do
    FileUtils.remove_entry_secure(tmp_dir) if File.exist?(tmp_dir)
  end

  describe '#initialize' do
    it 'initializes with default persistence file when none provided' do
      allow(File).to receive(:exist?).and_return(false)
      mgr = described_class.new
      expect(mgr).to be_a(described_class)
      expect(mgr.form_names).to eq([])
      expect(mgr.get_aggregated('anything')).to eq({})
      expect(mgr.response_count('anything')).to eq(0)
    end

    it 'initializes with custom persistence file and loads nothing when missing' do
      expect(File.exist?(persistence_file)).to be false
      mgr = described_class.new(persistence_file)
      expect(mgr.form_names).to eq([])
      expect(mgr.response_count('quiz1')).to eq(0)
    end

    it 'loads from JSON when file exists' do
      payload = {
        forms: {
          quiz1: [
            { session_id: 's1', responses: { 'q1' => 'a' }, timestamp: Time.now.iso8601 },
            { session_id: 's2', responses: { 'q1' => 'b' }, timestamp: (Time.now - 60).iso8601 }
          ],
          survey: [
            { session_id: 'x', responses: { 'like' => 'yes' }, timestamp: (Time.now - 120).iso8601 }
          ]
        },
        exported_at: Time.now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))

      mgr = described_class.new(persistence_file)

      expect(mgr.form_names).to contain_exactly('quiz1', 'survey')
      expect(mgr.response_count('quiz1')).to eq(2)

      resps = mgr.get_responses('quiz1')
      expect(resps.first[:timestamp]).to be_a(Time)
      expect(resps.map { |r| r[:session_id] }).to contain_exactly('s1', 's2')
    end
  end

  describe 'basic functionality' do
    it 'submits and retrieves responses with custom timestamps' do
      ts = Time.now
      stored = forms.submit('quiz1', 'sess-1', { 'q1' => 'a', 'q2' => 'b' }, ts)
      expect(stored[:session_id]).to eq('sess-1')
      expect(stored[:responses]).to eq({ 'q1' => 'a', 'q2' => 'b' })
      expect(stored[:timestamp]).to eq(ts)

      resps = forms.get_responses('quiz1')
      expect(resps.size).to eq(1)
      expect(resps.first[:responses]['q2']).to eq('b')
      expect(forms.response_count('quiz1')).to eq(1)
      expect(forms.form_names).to eq(['quiz1'])
    end

    it 'aggregates results across multiple responses and sessions' do
      forms.submit('quizA', 's1', { 'q1' => 'A', 'q2' => 'X' })
      forms.submit('quizA', 's1', { 'q1' => 'B', 'q2' => 'X' })
      forms.submit('quizA', 's2', { 'q1' => 'A', 'q2' => 'Y' })

      agg = forms.get_aggregated('quizA')
      expect(agg[:total_responses]).to eq(3)
      expect(agg[:questions]['q1']).to include('A' => 2, 'B' => 1)
      expect(agg[:questions]['q2']).to include('X' => 2, 'Y' => 1)
      expect(agg[:response_rate]).to be_nil
    end
  end

  describe '#responses' do
    it 'returns nil for non-existent forms' do
      expect(forms.responses('nonexistent')).to be_nil
    end

    it 'returns nil for empty forms' do
      forms.submit('empty_form', 's1', {})
      forms.clear('empty_form')
      expect(forms.responses('empty_form')).to be_nil
    end

    it 'organizes responses by client_id' do
      forms.submit('survey', 'client1', { 'q1' => 'a', 'q2' => 'b' })
      forms.submit('survey', 'client2', { 'q1' => 'c', 'q2' => 'd' })

      result = forms.responses('survey')
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly('client1', 'client2')
      expect(result['client1']).to eq({ 'q1' => 'a', 'q2' => 'b' })
      expect(result['client2']).to eq({ 'q1' => 'c', 'q2' => 'd' })
    end

    it 'keeps only the latest response per client' do
      # First submission
      forms.submit('quiz', 'client1', { 'q1' => 'first' })

      # Second submission from same client - should override
      forms.submit('quiz', 'client1', { 'q1' => 'second' })

      result = forms.responses('quiz')
      expect(result['client1']).to eq({ 'q1' => 'second' })
    end
  end

  describe 'validation' do
    it 'rejects nil form_name' do
      expect { forms.submit(nil, 'sess', {}) }.to raise_error(ArgumentError, /form_name/)
    end

    it 'rejects nil session_id' do
      expect { forms.submit('quiz', nil, {}) }.to raise_error(ArgumentError, /session_id/)
    end

    it 'rejects non-Hash responses' do
      expect { forms.submit('quiz', 's1', nil) }.to raise_error(ArgumentError, /responses/)
      expect { forms.submit('quiz', 's1', 'nope') }.to raise_error(ArgumentError)
      expect { forms.submit('quiz', 's1', 123) }.to raise_error(ArgumentError)
    end
  end

  describe 'persistence' do
    it 'exports JSON atomically with expected structure' do
      forms.submit('quiz1', 's1', { 'q1' => 'A' }, Time.now)
      forms.submit('quiz2', 's2', { 'q2' => 'B' }, Time.now - 60)

      forms.export_json

      expect(File).to exist(persistence_file)
      expect(Dir.glob(File.join(tmp_dir, '*.tmp'))).to be_empty

      raw = File.read(persistence_file)
      json = JSON.parse(raw)

      expect(json.keys).to include('forms', 'exported_at')
      expect(json['forms'].keys).to contain_exactly('quiz1', 'quiz2')
      expect(json['forms']['quiz1']).to be_a(Array)
      expect(json['forms']['quiz1'].first['timestamp']).to be_a(String)
      expect { Time.parse(json['forms']['quiz1'].first['timestamp']) }.not_to raise_error
    end

    it 'exports a specific form when name provided' do
      forms.submit('quiz1', 's1', { 'q1' => 'A' })
      forms.submit('quiz2', 's2', { 'q2' => 'B' })

      forms.export_json('quiz1')

      expect(File).to exist(persistence_file)

      json = JSON.parse(File.read(persistence_file))
      expect(json['forms'].keys).to contain_exactly('quiz1')
      expect(json['forms']).not_to have_key('quiz2')
    end

    it 'saves via save_to_disk alias' do
      forms.submit('q', 's', { 'a' => 'b' })
      forms.save_to_disk
      expect(File).to exist(persistence_file)
    end

    it 'handles missing files gracefully in load' do
      allow(File).to receive(:exist?).and_return(false)
      expect { forms.load_from_disk }.not_to raise_error
      expect(forms.form_names).to eq([])
    end

    it 'handles corrupt JSON files without raising and warns' do
      File.write(persistence_file, '{not json')
      expect(Kernel).to receive(:warn).with(/Failed to load forms/)

      mgr = described_class.new(persistence_file)
      expect(mgr.form_names).to eq([])
      expect(mgr.get_aggregated('quiz1')).to eq({})
    end

    it 'handles missing keys in JSON data' do
      # Missing 'forms' key - should just result in empty forms, no warning
      payload = { exported_at: Time.now.iso8601 }
      File.write(persistence_file, JSON.generate(payload))

      mgr = described_class.new(persistence_file)
      expect(mgr.form_names).to eq([])
    end

    it 'handles malformed timestamps in JSON data' do
      payload = {
        forms: {
          quiz1: [
            { session_id: 's1', responses: { 'q1' => 'a' }, timestamp: 'not-a-timestamp' }
          ]
        },
        exported_at: Time.now.iso8601
      }
      File.write(persistence_file, JSON.generate(payload))

      expect(Kernel).to receive(:warn).with(/Failed to load forms/)
      mgr = described_class.new(persistence_file)
      expect(mgr.form_names).to eq([])
    end

    it 'ignores extra fields in JSON data' do
      payload = {
        forms: {
          quiz1: [
            {
              session_id: 's1',
              responses: { 'q1' => 'a' },
              timestamp: Time.now.iso8601,
              extra_field: 'should be ignored'
            }
          ]
        },
        exported_at: Time.now.iso8601,
        extra_root_field: 'should be ignored'
      }
      File.write(persistence_file, JSON.generate(payload))

      mgr = described_class.new(persistence_file)
      expect(mgr.form_names).to eq(['quiz1'])
      expect(mgr.response_count('quiz1')).to eq(1)

      # Verify the response was loaded correctly
      responses = mgr.get_responses('quiz1')
      expect(responses.first[:session_id]).to eq('s1')
      # JSON.parse with symbolize_names converts keys to symbols
      expect(responses.first[:responses]).to eq({ q1: 'a' })
      expect(responses.first[:timestamp]).to be_a(Time)
      expect(responses.first).not_to have_key(:extra_field)
    end
  end

  describe '#clear' do
    it 'clears a specific form' do
      forms.submit('quiz1', 's1', { 'q1' => 'A' })
      forms.submit('quiz2', 's2', { 'q2' => 'B' })

      forms.clear('quiz1')
      expect(forms.form_names).to eq(['quiz2'])
      expect(forms.response_count('quiz1')).to eq(0)
    end

    it 'clears all forms when no name provided' do
      forms.submit('quiz1', 's1', { 'q1' => 'A' })
      forms.submit('quiz2', 's2', { 'q2' => 'B' })

      forms.clear
      expect(forms.form_names).to eq([])
    end
  end

  describe 'get_aggregated edge cases' do
    it 'handles complex response data in aggregation' do
      forms.submit('complex', 's1', {
        'multi_choice' => ['A', 'B'],
        'nested' => { 'key' => 'value' },
        'numeric' => 42,
        'boolean' => true
      })

      forms.submit('complex', 's2', {
        'multi_choice' => ['B', 'C'],
        'nested' => { 'key' => 'value' },
        'numeric' => 42,
        'boolean' => false
      })

      agg = forms.get_aggregated('complex')
      expect(agg[:total_responses]).to eq(2)

      # Each answer is counted as a separate entity
      expect(agg[:questions]['multi_choice']).to include(['A', 'B'] => 1, ['B', 'C'] => 1)
      expect(agg[:questions]['nested']).to include({ 'key' => 'value' } => 2)
      expect(agg[:questions]['numeric']).to include(42 => 2)
      expect(agg[:questions]['boolean']).to include(true => 1, false => 1)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent submissions without data loss' do
      threads = []
      per_thread = 25

      10.times do |i|
        threads << Thread.new do
          per_thread.times do |j|
            forms.submit('quizX', "sess-#{i}", { 'q' => ((i + j) % 3).to_s })
          end
        end
      end

      threads.each(&:join)

      count = forms.response_count('quizX')
      expect(count).to eq(10 * per_thread)

      agg = forms.get_aggregated('quizX')
      expect(agg[:total_responses]).to eq(count)
      expect(agg[:questions]['q'].values.sum).to eq(count)
    end

    it 'allows concurrent reads while writing without raising' do
      100.times { |i| forms.submit('quizY', "s#{i}", { 'q' => 'A' }) }

      writer = Thread.new { 5.times { forms.export_json } }

      readers = 10.times.map do
        Thread.new do
          20.times do
            agg = forms.get_aggregated('quizY')
            expect(agg).to be_a(Hash)
          end
        end
      end

      (readers + [writer]).each(&:join)

      expect(File).to exist(persistence_file)
      expect { JSON.parse(File.read(persistence_file)) }.not_to raise_error
    end
  end
end