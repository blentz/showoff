# frozen_string_literal: true

require 'sinatra/base'
require 'showoff/server'

class Showoff
  # ServerAdapter provides a Sinatra::Application-compatible interface
  # for the new Showoff::Server (Sinatra::Base) architecture.
  #
  # This adapter serves as a compatibility layer between the legacy CLI interface
  # (which expects a Sinatra::Application class with class-level run! method)
  # and the new modular Showoff::Server (Sinatra::Base) architecture.
  #
  # The adapter translates between:
  # - CLI options format → Server initialization
  # - SSL configuration → SSLShim middleware
  # - Presentation loading → Config + Presentation objects
  #
  # This enables a smooth transition from the monolithic architecture to the
  # new modular architecture without breaking existing CLI functionality.
  #
  # @example Basic usage with CLI options
  #   options = {
  #     pres_dir: './my_presentation',
  #     pres_file: 'showoff.json',
  #     verbose: true,
  #     port: 9090
  #   }
  #
  #   ServerAdapter.run!(options)
  #
  # @example With SSL configuration
  #   ServerAdapter.run!(options) do |server|
  #     server.ssl = true
  #     server.ssl_options = {
  #       cert_chain_file: 'cert.pem',
  #       private_key_file: 'key.pem'
  #     }
  #   end
  #
  # @example Feature flag usage in bin/showoff
  #   if ENV['SHOWOFF_USE_NEW_SERVER'] == 'true'
  #     require 'showoff/server_adapter'
  #     Showoff::ServerAdapter.run!(options) do |server|
  #       # SSL configuration
  #     end
  #   else
  #     # Legacy path
  #     Showoff.run!(options) do |server|
  #       # SSL configuration
  #     end
  #   end
  class ServerAdapter
    # Run the new Showoff::Server with legacy-compatible interface
    #
    # This method provides a drop-in replacement for the legacy Showoff.run!
    # method, maintaining backward compatibility with the CLI interface while
    # using the new modular architecture internally.
    #
    # It handles:
    # 1. Translating CLI options to Server settings
    # 2. Creating a Showoff::Server instance
    # 3. Applying SSL configuration via SSLShim (if provided)
    # 4. Starting the Rack server with the correct settings
    #
    # @param options [Hash] CLI options from bin/showoff
    # @option options [String] :pres_dir Presentation directory
    # @option options [String] :pres_file Config file (default: showoff.json)
    # @option options [String] :file Alias for :pres_file
    # @option options [Boolean] :verbose Enable verbose logging
    # @option options [Boolean] :review Enable review mode
    # @option options [Boolean] :execute Enable code execution
    # @option options [Boolean] :standalone Enable standalone mode
    # @option options [Boolean] :nocache Disable caching
    # @option options [String] :host Bind host (alias for :bind)
    # @option options [String] :bind Bind host
    # @option options [Integer] :port Port number
    # @option options [String] :language Presentation language
    # @option options [String] :css Custom CSS file
    # @option options [String] :js Custom JS file
    # @option options [Hash] :pdf_options PDF generation options
    # @option options [Hash] :settings Custom settings
    # @yield [SSLShim] Block for SSL configuration (legacy compat)
    # @return [void]
    def self.run!(options = {}, &block)
      begin
        # Log that we're using the new server architecture
        if defined?(Showoff::Logger)
          Showoff::Logger.info("Using new modular server architecture via ServerAdapter")
          Showoff::Logger.debug("ServerAdapter options: #{options.inspect}")
        end

        # Create server instance with merged options
        translated_options = translate_options(options)
        if defined?(Showoff::Logger)
          Showoff::Logger.debug("Translated options: #{translated_options.inspect}")
        end

        server = Showoff::Server.new(translated_options)

        # Apply SSL configuration if provided via block
        if block_given?
          if defined?(Showoff::Logger)
            Showoff::Logger.debug("Applying SSL configuration via block")
          end

          shim = SSLShim.new(server)
          block.call(shim)
        end

        # Start the Rack server
        host = options[:bind] || options[:host] || 'localhost'
        port = options[:port] || 9090

        if defined?(Showoff::Logger)
          Showoff::Logger.info("Starting server on #{host}:#{port}")
        end

        server.run!(
          host: host,
          port: port,
          server: 'thin'
        )
      rescue => e
        # Log the error if a logger is available
        if defined?(Showoff::Logger) && Showoff::Logger.respond_to?(:error)
          Showoff::Logger.error("Error in ServerAdapter.run!: #{e.message}")
          Showoff::Logger.error(e.backtrace.join("\n")) if e.backtrace
        else
          # Fall back to standard error output
          $stderr.puts "Error in ServerAdapter.run!: #{e.message}"
          $stderr.puts e.backtrace.join("\n") if e.backtrace
        end

        # Re-raise the exception to maintain compatibility with legacy error handling
        raise
      end
    end

    # Translate CLI options to Server settings format
    #
    # This method handles the translation of CLI options from the format
    # expected by the legacy Showoff.run! method to the format expected
    # by the new Showoff::Server architecture.
    #
    # It handles:
    # - Option aliases (e.g., :file → :pres_file, :host → :bind)
    # - Path normalization (expanding relative paths)
    # - Boolean flag normalization
    # - Special case handling for various option types
    #
    # @param options [Hash] CLI options from bin/showoff
    # @return [Hash] Options formatted for Showoff::Server
    # @see ServerAdapter.run! for a list of supported options
    def self.translate_options(options)
      # Start with a copy of the original options
      translated = options.dup

      # Handle aliases and special cases
      translated[:pres_file] ||= options[:file] if options[:file]
      translated[:bind] ||= options[:host] if options[:host]

      # Ensure pres_dir is set and expanded
      if translated[:pres_dir]
        translated[:pres_dir] = File.expand_path(translated[:pres_dir])
      else
        # Default to current directory if not specified
        translated[:pres_dir] = File.expand_path(Dir.pwd)

        # Log the default if a logger is available
        if defined?(Showoff::Logger)
          Showoff::Logger.debug("No pres_dir specified, defaulting to: #{translated[:pres_dir]}")
        end
      end

      # Ensure pres_file is set
      translated[:pres_file] ||= 'showoff.json'

      # Validate that the presentation directory exists
      unless File.directory?(translated[:pres_dir])
        raise ArgumentError, "Presentation directory does not exist: #{translated[:pres_dir]}"
      end

      # Validate that the presentation file exists
      pres_file_path = File.join(translated[:pres_dir], translated[:pres_file])
      unless File.exist?(pres_file_path)
        raise ArgumentError, "Presentation file does not exist: #{pres_file_path}"
      end

      # Map CLI options to Server settings
      # These are the key mappings from the design document (section 4.4)
      # - `pres_dir` → `set :pres_dir`
      # - `pres_file` / `file` → `set :pres_file`
      # - `verbose` → `set :verbose` + logger level
      # - `review` → `set :review`
      # - `execute` → `set :execute`
      # - `standalone` → `set :standalone`
      # - `nocache` → `set :nocache`
      # - `port` → `set :port`
      # - `bind` / `host` → `set :bind`

      # Ensure boolean flags are properly set
      [:verbose, :review, :execute, :standalone, :nocache].each do |flag|
        translated[flag] = !!options[flag] if options.key?(flag)
      end

      # Handle additional settings
      translated[:page_size] = options[:page_size] if options[:page_size]
      translated[:pres_template] = options[:template] if options[:template]
      translated[:encoding] = options[:encoding] if options[:encoding]
      translated[:url] = options[:url] if options[:url]

      # Handle language/locale settings
      translated[:language] = options[:language] if options[:language]

      # Handle custom CSS/JS files
      translated[:css] = options[:css] if options[:css]
      translated[:js] = options[:js] if options[:js]

      # Handle PDF options
      if options[:pdf_options]
        translated[:pdf_options] = options[:pdf_options]
      end

      # Handle custom settings from showoff.json
      if options[:settings]
        translated[:settings] = options[:settings]
      end

      # Return the translated options
      translated
    end

    # SSLShim translates legacy Thin SSL configuration to Rack middleware
    #
    # This shim provides compatibility with the legacy Thin SSL API, which
    # was used in the monolithic Showoff.run! implementation. It translates
    # the legacy SSL configuration to the appropriate settings in the new
    # Showoff::Server architecture.
    #
    # The legacy code used Thin's built-in SSL support, while the new architecture
    # uses Rack::SSL middleware for SSL termination.
    class SSLShim
      # Initialize the SSL shim
      #
      # @param server [Showoff::Server] Server instance to configure
      def initialize(server)
        @server = server
      end

      # Set SSL enabled flag
      #
      # @param value [Boolean] Enable SSL
      def ssl=(value)
        @server.class.set :ssl, value

        # If SSL is enabled, ensure we have the Rack::SSL middleware
        if value && !@server.class.middleware.any? { |m| m[0] == Rack::SSL }
          require 'rack/ssl'
          @server.class.use Rack::SSL
        end
      end

      # Set SSL options
      #
      # @param options [Hash] SSL configuration
      # @option options [String] :cert_chain_file Path to certificate
      # @option options [String] :private_key_file Path to private key
      # @option options [Boolean] :verify_peer Verify peer certificates
      # @option options [String] :verify_client_cert Path to client certificate
      # @option options [String] :ssl_cipher_list Cipher list
      # @option options [Integer] :ssl_version SSL version
      def ssl_options=(options)
        # Store the original options for Thin
        @server.class.set :ssl_options, options

        # Translate Thin SSL options to Rack::SSL options
        rack_ssl_options = {}

        # Map certificate paths
        if options[:cert_chain_file]
          rack_ssl_options[:cert_file] = options[:cert_chain_file]
        end

        if options[:private_key_file]
          rack_ssl_options[:key_file] = options[:private_key_file]
        end

        # Map verification options
        if options[:verify_peer]
          rack_ssl_options[:verify_peer] = options[:verify_peer]
        end

        # Set the Rack::SSL options
        @server.class.set :rack_ssl_options, rack_ssl_options

        # Configure Rack::SSL middleware with our options
        if @server.class.settings.ssl && !rack_ssl_options.empty?
          # Remove any existing Rack::SSL middleware
          @server.class.middleware.reject! { |m| m[0] == Rack::SSL }

          # Add Rack::SSL with our options
          require 'rack/ssl'
          @server.class.use Rack::SSL, rack_ssl_options
        end
      end
    end
  end
end