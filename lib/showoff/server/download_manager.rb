require 'thread'

# Ensure Showoff::Server namespace exists
class Showoff
  class Server
    # This is just a placeholder to ensure the namespace exists
  end
end

# Thread-safe download manager for Showoff server.
#
# Replaces legacy class variable:
# - @@downloads (downloadable files storage)
#
# Manages downloadable files for slides, enabling/disabling them as slides are presented.
#
# @example
#   downloads = Showoff::Server::DownloadManager.new
#   downloads.register(5, 'Slide 5', ['file1.txt', 'file2.pdf'])
#   downloads.enable(5)
#   downloads.files(5) # => ['file1.txt', 'file2.pdf']
class Showoff::Server::DownloadManager
  # Initialize a new download manager
  def initialize
    @mutex = Mutex.new
    @downloads = {}  # slide_num => [enabled, name, files]
  end

  # Register downloadable files for a slide
  #
  # @param slide_num [Integer] The slide number
  # @param name [String] The slide name
  # @param files [Array<String>] The files to make available
  # @return [Array] The registered files entry [enabled, name, files]
  # @raise [ArgumentError] If parameters are invalid
  def register(slide_num, name, files)
    validate_slide_num!(slide_num)
    validate_name!(name)
    validate_files!(files)

    @mutex.synchronize do
      @downloads[slide_num] = [false, name, files.dup]
    end
  end

  # Enable downloads for a slide (when presented)
  #
  # @param slide_num [Integer] The slide number
  # @return [Boolean] True if downloads were enabled, false if slide not found
  def enable(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      if @downloads.key?(slide_num)
        @downloads[slide_num][0] = true
        true
      else
        false
      end
    end
  end

  # Disable downloads for a slide
  #
  # @param slide_num [Integer] The slide number
  # @return [Boolean] True if downloads were disabled, false if slide not found
  def disable(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      if @downloads.key?(slide_num)
        @downloads[slide_num][0] = false
        true
      else
        false
      end
    end
  end

  # Check if downloads are enabled for a slide
  #
  # @param slide_num [Integer] The slide number
  # @return [Boolean] True if downloads are enabled, false otherwise
  def enabled?(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      @downloads.dig(slide_num, 0) || false
    end
  end

  # Get the name for a slide's download section
  #
  # @param slide_num [Integer] The slide number
  # @return [String, nil] The name or nil if slide not found
  def name(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      @downloads.dig(slide_num, 1)
    end
  end

  # Get downloadable files for a slide
  #
  # @param slide_num [Integer] The slide number
  # @return [Array<String>, nil] The files or empty array if disabled/not found
  def files(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      if @downloads.key?(slide_num) && @downloads[slide_num][0]
        @downloads[slide_num][2].dup
      else
        []
      end
    end
  end

  # Get all registered downloads
  #
  # @return [Hash] All downloads (slide_num => [enabled, name, files])
  def all
    @mutex.synchronize do
      @downloads.dup
    end
  end

  # Get all enabled downloads
  #
  # @return [Hash] Enabled downloads (slide_num => [true, name, files])
  def enabled
    @mutex.synchronize do
      @downloads.select { |_, entry| entry[0] }
    end
  end

  # Add a file to an existing slide's downloads
  #
  # @param slide_num [Integer] The slide number
  # @param file [String] The file to add
  # @return [Boolean] True if file was added, false if slide not found
  # @raise [ArgumentError] If file is invalid
  def add_file(slide_num, file)
    validate_slide_num!(slide_num)
    validate_file!(file)

    @mutex.synchronize do
      if @downloads.key?(slide_num)
        @downloads[slide_num][2] << file unless @downloads[slide_num][2].include?(file)
        true
      else
        false
      end
    end
  end

  # Remove a file from a slide's downloads
  #
  # @param slide_num [Integer] The slide number
  # @param file [String] The file to remove
  # @return [Boolean] True if file was removed, false if slide or file not found
  def remove_file(slide_num, file)
    validate_slide_num!(slide_num)
    validate_file!(file)

    @mutex.synchronize do
      if @downloads.key?(slide_num) && @downloads[slide_num][2].include?(file)
        @downloads[slide_num][2].delete(file)
        true
      else
        false
      end
    end
  end

  # Check if a slide has registered downloads
  #
  # @param slide_num [Integer] The slide number
  # @return [Boolean] True if slide has registered downloads
  def has_downloads?(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      @downloads.key?(slide_num)
    end
  end

  # Get count of registered slides with downloads
  #
  # @return [Integer] Number of slides with downloads
  def count
    @mutex.synchronize do
      @downloads.size
    end
  end

  # Clear all downloads
  #
  # @return [void]
  def clear
    @mutex.synchronize do
      @downloads.clear
    end
  end

  # Clear downloads for a specific slide
  #
  # @param slide_num [Integer] The slide number
  # @return [Boolean] True if downloads were cleared, false if slide not found
  def clear_slide(slide_num)
    validate_slide_num!(slide_num)

    @mutex.synchronize do
      if @downloads.key?(slide_num)
        @downloads.delete(slide_num)
        true
      else
        false
      end
    end
  end

  # Merge another hash of downloads into this manager
  #
  # @param other_downloads [Hash] Downloads hash to merge (slide_num => [enabled, name, files])
  # @return [Hash] The updated downloads hash
  # @raise [ArgumentError] If other_downloads is not a Hash
  def merge!(other_downloads)
    raise ArgumentError, "other_downloads must be a Hash" unless other_downloads.is_a?(Hash)

    @mutex.synchronize do
      other_downloads.each do |slide_num, entry|
        next unless entry.is_a?(Array) && entry.size == 3

        enabled = !!entry[0]  # Convert to boolean
        name = entry[1].to_s
        files = entry[2].is_a?(Array) ? entry[2].map(&:to_s) : []

        @downloads[slide_num.to_i] = [enabled, name, files]
      end

      @downloads
    end
  end

  private

  # Validate slide_num parameter
  #
  # @param slide_num [Integer] The slide number to validate
  # @raise [ArgumentError] If slide_num is invalid
  def validate_slide_num!(slide_num)
    unless slide_num.is_a?(Integer) && slide_num >= 0
      raise ArgumentError, "slide_num must be an Integer >= 0"
    end
  end

  # Validate name parameter
  #
  # @param name [String] The name to validate
  # @raise [ArgumentError] If name is invalid
  def validate_name!(name)
    unless name.is_a?(String)
      raise ArgumentError, "name must be a String"
    end
  end

  # Validate files parameter
  #
  # @param files [Array<String>] The files to validate
  # @raise [ArgumentError] If files is invalid
  def validate_files!(files)
    unless files.is_a?(Array)
      raise ArgumentError, "files must be an Array"
    end

    files.each { |file| validate_file!(file) }
  end

  # Validate a single file
  #
  # @param file [String] The file to validate
  # @raise [ArgumentError] If file is invalid
  def validate_file!(file)
    unless file.is_a?(String)
      raise ArgumentError, "file must be a String"
    end
  end
end