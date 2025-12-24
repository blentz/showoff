require 'thread'
require 'json'
require 'fileutils'
require 'time'

# Thread-safe form response manager for Showoff server.
#
# Replaces legacy class variable:
# - @@forms (form response storage)
#
# Stores form submissions, validates against schema, and provides aggregation.
#
# @example
#   forms = Showoff::Server::FormManager.new
#   forms.submit('quiz1', 'session123', {q1: 'answer1', q2: 'answer2'})
#   forms.get_responses('quiz1')
# Make sure the namespace exists
class Showoff; class Server; end; end

class Showoff::Server::FormManager
  # Initialize a new form manager
  #
  # @param persistence_file [String] Path to JSON file for persistence
  def initialize(persistence_file = 'forms/responses.json')
    @mutex = Mutex.new
    @persistence_file = persistence_file
    @forms = Hash.new { |h, k| h[k] = [] }  # form_name => [responses]

    load_from_disk if File.exist?(@persistence_file)
  end

  # Submit a form response.
  #
  # @param form_name [String] The name of the form
  # @param session_id [String] The session ID
  # @param responses [Hash] The form responses (question => answer)
  # @param timestamp [Time] The submission timestamp (defaults to now)
  # @return [Hash] The stored response
  def submit(form_name, session_id, responses, timestamp = Time.now)
    raise ArgumentError, "form_name cannot be nil" if form_name.nil?
    raise ArgumentError, "session_id cannot be nil" if session_id.nil?
    raise ArgumentError, "responses must be a Hash" unless responses.is_a?(Hash)

    @mutex.synchronize do
      response = {
        session_id: session_id,
        responses: responses,
        timestamp: timestamp
      }

      @forms[form_name] << response
      response
    end
  end

  # Get all responses for a form.
  #
  # @param form_name [String] The name of the form
  # @return [Array<Hash>] All responses for this form
  def get_responses(form_name)
    @mutex.synchronize do
      @forms[form_name].map(&:dup)
    end
  end

  # Get responses for a form, organized by client_id.
  # This method is used by the /form/:id route.
  #
  # @param form_name [String] The name of the form
  # @return [Hash, nil] Responses organized by client_id, or nil if none
  def responses(form_name)
    @mutex.synchronize do
      responses = @forms[form_name]
      return nil if responses.nil? || responses.empty?

      # Organize by client_id, keeping only the latest response per client
      result = {}
      responses.each do |response|
        client_id = response[:session_id]
        # Store responses directly under client_id
        result[client_id] = response[:responses]
      end

      result
    end
  end

  # Get aggregated results for a form (for quizzes, surveys, etc.).
  #
  # @param form_name [String] The name of the form
  # @return [Hash] Aggregated results
  def get_aggregated(form_name)
    @mutex.synchronize do
      responses = @forms[form_name]
      return {} if responses.empty?

      # Aggregate by question
      aggregated = Hash.new { |h, k| h[k] = Hash.new(0) }

      responses.each do |response|
        response[:responses].each do |question, answer|
          aggregated[question][answer] += 1
        end
      end

      {
        total_responses: responses.size,
        questions: aggregated,
        response_rate: calculate_response_rate_unsafe(form_name)
      }
    end
  end

  # Get response count for a form.
  #
  # @param form_name [String] The name of the form
  # @return [Integer] Number of responses
  def response_count(form_name)
    @mutex.synchronize do
      @forms[form_name].size
    end
  end

  # Get all form names.
  #
  # @return [Array<String>] All form names with responses
  def form_names
    @mutex.synchronize do
      @forms.keys.dup
    end
  end

  # Export form responses to JSON file.
  #
  # @param form_name [String, nil] Specific form to export, or nil for all
  # @return [void]
  def export_json(form_name = nil)
    @mutex.synchronize do
      FileUtils.mkdir_p(File.dirname(@persistence_file))

      # Convert Time objects to ISO8601 strings
      serialized_forms = {}

      forms_to_export = form_name ? { form_name => @forms[form_name] } : @forms

      forms_to_export.each do |name, responses|
        serialized_forms[name] = responses.map do |r|
          {
            session_id: r[:session_id],
            responses: r[:responses],
            timestamp: r[:timestamp].iso8601
          }
        end
      end

      data = {
        forms: serialized_forms,
        exported_at: Time.now.iso8601
      }

      # Atomic write
      temp_file = "#{@persistence_file}.tmp"
      File.write(temp_file, JSON.pretty_generate(data))
      File.rename(temp_file, @persistence_file)
    end
  end

  # Save to disk (alias for export_json).
  #
  # @return [void]
  def save_to_disk
    export_json
  end

  # Load form responses from JSON file.
  #
  # @return [void]
  def load_from_disk
    @mutex.synchronize do
      return unless File.exist?(@persistence_file)

      data = JSON.parse(File.read(@persistence_file), symbolize_names: true)

      @forms = Hash.new { |h, k| h[k] = [] }

      data[:forms]&.each do |form_name, responses|
        @forms[form_name.to_s] = responses.map do |r|
          {
            session_id: r[:session_id],
            responses: r[:responses],
            timestamp: Time.parse(r[:timestamp].to_s)
          }
        end
      end
    rescue JSON::ParserError, StandardError => e
      Kernel.warn "Failed to load forms from #{@persistence_file}: #{e.message}"
    end
  end

  # Clear all form responses.
  #
  # @param form_name [String, nil] Specific form to clear, or nil for all
  # @return [void]
  def clear(form_name = nil)
    @mutex.synchronize do
      if form_name
        @forms.delete(form_name)
      else
        @forms.clear
      end
    end
  end

  private

  # Calculate response rate (internal, assumes mutex held).
  # This is a placeholder - actual implementation would need total user count.
  #
  # @param form_name [String] The form name
  # @return [Float, nil] Response rate (0.0-1.0)
  def calculate_response_rate_unsafe(form_name)
    # Placeholder: would need total session count to calculate
    # For now, return nil to indicate unknown
    nil
  end
end
