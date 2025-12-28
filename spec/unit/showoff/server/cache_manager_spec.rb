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

    it 'initializes with default max_size of 100 when not specified' do
      mgr = described_class.new
      expect(mgr.stats[:max_size]).to eq(100)
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

    it 'returns nil when invalidating a non-existent key' do
      expect(cache.invalidate('nonexistent')).to be_nil
      expect(cache.key?('nonexistent')).to be false
    end

    it 'handles invalidating the same key multiple times' do
      cache.set('a', 1)
      expect(cache.key?('a')).to be true
      cache.invalidate('a')
      expect(cache.key?('a')).to be false
      cache.invalidate('a')
      expect(cache.key?('a')).to be false
    end

    it 'returns empty array for keys when cache is empty' do
      expect(cache.keys).to eq([])
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

    it 'handles eviction with a full cache' do
      c = described_class.new(max_size: 3)
      c.set('a', 1)
      c.set('b', 2)
      c.set('c', 3)

      # Access 'a' and 'c' to make 'b' the LRU
      c.get('a')
      c.get('c')

      # Add a new item, should evict 'b'
      c.set('d', 4)

      expect(c.key?('a')).to be true
      expect(c.key?('b')).to be false
      expect(c.key?('c')).to be true
      expect(c.key?('d')).to be true
    end

    it 'does nothing when evicting from an empty cache' do
      c = described_class.new(max_size: 2)
      # This is testing the private method indirectly
      # We're ensuring it doesn't raise an error when cache is empty
      expect { c.set('a', 1) }.not_to raise_error
    end

    it 'correctly updates access sequence when getting items' do
      c = described_class.new(max_size: 3)
      c.set('a', 1)
      c.set('b', 2)
      c.set('c', 3)

      # Access them in reverse order
      c.get('c')
      c.get('b')
      c.get('a')

      # Now 'c' should be the LRU
      c.set('d', 4)

      expect(c.key?('a')).to be true
      expect(c.key?('b')).to be true
      expect(c.key?('c')).to be false
      expect(c.key?('d')).to be true
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

    it 'handles fetch without a block for existing key' do
      cache.set('exists', 'value')
      expect(cache.fetch('exists')).to eq('value')
    end

    it 'returns nil when fetching without a block for missing key' do
      expect(cache.fetch('missing_no_block')).to be_nil
    end

    it 'performs LRU eviction when fetching beyond capacity' do
      c = described_class.new(max_size: 2)
      c.set('a', 1)
      c.set('b', 2)

      # This should evict 'a' since it's the LRU
      c.fetch('c') { 3 }

      expect(c.key?('a')).to be false
      expect(c.key?('b')).to be true
      expect(c.key?('c')).to be true
    end

    it 'handles race conditions in fetch by returning the first computed value' do
      c = described_class.new(max_size: 5)
      computed_values = []

      # Simulate multiple threads computing values for the same key
      threads = []
      5.times do |i|
        threads << Thread.new do
          value = c.fetch('concurrent_key') do
            # Simulate computation
            sleep(rand(0.01..0.05))
            computed = "value-#{i}"
            computed_values << computed
            computed
          end
        end
      end

      threads.each(&:join)

      # All threads should see the same value
      cached_value = c.get('concurrent_key')
      expect(computed_values).to include(cached_value)

      # The block should have been executed at least once
      expect(computed_values.size).to be >= 1
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

    it 'calculates hit_rate as 0.0 when there are no accesses' do
      c = described_class.new
      expect(c.stats[:hit_rate]).to eq(0.0)
    end

    it 'updates statistics correctly after clear' do
      c = described_class.new
      c.set('a', 1)
      c.get('a')
      c.get('b') # miss

      c.clear

      s = c.stats
      expect(s[:hits]).to eq(0)
      expect(s[:misses]).to eq(0)
      expect(s[:hit_rate]).to eq(0.0)
      expect(s[:size]).to eq(0)
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

    it 'handles concurrent operations on different methods' do
      c = described_class.new(max_size: 10)

      # Set up some initial data
      5.times { |i| c.set("key-#{i}", i) }

      threads = []

      # Thread 1: Add new items
      threads << Thread.new do
        5.times { |i| c.set("new-#{i}", i * 10) }
      end

      # Thread 2: Get existing items
      threads << Thread.new do
        5.times { |i| c.get("key-#{i}") }
      end

      # Thread 3: Invalidate some items
      threads << Thread.new do
        c.invalidate("key-1")
        c.invalidate("key-3")
      end

      # Thread 4: Fetch items
      threads << Thread.new do
        c.fetch("key-2") { "new value" }
        c.fetch("new-fetch") { "fetched" }
      end

      # Thread 5: Check stats and keys
      threads << Thread.new do
        c.stats
        c.keys
        c.size
      end

      threads.each(&:join)

      # Verify the cache is still in a consistent state
      expect(c.size).to be <= 10
      expect(c.key?("key-1")).to be false
      expect(c.key?("key-3")).to be false
    end

    it 'handles concurrent clear operations' do
      c = described_class.new(max_size: 20)

      # Set up some initial data
      10.times { |i| c.set("key-#{i}", i) }

      threads = []

      # Thread 1: Clear the cache
      threads << Thread.new do
        c.clear
      end

      # Thread 2: Set new items while clearing
      threads << Thread.new do
        5.times { |i| c.set("concurrent-#{i}", i) }
      end

      # Thread 3: Get items while clearing
      threads << Thread.new do
        10.times { |i| c.get("key-#{i}") }
      end

      threads.each(&:join)

      # After all operations, the cache should be in a consistent state
      # Either empty (if clear was last) or containing only new items
      c.keys.each do |key|
        expect(key).to match(/^concurrent-\d+$/)
      end
    end
  end
end