require 'thread'

# Thread-safe session state management for Showoff server.
#
# Replaces legacy class variables:
# - @@cookie (presenter session token)
# - @@master (master presenter client ID)
# - @@current (current slide state per session)
#
# @example
#   sessions = Showoff::Server::SessionState.new
#   sessions.set_presenter_session('abc123')
#   sessions.is_presenter?('abc123') # => true
class Showoff::Server::SessionState
  # Initialize a new session state manager
  def initialize
    @mutex = Mutex.new
    @sessions = {}  # session_id => session_data
    @presenter_token = nil
    @master_presenter_id = nil
    @presenter_cookie = nil
  end

  # Set the presenter session token.
  #
  # @param token [String] The presenter session token
  # @return [String] The token
  def set_presenter_token(token)
    @mutex.synchronize do
      @presenter_token = token
    end
  end

  # Get the current presenter token.
  #
  # @return [String, nil] The presenter token
  def presenter_token
    @mutex.synchronize { @presenter_token }
  end

  # Check if a session is the presenter.
  #
  # @param session_id [String] The session ID to check
  # @return [Boolean] True if this session is the presenter
  def is_presenter?(session_id)
    @mutex.synchronize do
      @presenter_token && session_id == @presenter_token
    end
  end

  # Set the master presenter client ID.
  #
  # @param client_id [String] The WebSocket client ID
  # @return [String] The client ID
  def set_master_presenter(client_id)
    @mutex.synchronize do
      @master_presenter_id = client_id
    end
  end

  # Get the master presenter client ID.
  #
  # @return [String, nil] The master presenter client ID
  def master_presenter
    @mutex.synchronize { @master_presenter_id }
  end

  # Check if a client is the master presenter.
  #
  # @param client_id [String] The WebSocket client ID to check
  # @return [Boolean] True if this is the master presenter
  def is_master_presenter?(client_id)
    @mutex.synchronize do
      @master_presenter_id && client_id == @master_presenter_id
    end
  end

  # Set the current slide for a session.
  #
  # @param session_id [String] The session ID
  # @param slide_number [Integer] The slide number (0-indexed)
  # @return [Integer] The slide number
  def set_current_slide(session_id, slide_number)
    @mutex.synchronize do
      @sessions[session_id] ||= {}
      @sessions[session_id][:current_slide] = slide_number.to_i
    end
  end

  # Get the current slide for a session.
  #
  # @param session_id [String] The session ID
  # @return [Integer, nil] The current slide number
  def get_current_slide(session_id)
    @mutex.synchronize do
      @sessions.dig(session_id, :current_slide)
    end
  end

  # Set follow mode for a session.
  #
  # @param session_id [String] The session ID
  # @param enabled [Boolean] Whether follow mode is enabled
  # @return [Boolean] The enabled state
  def set_follow_mode(session_id, enabled)
    @mutex.synchronize do
      @sessions[session_id] ||= {}
      @sessions[session_id][:follow_mode] = !!enabled
    end
  end

  # Check if a session is in follow mode.
  #
  # @param session_id [String] The session ID
  # @return [Boolean] True if following presenter
  def following?(session_id)
    @mutex.synchronize do
      @sessions.dig(session_id, :follow_mode) || false
    end
  end

  # Get session data for a session.
  #
  # @param session_id [String] The session ID
  # @return [Hash, nil] The session data
  def get_session(session_id)
    @mutex.synchronize do
      @sessions[session_id]&.dup
    end
  end

  # Clear a session.
  #
  # @param session_id [String] The session ID
  # @return [void]
  def clear_session(session_id)
    @mutex.synchronize do
      @sessions.delete(session_id)
    end
  end

  # Clear all sessions.
  #
  # @return [void]
  def clear_all
    @mutex.synchronize do
      @sessions.clear
      @presenter_token = nil
      @master_presenter_id = nil
    end
  end

  # Get count of active sessions.
  #
  # @return [Integer] The number of active sessions
  def count
    @mutex.synchronize { @sessions.size }
  end

  # Get all session IDs.
  #
  # @return [Array<String>] All active session IDs
  def all_session_ids
    @mutex.synchronize { @sessions.keys.dup }
  end

  # Generate a GUID for client identification
  #
  # @return [String] A simple GUID
  def generate_guid
    (0..15).to_a.map{|a| rand(16).to_s(16)}.join
  end

  # Register a presenter and set up cookies
  #
  # @param client_id [String] The client ID to register as presenter
  # @return [void]
  def register_presenter(client_id)
    @mutex.synchronize do
      # Generate a presenter cookie if we don't have one
      @presenter_cookie ||= generate_guid

      # Set the master presenter if we don't have one
      @master_presenter_id ||= client_id
    end
  end

  # Get the presenter cookie
  #
  # @return [String, nil] The presenter cookie
  def presenter_cookie
    @mutex.synchronize { @presenter_cookie }
  end

  # Check if a presenter cookie is valid
  #
  # @param cookie [String] The presenter cookie to check
  # @return [Boolean] True if the cookie is valid
  def valid_presenter_cookie?(cookie)
    return false if cookie.nil?
    @mutex.synchronize { cookie == @presenter_cookie }
  end

  # Check if a client is the master presenter
  #
  # @param client_id [String] The client ID to check
  # @return [Boolean] True if this is the master presenter
  def master_presenter?(client_id)
    @mutex.synchronize { client_id == @master_presenter_id }
  end
end
