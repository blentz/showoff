class Showoff::Presentation
  require 'showoff/presentation/section'
  require 'showoff/presentation/slide'
  require 'showoff/compiler'
  require 'keymap'

  attr_reader :sections, :title, :favicon, :feedback, :pause_msg, :language, :interactive, :keymap, :keycode_dictionary, :keycode_shifted_keys, :highlightStyle

  def initialize(options)
    @options = options

    # Handle missing or empty sections
    begin
      # Ensure config is loaded
      unless Showoff::Config.loaded?
        config_file = File.join(Dir.pwd, 'showoff.json')
        Showoff::Config.load(config_file)
      end

      sections = Showoff::Config.sections
      if sections.nil? || sections.empty?
        Showoff::Logger.warn "No sections found in config. Using current directory."
        sections = {'.': ['.']}
      end

      @sections = sections.map do |name, files|
        Showoff::Presentation::Section.new(name, files || ['.'])
      end
    rescue => e
      Showoff::Logger.error "Error initializing sections: #{e.message}"
      Showoff::Logger.debug e.backtrace
      # Create a minimal section with the current directory
      @sections = [Showoff::Presentation::Section.new('.', ['.'])]
    end

    # weird magic variables the presentation expects - with fallbacks
    @baseurl   = nil # this doesn't appear to have ever been used
    @title     = Showoff::Config.get('name') || I18n.t('name') rescue 'Untitled Presentation'
    @favicon   = Showoff::Config.get('favicon') || 'favicon.ico'
    @feedback  = Showoff::Config.get('feedback') # note: the params check is obsolete
    @pause_msg = Showoff::Config.get('pause_msg')

    # Handle missing translations
    begin
      @language = Showoff::Locale.translations
    rescue => e
      Showoff::Logger.warn "Error loading translations: #{e.message}"
      @language = {}
    end

    @edit = Showoff::Config.get('edit') if options[:review]

    # invert the logic to maintain backwards compatibility of interactivity on by default
    @interactive = !options[:standalone]

    # Load up the default keymap, then merge in any customizations
    begin
      keymapfile = File.expand_path(File.join('~', '.showoff', 'keymap.json'))
      @keymap = Keymap.default
      @keymap.merge! JSON.parse(File.read(keymapfile)) rescue {}

      # map keys to the labels we're using
      @keycode_dictionary = Keymap.keycodeDictionary
      @keycode_shifted_keys = Keymap.shiftedKeyDictionary
    rescue => e
      Showoff::Logger.warn "Error loading keymap: #{e.message}"
      @keymap = {}
      @keycode_dictionary = {}
      @keycode_shifted_keys = {}
    end

    @highlightStyle = Showoff::Config.get('highlight') || 'default'

    if Showoff::State.get(:supplemental)
      @wrapper_classes = ['supplemental']
    end
  end

  # Reload all sections from disk
  # Called when hot reload detects file changes
  #
  # @param pres_dir [String] Presentation directory (required for correct file paths)
  def reload_sections(pres_dir = nil)
    # Use provided pres_dir or fall back to Showoff::Config.root
    pres_dir ||= Showoff::Config.root || Dir.pwd

    begin
      # Must chdir to presentation directory for correct file path resolution
      Dir.chdir(pres_dir) do
        # First, reload the config file (showoff.json) to pick up any changes
        config_file = File.join(pres_dir, 'showoff.json')
        Showoff::Config.load(config_file)

        # Update presentation metadata from reloaded config
        @title = Showoff::Config.get('name') || I18n.t('name') rescue 'Untitled Presentation'
        @favicon = Showoff::Config.get('favicon') || 'favicon.ico'
        @feedback = Showoff::Config.get('feedback')
        @pause_msg = Showoff::Config.get('pause_msg')
        @highlightStyle = Showoff::Config.get('highlight') || 'default'

        # Now reload sections with fresh config
        sections = Showoff::Config.sections
        if sections.nil? || sections.empty?
          Showoff::Logger.warn "No sections found in config. Using current directory."
          sections = {'.': ['.']}
        end

        @sections = sections.map do |name, files|
          Showoff::Presentation::Section.new(name, files || ['.'])
        end

        Showoff::Logger.info "Reloaded #{@sections.size} sections from disk"
      end
    rescue => e
      Showoff::Logger.error "Error reloading sections: #{e.message}"
      Showoff::Logger.debug e.backtrace.join("\n") if e.backtrace
    end
  end

  def compile
    Showoff::State.reset([:slide_count, :section_major, :section_minor])

    # @todo For now, we reparse the html so that we can generate content via slide
    #       templates. This adds a bit of extra time, but not too much. Perhaps
    #       we'll change that at some point.
    html = @sections.map(&:render).join("\n")
    doc  = Nokogiri::HTML::DocumentFragment.parse(html)

    Showoff::Compiler::TableOfContents.generate!(doc)
    Showoff::Compiler::Glossary.generatePage!(doc)

    doc
  end

  # The index page does not contain content; just a placeholder div that's
  # dynamically loaded after the page is displayed. This increases perceived
  # responsiveness.
  def index
    template_path = File.join(Showoff::GEMROOT, 'views','index.erb')
    ShowoffUtils.create_erb(File.read(template_path)).result(binding)
  end

  def slides
    compile.to_html
  end

  def static
    begin
      # This singleton guard removes ordering coupling between assets() & static()
      @doc ||= compile
      @slides = @doc.to_html

      # All static snapshots should be non-interactive by definition
      @interactive = false

      # Determine template based on format
      format = Showoff::State.get(:format) || 'web'
      template = case format
      when 'print', 'supplemental', 'pdf'
        'onepage.erb'
      else
        'index.erb'
      end

      # Load and process template
      template_path = File.join(Showoff::GEMROOT, 'views', template)
      if File.exist?(template_path)
        ShowoffUtils.create_erb(File.read(template_path)).result(binding)
      else
        Showoff::Logger.error "Template not found: #{template_path}"
        "<html><body><h1>#{@title}</h1><div>#{@slides}</div></body></html>"
      end
    rescue => e
      Showoff::Logger.error "Error generating static HTML: #{e.message}"
      Showoff::Logger.debug e.backtrace
      # Return minimal HTML if we can't generate the proper template
      "<html><body><h1>#{@title || 'Untitled Presentation'}</h1><p>Error generating presentation: #{e.message}</p></body></html>"
    end
  end

  # Generates a list of all image/font/etc files used by the presentation. This
  # will only identify the sources of <img> tags and files referenced by the
  # CSS url() function.
  #
  # @see
  #     https://github.com/puppetlabs/showoff/blob/220d6eef4c5942eda625dd6edc5370c7490eced7/lib/showoff.rb#L1509-L1573
  # @returns [Array]
  #     List of assets, such as images or fonts, used by the presentation.
  def assets
    begin
      # This singleton guard removes ordering coupling between assets() & static()
      @doc ||= compile

      # matches url(<path>) and returns the path as a capture group
      urlsrc = /url\([\"\']?(.*?)(?:[#\?].*)?[\"\']?\)/

      # get all image and url() sources
      files = []
      begin
        files = @doc.search('img').map {|img| img[:src] }
        @doc.search('*').each do |node|
          next unless node[:style]
          next unless matches = node[:style].match(urlsrc)
          files << matches[1]
        end
      rescue => e
        Showoff::Logger.warn "Error extracting image sources: #{e.message}"
      end

      # add in images from css files too
      begin
        css_files.each do |css_path|
          begin
            css_file_path = File.join(Showoff::Config.root, css_path)
            if File.exist?(css_file_path)
              data = File.read(css_file_path)

              # @todo: This isn't perfect. It will match commented out styles. But its
              # worst case behavior is displaying a warning message, so that's ok for now.
              data.scan(urlsrc).flatten.each do |path|
                # resolve relative paths in the stylesheet
                path = File.join(File.dirname(css_path), path) unless path.start_with? '/'
                files << path
              end
            else
              Showoff::Logger.warn "CSS file not found: #{css_path}"
            end
          rescue => e
            Showoff::Logger.warn "Error processing CSS file #{css_path}: #{e.message}"
          end
        end
    rescue => e
      # Silently handle missing or invalid config - use defaults
      # Config loading handles warnings, so we don't need to log here
      @sections = []
    end

      # also all user-defined styles and javascript files
      files.concat css_files rescue []
      files.concat js_files rescue []
      files.uniq
    rescue => e
      Showoff::Logger.error "Error collecting assets: #{e.message}"
      Showoff::Logger.debug e.backtrace
      # Return empty array if we can't collect assets
      []
    end
  end

  # Use the ShowoffUtils.create_erb helper method

  def erb(template)
    template_path = File.join(Showoff::GEMROOT, 'views', "#{template}.erb")
    ShowoffUtils.create_erb(File.read(template_path)).result(binding)
  end

  def css_files
    begin
      base = Dir.glob("#{Showoff::Config.root}/*.css").map { |path| File.basename(path) }
      extra = Array(Showoff::Config.get('styles'))
      base + extra
    rescue => e
      Showoff::Logger.warn "Error getting CSS files: #{e.message}"
      []
    end
  end

  def js_files
    begin
      base = Dir.glob("#{Showoff::Config.root}/*.js").map { |path| File.basename(path) }
      extra = Array(Showoff::Config.get('scripts'))
      base + extra
    rescue => e
      Showoff::Logger.warn "Error getting JS files: #{e.message}"
      []
    end
  end

  # return a list of keys associated with a given action in the keymap
  def mapped_keys(action, klass='key')
    list = @keymap.select { |key,value| value == action }.keys

    if klass
      list.map { |val| "<span class=\"#{klass}\">#{val}</span>" }.join
    else
      list.join ', '
    end
  end




  # @todo: backwards compatibility shim
  def user_translations
    Showoff::Locale.userTranslations
  end

  # @todo: backwards compatibility shim
  def language_names
    Showoff::Locale.contentLanguages
  end


  # @todo: this should be part of the server. Move there with the least disruption.
  def master_presenter?
    false
  end

  # @todo: this should be part of the server. Move there with the least disruption.
  def valid_presenter_cookie?
    false
  end


end
