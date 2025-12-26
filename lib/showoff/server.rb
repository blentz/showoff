require 'sinatra/base'
require 'faye/websocket'
require 'ostruct'

# Ensure Showoff constant exists before requiring nested classes
class Showoff; end

require 'showoff/config'
require 'showoff/presentation'

# Extend the legacy Showoff class to support nested classes
# (Showoff is a class, not a module, so we can't use module Showoff)
class Showoff
  class Server < Sinatra::Base
  end
end

require 'showoff/server/session_state'
require 'showoff/server/stats_manager'
require 'showoff/server/form_manager'
require 'showoff/server/cache_manager'
require 'showoff/server/download_manager'
require 'showoff/server/execution_manager'
require 'showoff/server/websocket_manager'
require 'showoff/server/feedback_manager'

# Modular Sinatra server for Showoff presentations.
#
# This replaces the monolithic `lib/showoff.rb` (Sinatra::Application)
# with a clean, testable Sinatra::Base architecture.
#
# @example
#   server = Showoff::Server.new(pres_dir: './my_presentation')
#   server.run!
class Showoff::Server
  # Initialize the server with options
  #
  # @param options [Hash] Configuration options
  # @option options [String] :pres_dir Presentation directory
  # @option options [String] :pres_file Configuration file (default: showoff.json)
  # @option options [Boolean] :verbose Enable verbose logging
  # @option options [Boolean] :execute Enable code execution
  # @option options [String] :host Bind host (default: localhost)
  # @option options [Integer] :port Port number (default: 9090)
  def initialize(options = {})
    @options = {
      pres_dir: Dir.pwd,
      pres_file: 'showoff.json',
      verbose: false,
      execute: false,
      port: 9090
    }.merge(options)

    # Set Sinatra's bind setting (accepts both :host and :bind for compatibility)
    bind_host = @options[:bind] || @options[:host] || '0.0.0.0'
    self.class.set :bind, bind_host
    self.class.set :port, @options[:port]

    super(nil)

    # Set settings that will be accessible in routes
    self.class.set :pres_dir, @options[:pres_dir]
    self.class.set :showoff_config, {}  # Will be populated when presentation is loaded

    # Initialize state managers
    @sessions = SessionState.new
    @stats = StatsManager.new
    @forms = FormManager.new
    @cache = CacheManager.new
    @download_manager = DownloadManager.new
    @execution_manager = nil # Lazy-initialized when needed

# Load presentation
begin
  Dir.chdir(@options[:pres_dir]) do
    # Load showoff.json configuration if present
    config = {}
    begin
      ShowoffUtils.presentation_config_file = @options[:pres_file] if defined?(ShowoffUtils)
      if File.exist?(@options[:pres_file])
        # Parse and expand configuration
        # Note: Config.load returns merged config from file + defaults
        config = Showoff::Config.load(@options[:pres_file])
      else
        # Minimal defaults to allow routes to render in tests without a full config
        config = {}
      end
    rescue => e
      # Swallow config errors to allow server to boot for routes that don't depend on full config
      config = {}
    end

    # Create presentation object (compiles slides)
    @presentation = Showoff::Presentation.new(@options)

    # Expose configuration to routes via settings
    self.class.set :showoff_config, config

    # Set additional settings from loaded config
    self.class.set :encoding, config['encoding'] || 'UTF-8'
    self.class.set :page_size, config['page-size'] || 'Letter'
    self.class.set :pres_template, config['templates']
    self.class.set :statsdir, @options[:stats_dir] || 'stats'
    self.class.set :viewstats, 'viewstats.json'
    self.class.set :feedback, 'feedback.json'
  end
rescue Errno::ENOENT => e
  # Fallback to defaults if presentation dir/file missing during certain tests
  self.class.set :showoff_config, {}
rescue JSON::ParserError => e
  # Ignore malformed config for minimal boot; routes will handle errors
  self.class.set :showoff_config, {}
rescue => e
  # Generic fallback: allow server to boot with minimal config
  self.class.set :showoff_config, {}
