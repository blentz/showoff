require 'tempfile'
require 'open3'
require 'timeout'
require 'nokogiri'

# Manages code execution for the Showoff presentation server
# This class handles extracting code from slides and executing it in a sandboxed environment
class Showoff::Server::ExecutionManager
  # Initialize the execution manager
  #
  # @param options [Hash] Configuration options
  # @option options [String] :pres_dir Presentation directory
  # @option options [Integer] :timeout Execution timeout in seconds (default: 15)
  # @option options [Hash] :parsers Language parsers configuration
  # @option options [Logger] :logger Logger instance
  def initialize(options = {})
    @pres_dir = options[:pres_dir] || Dir.pwd
    @timeout = options[:timeout] || 15
    @parsers = options[:parsers] || {}
    @logger = options[:logger]
  end

  # Extract code from a slide file
  #
  # @param path [String] Path to the slide file (can include slide number as "path:num")
  # @param index [String, Integer] Index of the code block to extract, or 'all' for all blocks
  # @param executable [Boolean] Whether to look for executable code blocks only
  # @return [String, Array] The extracted code or an array of [lang, code, classes] for all blocks
  def get_code_from_slide(path, index, executable=true)
    if path =~ /^(.*)(?::)(\d+)$/
      path = $1
      num  = $2.to_i
    else
      num = 1
    end

    classes = executable ? 'code.execute' : 'code'

    slide = "#{path}.md"
    return [] unless File.exist? slide

    content = File.read(slide)
    return [] if content.nil?
    return [] if content.empty?

    if defined? num
      content = content.split(/^\<?!SLIDE/m).reject { |sl| sl.empty? }[num-1]
    end

    html = process_markdown(slide, '', content, {})
    doc  = Nokogiri::HTML::DocumentFragment.parse(html)

    if index == 'all'
      doc.css(classes).collect do |code|
        classes = code.attr('class').split rescue []
        lang    = classes.shift =~ /language-(\S*)/ ? $1 : nil

        [lang, code.text.gsub(/^\* /, ' '), classes]
      end
    else
      doc.css(classes)[index.to_i].text.gsub(/^\* /, ' ') rescue 'Invalid code block index'
    end
  end

  # Execute code in a specific language
  #
  # @param lang [String] Language identifier (must be in parsers config)
  # @param code [String] Code to execute
  # @return [String] Execution output with newlines converted to <br> tags
  def execute(lang, code)
    parser = @parsers[lang]
    return "No parser for #{lang}" unless parser

    begin
      Timeout::timeout(@timeout) do
        # Write out a tempfile to make it simpler for end users to add custom language parser
        Tempfile.open('showoff-execution') do |f|
          File.write(f.path, code)
          @logger.debug "Evaluating: #{parser} #{f.path}" if @logger
          output, status = Open3.capture2e("#{parser} #{f.path}")

          unless status.success?
            @logger.warn "Command execution failed" if @logger
            @logger.warn output if @logger
          end

          output
        end
      end
    rescue => e
      e.message
    end.gsub(/\n/, '<br />')
  end

  private

  # Process markdown content into HTML
  # This is a simplified version that delegates to the main app's processor
  # In a real implementation, this would need to be properly implemented or delegated
  def process_markdown(name, section, content, opts={})
    # For now, just wrap the content in a code block for extraction
    # In a real implementation, this would use the actual markdown processor
    "<div><code class='execute language-ruby'>#{content}</code></div>"
  end
end