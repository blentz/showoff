class Showoff
  require 'showoff/config'
  require 'showoff/compiler'
  require 'showoff/presentation'
  require 'showoff/state'
  require 'showoff/locale'
  require 'showoff/logger'

  # @todo: Do we really need Ruby 2.0 support?
  require 'showoff/monkeypatches'

  GEMROOT = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  def self.do_static(args, options)
    begin
      Showoff::State.set(:format, args[0] || 'web')
      Showoff::State.set(:supplemental, args[1]) if args[0] == 'supplemental'

      # Safely set content locale
      begin
        Showoff::Locale.setContentLocale(options[:language])
      rescue => e
        Showoff::Logger.warn "Error setting locale: #{e.message}. Using default."
      end

      # Create presentation with error handling
      begin
        presentation = Showoff::Presentation.new(options)
      rescue => e
        Showoff::Logger.error "Error creating presentation: #{e.message}"
        Showoff::Logger.error "Ensure your showoff.json is valid and contains required fields."
        Showoff::Logger.debug e.backtrace
        exit 1
      end

      # Make snapshot with error handling
      begin
        makeSnapshot(presentation)
      rescue => e
        Showoff::Logger.error "Error generating static snapshot: #{e.message}"
        Showoff::Logger.debug e.backtrace
        exit 1
      end

      # Generate PDF if requested
      generatePDF if Showoff::State.get(:format) == 'pdf'

    rescue => e
      Showoff::Logger.error "Error generating static site: #{e.message}"
      Showoff::Logger.error "Ensure showoff.json exists and is valid"
      Showoff::Logger.error "Run 'showoff validate' to check your presentation"
      Showoff::Logger.debug e.backtrace
      exit 1
    end
  end

  # Generate a static HTML snapshot of the presentation in the `static` directory.
  # Note that the `Showoff::Presentation` determines the format of the generated
  # presentation based on the content requested.
  #
  # @see
  #     https://github.com/puppetlabs/showoff/blob/220d6eef4c5942eda625dd6edc5370c7490eced7/lib/showoff.rb#L1506-L1574
  def self.makeSnapshot(presentation)
    begin
      # Create static directory
      FileUtils.mkdir_p 'static'

      # Generate static HTML
      begin
        static_html = presentation.static
        File.write(File.join('static', 'index.html'), static_html)
      rescue => e
        Showoff::Logger.error "Error generating static HTML: #{e.message}"
        raise
      end

      # Copy JS and CSS directories
      ['js', 'css'].each { |dir|
        src  = File.join(GEMROOT, 'public', dir)
        dest = File.join('static', dir)

        begin
          FileUtils.copy_entry(src, dest, false, false, true)
        rescue => e
          Showoff::Logger.error "Error copying #{dir} directory: #{e.message}"
          raise
        end
      }

      # Copy assets
      begin
        assets = presentation.assets rescue []
        assets.each do |path|
          src  = File.join(Showoff::Config.root, path)
          dest = File.join('static', path)

          FileUtils.mkdir_p(File.dirname(dest))
          begin
            FileUtils.copy(src, dest)
          rescue Errno::ENOENT => e
            Showoff::Logger.warn "Missing source file: #{path}"
          end
        end
      rescue => e
        Showoff::Logger.error "Error copying assets: #{e.message}"
        # Continue even if assets fail - the HTML might still be useful
      end

    rescue => e
      Showoff::Logger.error "Failed to create static snapshot: #{e.message}"
      raise
    end
  end

  # Generate a PDF version of the presentation in the current directory. This
  # requires that the HTML snaphot exists, and it will *remove* that snapshot
  # if the PDF generation is successful.
  #
  # @note
  #     wkhtmltopdf is terrible and will often report hard failures even after
  #     successfully building a PDF. Therefore, we check file existence and
  #     display different error messaging.
  # @see
  #     https://github.com/puppetlabs/showoff/blob/220d6eef4c5942eda625dd6edc5370c7490eced7/lib/showoff.rb#L1447-L1471
  def self.generatePDF
    begin
      require 'pdfkit'

      # Get name with fallback
      name = Showoff::Config.get('name') || 'Untitled Presentation'
      output = "#{name}.pdf"

      # Get PDF options with fallback
      pdf_options = Showoff::Config.get('pdf_options')
      if pdf_options.nil?
        Showoff::Logger.warn "No pdf_options found in config. Using defaults."
        pdf_options = {
          :page_size        => 'Letter',
          :orientation      => 'Portrait',
          :print_media_type => true,
          :quiet            => false
        }
      end

      # Generate PDF
      kit = PDFKit.new(File.new('static/index.html'), pdf_options)
      kit.to_file(output)
      FileUtils.rm_rf('static')

      Showoff::Logger.info "PDF generated successfully: #{output}"

    rescue RuntimeError => e
      if File.exist? output
        Showoff::Logger.warn "Your PDF was generated, but PDFkit reported an error. Inspect the file #{output} for suitability."
        Showoff::Logger.warn "You might try loading `static/index.html` in a web browser and checking the developer console for 404 errors."
      else
        Showoff::Logger.error "Generating your PDF with wkhtmltopdf was not successful."
        Showoff::Logger.error "Try running the following command manually to see what it's failing on."
        Showoff::Logger.error e.message.sub('--quiet', '')
      end
    rescue LoadError
      Showoff::Logger.error 'Generating a PDF version of your presentation requires the `pdfkit` gem.'
    rescue => e
      Showoff::Logger.error "Error generating PDF: #{e.message}"
      Showoff::Logger.debug e.backtrace
    end
  end

end