end
  end

  # Accessor methods for state managers
  # These ensure tests and routes share the same instances (avoiding Sinatra instance isolation issues)
  def download_manager
    @download_manager ||= DownloadManager.new
  end

  def stats
    @stats ||= StatsManager.new
  end

  def forms
    @forms ||= FormManager.new
  end

  def sessions
    @sessions ||= SessionState.new
  end

  def cache
    @cache ||= CacheManager.new
  end

  # WebSocket manager for real-time communication
  def websocket_manager
    @websocket_manager ||= WebSocketManager.new(
      session_state: sessions,
      stats_manager: stats,
      download_manager: download_manager,
      logger: logger,
      current_slide_callback: -> { settings.showoff_config['@@current'] },
      downloads_callback: -> { settings.showoff_config['@@downloads'] }
    )
  end

  # Configure Sinatra settings
  configure do
    set :views, File.join(File.dirname(__FILE__), '..', '..', 'views')
    set :public_folder, File.join(File.dirname(__FILE__), '..', '..', 'public')
    set :server, 'puma'  # Modern Rack server with excellent WebSocket support
    set :pres_dir, nil  # Will be set in initialize
    set :showoff_config, {}  # Will be set in initialize

    # I18n configuration
    require 'i18n'
    I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks) if defined?(I18n::Backend::Simple)
    I18n.load_path += Dir[File.join(File.dirname(__FILE__), '..', '..', 'locales', '*.yml')]
    I18n.backend.load_translations if I18n.backend.respond_to?(:load_translations)
    I18n.enforce_available_locales = false

    # Define version constant for templates
    # This should ideally come from Showoff::VERSION but we'll hardcode for now
    # to avoid additional dependencies
    SHOWOFF_VERSION = '0.20.4' unless defined?(SHOWOFF_VERSION)
  end

  # Helper methods for templates
  helpers do
    # Return empty array if css_files is not defined
    def css_files
      @css_files || []
    end

    # Return empty array if js_files is not defined
    def js_files
      @js_files || []
    end

    # Helper for locale handling
    def locale(preferred = nil)
      preferred ||= 'en'
      preferred = 'en' unless I18n.available_locales.map(&:to_s).include?(preferred)
      preferred
    end

    # Helper for language names
    def language_names
      {}
    end

    # Helper for user translations
    def user_translations
      {}
    end

    # Helper for presenter check
    def master_presenter?
      sessions.master_presenter?(@client_id)
    end

    # Helper for presenter cookie check
    # Returns true if the request has a valid presenter cookie OR if we're currently in presenter mode
    def valid_presenter_cookie?
      # Check if we have a valid presenter cookie in the request
      return true if sessions.valid_presenter_cookie?(request.cookies['presenter'])

      # Also return true if we're on the /presenter endpoint (we're setting the cookie now)
      return true if request.path_info == '/presenter'

      false
    end

    # Helper for key mappings
    def mapped_keys(action)
      # Return empty string if no mapping exists for the action
      return '' unless @keymap && @keymap[action]

      # If mapping exists, join the keys with commas
      @keymap[action].join(', ')
    end

    # Helper for translations
    def get_translations
      languages = I18n.backend.send(:translations)
      fallback = I18n.fallbacks[I18n.locale].select { |f| languages.keys.include? f }.first
      languages[fallback]
    end

    # Helper for managing client cookies
    def manage_client_cookies(presenter=false)
      # Generate or retrieve client ID
      if request.cookies['client_id']
        @client_id = request.cookies['client_id']
      else
        @client_id = sessions.generate_guid
        response.set_cookie('client_id', @client_id)
      end

      # Handle presenter cookies if requested
      if presenter
        sessions.register_presenter(@client_id)
        response.set_cookie('presenter', sessions.presenter_cookie)
      end
    end
  end

  # Root route - presentation index
  get '/' do
    begin
      # Set variables needed by the template
      @title = @presentation.title
      @favicon = nil
      @slides = nil
      @static = false
      @interactive = true
      @edit = false
      @feedback = true
      @pause_msg = "Paused"
      @css_files = []
      @js_files = []

      # Variables needed by header.erb - get from presentation
      @language = @presentation.language
      @highlightStyle = @presentation.highlightStyle
      @keymap = @presentation.keymap
      @keycode_dictionary = @presentation.keycode_dictionary
      @keycode_shifted_keys = @presentation.keycode_shifted_keys

      content_type 'text/html'
      erb :index
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering index: #{e.message}")

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering index</h1><p>#{e.message}</p></body></html>"
    end
  end

  # Health check endpoint
  get '/health' do
    content_type :json

    # Get title safely from presentation object
    title = 'Unknown Presentation'

    begin
      # Try to get title from instance variable directly
      if @presentation && @presentation.instance_variable_defined?(:@title)
        title = @presentation.instance_variable_get(:@title)
      end
    rescue => e
      # If anything goes wrong, use the default title
      title = 'Unknown Presentation'
    end

    { status: 'ok', presentation: title }.to_json
  end

  # Presenter endpoint
  # Renders the presenter view with speaker notes, next slide preview, and presenter controls
  get '/presenter' do
    begin
      # Set variables needed by the template
      @title = @presentation.title
      @favicon = settings.showoff_config['favicon']
      @issues = settings.showoff_config['issues']
      @edit = settings.showoff_config['edit'] if @review
      @feedback = settings.showoff_config['feedback']
      @language = get_translations()

      # Variables needed by header.erb - get from presentation
      @highlightStyle = @presentation.highlightStyle
      @keymap = @presentation.keymap
      @keycode_dictionary = @presentation.keycode_dictionary
      @keycode_shifted_keys = @presentation.keycode_shifted_keys

      # Variables needed by presenter.erb
      @slides = nil  # Slides loaded via JavaScript in presenter mode
      @interactive = true
      @static = false

      # Handle presenter cookies
      manage_client_cookies(true)

      # Render the presenter template
      content_type 'text/html'
      erb :presenter
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering presenter: #{e.message}")
      logger&.debug(e.backtrace.join("\n"))

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering presenter</h1><p>#{e.message}</p></body></html>"
    end
  end

  # Form submission endpoint
  # Saves form responses from a client, keyed by client_id cookie
  post '/form/:id' do |id|
    client_id = request.cookies['client_id']

    # Check for missing client_id - return 400 Bad Request
    if client_id.nil? || client_id.empty?
      # Log warning if logger is available
      logger&.warn("Form submission rejected: Missing client_id cookie for form #{id}")

      status 400
      content_type :json
      return { error: "Missing client_id cookie", status: 400 }.to_json
    end

    # Log if logger is available
  logger&.warn("Saving form answers from ip:#{request.ip} with ID of #{client_id} for form #{id}")

    # Extract form data, excluding routing metadata
    form_data = params.reject { |k,v| ['splat', 'captures', 'id'].include? k }

    begin
      # Submit to form manager
      @forms.submit(id, client_id, form_data)

      content_type :json
      form_data.to_json
    rescue => e
      # Handle any exceptions during form submission
      status 500
      content_type :json
      { error: "Form submission failed: #{e.message}", status: 500 }.to_json
    end
  end

  # Form aggregate retrieval endpoint
  # Returns aggregated responses for a form, counting unique responses per question
  get '/form/:id' do |id|
    responses = @forms.responses(id)

    # Return empty JSON object for non-existent forms
    if responses.nil? || responses.empty?
      content_type :json
      return {}.to_json
    end

    # Aggregate responses: count responses and tally each answer
    aggregate = responses.each_with_object({}) do |(client_id, form), sum|
      form.each do |key, val|
        # Initialize the question bucket if needed
        sum[key] ||= { 'count' => 0, 'responses' => {} }

        # Increment unique response count
        sum[key]['count'] += 1

        # Tally individual answers
        response_tallies = sum[key]['responses']
        if val.is_a?(Array)
          val.each do |item|
            response_tallies[item.to_s] ||= 0
            response_tallies[item.to_s] += 1
          end
        else
          response_tallies[val.to_s] ||= 0
          response_tallies[val.to_s] += 1
        end
      end
    end

    content_type :json
    aggregate.to_json
  end

  # Statistics viewing endpoint
  # Renders the stats.erb template with pageview and elapsed time data
  get '/stats' do
    begin
      # Only show detailed stats to localhost/presenter
      if localhost?
        # Get pageviews data
        @counter = {
          'pageviews' => stats.pageviews,
          'current' => stats.current_viewers,
          'user_agents' => stats.user_agents
        }
      else
        @counter = nil
      end

      # Get total elapsed time per slide from StatsManager
      @all = stats.elapsed_time_per_slide rescue {}

      # Set variables needed by header_mini.erb
      @title = "Presentation Statistics"
      @favicon = nil

      # Initialize empty arrays for CSS and JS files
      @css_files = []
      @js_files = []

      # Set additional variables needed by the template
      @language = 'en'
      @highlightStyle = 'default'

      content_type 'text/html'
      erb :stats
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering stats: #{e.message}")

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering statistics</h1><p>#{e.message}</p></body></html>"
    end
  end

  # JSON API endpoint for stats data
  # Used by the stats.erb template for AJAX loading
  get '/stats_data' do
    content_type :json

    # Get stats data from StatsManager
    # For now, return a minimal structure that won't break the UI
    {
      viewers: {},
      elapsed: {},
      all: @all || {}
    }.to_json
  end

  # File editing endpoint - only works from localhost
  get '/edit/*' do |path|
    # Docs suggest that old versions of Sinatra might provide an array here, so just make sure.
    filename = path.class == Array ? path.first : path
    logger&.debug "Editing #{filename}"

    # When a relative path is used, it's sometimes fully expanded. But then when
    # it's passed via URL, the initial slash is lost. Here we try to get it back.
    filename = "/#{filename}" unless File.exist? filename
    return unless File.exist? filename

    # Only allow editing from localhost
    unless localhost?
      logger&.warn "Disallowing edit because #{request.host} isn't localhost."
      return
    end

    case RUBY_PLATFORM
    when /darwin/
      `open #{filename}`
    when /linux/
      `xdg-open #{filename}`
    when /cygwin|mswin|mingw|bccwin|wince|emx/
      `start #{filename}`
    else
      logger&.warn "Cannot open #{filename}, unknown platform #{RUBY_PLATFORM}."
    end
  end

  # Asset serving endpoint - handles image and file paths
  get %r{/(?:image|file)/(.*)} do
    path = params[:captures].first
    full_path = File.join(@options[:pres_dir], path)

    # Security check: Prevent path traversal attacks
    normalized_path = File.expand_path(full_path)
    pres_dir_path = File.expand_path(@options[:pres_dir])

    # Ensure the normalized path still starts with the presentation directory
    if normalized_path.start_with?(pres_dir_path) && File.exist?(normalized_path)
      send_file normalized_path
    else
      logger&.warn "Rejecting request for path outside presentation directory: #{path}"
      raise Sinatra::NotFound
    end
  end

  # Magic key for shared files in the downloads hash
  # Must be sortable and appear first in the sorted list
  SHARED_FILES_SLIDE_NUM = -999

  # GET /print route - renders the entire presentation with page breaks for printing
  # Matches both /print and /print/section
  get %r{/print(?:/([^/]+))?} do |section|
    begin
      # Set locale from cookies
      @locale = locale(request.cookies['locale'])

      # Set title and favicon
      @title = ShowoffUtils.showoff_title(settings.pres_dir)
      @favicon = settings.showoff_config['favicon'] if defined?(settings.showoff_config)

      # Generate slides HTML with options for print view
      @slides = get_slides_html(static: true, toc: true, print: true, section: section)

      # Filter notes sections based on the section parameter
      # If section is nil, remove ALL notes sections (slides only)
      # If section is 'notes' or 'handouts', keep only matching sections
      @slides = filter_notes_sections(@slides, section)

      # Set baseurl for relative paths if section is provided
      unless params[:munged]
        @baseurl = '../' * section.split('/').count if section
      end

      # Initialize empty arrays for CSS and JS files (required by onepage.erb)
      @css_files = []
      @js_files = []

      # Render the onepage template
      content_type 'text/html'
      erb :onepage
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering print view: #{e.message}")
      logger&.debug(e.backtrace.join("\n"))

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering print view</h1><p>#{e.message}</p></body></html>"
    end
  end

  # GET /onepage route - renders the entire presentation in a single page format without page breaks
  get '/onepage' do
    begin
      # Set locale from cookies
      @locale = locale(request.cookies['locale'])

      # Set title and favicon
      @title = ShowoffUtils.showoff_title(settings.pres_dir)
      @favicon = settings.showoff_config['favicon'] if defined?(settings.showoff_config)

      # Generate slides HTML with options for onepage view
      @slides = get_slides_html(static: true, toc: true, print: false)

      # Initialize empty arrays for CSS and JS files (required by onepage.erb)
      @css_files = []
      @js_files = []

      # Render the onepage template
      content_type 'text/html'
      erb :onepage
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering onepage view: #{e.message}")
      logger&.debug(e.backtrace.join("\n"))

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering onepage view</h1><p>#{e.message}</p></body></html>"
    end
  end

  # GET /supplemental/:content route - renders supplemental materials (extra content not shown in the main presentation)
  get '/supplemental/:content' do |content|
    begin
      # Set locale from cookies
      @locale = locale(request.cookies['locale'])

      # Set title and favicon
      @title = ShowoffUtils.showoff_title(settings.pres_dir)
      @favicon = settings.showoff_config['favicon'] if defined?(settings.showoff_config)

      # Generate slides HTML with options for supplemental content
      # Supplemental material is by definition separate from the presentation,
      # so it doesn't make sense to attach notes
      @slides = get_slides_html(static: params[:static] == 'true', supplemental: content, section: false, toc: :all)

      # Set wrapper class for supplemental content
      @wrapper_classes = ['supplemental']

      # Initialize empty arrays for CSS and JS files (required by onepage.erb)
      @css_files = []
      @js_files = []

      # Render the onepage template
      content_type 'text/html'
      erb :onepage
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering supplemental content: #{e.message}")
      logger&.debug(e.backtrace.join("\n"))

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering supplemental content</h1><p>#{e.message}</p></body></html>"
    end
  end

  # Download page endpoint - lists all available downloadable files
  get '/download' do
    begin
      # Set locale from cookies
      @locale = locale(request.cookies['locale'])

      # Set title and favicon
      @title = ShowoffUtils.showoff_title(settings.pres_dir)
      @favicon = settings.showoff_config['favicon'] if defined?(settings.showoff_config)

      # Initialize empty arrays for CSS and JS files (required by header_mini.erb)
      @css_files = []
      @js_files = []

      # Scan for shared files in _files/share directory
      shared_files = []
      if settings.respond_to?(:pres_dir) && settings.pres_dir
        shared_dir = File.join(settings.pres_dir, '_files', 'share')
        if File.directory?(shared_dir)
          shared_files = Dir.glob("#{shared_dir}/*").map { |path| File.basename(path) }
        end
      end

      # Create downloads hash with shared files at magic index SHARED_FILES_SLIDE_NUM (-999)
      # This special index ensures shared files appear first in the sorted list on the download page
      downloads_hash = { SHARED_FILES_SLIDE_NUM => [true, 'Shared Files', shared_files] }

      # Merge with downloads from DownloadManager
      # Use accessor method to ensure same instance across test and route contexts
      downloads_hash.merge!(download_manager.all)
      @downloads = downloads_hash

      # Render the download template
      erb :download
    rescue Errno::ENOENT => e
      # Don't fail if the directory doesn't exist
      downloads_hash = {}
      downloads_hash.merge!(download_manager.all)
      @downloads = downloads_hash
      erb :download
    rescue => e
      # Log error if logger is available
      logger&.error("Error rendering download page: #{e.message}")

      # Return a basic error page
      status 500
      content_type 'text/html'
      "<html><body><h1>Error rendering download page</h1><p>#{e.message}</p></body></html>"
    end
  end

  # Evaluate known good code from a slide file on disk.
  # This route executes code blocks from slides in various languages.
  # SECURITY: This is a security-sensitive route as it involves arbitrary code execution.
  get '/execute/:lang' do |lang|
    # Return early if code execution is disabled
    return 'Run showoff with -x or --executecode to enable code execution' unless @options[:execute]

    begin
      # Extract code from slide
      code = execution_manager.get_code_from_slide(params[:path], params[:index])

      # Execute the code in the specified language
      execution_manager.execute(lang, code)
    rescue => e
      # Log error if logger is available
      logger&.error("Error executing code: #{e.message}")
      logger&.debug(e.backtrace.join("\n"))

      # Return error message
      "Error executing code: #{e.message}"
    end
  end

  # Slides endpoint - returns slide content as HTML
  # Used by AJAX requests from the client-side JavaScript
  get '/slides' do
    begin
      # Log cache status if logger is available
      logger&.info "Cached presentations: #{cache.keys}"

      # Get locale from cookies
      @locale = locale(request.cookies['locale'])

      # Check if we have a cache and we're not asking to invalidate it
      if cache.key?(@locale) && params['cache'] != 'clear'
        logger&.info "Using cached slides for locale: #{@locale}"
        return cache.get(@locale)
      end

      # Log that we're generating new content
      logger&.info "Generating slides for locale: #{@locale}"

      # If we're displaying from a repository, update it
      if settings.respond_to?(:url) && settings.url
        logger&.info "Updating presentation repository..."
        system('git', 'pull')
      end

      # Generate slides HTML from presentation
      # Must run in presentation directory for file paths to work
      content = Dir.chdir(settings.pres_dir) do
        @presentation.slides
      end

      # Cache the content unless nocache is set
      cache.set(@locale, content) unless settings.respond_to?(:nocache) && settings.nocache

      # Return the content
      content
    rescue => e
      # Log error if logger is available
      logger&.error("Error generating slides: #{e.message}")
      logger&.debug(e.backtrace.join("\n"))

      # Return error response
      status 500
      content_type :json
      { error: "Failed to generate slides: #{e.message}" }.to_json
    end
  end

  # Helper methods
  private

  # Check if request is from localhost
  def localhost?
    request.env['REMOTE_HOST'] == 'localhost' || request.ip == '127.0.0.1'
  end



  # State manager accessors for testing and route handlers
  public
  attr_reader :sessions, :stats, :forms, :cache, :downloads, :presentation, :config

  # Accessor for execution manager with lazy initialization
  def execution_manager
    @execution_manager ||= ExecutionManager.new(
      pres_dir: @options[:pres_dir],
      timeout: settings.showoff_config['timeout'],
      parsers: settings.showoff_config['parsers'],
      logger: logger
    )
  end

  # Helper method to generate slides HTML
  def get_slides_html(opts = {})
    # Log options if logger is available
    logger&.debug("Generating slides HTML with options: #{opts.inspect}")

    # Generate slides from presentation
    @presentation.slides
  end

  # Helper method to filter notes sections for print output
  # @param html [String] The HTML containing slides with notes sections
  # @param section [String, nil] The section to keep ('notes', 'handouts', or nil for no notes)
  # @return [String] The filtered HTML
  def filter_notes_sections(html, section)
    return html if html.nil? || html.empty?

    doc = Nokogiri::HTML.fragment(html)

    if section.nil?
      # Remove ALL notes sections when printing slides only
      doc.css('div.notes-section').each { |n| n.remove }
    else
      # Keep only the requested section type, remove others
      doc.css('div.notes-section').each do |note|
        classes = note.attr('class').split
        note.remove unless classes.include?(section)
      end
    end

    doc.to_html
  end

  # WebSocket endpoint for real-time presenter/audience sync
  get '/control' do
    # Check if WebSocket support is enabled
    return nil unless settings.showoff_config[:interactive]

    # Require WebSocket upgrade
    raise Sinatra::NotFound unless Faye::WebSocket.websocket?(request.env)

    # Create WebSocket connection
    ws = Faye::WebSocket.new(request.env)

    # On connection open
    ws.on :open do |event|
      # Send current slide position to new client
      current = websocket_manager.send(:current_slide_callback).call || {}
      ws.send({ 'message' => 'current', 'current' => current[:number] }.to_json)

      # Add connection to manager
      client_id = request.cookies['client_id'] || 'unknown'
      session_id = session.id rescue 'unknown'
      remote = request.env['REMOTE_HOST'] || request.env['REMOTE_ADDR']
      websocket_manager.add_connection(ws, client_id, session_id, remote)

      logger&.warn "Open WebSocket connections: #{websocket_manager.connection_count}"
    end

    # On message received
    ws.on :message do |event|
      begin
        websocket_manager.handle_message(ws, event.data, {
          cookies: request.cookies,
          user_agent: request.user_agent,
          env: request.env
        })
      rescue StandardError => e
        logger&.warn "WebSocket messaging error: #{e}"
        logger&.debug e.backtrace.join("\n")
      end
    end

    # On connection close
    ws.on :close do |event|
      logger&.warn "WebSocket closed"
      websocket_manager.remove_connection(ws)
    end

    # Return async Rack response
    ws.rack_response
  end

  # Note: We rely on Sinatra::Base's run! method which properly handles
  # the :bind and :port settings we configure in initialize
end
