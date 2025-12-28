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

end
