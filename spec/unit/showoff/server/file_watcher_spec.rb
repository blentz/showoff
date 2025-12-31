require 'spec_helper'
require 'showoff/server/cache_manager'
require 'showoff/server/file_watcher'
require 'showoff/server'  # For Showoff::Server.slide_cache and needs_reload
require 'fileutils'
require 'tmpdir'

RSpec.describe Showoff::Server::FileWatcher do
  let(:temp_dir) { Dir.mktmpdir('showoff_test') }
  let(:mock_ws_manager) { MockWebSocketManager.new }
  let(:mock_cache) { Showoff::Server::CacheManager.new }
  let(:mock_logger) { MockLogger.new }

  let(:file_watcher) do
    described_class.new(
      root_dir: temp_dir,
      websocket_manager: mock_ws_manager,
      cache_manager: mock_cache,
      logger: mock_logger,
      force_polling: true,
      debounce_delay: 0.05,
      polling_interval: 0.1
    )
  end

  # Mock WebSocket manager for testing
  class MockWebSocketManager
    attr_reader :broadcasts

    def initialize
      @broadcasts = []
    end

    def broadcast_to_all(message)
      @broadcasts << message
    end

    def connection_count
      1
    end
  end

  # Mock logger for testing
  class MockLogger
    attr_reader :messages

    def initialize
      @messages = { debug: [], info: [], warn: [], error: [] }
    end

    def debug(msg); @messages[:debug] << msg; end
    def info(msg); @messages[:info] << msg; end
    def warn(msg); @messages[:warn] << msg; end
    def error(msg); @messages[:error] << msg; end
  end

  after do
    file_watcher.stop if file_watcher.running?
    FileUtils.rm_rf(temp_dir)
  end

  describe '#initialize' do
    it 'sets up with provided options' do
      expect(file_watcher).not_to be_running
    end

    it 'uses default values when not provided' do
      watcher = described_class.new(
        root_dir: temp_dir,
        websocket_manager: mock_ws_manager,
        cache_manager: mock_cache,
        logger: mock_logger
      )
      expect(watcher).not_to be_running
    end
  end

  describe '#start and #stop' do
    it 'starts and stops the watcher' do
      expect(file_watcher.running?).to be false

      file_watcher.start
      expect(file_watcher.running?).to be true

      file_watcher.stop
      expect(file_watcher.running?).to be false
    end

    it 'does not start twice' do
      file_watcher.start
      expect(file_watcher.running?).to be true

      # Second start should be a no-op
      file_watcher.start
      expect(file_watcher.running?).to be true
    end

    it 'handles stop when not running' do
      expect { file_watcher.stop }.not_to raise_error
      expect(file_watcher.running?).to be false
    end

    it 'logs when starting in polling mode' do
      file_watcher.start
      expect(mock_logger.messages[:info]).to include(a_string_matching(/polling mode/i))
    end
  end

  describe 'file change detection', :slow do
    before do
      file_watcher.start
      # Wait for listener to be ready
      sleep 0.2
    end

    it 'detects markdown file changes' do
      # Create a markdown file
      md_file = File.join(temp_dir, 'slides.md')
      File.write(md_file, '# Test Slide')

      # Wait for detection
      sleep 0.5

      expect(mock_ws_manager.broadcasts).not_to be_empty
      last_broadcast = mock_ws_manager.broadcasts.last
      expect(last_broadcast['message']).to eq('reload')
      expect(last_broadcast['reload_type']).to eq('full')
    end

    it 'detects CSS file changes with css reload type' do
      mock_ws_manager.broadcasts.clear

      # Create a CSS file
      css_file = File.join(temp_dir, 'custom.css')
      File.write(css_file, 'body { color: red; }')

      # Wait for detection
      sleep 0.5

      expect(mock_ws_manager.broadcasts).not_to be_empty
      last_broadcast = mock_ws_manager.broadcasts.last
      expect(last_broadcast['message']).to eq('reload')
      expect(last_broadcast['reload_type']).to eq('css')
    end

    it 'uses full reload for mixed file types' do
      mock_ws_manager.broadcasts.clear

      # Create both CSS and markdown
      File.write(File.join(temp_dir, 'test.css'), 'body {}')
      File.write(File.join(temp_dir, 'test.md'), '# Hi')

      # Wait for detection (debounce should combine them)
      sleep 0.5

      # May have multiple broadcasts, check that at least one is full reload
      full_reloads = mock_ws_manager.broadcasts.select { |b| b['reload_type'] == 'full' }
      expect(full_reloads).not_to be_empty
    end
  end

  describe 'cache invalidation', :slow do
    before do
      # Add something to the cache
      mock_cache.set('en', '<div>cached content</div>')
      expect(mock_cache.key?('en')).to be true

      file_watcher.start
      sleep 0.2
    end

    it 'clears the cache when files change' do
      # Pre-populate the Server's slide cache (not the mock_cache)
      Showoff::Server.slide_cache.set('en', '<div>Test</div>')
      expect(Showoff::Server.slide_cache.key?('en')).to be true

      # Modify a file
      File.write(File.join(temp_dir, 'slides.md'), '# New Content')

      # Wait for detection
      sleep 0.5

      # Server's slide cache should be cleared and needs_reload should be set
      expect(Showoff::Server.slide_cache.key?('en')).to be false
      expect(Showoff::Server.needs_reload?).to be true

      # Clean up
      Showoff::Server.needs_reload = false
    end
  end

  describe 'ignored patterns' do
    before do
      file_watcher.start
      sleep 0.2
    end

    it 'ignores .git directory changes' do
      mock_ws_manager.broadcasts.clear

      git_dir = File.join(temp_dir, '.git')
      FileUtils.mkdir_p(git_dir)
      File.write(File.join(git_dir, 'HEAD'), 'ref: refs/heads/main')

      sleep 0.5

      # Should have no broadcasts for .git changes
      # Note: The pattern might not match subdirs, so we check the files list
      git_broadcasts = mock_ws_manager.broadcasts.select do |b|
        b['files']&.any? { |f| f.include?('.git') }
      end
      expect(git_broadcasts).to be_empty
    end

    it 'ignores swap files' do
      mock_ws_manager.broadcasts.clear

      # Create a swap file (vim style)
      File.write(File.join(temp_dir, '.slides.md.swp'), 'swap content')

      sleep 0.5

      swp_broadcasts = mock_ws_manager.broadcasts.select do |b|
        b['files']&.any? { |f| f.end_with?('.swp') }
      end
      expect(swp_broadcasts).to be_empty
    end
  end

  describe 'WATCH_EXTENSIONS constant' do
    it 'includes common presentation file types' do
      extensions = described_class::WATCH_EXTENSIONS

      expect(extensions).to include('md')
      expect(extensions).to include('css')
      expect(extensions).to include('json')
      expect(extensions).to include('erb')
      expect(extensions).to include('html')
      expect(extensions).to include('js')
    end
  end

  describe 'IGNORE_PATTERNS constant' do
    it 'includes common directories to ignore' do
      patterns = described_class::IGNORE_PATTERNS

      # Check patterns match expected strings
      expect(patterns.any? { |p| '.git/HEAD' =~ p }).to be true
      expect(patterns.any? { |p| 'node_modules/foo' =~ p }).to be true
      expect(patterns.any? { |p| 'file.swp' =~ p }).to be true
    end
  end

  describe 'native mode' do
    it 'can be configured for native filesystem events' do
      native_watcher = described_class.new(
        root_dir: temp_dir,
        websocket_manager: mock_ws_manager,
        cache_manager: mock_cache,
        logger: mock_logger,
        force_polling: false
      )

      native_watcher.start
      expect(native_watcher.running?).to be true

      # Check log message
      expect(mock_logger.messages[:info]).to include(a_string_matching(/native/i))

      native_watcher.stop
    end
  end
end
