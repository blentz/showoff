# adds presenter notes processing to the compiler
class Showoff::Compiler::Notes

  # Generate the presenter notes sections, including personal notes
  #
  # @param doc [Nokogiri::HTML::DocumentFragment]
  #     The slide document
  #
  # @param profile [String]
  #     The markdown engine profile to use when rendering
  #
  # @param options [Hash] Options used for rendering any embedded markdown
  # @option options [String] :name The markdown slide name
  # @option options [String] :seq The sequence number for multiple slides in one file
  #
  # @return [Array<Nokogiri::HTML::DocumentFragment, Nokogiri::XML::NodeSet>]
  #     A tuple of (slide DOM with notes removed, extracted notes sections)
  #
  # @see
  #     https://github.com/puppetlabs/showoff/blob/3f43754c84f97be4284bb34f9bc7c42175d45226/lib/showoff.rb#L616-L716
  # @note
  #     A ton of the functionality in the original method got refactored to its logical location
  def self.render!(doc, profile, options = {})
    # Collect notes sections as we create them
    notes_sections = []

    # Turn tags into classed divs.
    doc.search('p').select {|p| p.text.start_with?('~~~SECTION:') }.each do |p|
      klass = p.text.match(/~~~SECTION:([^~]*)~~~/)[1]

      # Don't bother creating this if we don't want to use it
      next unless Showoff::Config.includeNotes?(klass)

      notes = Nokogiri::XML::Node.new('div', doc)
      notes.add_class("notes-section #{klass}")
      nodes = []
      iter = p.next_sibling
      until iter.text == '~~~ENDSECTION~~~' do
        nodes << iter
        iter = iter.next_sibling

        # if the author forgot the closing tag, let's not crash, eh?
        break unless iter
      end
      iter.remove if iter # remove the extraneous closing ~~~ENDSECTION~~~ tag

      # We need to collect the list before moving or the iteration crashes since the iterator no longer has a sibling
      nodes.each {|n| n.parent = notes }

      p.replace(notes)
      notes_sections << notes
    end

    filename = [
      File.join(Showoff::Config.root, '_notes', "#{options[:name]}.#{options[:seq]}.md"),
      File.join(Showoff::Config.root, '_notes', "#{options[:name]}.md"),
    ].find {|path| File.file?(path) }

    if filename and Showoff::Config.includeNotes?('notes')
      # Find existing notes section or create one
      notes_div = notes_sections.find { |n| n['class'].include?('notes') }
      unless notes_div
        notes_div = Nokogiri::XML::Node.new('div', doc)
        notes_div.add_class('notes-section notes')
        doc.add_child(notes_div)
        notes_sections << notes_div
      end

      text = Tilt[:markdown].new(nil, nil, options[:profile]) { File.read(filename) }.render
      frag = "<div class=\"personal\"><h1>#{I18n.t('presenter.notes.personal')}</h1>#{text}</div>"
      notes_div.prepend_child(frag)
    end

    # Extract notes from the document - they are rendered separately in the slide template
    notes_sections.each { |notes| notes.remove }

    # Return the document (with notes removed) and the extracted notes as a NodeSet
    notes_nodeset = Nokogiri::XML::NodeSet.new(doc.document, notes_sections)
    [doc, notes_nodeset]
  end

end
