require 'json'

class Showoff::Config
  # Initialize class variables to prevent nil errors
  @@config ||= {}
  @@sections ||= {'.': ['.']}
  @@root ||= Dir.pwd
  @@loaded = false

  def self.keys
    (@@config || {}).keys
  end

  # Retrieve settings from the config hash.
  # If multiple arguments are given then it will dig down through data
  # structures argument by argument.
  #
  # Returns the data type & value requested, nil on error.
  def self.get(*setting)
    (@@config || {}).dig(*setting) rescue nil
  end

  def self.sections
    @@sections || {'.': ['.']}
  end

  # Check if config has been loaded
  def self.loaded?
    @@loaded
  end

  # Absolute root of presentation
  def self.root
    @@root
  end

  # Relative path to an item in the presentation directory structure
  def self.path(path)
    File.expand_path(File.join(@@root, path)).sub(/^#{@@root}\//, '')
  end

  # Identifies whether we're including a given notes section
  #
  # @param section [String] The name of the notes section of interest.
  # @return [Boolean] Whether to include this section in the output
  def self.includeNotes?(section)
    return true # todo make this work
  end

  def self.load(path = 'showoff.json')
    begin
      # Check if file exists
      unless File.exist?(path)
        Showoff::Logger.warn "Presentation file does not exist at #{path}. Using minimal defaults."
        @@root = File.dirname(path)
        @@config = {}
        @@sections = {'.': ['.']}
        self.load_defaults!
        @@loaded = true
        return
      end

      # Try to parse the JSON file
      @@root = File.dirname(path)
      begin
        @@config = JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        Showoff::Logger.error "Invalid JSON in presentation file: #{path}"
        Showoff::Logger.error e.message
        @@config = {}
      end

      # Ensure config is a hash
      @@config = {} unless @@config.is_a?(Hash)

      # Expand sections and load defaults
      @@sections = self.expand_sections
      self.load_defaults!
      @@loaded = true
    rescue => e
      Showoff::Logger.error "Error loading presentation file: #{e.message}"
      Showoff::Logger.debug e.backtrace

      # Set minimal defaults
      @@root = File.dirname(path)
      @@config = {}
      @@sections = {'.': ['.']}
      self.load_defaults!
      @@loaded = true
    end
  end

  # Expand and normalize all the different variations that the sections structure
  # can exist in. When finished, this should return an ordered hash of one or more
  # section titles pointing to an array of filenames, for example:
  #
  # {
  #     "Section name": [ "array.md, "of.md, "files.md"],
  #     "Another Section": [ "two/array.md, "two/of.md, "two/files.md"],
  # }
  #
  # See valid input forms at
  #   https://puppetlabs.github.io/showoff/documentation/PRESENTATION_rdoc.html#label-Defining+slides+using+the+sections+setting.
  # Source:
  #  https://github.com/puppetlabs/showoff/blob/3f43754c84f97be4284bb34f9bc7c42175d45226/lib/showoff_utils.rb#L427-L475
  def self.expand_sections
    begin
      # Ensure @@config exists
      @@config ||= {}

      if @@config.is_a?(Hash)
        # dup so we don't overwrite the original data structure and make it impossible to re-localize
        sections = @@config['sections']

        # Handle missing sections key gracefully
        if sections.nil?
          Showoff::Logger.warn "No 'sections' key found in config. Using current directory."
          sections = ['.']
        else
          sections = sections.dup
        end
      else
        sections = @@config.dup
      end

      if sections.is_a? Array
        sections = self.legacy_sections(sections)
      elsif sections.is_a? Hash
        raise "Named sections are unsupported on Ruby versions less than 1.9." if RUBY_VERSION.start_with? '1.8'
        sections.each do |key, value|
          next if value.is_a? Array
          path = File.dirname(value)
          data = JSON.parse(File.read(File.join(@@root, value)))
          raise "The section file #{value} must contain an array of filenames." unless data.is_a? Array

          # get relative paths to each slide in the array
          sections[key] = data.map do |filename|
            Pathname.new("#{path}/#{filename}").cleanpath.to_path
          end
        end
      else
        raise "The `sections` key must be an Array or Hash, not a #{sections.class}."
      end

    rescue => e
      Showoff::Logger.error "There was a problem with the presentation file #{index}"
      Showoff::Logger.error e.message
      Showoff::Logger.debug e.backtrace
      # Default to current directory if sections can't be parsed
      sections = {'.': ['.']}
    end

    sections
  end

  # Source:
  #  https://github.com/puppetlabs/showoff/blob/3f43754c84f97be4284bb34f9bc7c42175d45226/lib/showoff_utils.rb#L477-L545
  def self.legacy_sections(data)
    # each entry in sections can be:
    # - "filename.md"
    # - "directory"
    # - { "section": "filename.md" }
    # - { "section": "directory" }
    # - { "section": [ "array.md, "of.md, "files.md"] }
    # - { "include": "sections.json" }
    sections = {}
    counters = {}
    lastpath = nil

    data.map do |entry|
      next entry if entry.is_a? String
      next nil unless entry.is_a? Hash
      next entry['section'] if entry.include? 'section'

      section = nil
      if entry.include? 'include'
        file = entry['include']
        path = File.dirname(file)
        data = JSON.parse(File.read(File.join(@@root, file)))
        if data.is_a? Array
          if path == '.'
            section = data
          else
            section = data.map do |source|
              "#{path}/#{source}"
            end
          end
        end
      end
      section
    end.flatten.compact.each do |entry|
      # We do this in two passes simply because most of it was already done
      # and I don't want to waste time on legacy functionality.

      # Normalize to a proper path from presentation root
      if File.directory? File.join(@@root, entry)
        sections[entry] = Dir.glob("#{@@root}/#{entry}/**/*.md").map {|e| e.sub(/^#{@@root}\//, '') }
        lastpath = entry
      else
        path = File.dirname(entry)

        # this lastpath business allows us to reference files in a directory that aren't
        # necessarily contiguous.
        if path != lastpath
          counters[path] ||= 0
          counters[path]  += 1
        end

        # now record the last path we've seen
        lastpath = path

        # and if there are more than one disparate occurences of path, add a counter to this string
        path = "#{path} (#{counters[path]})" unless counters[path] == 1

        sections[path] ||= []
        sections[path]  << entry
      end
    end

    sections
  end

  def self.load_defaults!
    # Ensure config is a hash
    @@config = {} unless @@config.is_a?(Hash)

    # Set default name if missing
    @@config['name'] ||= 'Untitled Presentation'

    # Ensure sections exists (will be expanded in expand_sections)
    @@config['sections'] ||= ['.']

    # use a symbol which cannot clash with a string key loaded from json
    @@config['markdown'] ||= :default
    renderer = @@config['markdown']
    defaults = case renderer
      when 'rdiscount'
        {
          :autolink          => true,
        }
      when 'maruku'
        {
          :use_tex           => false,
          :png_dir           => 'images',
          :html_png_url      => '/file/images/',
        }
      when 'bluecloth'
        {
          :auto_links        => true,
          :definition_lists  => true,
          :superscript       => true,
          :tables            => true,
        }
      when 'kramdown'
        {}
      else
        {
          :autolink          => true,
          :no_intra_emphasis => true,
          :superscript       => true,
          :tables            => true,
          :underline         => true,
          :escape_html       => false,
        }
      end

    @@config[renderer] ||= {}
    @@config[renderer]   = defaults.merge!(@@config[renderer])

    # run `wkhtmltopdf --extended-help` for a full list of valid options here
    pdf_defaults = {
      :page_size        => 'Letter',
      :orientation      => 'Portrait',
      :print_media_type => true,
      :quiet            => false}
    pdf_options = @@config['pdf_options'] || {}
    pdf_options = Hash[pdf_options.map {|k, v| [k.to_sym, v]}] if pdf_options.is_a?(Hash)

    @@config['pdf_options'] = pdf_defaults.merge!(pdf_options)

    # Do not inject 'favicon' into the config keys by default.
    # Presentation layer will default to 'favicon.ico' when not configured.
    # This keeps Config.keys stable for specs and avoids leaking UI concerns here.
  end

end
