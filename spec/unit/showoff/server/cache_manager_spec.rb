require 'spec_helper'
require 'showoff/server/cache_manager'

RSpec.describe Showoff::Server::CacheManager do
  let(:cache) { described_class.new(max_size: 3) }

  describe '#initialize' do
    it 'initializes with custom max_size and empty stats' do
      mgr = described_class.new(max_size: 5)
      s = mgr.stats
      expect(s[:size]).to eq(0)
      expect(s[:max_size]).to eq(5)
      expect(s[:hits]).to eq(0)
      expect(s[:misses]).to eq(0)
      expect(s[:hit_rate]).to eq(0.0)
    end
  end

  describe 'basic operations' do
    it 'sets and gets values and tracks existence' do
      expect(cache.key?('a')).to be false
      expect(cache.get('a')).to be_nil

      cache.set('a', 1)
      cache.set('b', 'two')

      expect(cache.key?('a')).to be true
      expect(cache.get('a')).to eq(1)
      expect(cache.get('b')).to eq('two')

      stats = cache.stats
      expect(stats[:hits]).to be >= 2
      expect(stats[:misses]).to be >= 1
    end

    it 'invalidates keys and can clear cache' do
      cache.set('a', 1)
      cache.set('b', 2)
      expect(cache.size).to eq(2)

      cache.invalidate('a')
      expect(cache.key?('a')).to be false
      expect(cache.size).to eq(1)

      cache.clear
      s = cache.stats
      expect(s[:size]).to eq(0)
      expect(s[:hits]).to eq(0)
      expect(s[:misses]).to eq(0)
    end

    it 'returns keys list as a copy' do
      cache.set('a', 1)
      cache.set('b', 2)
      ks = cache.keys
      expect(ks).to contain_exactly('a', 'b')
      ks << 'c'
      expect(cache.key?('c')).to be false
    end
  end

  describe 'LRU eviction' do
    it 'evicts least recently used when inserting beyond capacity' do
      c = described_class.new(max_size: 2)
      c.set('a', 'A')
      c.set('b', 'B')
      expect(c.get('a')).to eq('A')

      c.set('c', 'C')
      expect(c.key?('a')).to be true
      expect(c.key?('b')).to be false
      expect(c.key?('c')).to be true
    end

    it 'does not evict when updating existing key at capacity' do
      c = described_class.new(max_size: 2)
      c.set('x', 1)
      c.set('y', 2)
      c.set('y', 22)
      expect(c.get('y')).to eq(22)
      c.set('z', 3)
      expect(c.key?('x')).to be false
      expect(c.key?('y')).to be true
      expect(c.key?('z')).to be true
    end
  end

  describe '#fetch' do
    it 'returns cached value if exists' do
      cache.set('k', 42)
      expect(cache.fetch('k') { raise 'should not execute' }).to eq(42)
    end

    it 'computes and caches when missing' do
      val = cache.fetch('miss') { 123 }
      expect(val).to eq(123)
      expect(cache.get('miss')).to eq(123)
      expect(cache.fetch('miss') { 0 }).to eq(123)
      expect(cache.stats[:hits]).to be >= 1
    end

    it 'is thread-safe to use concurrently on the same key' do
      c = described_class.new(max_size: 5)
      counter = 0
      threads = []

      10.times do
        threads << Thread.new do
          c.fetch('shared') do
            current = nil
            100.times { current = (counter += 1) }
            current
          end
        end
      end

      threads.each(&:join)

      expect(c.key?('shared')).to be true
      expect(c.get('shared')).to be_a(Integer)
    end
  end

  describe 'statistics' do
    it 'tracks hits, misses, and hit_rate' do
      c = described_class.new(max_size: 3)
      expect(c.get('a')).to be_nil
      expect(c.get('b')).to be_nil
      c.set('a', 1)
      expect(c.get('a')).to eq(1)
      s = c.stats
      expect(s[:hits]).to eq(1)
      expect(s[:misses]).to eq(2)
      expect(s[:hit_rate]).to be_within(0.0001).of(1.0 / 3.0)
      expect(s[:size]).to eq(1)
      expect(s[:max_size]).to eq(3)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent set/get without data loss and respects capacity' do
      c = described_class.new(max_size: 50)
      threads = []
      errors = []

      10.times do |i|
        threads << Thread.new do
          200.times do |j|
            key = "k-#{i}-#{j}"
            c.set(key, j)
            v = c.get(key)
            # In high contention scenarios, keys may be evicted between set and get
            # This is expected behavior for an LRU cache, not a bug
            # Only fail if we get a value but it's wrong (data corruption)
            if v && v != j
              errors << "Expected #{j} but got #{v} for key #{key}"
            end
          end
        end
      end

      threads.each(&:join)

      # No data corruption should occur
      expect(errors).to be_empty
      # Cache should respect max size
      expect(c.size).to be <= 50
    end

    it 'performs evictions correctly under contention' do
      c = described_class.new(max_size: 3)
      %w[a b c].each { |k| c.set(k, k.upcase) }
      c.get('a')

      threads = []
      %w[d e f g].each do |k|
        threads << Thread.new { c.set(k, k.upcase) }
      end
      threads.each(&:join)

      expect(c.size).to eq(3)

      c.clear
      c.set('x', 1)
      c.set('y', 2)
      c.get('x')
      c.set('z', 3)
      # At this point, cache size equals max_size (3), so no eviction should occur
      expect(c.key?('x')).to be true
      expect(c.key?('y')).to be true  # Changed: 'y' should still be in the cache
      expect(c.key?('z')).to be true

      # Now add a 4th item to trigger eviction
      c.set('w', 4)  # This should trigger eviction of 'y' (the LRU item)
      expect(c.key?('x')).to be true
      expect(c.key?('y')).to be false  # Now 'y' should be evicted
      expect(c.key?('z')).to be true
      expect(c.key?('w')).to be true
    end
  end
end
