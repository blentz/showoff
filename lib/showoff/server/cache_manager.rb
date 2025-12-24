require 'thread'

# Thread-safe LRU cache manager for Showoff server.
#
# Replaces legacy class variable:
# - @@cache (slide content caching)
#
# Implements a simple LRU (Least Recently Used) cache with configurable size.
#
# @example
#   cache = Showoff::Server::CacheManager.new(max_size: 50)
#   cache.set('slide_1', compiled_html)
#   cache.get('slide_1')
# Make sure the namespace exists
class Showoff; class Server; end; end

class Showoff::Server::CacheManager
  # Initialize a new cache manager
  #
  # @param max_size [Integer] Maximum number of items to cache
  def initialize(max_size: 100)
    @mutex = Mutex.new
    @max_size = max_size
    @cache = {}  # key => {value:, accessed_at:}
    @hits = 0
    @misses = 0
  end

  # Get a value from the cache.
  #
  # @param key [String] The cache key
  # @return [Object, nil] The cached value, or nil if not found
  def get(key)
    @mutex.synchronize do
      if @cache.key?(key)
        @hits += 1
        @cache[key][:accessed_at] = Time.now
        @cache[key][:value]
      else
        @misses += 1
        nil
      end
    end
  end

  # Set a value in the cache.
  #
  # @param key [String] The cache key
  # @param value [Object] The value to cache
  # @return [Object] The cached value
  def set(key, value)
    @mutex.synchronize do
      # Evict LRU item if at capacity and this is a new key
      if @cache.size >= @max_size && !@cache.key?(key)
        evict_lru_unsafe
      end

      @cache[key] = {
        value: value,
        accessed_at: Time.now
      }

      value
    end
  end

  # Check if a key exists in the cache.
  #
  # @param key [String] The cache key
  # @return [Boolean] True if key exists
  def key?(key)
    @mutex.synchronize do
      @cache.key?(key)
    end
  end

  # Invalidate (remove) a key from the cache.
  #
  # @param key [String] The cache key
  # @return [void]
  def invalidate(key)
    @mutex.synchronize do
      @cache.delete(key)
    end
  end

  # Clear all cached items.
  #
  # @return [void]
  def clear
    @mutex.synchronize do
      @cache.clear
      @hits = 0
      @misses = 0
    end
  end

  # Get cache statistics.
  #
  # @return [Hash] Statistics including size, hits, misses, hit rate
  def stats
    @mutex.synchronize do
      total = @hits + @misses
      hit_rate = total > 0 ? @hits.to_f / total : 0.0

      {
        size: @cache.size,
        max_size: @max_size,
        hits: @hits,
        misses: @misses,
        hit_rate: hit_rate
      }
    end
  end

  # Get current cache size.
  #
  # @return [Integer] Number of items in cache
  def size
    @mutex.synchronize { @cache.size }
  end

  # Get all cache keys.
  #
  # @return [Array<String>] All keys in cache
  def keys
    @mutex.synchronize { @cache.keys.dup }
  end

  # Fetch a value from cache, or compute and cache it if missing.
  #
  # @param key [String] The cache key
  # @yield Block to compute value if cache miss
  # @return [Object] The cached or computed value
  def fetch(key)
    # First try to get the value with a read lock
    value = get(key)

    # If value is missing and we have a block, compute and set atomically
    if value.nil? && block_given?
      @mutex.synchronize do
        # Check again inside the lock in case another thread set it
        value = @cache.key?(key) ? @cache[key][:value] : nil

        if value.nil?
          value = yield
          # Use the internal set method to avoid double-locking
          @cache[key] = {
            value: value,
            accessed_at: Time.now
          }
          # Evict LRU item if at capacity
          evict_lru_unsafe if @cache.size > @max_size
        else
          # Update access time for the key we found
          @cache[key][:accessed_at] = Time.now
        end
      end
    end

    value
  end

  private

  # Evict the least recently used item (internal, assumes mutex held).
  #
  # @return [void]
  def evict_lru_unsafe
    return if @cache.empty?

    # Find the key with the oldest accessed_at timestamp
    # Explicitly destructure the key-value pair from min_by
    lru_key, _lru_data = @cache.min_by { |key, data| data[:accessed_at] }
    @cache.delete(lru_key) if lru_key
  end
end
