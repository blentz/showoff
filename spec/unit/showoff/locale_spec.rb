RSpec.describe Showoff::Locale do
  before(:each) do
    Showoff::Config.load(File.join(fixtures, 'i18n', 'showoff.json'))
  end

  it "selects a default content language" do
    expect(I18n.available_locales.include?(Showoff::Locale.setContentLocale)).to be_truthy
  end

  it "allows user to set content language" do
    Showoff::Locale.setContentLocale(:de)
    expect(Showoff::Locale.contentLocale).to eq(:de)
  end

  it "allows user to set content language with extended codes" do
    Showoff::Locale.setContentLocale('de-li')
    expect(Showoff::Locale.contentLocale).to eq(:de)
  end

  it "returns the name of a language code" do
    Showoff::Locale.setContentLocale(:de)
    expect(Showoff::Locale.languageName).to eq('German')
  end

  it "interpolates the proper content path when it exists" do
    Showoff::Locale.setContentLocale(:de)
    expect(Showoff::Locale.contentPath).to eq(File.join(fixtures, 'i18n', 'locales', 'de'))
  end

  it "interpolates the proper content path when it does not exist" do
    Showoff::Locale.setContentLocale(:ja)
    expect(Showoff::Locale.contentPath).to eq(File.join(fixtures, 'i18n'))
  end

  it "returns the appropriate content language hash" do
    expect(Showoff::Locale.contentLanguages).to eq({"de"=>"German", "en"=>"English", "es"=>"Spanish; Castilian", "fr"=>"French", "ja"=>"Japanese"})
  end

  it "returns UI string translations" do
    expect(Showoff::Locale.translations[:menu][:title]).to be_a(String)
  end

  it "retrieves the proper translations from strings.json" do
    Showoff::Locale.setContentLocale(:de)
    expect(Showoff::Locale.userTranslations).to eq({'greeting' => 'Hallo!'})
  end

  it "retrieves an empty hash from strings.json when the key doesn't exist" do
    Showoff::Locale.setContentLocale(:nl)
    expect(Showoff::Locale.userTranslations).to eq({})
  end

  describe '.resolve' do
    it 'finds a matching locale in items array' do
      Showoff::Locale.setContentLocale(:de)
      result = Showoff::Locale.resolve(['en', 'de', 'fr'])
      expect(result).to eq(:de)
    end

    it 'returns nil when no match found' do
      Showoff::Locale.setContentLocale(:zh)
      result = Showoff::Locale.resolve(['en', 'de', 'fr'])
      expect(result).to be_nil
    end

    it 'returns nil for empty items array' do
      Showoff::Locale.setContentLocale(:de)
      result = Showoff::Locale.resolve([])
      expect(result).to be_nil
    end
  end

  describe '.setContentLocale' do
    it 'handles nil locale' do
      result = Showoff::Locale.setContentLocale(nil)
      expect(I18n.available_locales).to include(result)
    end

    it 'handles empty string locale' do
      result = Showoff::Locale.setContentLocale('')
      expect(I18n.available_locales).to include(result)
    end

    it 'handles auto locale' do
      result = Showoff::Locale.setContentLocale('auto')
      expect(I18n.available_locales).to include(result)
    end
  end

  describe '.languageName' do
    it 'returns nil for invalid locale' do
      expect(Showoff::Locale.languageName('zzz')).to be_nil
    end

    it 'returns language name for valid locale' do
      expect(Showoff::Locale.languageName('en')).to eq('English')
    end
  end

  describe '.userTranslations' do
    it 'returns empty hash when strings.json does not exist' do
      allow(File).to receive(:file?).and_return(false)
      expect(Showoff::Locale.userTranslations).to eq({})
    end
  end

end
