RSpec.describe Showoff::Config do
  describe '.loaded?' do
    it 'returns true after loading a config' do
      Showoff::Config.load(File.join(fixtures, 'base.json'))
      expect(Showoff::Config.loaded?).to be true
    end
  end

  describe '.config' do
    it 'returns the full configuration hash' do
      Showoff::Config.load(File.join(fixtures, 'base.json'))
      expect(Showoff::Config.config).to be_a(Hash)
      expect(Showoff::Config.config['name']).to eq('Basic Showoff config file')
    end
  end

  describe '.includeNotes?' do
    it 'returns true for any section' do
      expect(Showoff::Config.includeNotes?('notes')).to be true
      expect(Showoff::Config.includeNotes?('handouts')).to be true
    end
  end

  describe '.load' do
    it 'handles non-existent file gracefully' do
      expect {
        Showoff::Config.load('/nonexistent/path/showoff.json')
      }.not_to raise_error
      expect(Showoff::Config.loaded?).to be true
    end

    it 'handles invalid JSON gracefully' do
      Dir.mktmpdir('config_spec') do |dir|
        invalid_json = File.join(dir, 'invalid.json')
        File.write(invalid_json, '{ invalid json }')

        expect {
          Showoff::Config.load(invalid_json)
        }.not_to raise_error
        expect(Showoff::Config.loaded?).to be true
      end
    end

    it 'handles empty JSON file' do
      Dir.mktmpdir('config_spec') do |dir|
        empty_json = File.join(dir, 'empty.json')
        File.write(empty_json, '{}')

        Showoff::Config.load(empty_json)
        expect(Showoff::Config.loaded?).to be true
        expect(Showoff::Config.get('name')).to eq('Untitled Presentation')
      end
    end
  end

  describe '.get' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'base.json'))
    end

    it 'returns nil for non-existent keys' do
      expect(Showoff::Config.get('nonexistent')).to be_nil
    end

    it 'supports nested key access' do
      expect(Showoff::Config.get('pdf_options', :page_size)).to eq('Letter')
    end
  end

  describe '.load_defaults!' do
    it 'sets defaults for rdiscount renderer' do
      Dir.mktmpdir('config_spec') do |dir|
        config = File.join(dir, 'rdiscount.json')
        File.write(config, JSON.dump({ 'markdown' => 'rdiscount', 'sections' => ['.'] }))

        Showoff::Config.load(config)
        expect(Showoff::Config.get('rdiscount', :autolink)).to be true
      end
    end

    it 'sets defaults for bluecloth renderer' do
      Dir.mktmpdir('config_spec') do |dir|
        config = File.join(dir, 'bluecloth.json')
        File.write(config, JSON.dump({ 'markdown' => 'bluecloth', 'sections' => ['.'] }))

        Showoff::Config.load(config)
        expect(Showoff::Config.get('bluecloth', :auto_links)).to be true
        expect(Showoff::Config.get('bluecloth', :definition_lists)).to be true
      end
    end

    it 'sets defaults for kramdown renderer' do
      Dir.mktmpdir('config_spec') do |dir|
        config = File.join(dir, 'kramdown.json')
        File.write(config, JSON.dump({ 'markdown' => 'kramdown', 'sections' => ['.'] }))

        Showoff::Config.load(config)
        expect(Showoff::Config.get('kramdown')).to eq({})
      end
    end

    it 'merges user pdf_options with defaults' do
      Dir.mktmpdir('config_spec') do |dir|
        config = File.join(dir, 'pdf.json')
        File.write(config, JSON.dump({
          'sections' => ['.'],
          'pdf_options' => { 'orientation' => 'Landscape' }
        }))

        Showoff::Config.load(config)
        expect(Showoff::Config.get('pdf_options', :orientation)).to eq('Landscape')
        expect(Showoff::Config.get('pdf_options', :page_size)).to eq('Letter')
      end
    end
  end

  context 'base configuration' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'base.json'))
    end

    it "loads configuration from disk" do
      expect(Showoff::Config.root).to eq(fixtures)
      expect(Showoff::Config.keys).to eq(['name', 'description', 'protected', 'version', 'feedback', 'parsers', 'sections', 'markdown', :default, 'pdf_options'])
      expect(Showoff::Config.get('pdf_options')).to eq({:page_size=>"Letter", :orientation=>"Portrait", :print_media_type=>true, :quiet=>false})
    end

    it "calculates relative paths" do
      expect(Showoff::Config.path('foo/bar')).to eq('foo/bar')
      expect(Showoff::Config.path('../fixtures')).to eq(fixtures)
    end

    it "loads proper markdown profile" do
      expect(Showoff::Config.get('markdown')).to eq(:default)
      expect(Showoff::Config.get(:default)).to be_a(Hash)
      expect(Showoff::Config.get(:default)).to eq({
        :autolink          => true,
        :no_intra_emphasis => true,
        :superscript       => true,
        :tables            => true,
        :underline         => true,
        :escape_html       => false,
      })
    end

    it "expands sections" do
      expect(Showoff::Config.sections).to be_a(Hash)
      expect(Showoff::Config.sections['.']).to be_an(Array)
      expect(Showoff::Config.sections['.']).to all be_a(String)

      expect(Showoff::Config.sections['.']).to eq(['Overview.md', 'Content.md'])
      expect(Showoff::Config.sections.keys).to eq(['.', 'slides', '. (2)'])
    end
  end

  context 'with named hash sections' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'namedhash.json'))
    end

    it "loads configuration from disk" do
      expect(Showoff::Config.root).to eq(fixtures)
      expect(Showoff::Config.keys).to eq(['name', 'description', 'protected', 'version', 'feedback', 'parsers', 'sections', 'markdown', :default, 'pdf_options'])
      expect(Showoff::Config.get('pdf_options')).to eq({:page_size=>"Letter", :orientation=>"Portrait", :print_media_type=>true, :quiet=>false})
    end

    it "expands sections" do
      expect(Showoff::Config.sections).to be_a(Hash)
      expect(Showoff::Config.sections.keys).to eq(['Overview', 'Content', 'Conclusion'])
      expect(Showoff::Config.sections['Overview']).to all be_a(String)
      expect(Showoff::Config.sections['Overview']).to eq(['title.md', 'intro.md', 'about.md'])
    end
  end

  context 'with configured markdown renderer' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'renderer.json'))
    end

    it "loads configuration from disk" do
      expect(Showoff::Config.root).to eq(fixtures)
      expect(Showoff::Config.keys).to eq(['name', 'description', 'protected', 'version', 'feedback', 'parsers', 'sections', 'markdown', 'maruku', 'pdf_options'])
    end

    it "loads proper markdown profile" do
      expect(Showoff::Config.get('markdown')).to eq('maruku')
      expect(Showoff::Config.get('maruku')).to be_a(Hash)
      expect(Showoff::Config.get('maruku')).to eq({
        :use_tex           => false,
        :png_dir           => 'images',
        :html_png_url      => '/file/images/',
      })
    end
  end

  context 'complex config file' do
    before(:each) do
      Showoff::Config.load(File.join(fixtures, 'complex', 'showoff.json'))
    end

    it "loads configuration from disk" do
      expect(Showoff::Config.root).to eq(File.join(fixtures, 'complex'))

      expect(Showoff::Config.keys).to eq(["name", "description", "pdf_options", "sections", "markdown", :default])
      expect(Showoff::Config.sections['Overview']).to eq(['Overview/objectives.md', 'Overview/overview.md'])
      expect(Showoff::Config.sections['Environment']).to eq(["environment/one.md", "environment/two.md"])
      expect(Showoff::Config.sections['Appendix']).to eq(['Shared/Appendix/appendix.md'])
      expect(Showoff::Config.get('pdf_options')).to eq({:page_size=>"Letter", :orientation=>"Landscape", :print_media_type=>true, :quiet=>true})
    end

  end
end
