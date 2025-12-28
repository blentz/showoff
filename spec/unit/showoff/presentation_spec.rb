RSpec.describe Showoff::Presentation do
  context 'asset management base' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:format, 'web')
      Showoff::State.set(:supplemental, nil)
    end

    it "lists all user styles" do
      presentation = Showoff::Presentation.new({})
      expect(presentation.css_files).to eq ['styles.css']
    end

    it "lists all user scripts" do
      presentation = Showoff::Presentation.new({})
      expect(presentation.js_files).to eq ['scripts.js']
    end

    it "generates a list of all assets" do
      presentation = Showoff::Presentation.new({})
      assets = presentation.assets

      [ 'grumpy_lawyer.jpg',
        'assets/grumpycat.jpg',
        'assets/yellow-brick-road.jpg',
        'styles.css',
        'scripts.js',
      ].each { |file| expect(assets.include? file).to be_truthy }

      [ 'assets/tile.jpg',
        'assets/another.css',
        'assets/another.js',
      ].each { |file| expect(assets.include? file).to be_falsey }
    end
  end

  context 'asset management with additional configs' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'extra.json'))
      Showoff::State.set(:format, 'web')
      Showoff::State.set(:supplemental, nil)
    end

    it "lists all user styles" do
      presentation = Showoff::Presentation.new({})
      expect(presentation.css_files).to eq ['styles.css', 'assets/another.css']
    end

    it "lists all user scripts" do
      presentation = Showoff::Presentation.new({})
      expect(presentation.js_files).to eq ['scripts.js', 'assets/another.js']
    end

    it "generates a list of all assets" do
      presentation = Showoff::Presentation.new({})
      assets = presentation.assets

      [ 'grumpy_lawyer.jpg',
        'assets/grumpycat.jpg',
        'assets/yellow-brick-road.jpg',
        'styles.css',
        'scripts.js',
        'assets/tile.jpg',
        'assets/another.css',
        'assets/another.js',
      ].each { |file| expect(assets.include? file).to be_truthy }
    end
  end

  it "generates a web format static presentation" do
    Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
    Showoff::State.set(:format, 'web')
    presentation = Showoff::Presentation.new({})

    expect(presentation.static).to match(/<meta name="viewport"/)
    expect(presentation.static).to_not match(/The Guidebook/)
  end

  it "generates a print format presentation" do
    Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
    Showoff::State.set(:format, 'print')
    presentation = Showoff::Presentation.new({})

    expect(presentation.static).to_not match(/<meta name="viewport"/)
    expect(presentation.static).to_not match(/The Guidebook/)
  end

  it "generates supplemental material" do
    Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
    Showoff::State.set(:format, 'supplemental')
    Showoff::State.set(:supplemental, 'guide')
    presentation = Showoff::Presentation.new({})

    expect(presentation.static).to_not match(/<meta name="viewport"/)
    expect(presentation.static).to match(/The Guidebook/)
  end

  context 'initialization' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:format, 'web')
      Showoff::State.set(:supplemental, nil)
    end

    it 'sets interactive to true by default' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.interactive).to be true
    end

    it 'sets interactive to false when standalone' do
      presentation = Showoff::Presentation.new({ standalone: true })
      expect(presentation.interactive).to be false
    end

    it 'loads title from config' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.title).to be_a(String)
    end

    it 'loads keymap' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.keymap).to be_a(Hash)
    end

    it 'loads keycode dictionary' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.keycode_dictionary).to be_a(Hash)
    end

    it 'sets highlight style' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.highlightStyle).to be_a(String)
    end
  end

  context 'mapped_keys' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:format, 'web')
    end

    it 'returns keys with default class' do
      presentation = Showoff::Presentation.new({})
      presentation.instance_variable_set(:@keymap, { 'n' => 'next', 'p' => 'prev' })
      result = presentation.mapped_keys('next')
      expect(result).to include('<span class="key">n</span>')
    end

    it 'returns keys with custom class' do
      presentation = Showoff::Presentation.new({})
      presentation.instance_variable_set(:@keymap, { 'p' => 'prev' })
      result = presentation.mapped_keys('prev', 'custom')
      expect(result).to include('<span class="custom">p</span>')
    end

    it 'returns comma-separated keys without class' do
      presentation = Showoff::Presentation.new({})
      presentation.instance_variable_set(:@keymap, { 'n' => 'next' })
      result = presentation.mapped_keys('next', nil)
      expect(result).to eq('n')
    end

    it 'returns empty string for unknown action' do
      presentation = Showoff::Presentation.new({})
      presentation.instance_variable_set(:@keymap, {})
      result = presentation.mapped_keys('unknown')
      expect(result).to eq('')
    end
  end

  context 'compatibility shims' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
    end

    it 'returns false for master_presenter?' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.master_presenter?).to be false
    end

    it 'returns false for valid_presenter_cookie?' do
      presentation = Showoff::Presentation.new({})
      expect(presentation.valid_presenter_cookie?).to be false
    end

    it 'delegates user_translations to Locale' do
      allow(Showoff::Locale).to receive(:userTranslations).and_return({ 'key' => 'value' })
      presentation = Showoff::Presentation.new({})
      expect(presentation.user_translations).to eq({ 'key' => 'value' })
    end

    it 'delegates language_names to Locale' do
      allow(Showoff::Locale).to receive(:contentLanguages).and_return({ 'en' => 'English' })
      presentation = Showoff::Presentation.new({})
      expect(presentation.language_names).to eq({ 'en' => 'English' })
    end
  end

  context 'slides method' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:format, 'web')
    end

    it 'returns compiled HTML' do
      presentation = Showoff::Presentation.new({})
      result = presentation.slides
      expect(result).to be_a(String)
      expect(result).to include('<div')
    end
  end

  # New tests start here
  context 'compile method' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:format, 'web')
      Showoff::State.set(:supplemental, nil)
    end

    it 'produces valid slide output' do
      presentation = Showoff::Presentation.new({})
      result = presentation.compile

      # After compile, slides should have been processed
      expect(Showoff::State.get(:slide_count)).to be > 0
      expect(result).to be_a(Nokogiri::HTML::DocumentFragment)
    end

    it 'renders sections and returns a Nokogiri document' do
      presentation = Showoff::Presentation.new({})
      result = presentation.compile

      expect(result).to be_a(Nokogiri::HTML::DocumentFragment)
      expect(result.to_html).to include('This little piggy')
    end

    it 'generates table of contents' do
      allow(Showoff::Compiler::TableOfContents).to receive(:generate!).and_call_original

      presentation = Showoff::Presentation.new({})
      presentation.compile

      expect(Showoff::Compiler::TableOfContents).to have_received(:generate!)
    end

    it 'generates glossary page' do
      allow(Showoff::Compiler::Glossary).to receive(:generatePage!).and_call_original

      presentation = Showoff::Presentation.new({})
      presentation.compile

      expect(Showoff::Compiler::Glossary).to have_received(:generatePage!)
    end
  end

  context 'index method' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:format, 'web')
    end

    it 'returns a string containing HTML' do
      presentation = Showoff::Presentation.new({})
      result = presentation.index

      expect(result).to be_a(String)
      expect(result).to include('<!DOCTYPE html>')
      expect(result).to include('<html')
      expect(result).to include('</html>')
    end

    it 'includes the title from config' do
      presentation = Showoff::Presentation.new({})
      result = presentation.index

      expect(result).to include('Slides and sections')
    end
  end

  context 'erb method' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
    end

    it 'loads and processes an ERB template' do
      presentation = Showoff::Presentation.new({})
      # Use a template that exists - 'header' is a simple one
      result = presentation.erb('header')

      expect(result).to be_a(String)
      # header.erb produces HTML output
      expect(result.length).to be > 0
    end

    it 'handles missing templates gracefully' do
      presentation = Showoff::Presentation.new({})

      # Mock File.read to raise an error for a non-existent template
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(File.join(Showoff::GEMROOT, 'views', 'nonexistent.erb')).and_raise(Errno::ENOENT.new('File not found'))

      expect {
        presentation.erb('nonexistent')
      }.to raise_error(Errno::ENOENT)
    end
  end

  context 'error handling' do
    it 'handles missing or empty sections during initialization' do
      # Create a config with no sections
      allow(Showoff::Config).to receive(:loaded?).and_return(true)
      allow(Showoff::Config).to receive(:sections).and_return(nil)
      allow(Showoff::Logger).to receive(:warn)

      presentation = Showoff::Presentation.new({})

      # Should create a default section
      expect(presentation.sections).to be_an(Array)
      expect(presentation.sections.length).to eq(1)
      expect(Showoff::Logger).to have_received(:warn).with("No sections found in config. Using current directory.")
    end

    it 'handles initialization errors' do
      allow(Showoff::Config).to receive(:loaded?).and_return(true)
      allow(Showoff::Config).to receive(:sections).and_raise(StandardError.new("Test error"))
      allow(Showoff::Logger).to receive(:error)
      allow(Showoff::Logger).to receive(:debug)

      presentation = Showoff::Presentation.new({})

      # Should create a default section
      expect(presentation.sections).to be_an(Array)
      expect(presentation.sections.length).to eq(1)
      expect(Showoff::Logger).to have_received(:error).with("Error initializing sections: Test error")
    end

    it 'handles errors in assets method' do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))

      presentation = Showoff::Presentation.new({})

      # Force an error in the assets method
      allow(presentation).to receive(:compile).and_raise(StandardError.new("Test error"))
      allow(Showoff::Logger).to receive(:error)
      allow(Showoff::Logger).to receive(:debug)

      result = presentation.assets

      expect(result).to eq([])
      expect(Showoff::Logger).to have_received(:error).with("Error collecting assets: Test error")
    end

    it 'handles errors in css_files method' do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))

      presentation = Showoff::Presentation.new({})

      # Force an error in the css_files method
      allow(Dir).to receive(:glob).and_raise(StandardError.new("Test error"))
      allow(Showoff::Logger).to receive(:warn)

      result = presentation.css_files

      expect(result).to eq([])
      expect(Showoff::Logger).to have_received(:warn).with("Error getting CSS files: Test error")
    end

    it 'handles errors in js_files method' do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))

      presentation = Showoff::Presentation.new({})

      # Force an error in the js_files method
      allow(Dir).to receive(:glob).and_raise(StandardError.new("Test error"))
      allow(Showoff::Logger).to receive(:warn)

      result = presentation.js_files

      expect(result).to eq([])
      expect(Showoff::Logger).to have_received(:warn).with("Error getting JS files: Test error")
    end

    it 'handles errors in static method' do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))

      presentation = Showoff::Presentation.new({})

      # Force an error in the static method
      allow(presentation).to receive(:compile).and_raise(StandardError.new("Test error"))
      allow(Showoff::Logger).to receive(:error)
      allow(Showoff::Logger).to receive(:debug)

      result = presentation.static

      expect(result).to include("<html><body><h1>#{presentation.title}</h1><p>Error generating presentation: Test error</p></body></html>")
      expect(Showoff::Logger).to have_received(:error).with("Error generating static HTML: Test error")
    end
  end

  context 'section loading' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
    end

    it 'initializes with actual sections from config' do
      presentation = Showoff::Presentation.new({})

      expect(presentation.sections).to be_an(Array)
      expect(presentation.sections.length).to be > 0
      expect(presentation.sections[0]).to be_a(Showoff::Presentation::Section)
    end

    it 'returns slides from sections' do
      presentation = Showoff::Presentation.new({})

      # slides method returns rendered HTML string, not array
      slides = presentation.slides
      expect(slides).to be_a(String)
      expect(slides.length).to be > 0
      expect(slides).to include('class="slide')
    end

    it 'sets wrapper classes when supplemental' do
      Showoff::Config.load(File.join(fixtures, 'assets', 'showoff.json'))
      Showoff::State.set(:supplemental, 'guide')

      presentation = Showoff::Presentation.new({})

      expect(presentation.instance_variable_get(:@wrapper_classes)).to eq(['supplemental'])
    end
  end
end