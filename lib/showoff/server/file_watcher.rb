require 'listen'
require 'thread'

class Showoff
  class Server
    # FileWatcher monitors presentation files for changes and triggers
    # browser reloads via WebSocket.
    #
    # Designed for container environments where presentations are mounted
    # as volumes. Uses polling by default since native filesystem events
    # don't propagate reliably across container volume mounts.
    #
    # @example
    #   watcher = FileWatcher.new(
    #     root_dir: '/presentation',
    #     websocket_manager: ws_manager,
    #     cache_manager: cache,
    #     logger: logger
    #   )
    #   watcher.start
    #   # ... later ...
    #   watcher.stop
    #
    class FileWatcher
      # File patterns to watch for changes
      WATCH_EXTENSIONS = %w[md css json erb html js svg png jpg jpeg gif].freeze

      # Patterns to ignore (reduces noise and improves performance)
      IGNORE_PATTERNS = [
        /\.git/,
        /node_modules/,
        /_files\/.*downloads/,
        /\.stats\.json$/,
        /\.swp$/,
        /~$/,
        /\#.*\#$/
      ].freeze

      # Default debounce delay in seconds
      # Prevents multiple reloads when editors save backup files
      DEFAULT_DEBOUNCE_DELAY = 0.1

      # Default polling interval in seconds
      # 1.0s is the listen gem default for polling mode
      DEFAULT_POLLING_INTERVAL = 1.0

      # Initialize a new FileWatcher
      #
      # @param root_dir [String] Directory to watch (presentation root)
      # @param websocket_manager [WebSocketManager] For broadcasting reload messages
      # @param cache_manager [CacheManager] For invalidating cached slides
      # @param logger [Logger] For logging events
      # @param force_polling [Boolean] Force polling mode (default: true for container compatibility)
      # @param debounce_delay [Float] Debounce delay in seconds
      # @param polling_interval [Float] Polling interval in seconds
      def initialize(root_dir:, websocket_manager:, cache_manager:, logger:,
                     force_polling: true, debounce_delay: DEFAULT_DEBOUNCE_DELAY,
                     polling_interval: DEFAULT_POLLING_INTERVAL)
        @root_dir = File.expand_path(root_dir)
        @ws_manager = websocket_manager
        @cache_manager = cache_manager
        @logger = logger
        @force_polling = force_polling
        @debounce_delay = debounce_delay
        @polling_interval = polling_interval

        @listener = nil
        @debounce_mutex = Mutex.new
        @debounce_thread = nil
        @pending_files = []
        @running = false
      end

      # Start watching for file changes
      #
      # @return [void]
      def start
        return if @running

        @running = true

        listen_options = {
          only: build_extension_regex,
          ignore: IGNORE_PATTERNS,
          wait_for_delay: @debounce_delay
        }

        # Force polling for container compatibility
        if @force_polling
          listen_options[:force_polling] = true
          listen_options[:latency] = @polling_interval
          @logger.info "FileWatcher: Starting in polling mode (interval: #{@polling_interval}s)"
        else
          @logger.info "FileWatcher: Starting with native filesystem events"
        end

        @listener = Listen.to(@root_dir, listen_options) do |modified, added, removed|
          handle_changes(modified + added + removed)
        end

        @listener.start
        @logger.info "FileWatcher: Watching #{@root_dir}"
      end

      # Stop watching for file changes
      #
      # @return [void]
      def stop
        return unless @running

        @running = false
        @listener&.stop
        @listener = nil

        @debounce_mutex.synchronize do
          @debounce_thread&.kill
          @debounce_thread = nil
          @pending_files.clear
        end

        @logger.info "FileWatcher: Stopped"
      end

      # Check if the watcher is running
      #
      # @return [Boolean]
      def running?
        @running
      end

      private

      # Handle file changes with debouncing
      #
      # @param files [Array<String>] List of changed file paths
      # @return [void]
      def handle_changes(files)
        return if files.empty?

        @debounce_mutex.synchronize do
          @pending_files.concat(files)

          # Cancel existing debounce timer
          if @debounce_thread&.alive?
            @debounce_thread.kill
          end

          # Start new debounce timer
          @debounce_thread = Thread.new do
            sleep @debounce_delay
            process_pending_changes
          end
        end
      end

      # Process accumulated changes after debounce period
      #
      # @return [void]
      def process_pending_changes
        files = nil
        @debounce_mutex.synchronize do
          files = @pending_files.uniq
          @pending_files.clear
        end

        return if files.nil? || files.empty?

        # Log changed files
        relative_files = files.map { |f| f.sub("#{@root_dir}/", '') }
        @logger.info "FileWatcher: Changes detected: #{relative_files.join(', ')}"

        # Invalidate cache
        invalidate_cache

        # Determine reload type and broadcast
        reload_type = determine_reload_type(files)
        broadcast_reload(reload_type, relative_files)
      end

      # Invalidate the slide cache and mark presentation for reload
      #
      # @return [void]
      def invalidate_cache
        # Call the Server class method which clears cache AND sets needs_reload flag
        Showoff::Server.clear_slide_cache
        @logger.debug "FileWatcher: Cache invalidated, presentation marked for reload"
      rescue => e
        @logger.warn "FileWatcher: Failed to invalidate cache: #{e.message}"
      end

      # Broadcast reload message to all connected clients
      #
      # @param reload_type [String] 'css' for CSS-only, 'full' for everything else
      # @param files [Array<String>] List of changed files (relative paths)
      # @return [void]
      def broadcast_reload(reload_type, files)
        message = {
          'message' => 'reload',
          'reload_type' => reload_type,
          'files' => files,
          'timestamp' => Time.now.to_i
        }

        @ws_manager.broadcast_to_all(message)
        @logger.info "FileWatcher: Broadcast #{reload_type} reload to #{@ws_manager.connection_count} clients"
      rescue => e
        @logger.error "FileWatcher: Failed to broadcast reload: #{e.message}"
      end

      # Determine if we can do a CSS-only hot swap or need full reload
      #
      # @param files [Array<String>] List of changed file paths
      # @return [String] 'css' or 'full'
      def determine_reload_type(files)
        if files.all? { |f| f.end_with?('.css') }
          'css'
        else
          'full'
        end
      end

      # Build regex to match watched file extensions
      #
      # @return [Regexp]
      def build_extension_regex
        extensions = WATCH_EXTENSIONS.join('|')
        /\.(#{extensions})$/i
      end
    end
  end
end
