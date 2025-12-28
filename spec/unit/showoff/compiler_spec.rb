RSpec.describe Showoff::Compiler do

  it "resolves the default renderer properly" do
    expect(Showoff::Config).to receive(:get).with('markdown').and_return(:default)
    expect(Showoff::Config).to receive(:get).with(:default).and_return({})
    expect(Tilt).to receive(:prefer).with(Tilt::RedcarpetTemplate, 'markdown')
    #expect(Tilt.template_for('markdown')).to eq(Tilt::RedcarpetTemplate)     # polluted state doesn't allow this to succeed deterministically

    Showoff::Compiler.new({:name => 'foo'})
  end

  it "resolves a configured renderer" do
    expect(Showoff::Config).to receive(:get).with('markdown').and_return('commonmarker')
    expect(Showoff::Config).to receive(:get).with('commonmarker').and_return({})
    expect(Tilt).to receive(:prefer).with(Tilt::CommonMarkerTemplate, 'markdown')
    #expect(Tilt.template_for('markdown')).to eq(Tilt::CommonMarkerTemplate)  # polluted state doesn't allow this to succeed deterministically

    Showoff::Compiler.new({:name => 'foo'})
  end

  it "errors when configured with an unknown renderer" do
    expect(Showoff::Config).to receive(:get).with('markdown').and_return('wrong')
    expect(Showoff::Config).to receive(:get).with('wrong').and_return({})

    expect { Showoff::Compiler.new({:name => 'foo'}) }.to raise_error(StandardError, 'Unsupported markdown renderer')
  end

  # note that this test is basically a simple integration test of all the compiler components.
  it "renders content as expected" do
    Showoff::Config.load(File.join(fixtures, 'base.json'))

    content, notes = Showoff::Compiler.new({:name => 'foo'}).render("#Hi there!\n\n.callout The Internet is serious business.")

    expect(content).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(notes).to be_a(Nokogiri::XML::NodeSet)
    expect(notes.empty?).to be_truthy

    expect(content.search('h1').first.text).to eq('Hi there!')
    expect(content.search('p').first.text).to eq('The Internet is serious business.')
    expect(content.search('p').first.classes).to eq(['callout'])
  end

  it "renders empty content" do
    Showoff::Config.load(File.join(fixtures, 'base.json'))

    content, notes = Showoff::Compiler.new({:name => 'empty'}).render('')

    expect(content).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(notes).to be_a(Nokogiri::XML::NodeSet)
  end

  it "stores form option in context" do
    Showoff::Config.load(File.join(fixtures, 'base.json'))
    compiler = Showoff::Compiler.new({ name: 'foo', form: 'testform' })
    expect(compiler.instance_variable_get(:@options)[:form]).to eq('testform')
  end

  it "stores seq option in context" do
    Showoff::Config.load(File.join(fixtures, 'base.json'))
    compiler = Showoff::Compiler.new({ name: 'foo', seq: 5 })
    expect(compiler.instance_variable_get(:@options)[:seq]).to eq(5)
  end

  it "handles content with notes sections" do
    Showoff::Config.load(File.join(fixtures, 'base.json'))

    content_with_notes = "# Title\n\n~~~SECTION:notes~~~\nThese are speaker notes\n~~~ENDSECTION~~~"
    content, notes = Showoff::Compiler.new({:name => 'foo'}).render(content_with_notes)

    expect(content).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(notes).to be_a(Nokogiri::XML::NodeSet)
  end

  it "resolves kramdown renderer", skip: "kramdown gem not installed in test environment" do
    expect(Showoff::Config).to receive(:get).with('markdown').and_return('kramdown')
    expect(Showoff::Config).to receive(:get).with('kramdown').and_return({})
    expect(Tilt).to receive(:prefer).with(Tilt::KramdownTemplate, 'markdown')

    Showoff::Compiler.new({:name => 'foo'})
  end

end
