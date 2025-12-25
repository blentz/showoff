require 'showoff/server'

# ServerAdapter provides a compatibility layer between the CLI and the Showoff::Server class.
# It handles the transition from the legacy monolithic architecture to the new modular design.
#
# @example
#   Showoff::ServerAdapter.run!(pres_dir: '.', port: 9090) do |server|
#     server.ssl = true
#     server.ssl_options = {...}
#   end
class Showoff::ServerAdapter
  # SSL configuration shim for Thin server
  class SSLShim
    attr_accessor :ssl, :ssl_options
  end

  # Run the Showoff server with the given options
  #
  # @param options [Hash] Configuration options
  # @option options [String] :pres_dir Presentation directory
  # @option options [String] :pres_file Configuration file (default: showoff.json)
  # @option options [Boolean] :verbose Enable verbose logging
  # @option options [Boolean] :execute Enable code execution
  # @option options [Boolean] :review Enable code review
  # @option options [Boolean] :standalone Run in standalone mode
  # @option options [Boolean] :nocache Disable content caching
  # @option options [String] :host Bind host (default: localhost)
  # @option options [Integer] :port Port number (default: 9090)
  # @option options [Boolean] :ssl Run via HTTPS
  # @option options [String] :ssl_certificate Path to SSL certificate
  # @option options [String] :ssl_private_key Path to SSL private key
  # @yield [ssl_shim] Block to configure SSL options
  # @yieldparam ssl_shim [SSLShim] SSL configuration shim
  def self.run!(options = {})
    # Normalize options
    options = {
      pres_dir: options[:pres_dir] || '.',
      pres_file: options[:f] || options[:file] || options[:pres_file] || 'showoff.json',
      verbose: options[:v] || options[:verbose] || false,
      execute: options[:x] || options[:execute] || options[:executecode] || false,
      review: options[:r] || options[:review] || false,
      standalone: options[:S] || options[:standalone] || false,
      nocache: options[:nocache] || false,
      host: options[:h] || options[:host] || options[:bind] || 'localhost',
      port: options[:p] || options[:port] || 9090
    }

    # Create server instance
    server = Showoff::Server.new(options)

    # Configure SSL if block given
    if block_given?
      ssl_shim = SSLShim.new
      yield ssl_shim

      # Apply SSL configuration to server if provided
      if ssl_shim.ssl
        server.class.set :ssl, ssl_shim.ssl
        server.class.set :ssl_options, ssl_shim.ssl_options
      end
    end

    # Run the server
    server.run!
  end
end