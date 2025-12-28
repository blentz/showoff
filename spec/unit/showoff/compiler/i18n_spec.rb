RSpec.describe Showoff::Compiler::I18n do
  before(:each) do
    Showoff::Config.load(File.join(fixtures, 'i18n', 'showoff.json'))
  end

  it "selects the correct language" do
    content = <<-EOF
# This is a simple markdown slide

~~~LANG:en~~~
Hello, world!
~~~ENDLANG~~~

~~~LANG:fr~~~
Bonjour tout le monde!
~~~ENDLANG~~~
EOF

    Showoff::Locale.setContentLocale(:fr)

    # This call mutates the passed in object
    Showoff::Compiler::I18n.selectLanguage!(content)

    expect(content).to be_a(String)
    expect(content).to match(/Bonjour tout le monde!/)
    expect(content).not_to match(/Hello, world!/)
    expect(content).not_to match(/~~~LANG:[\w-]+~~~/)
    expect(content).not_to match(/~~~ENDLANG~~~/)
  end

  it "includes no languages if they don't match" do
    content = <<-EOF
# This is a simple markdown slide

~~~LANG:en~~~
Hello, world!
~~~ENDLANG~~~

~~~LANG:fr~~~
Bonjour tout le monde!
~~~ENDLANG~~~
EOF

    Showoff::Locale.setContentLocale(:js)

    # This call mutates the passed in object
    Showoff::Compiler::I18n.selectLanguage!(content)

    expect(content).to be_a(String)
    expect(content).not_to match(/Bonjour tout le monde!/)
    expect(content).not_to match(/Hello, world!/)
    expect(content).not_to match(/~~~LANG:[\w-]+~~~/)
    expect(content).not_to match(/~~~ENDLANG~~~/)
  end

  it "includes no languages if local is unset" do
    content = <<-EOF
# This is a simple markdown slide

~~~LANG:en~~~
Hello, world!
~~~ENDLANG~~~

~~~LANG:fr~~~
Bonjour tout le monde!
~~~ENDLANG~~~
EOF

    # This call mutates the passed in object
    Showoff::Compiler::I18n.selectLanguage!(content)

    expect(content).to be_a(String)
    expect(content).not_to match(/Bonjour tout le monde!/)
    expect(content).not_to match(/Hello, world!/)
    expect(content).not_to match(/~~~LANG:[\w-]+~~~/)
    expect(content).not_to match(/~~~ENDLANG~~~/)
  end

  it "handles content with no language blocks" do
    content = "# This is a simple markdown slide with no language blocks"
    original = content.dup

    Showoff::Locale.setContentLocale(:en)
    result = Showoff::Compiler::I18n.selectLanguage!(content)

    expect(result).to eq(content)
    expect(content).to eq(original) # Content should be unchanged
  end

  it "handles empty content" do
    content = ""

    Showoff::Locale.setContentLocale(:en)
    result = Showoff::Compiler::I18n.selectLanguage!(content)

    expect(result).to eq("")
    expect(content).to eq("")
  end

  it "returns modified content" do
    content = <<-EOF
# Slide with language block

~~~LANG:de~~~
Deutsches Inhalt
~~~ENDLANG~~~

~~~LANG:fr~~~
Ligne 1
Ligne 2
Ligne 3
~~~ENDLANG~~~
EOF

    Showoff::Locale.setContentLocale(:en)
    # Resolve picks the best match from available languages
    Showoff::Locale.setContentLocale(:de)
    result = Showoff::Compiler::I18n.selectLanguage!(content)

    expect(result).to eq(content)
    expect(content).to include('Deutsches Inhalt')
  end
end