# frozen_string_literal: true

require 'thread'
require 'json'
require 'fileutils'
require 'time'

class Showoff
  class Server
    # Thread-safe feedback manager for Showoff server.
    #
    # Replaces legacy feedback handling in showoff.rb (lines 1931-1951).
    #
    # Stores slide feedback with ratings (1-5) and optional text comments.
    # Tracks session IDs and timestamps for analytics.
    #
    # @example
    #   feedback = Showoff::Server::FeedbackManager.new
    #   feedback.submit_feedback('slide1', 'session123', 5, 'Great!')
    #   feedback.get_slide_rating_average('slide1') # => 5.0
    class FeedbackManager
      # Initialize a new feedback manager
      #
      # @param persistence_file [String] Path to JSON file for persistence
      def initialize(persistence_file = 'stats/feedback.json')
        @mutex = Mutex.new
        @persistence_file = persistence_file
        @feedback = Hash.new { |h, k| h[k] = [] }  # slide_id => [entries]

        load_from_disk if File.exist?(@persistence_file)
      end

      # Submit feedback for a slide.
      #
      # @param slide_id [String] The slide identifier
      # @param session_id [String] The session ID
      # @param rating [Integer] Rating from 1-5
      # @param feedback_text [String, nil] Optional text feedback
      # @param timestamp [Time] The submission timestamp (defaults to now)
      # @return [Hash] The stored feedback entry
      # @raise [ArgumentError] If slide_id, session_id nil or rating invalid
      # @thread_safe
      def submit_feedback(slide_id, session_id, rating, feedback_text = nil, timestamp = Time.now)
        @mutex.synchronize do
          # Validation
          raise ArgumentError, "slide_id cannot be nil" if slide_id.nil?
          raise ArgumentError, "session_id cannot be nil" if session_id.nil?
          raise ArgumentError, "rating must be Integer 1-5" unless (1..5).include?(rating.to_i)

          # Convert rating to integer
          rating = rating.to_i

          # Allow nil or empty feedback_text
          feedback_text = feedback_text.to_s.empty? ? nil : feedback_text

          # Store entry
          entry = {
            session_id: session_id,
            rating: rating,
            feedback: feedback_text,
            timestamp: timestamp
          }

          @feedback[slide_id] << entry
          entry.dup
        end
      end

      # Get all feedback for a specific slide.
      #
      # @param slide_id [String] The slide identifier
      # @return [Array<Hash>] All feedback entries for this slide
      # @thread_safe
      def get_feedback(slide_id)
        @mutex.synchronize do
          @feedback[slide_id].map(&:dup)
        end
      end

      # Get all feedback across all slides.
      #
      # @return [Hash] Hash of slide_id => [feedback_entries]
      # @thread_safe
      def get_all_feedback
        @mutex.synchronize do
          result = {}
          @feedback.each do |slide_id, entries|
            result[slide_id] = entries.map(&:dup)
          end
          result
        end
      end

      # Get aggregated statistics for a slide.
      #
      # @param slide_id [String] The slide identifier
      # @return [Hash] Aggregated stats (average, distribution, count)
      # @thread_safe
      def get_aggregated(slide_id)
        @mutex.synchronize do
          entries = @feedback[slide_id]
          return { count: 0, average: nil, distribution: {} } if entries.empty?

          {
            count: entries.size,
            average: calculate_average_unsafe(slide_id),
            distribution: calculate_distribution_unsafe(slide_id)
          }
        end
      end

      # Get average rating for a slide.
      #
      # @param slide_id [String] The slide identifier
      # @return [Float, nil] Average rating or nil if no feedback
      # @thread_safe
      def get_slide_rating_average(slide_id)
        @mutex.synchronize do
          calculate_average_unsafe(slide_id)
        end
      end

      # Get feedback count.
      #
      # @param slide_id [String, nil] Specific slide or nil for total
      # @return [Integer] Number of feedback entries
      # @thread_safe
      def feedback_count(slide_id = nil)
        @mutex.synchronize do
          if slide_id
            @feedback[slide_id].size
          else
            @feedback.values.sum(&:size)
          end
        end
      end

      # Get all slide IDs with feedback.
      #
      # @return [Array<String>] All slide IDs
      # @thread_safe
      def slide_ids
        @mutex.synchronize do
          @feedback.keys
        end
      end

      # Export feedback to JSON file.
      #
      # @return [void]
      # @thread_safe
      def export_json
        @mutex.synchronize do
          FileUtils.mkdir_p(File.dirname(@persistence_file))

          # Serialize Time objects to ISO8601
          serialized_feedback = {}
          @feedback.each do |slide_id, entries|
            serialized_feedback[slide_id] = entries.map do |e|
              {
                'session_id' => e[:session_id],
                'rating' => e[:rating],
                'feedback' => e[:feedback],
                'timestamp' => e[:timestamp].iso8601
              }
            end
          end

          data = {
            'feedback' => serialized_feedback,
            'exported_at' => Time.now.iso8601
          }

          # Atomic write: temp file + rename
          temp_file = "#{@persistence_file}.tmp"
          File.write(temp_file, JSON.pretty_generate(data))
          File.rename(temp_file, @persistence_file)
        end
      end

      # Load feedback from JSON file.
      #
      # @return [void]
      # @thread_safe
      def load_from_disk
        @mutex.synchronize do
          return unless File.exist?(@persistence_file)

          begin
            data = JSON.parse(File.read(@persistence_file))

            # Reset
            @feedback = Hash.new { |h, k| h[k] = [] }

            # Check for legacy format
            if data['feedback']
              # New format
              data['feedback'].each do |slide_id, entries|
                @feedback[slide_id] = entries.map do |e|
                  {
                    session_id: e['session_id'],
                    rating: e['rating'].to_i,
                    feedback: e['feedback'],
                    timestamp: Time.parse(e['timestamp'].to_s)
                  }
                end
              end
            else
              # Legacy format - migrate
              migrate_legacy_format(data)
            end

          rescue JSON::ParserError => e
            Kernel.warn "Failed to load feedback from #{@persistence_file}: Invalid JSON - #{e.message}"
            @feedback.clear
          rescue StandardError => e
            Kernel.warn "Failed to load feedback from #{@persistence_file}: #{e.message}"
            @feedback.clear
          end
        end
      end

      # Save to disk (alias for export_json).
      #
      # @return [void]
      def save_to_disk
        export_json
      end

      # Clear feedback.
      #
      # @param slide_id [String, nil] Specific slide or nil for all
      # @return [void]
      # @thread_safe
      def clear(slide_id = nil)
        @mutex.synchronize do
          if slide_id
            @feedback.delete(slide_id)
          else
            @feedback.clear
          end
        end
      end

      # Get feedback in legacy format for migration.
      #
      # @return [Hash] Legacy format (slide_id => [{rating:, feedback:}])
      # @thread_safe
      def legacy_format
        @mutex.synchronize do
          result = {}
          @feedback.each do |slide_id, entries|
            result[slide_id] = entries.map do |e|
              {
                'rating' => e[:rating],
                'feedback' => e[:feedback]
              }
            end
          end
          result
        end
      end

      private

      # Calculate average rating (internal, assumes mutex held).
      #
      # @param slide_id [String] The slide identifier
      # @return [Float, nil] Average rating
      def calculate_average_unsafe(slide_id)
        entries = @feedback[slide_id]
        return nil if entries.empty?

        sum = entries.sum { |e| e[:rating] }
        sum.to_f / entries.size
      end

      # Calculate rating distribution (internal, assumes mutex held).
      #
      # @param slide_id [String] The slide identifier
      # @return [Hash] Rating => count
      def calculate_distribution_unsafe(slide_id)
        distribution = Hash.new(0)
        @feedback[slide_id].each do |entry|
          distribution[entry[:rating]] += 1
        end
        distribution
      end

      # Migrate legacy format data.
      #
      # @param data [Hash] Legacy format data
      # @return [void]
      def migrate_legacy_format(data)
        file_mtime = File.mtime(@persistence_file)

        data.each do |slide_id, entries|
          @feedback[slide_id] = entries.map do |e|
            {
              session_id: 'unknown',
              rating: e['rating'].to_i,
              feedback: e['feedback'],
              timestamp: file_mtime
            }
          end
        end

        Kernel.warn "Migrated legacy feedback format from #{@persistence_file}"
      end
    end
  end
end