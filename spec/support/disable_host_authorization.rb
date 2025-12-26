# ULTRA NUCLEAR OPTION: Completely disable Sinatra 4.x host_authorization middleware
# This file contains an extremely aggressive fix for Sinatra 4.x host_authorization middleware
# which was added to address CVE-2024-21510 (https://nvd.nist.gov/vuln/detail/CVE-2024-21510)
#
# In test environments, the host_authorization middleware causes issues because
# Rack::Test doesn't always set the Host header correctly, and configuration-based
# approaches to disable it have proven unreliable.
#
# This ultra nuclear option:
# 1. Directly monkey patches Sinatra::HostAuthorization to ALWAYS PASS THROUGH requests
# 2. Monkey patches Sinatra::Base to PREVENT the middleware from being added
# 3. Ensures the Host header is always set to 'localhost' in Rack::Test requests
# 4. Provides a fallback middleware that bypasses any remaining host checks
# 5. Explicitly configures permitted_hosts to include localhost and 127.0.0.1
#
# WARNING: This is an extremely aggressive approach that should ONLY be used in tests.
# It completely bypasses a security feature, but that's acceptable in a test environment.

# Create a custom middleware to bypass host authorization checks in tests
class DisableHostAuthorization
  def initialize(app)
    @app = app
  end

  def call(env)
    # Set a default host header if not present
    env['HTTP_HOST'] ||= 'localhost'

    # Call the next middleware in the stack
    @app.call(env)
  end
end

# Nuclear option to completely disable host authorization in tests
module HostAuthorizationTestFixes
  def self.apply!
    # 1. ULTRA NUCLEAR OPTION: Monkey patch Sinatra::HostAuthorization itself
    # This completely neutralizes the middleware by making it always pass through
    monkey_patch_host_authorization_middleware

    # 2. NUCLEAR OPTION: Monkey patch Sinatra::Base.setup_default_middleware
    # This prevents the host_authorization middleware from being added at all
    monkey_patch_sinatra_middleware_setup

    # 3. Ensure Rack::Test uses a permitted host by default
    # Set this safely to avoid dynamic constant assignment errors
    if defined?(Rack::Test) && Rack::Test.const_defined?(:DEFAULT_HOST)
      Rack::Test.send(:remove_const, :DEFAULT_HOST)
      Rack::Test.const_set(:DEFAULT_HOST, 'localhost')
    end

    # 4. Monkey patch Rack::Test::Session to always set the Host header
    monkey_patch_rack_test

    # 5. Configure Showoff::Server with additional safeguards
    configure_showoff_server
  end

  # ULTRA NUCLEAR OPTION: Completely neutralize the host_authorization middleware
  def self.monkey_patch_host_authorization_middleware
    # Define the Sinatra::HostAuthorization class if it doesn't exist yet
    unless defined?(Sinatra::HostAuthorization)
      Sinatra.const_set(:HostAuthorization, Class.new)
    end

    # Monkey patch the class to always pass through requests
    Sinatra::HostAuthorization.class_eval do
      def initialize(app, options = {})
        @app = app
      end

      def call(env)
        # NUCLEAR OPTION: Always pass through to the next middleware
        # This completely bypasses the host authorization check
        @app.call(env)
      end
    end
  end

  # NUCLEAR OPTION: Prevent Sinatra from adding host_authorization middleware
  def self.monkey_patch_sinatra_middleware_setup
    # Only apply if Sinatra::Base responds to setup_default_middleware
    if Sinatra::Base.respond_to?(:setup_default_middleware)
      Sinatra::Base.singleton_class.class_eval do
        # Store the original method
        alias_method :original_setup_default_middleware, :setup_default_middleware

        # Override the method that sets up middleware
        def setup_default_middleware(builder)
          # Call original method to set up other middleware
          original_setup_default_middleware(builder)

          # NUCLEAR OPTION: Remove host_authorization middleware if it was added
          # This is the most aggressive approach - we directly modify the middleware stack
          if defined?(Sinatra::HostAuthorization)
            builder.middlewares.delete_if do |middleware|
              middleware.first == Sinatra::HostAuthorization
            end
          end
        end
      end
    end

    # Also monkey patch the instance method if it exists
    if Sinatra::Base.method_defined?(:setup_default_middleware)
      Sinatra::Base.class_eval do
        # Store the original instance method
        alias_method :original_setup_default_middleware, :setup_default_middleware

        # Override the instance method
        def setup_default_middleware(builder)
          # Call original method
          original_setup_default_middleware(builder)

          # Remove host_authorization middleware
          if defined?(Sinatra::HostAuthorization)
            builder.middlewares.delete_if do |middleware|
              middleware.first == Sinatra::HostAuthorization
            end
          end
        end
      end
    end
  end

  # Ensure Rack::Test always sets the Host header
  def self.monkey_patch_rack_test
    unless Rack::Test::Session.method_defined?(:original_env_for)
      Rack::Test::Session.class_eval do
        alias_method :original_env_for, :env_for

        def env_for(path, env = {})
          result = original_env_for(path, env)
          # Always set the Host header to localhost if not already set
          result["HTTP_HOST"] ||= "localhost"
          result
        end
      end
    end
  end

  # Configure Showoff::Server with additional safeguards
  def self.configure_showoff_server
    Showoff::Server.class_eval do
      # Add our custom middleware to bypass host authorization in test mode
      # This must be defined before any other middleware that might use the Host header
      use DisableHostAuthorization

      # NUCLEAR OPTION: Completely disable host_authorization in test environment
      set :host_authorization, false

      # NUCLEAR OPTION: Also disable host authorization protection in Rack::Protection
      set :protection, except: [:host_authorization]

      # NUCLEAR OPTION: Explicitly set permitted hosts to include localhost and 127.0.0.1
      # This is a belt-and-suspenders approach - even if other fixes fail, this should work
      set :host_authorization, {
        permitted_hosts: ['localhost', '127.0.0.1', '::1']
      }

      # Override the middleware setup method if it exists
      if method_defined?(:setup_middleware)
        alias_method :original_setup_middleware, :setup_middleware

        def setup_middleware(builder)
          # Call original method
          original_setup_middleware(builder)

          # Remove host_authorization middleware
          if defined?(Sinatra::HostAuthorization)
            builder.middlewares.delete_if do |middleware|
              middleware.first == Sinatra::HostAuthorization
            end
          end
        end
      end
    end
  end
end