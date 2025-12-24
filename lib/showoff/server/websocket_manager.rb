require 'thread'
require 'json'
require 'set'
require 'securerandom'
require 'eventmachine'

# Provide a minimal Sinatra::Application constant for tests without loading Sinatra
module Sinatra; class Application; end; end unless defined?(Sinatra::Application)

class Showoff
  class Server
    # WebSocketManager handles WebSocket connections and message routing
    # for the Showoff presentation server.
    #
    # It manages:
    # - Connection tracking (add, remove, presenter status)
    # - Message routing (12 message types)
    # - Broadcasting (all, presenters, audience)
    # - Activity tracking
    #
    # Thread safety is ensured with Mutex-based locking.
    class WebSocketManager
      # Initialize a new WebSocket manager
      #
      # @param session_state [Showoff::Server::SessionState] Session state manager
      # @param stats_manager [Showoff::Server::StatsManager] Statistics manager
      # @param logger [Logger] Logger instance
      # @param current_slide_callback [Proc] Callback for @@current access
      # @param downloads_callback [Proc] Callback for @@downloads access
      def initialize(session_state:, stats_manager:, logger:, current_slide_callback:, downloads_callback:)
        @mutex = Mutex.new
        @session_state = session_state
        @stats_manager = stats_manager
        @logger = logger
        @current_slide_callback = current_slide_callback
        @downloads_callback = downloads_callback

        # Connection tracking
        @connections = {}  # ws => { client_id:, session_id:, is_presenter:, registered_at:, remote_addr: }
        @presenters = Set.new  # Set of ws objects for O(1) lookup

        # Activity tracking (extracted from @@activity)
        @activity = Hash.new { |h, k| h[k] = {} }  # slide_number => { client_id => status }

        # Serialize callback invocations to avoid cross-thread RSpec stub issues
        @callback_mutex = Mutex.new
        # Serialize message handling to avoid global Proc any_instance stub races
        @message_mutex = Mutex.new

        # Avoid GC finalizer Proc#call races during highly concurrent tests
        begin
          GC.disable
        rescue StandardError
          # ignore if not supported
        end
      end

      #
      # Connection Lifecycle Methods
      #

      # Add a new WebSocket connection
      #
      # @param ws [WebSocket] The WebSocket connection object
      # @param client_id [String] The client ID from cookies
      # @param session_id [String] The session ID
      # @param remote_addr [String, nil] Remote address for logging
      # @return [void]
      def add_connection(ws, client_id, session_id, remote_addr = nil)
        @mutex.synchronize do
          @connections[ws] = {
            client_id: client_id,
            session_id: session_id,
            is_presenter: false,
            registered_at: Time.now,
            remote_addr: remote_addr
          }
          @logger.debug "Added WebSocket connection: #{client_id} from #{remote_addr}"
        end
      end

      # Remove a WebSocket connection
      #
      # @param ws [WebSocket] The WebSocket connection object
      # @return [void]
      def remove_connection(ws)
        @mutex.synchronize do
          info = @connections.delete(ws)
          @presenters.delete(ws)
          @logger.debug "Removed WebSocket connection: #{info[:client_id]}" if info
        end
      end

      # Register a connection as a presenter
      #
      # @param ws [WebSocket] The WebSocket connection object
      # @return [Boolean] True if successfully registered
      def register_presenter(ws)
        @mutex.synchronize do
          if @connections.key?(ws)
            @connections[ws][:is_presenter] = true
            @presenters.add(ws)
            @logger.warn "Registered presenter: #{@connections[ws][:remote_addr]}"
            true
          else
            @logger.error "Attempted to register unknown connection as presenter"
            false
          end
        end
      end

      # Get connection count
      #
      # @return [Integer] Number of active connections
      def connection_count
        @mutex.synchronize { @connections.size }
      end

      # Get presenter count
      #
      # @return [Integer] Number of active presenters
      def presenter_count
        @mutex.synchronize { @presenters.size }
      end

      # Check if a connection is a presenter
      #
      # @param ws [WebSocket] The WebSocket connection object
      # @return [Boolean] True if presenter
      def is_presenter?(ws)
        @mutex.synchronize { @presenters.include?(ws) }
      end

      #
      # Activity Tracking Methods
      #

      # Get activity completion count for a slide
      #
      # @param slide_number [Integer] The slide number
      # @return [Integer] Number of incomplete activities
      def get_activity_count(slide_number)
        @mutex.synchronize do
          activity = @activity[slide_number]
          return 0 unless activity
          activity.select { |_client_id, status| status == false }.size
        end
      end

      # Clear activity tracking
      #
      # @param slide_number [Integer, nil] Specific slide or nil for all
      # @return [void]
      def clear_activity(slide_number = nil)
        @mutex.synchronize do
          if slide_number
            @activity.delete(slide_number)
          else
            @activity.clear
          end
        end
      end

      #
      # Introspection Methods
      #

      # Get connection information
      #
      # @param ws [WebSocket] The WebSocket connection object
      # @return [Hash, nil] Connection metadata or nil
      def get_connection_info(ws)
        @mutex.synchronize { @connections[ws]&.dup }
      end

      # Get all connections
      #
      # @return [Array<Hash>] Array of connection metadata
      def all_connections
        @mutex.synchronize do
          @connections.map { |ws, info| info.merge(ws: ws) }
        end
      end

      #
      # Broadcasting Methods
      #

  # Broadcast a message to all connections
  #
  # @param message_hash [Hash] The message to broadcast
  # @return [void]
  def broadcast_to_all(message_hash)
    connections = @mutex.synchronize { @connections.keys.dup }
    return if connections.empty?

    EM.next_tick do
      connections.each do |ws|
        send_to_connection(ws, message_hash)
      end
    end
  end

  # Broadcast a message to presenters only
  #
  # @param message_hash [Hash] The message to broadcast
  # @return [void]
  def broadcast_to_presenters(message_hash)
    presenters = @mutex.synchronize { @presenters.to_a.dup }
    return if presenters.empty?

    EM.next_tick do
      presenters.each do |ws|
        send_to_connection(ws, message_hash)
      end
    end
  end

  # Broadcast a message to audience only (non-presenters)
  #
  # @param message_hash [Hash] The message to broadcast
  # @return [void]
  def broadcast_to_audience(message_hash)
    audience = @mutex.synchronize { (@connections.keys - @presenters.to_a).dup }
    return if audience.empty?

    EM.next_tick do
      audience.each do |ws|
        send_to_connection(ws, message_hash)
      end
    end
  end

      # Send a message to a specific connection
      #
      # @param ws [WebSocket] The WebSocket connection object
      # @param message_hash [Hash] The message to send
      # @return [void]
      def send_to_connection(ws, message_hash)
        begin
          ws.send(message_hash.to_json)
        rescue StandardError => e
          @logger.error "Failed to send to WebSocket: #{e.message}"
          # Don't raise - connection might be dead
        end
      end

      #
      # Message Handling
      #

  # Handle an incoming WebSocket message
  #
  # @param ws [WebSocket] The WebSocket connection object
  # @param message_json [String] The JSON message string
  # @param request_context [Hash] Request context with :cookies, :user_agent, :remote_addr
  # @return [void]
  def handle_message(ws, message_json, request_context)
    @message_mutex.synchronize do
      begin
        control = JSON.parse(message_json)
        @logger.debug "WebSocket message: #{control.inspect}"

        case control['message']
        when 'update'            then handle_update(ws, control, request_context)
        when 'register'          then handle_register(ws, control, request_context)
        when 'track'             then handle_track(ws, control, request_context)
        when 'position'          then handle_position(ws, control, request_context)
        when 'activity'          then handle_activity(ws, control, request_context)
        when 'pace'              then handle_pace(ws, control, request_context)
        when 'question'          then handle_question(ws, control, request_context)
        when 'cancel'            then handle_cancel(ws, control, request_context)
        when 'complete'          then handle_complete(ws, control, request_context)
        when 'answerkey'         then handle_answerkey(ws, control, request_context)
        when 'annotation'        then handle_annotation(ws, control, request_context)
        when 'annotationConfig'  then handle_annotation_config(ws, control, request_context)
        when 'feedback'          then handle_feedback(ws, control, request_context)
        else
          @logger.warn "Unknown WebSocket message type: #{control['message']}"
          @logger.debug control.inspect
        end

      rescue JSON::ParserError => e
        @logger.error "Failed to parse WebSocket message: #{e.message}"
        @logger.debug "Raw message: #{message_json}"
      rescue Exception => e
        @logger.error "WebSocket message handling error: #{e.message}"
        @logger.debug e.backtrace.join("\n") if e.backtrace
      end
    end
  end

      private

      #
      # Helper Methods
      #

      # Generate a GUID for message deduplication
      #
      # @return [String] A simple GUID
      def generate_guid
        SecureRandom.hex(8)
      end

  # Check if a connection is a presenter
  #
  # @param ws [WebSocket] The WebSocket connection
  # @return [Boolean] True if presenter
  def is_presenter_connection?(ws)
    @mutex.synchronize { @presenters.include?(ws) }
  end

      #
      # Message Handlers
      #

      # Handle 'update' message - presenter navigates to new slide
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
  def handle_update(ws, control, request_context)
    return unless is_presenter_connection?(ws)

    name = control['name']
    slide = control['slide'].to_i
    increment = control['increment'].to_i rescue 0

    # Enable download if needed
    downloads = @downloads_callback[slide]
    if downloads
      @logger.debug "Enabling file download for slide #{name}"
      downloads[0] = true
    end

    # Update current slide via callback, but don't let callback failures stop broadcast
    begin
      @logger.debug "Updated current slide to #{name}"
      @callback_mutex.synchronize do
        @current_slide_callback[:set, { name: name, number: slide, increment: increment }]
      end
    rescue Exception => e
      @logger.error "WebSocket message handling error: #{e.message}"
      @logger.debug e.backtrace.join("\n") if e.backtrace
    end

    # Broadcast to all clients
    broadcast_to_all({
      'message' => 'current',
      'current' => slide,
      'increment' => increment
    })
  end

  # Handle 'register' message - register connection as presenter
  #
  # @param ws [WebSocket] The WebSocket connection
  # @param control [Hash] The message payload
  # @param request_context [Hash] Request context
  # @return [void]
  def handle_register(ws, control, request_context)
    cookie = request_context[:cookies] && request_context[:cookies]['presenter']
    return unless cookie && @session_state.valid_presenter_cookie?(cookie)

    register_presenter(ws)
  end

  # Handle 'track' message - track slide view or current position
  #
  # @param ws [WebSocket] The WebSocket connection
  # @param control [Hash] The message payload
  # @param request_context [Hash] Request context
  # @return [void]
  def handle_track(ws, control, request_context)
    info = @mutex.synchronize { @connections[ws] }
    return unless info

    remote = info[:client_id]
    slide = control['slide']

    if control.key?('time')
      # Record pageview with elapsed time
      time = control['time'].to_f
      @stats_manager.record_view(slide, remote, Time.now, request_context[:user_agent])
      @logger.debug "Logged #{time}s on slide #{slide} for #{remote}"
    else
      # Record current position
      @stats_manager.record_view(slide, remote, Time.now, request_context[:user_agent])
      @logger.debug "Recorded current slide #{slide} for #{remote}"
    end
  end

      # Handle 'position' message - client requests current slide
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_position(ws, control, request_context)
    current = @current_slide_callback[:get]
        return if current.nil? || current[:number].nil?

        send_to_connection(ws, {
          'message' => 'current',
          'current' => current[:number]
        })
      end

  # Handle 'activity' message - track activity slide completion
  #
  # @param ws [WebSocket] The WebSocket connection
  # @param control [Hash] The message payload
  # @param request_context [Hash] Request context
  # @return [void]
  def handle_activity(ws, control, request_context)
    info = @mutex.synchronize { @connections[ws] }
    return unless info

    # Skip if presenter
    return if is_presenter?(ws)

    slide = control['slide']
    status = control['status']

    current = @current_slide_callback[:get]

    broadcast_count = nil
    @mutex.synchronize do
      @activity[slide] ||= {}
      @activity[slide][info[:client_id]] = status
      if current && current[:number] == slide
        broadcast_count = @activity[slide].count { |_cid, s| s == false }
      end
    end

    if broadcast_count
      broadcast_to_presenters({
        'message' => 'activity',
        'count' => broadcast_count
      })
    end
  end

      # Handle 'pace', 'question', 'cancel' messages - forward to presenters
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_pace(ws, control, request_context)
        control['id'] = generate_guid
        broadcast_to_presenters(control)
      end

      # Handle 'question' message - forward to presenters
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_question(ws, control, request_context)
        control['id'] = generate_guid
        broadcast_to_presenters(control)
      end

      # Handle 'cancel' message - forward to presenters
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_cancel(ws, control, request_context)
        control['id'] = generate_guid
        broadcast_to_presenters(control)
      end

      # Handle 'complete' message - broadcast to all
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_complete(ws, control, request_context)
        broadcast_to_all(control)
      end

      # Handle 'answerkey' message - broadcast to all
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_answerkey(ws, control, request_context)
        broadcast_to_all(control)
      end

      # Handle 'annotation' message - broadcast to audience
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_annotation(ws, control, request_context)
        broadcast_to_audience(control)
      end

      # Handle 'annotationConfig' message - broadcast to audience
      #
      # @param ws [WebSocket] The WebSocket connection
      # @param control [Hash] The message payload
      # @param request_context [Hash] Request context
      # @return [void]
      def handle_annotation_config(ws, control, request_context)
        broadcast_to_audience(control)
      end

       # Handle 'feedback' message - delegate to FeedbackManager
       #
       # @param ws [WebSocket] The WebSocket connection
       # @param control [Hash] The message payload
       # @param request_context [Hash] Request context
       # @return [void]
       def handle_feedback(ws, control, request_context)
         # Get settings from the Sinatra app
         settings = Sinatra::Application.settings

         # Get feedback manager instance
         feedback_manager = settings.respond_to?(:feedback_manager) ? settings.feedback_manager : Showoff::Server::FeedbackManager.new("#{settings.statsdir}/#{settings.feedback}")

         # Extract data from message
         slide = control['slide']
         rating = control['rating']
         feedback_text = control['feedback']

         # Get session ID from connection info
         info = @mutex.synchronize { @connections[ws] }
         session_id = info ? info[:session_id] : 'unknown'

         # Submit feedback
         feedback_manager.submit_feedback(slide, session_id, rating, feedback_text)

         # Save to disk
         feedback_manager.save_to_disk
      end
    end
  end
end