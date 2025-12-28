RSpec.describe Showoff::Compiler::Downloads do
  content = <<-EOF
<h1>This is a simple HTML slide with download tags</h1>
<p>Here are a few tags that should be transformed to attachments</p>
<p class="download">link/to/one.txt
.download link/to/two.txt all
.download link/to/three.txt prev
.download link/to/four.txt current
.download link/to/five.txt next</p>
EOF

  tests = {
    :all  => {:slide =>  0, :files => ['link/to/two.txt']},
    :pre  => {:slide => 21, :files => []},
    :prev => {:slide => 22, :files => ['link/to/three.txt']},
    :curr => {:slide => 23, :files => ['link/to/four.txt']},
    :next => {:slide => 24, :files => ['link/to/one.txt', 'link/to/five.txt']},
    :post => {:slide => 25, :files => []},
  }

  tests.each do |period, data|
    it "transforms download tags to #{period} slide attachments" do
      doc = Nokogiri::HTML::DocumentFragment.parse(content)

      Showoff::State.reset()
      Showoff::State.set(:slide_count, 23)

      # This call mutates the passed in object
      Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'foo')
      elements = doc.search('p')
      slide = data[:slide]
      files = data[:files]

      expect(doc).to be_a(Nokogiri::HTML::DocumentFragment)
      expect(elements.length).to eq(1)
      expect(Showoff::Compiler::Downloads.getFiles(slide)).to eq([])

      Showoff::Compiler::Downloads.enableFiles(slide)
      expect(Showoff::Compiler::Downloads.getFiles(slide).size).to eq(files.length)
      expect(Showoff::Compiler::Downloads.getFiles(slide).map{|a| a[:source] }).to all eq('foo')
      expect(Showoff::Compiler::Downloads.getFiles(slide).map{|a| a[:slidenum] }).to all eq(23)
      expect(Showoff::Compiler::Downloads.getFiles(slide).map{|a| a[:file] }).to eq(files)
    end
  end

  it "removes a paragraph of download tags from document" do
    doc = Nokogiri::HTML::DocumentFragment.parse(content)
    Showoff::State.set(:slide_count, 23)

    # This call mutates the passed in object
    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'foo')
    elements = doc.search('p')

    expect(doc).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(elements.length).to eq(1)
  end

  it "returns an empty array for a blank stack" do
    Showoff::State.reset()

    expect(Showoff::Compiler::Downloads.getFiles(12)).to eq([])
  end

  it "pushes a file onto the attachment stack" do
    Showoff::State.reset()

    expect(Showoff::Compiler::Downloads.pushFile(12, 12, 'foo', 'path/to/file.txt')[:enabled]).to be_falsey
    expect(Showoff::Compiler::Downloads.getFiles(12)).to eq([])
    Showoff::State.get(:downloads)[12] = {:enabled=>false, :slides=>[{:slidenum=>12, :source=>"foo", :file=>"path/to/file.txt"}]}
  end

  it "enables a download properly" do
    Showoff::State.reset()

    expect(Showoff::Compiler::Downloads.pushFile(12, 12, 'foo', 'path/to/file.txt')[:enabled]).to be_falsey
    expect(Showoff::Compiler::Downloads.getFiles(12)).to eq([])

    Showoff::Compiler::Downloads.enableFiles(12)
    expect(Showoff::Compiler::Downloads.getFiles(12)).to eq([{:slidenum=>12, :source=>"foo", :file=>"path/to/file.txt"}])
  end

  # Additional tests for better coverage

  it "handles multiple files pushed to the same index" do
    Showoff::State.reset()

    Showoff::Compiler::Downloads.pushFile(5, 10, 'source1', 'file1.txt')
    Showoff::Compiler::Downloads.pushFile(5, 11, 'source2', 'file2.pdf')

    Showoff::Compiler::Downloads.enableFiles(5)
    files = Showoff::Compiler::Downloads.getFiles(5)

    expect(files.size).to eq(2)
    expect(files[0][:file]).to eq('file1.txt')
    expect(files[0][:slidenum]).to eq(10)
    expect(files[0][:source]).to eq('source1')
    expect(files[1][:file]).to eq('file2.pdf')
    expect(files[1][:slidenum]).to eq(11)
    expect(files[1][:source]).to eq('source2')
  end

  it "handles the 'always' modifier correctly" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt always</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(0)
    files = Showoff::Compiler::Downloads.getFiles(0)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "handles the 'a' modifier as an alias for 'always'" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt a</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(0)
    files = Showoff::Compiler::Downloads.getFiles(0)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "handles the 'now' modifier as an alias for 'always'" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt now</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(0)
    files = Showoff::Compiler::Downloads.getFiles(0)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "handles the 'p' modifier as an alias for 'prev'" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt p</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(4)
    files = Showoff::Compiler::Downloads.getFiles(4)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "handles the 'c' modifier as an alias for 'current'" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt c</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(5)
    files = Showoff::Compiler::Downloads.getFiles(5)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "handles the 'n' modifier as an alias for 'next'" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt n</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(6)
    files = Showoff::Compiler::Downloads.getFiles(6)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "uses 'next' as the default modifier when none is specified" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download file.txt</p>')
    Showoff::State.reset()
    Showoff::State.set(:slide_count, 5)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(6)
    files = Showoff::Compiler::Downloads.getFiles(6)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('file.txt')
    expect(files[0][:slidenum]).to eq(5)
  end

  it "handles multiple file types correctly" do
    # Each download must be in its own paragraph
    doc = Nokogiri::HTML::DocumentFragment.parse(<<-EOF
      <p class="download">.download image.png next</p>
      <p class="download">.download document.pdf next</p>
      <p class="download">.download code.rb next</p>
      <p class="download">.download archive.zip next</p>
    EOF
    )

    Showoff::State.reset()
    Showoff::State.set(:slide_count, 10)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(11)
    files = Showoff::Compiler::Downloads.getFiles(11)

    expect(files.size).to eq(4)
    expect(files.map{|f| f[:file]}).to eq(['image.png', 'document.pdf', 'code.rb', 'archive.zip'])
  end

  it "handles files with paths correctly" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download">.download path/to/deep/file.txt next</p>')

    Showoff::State.reset()
    Showoff::State.set(:slide_count, 10)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    Showoff::Compiler::Downloads.enableFiles(11)
    files = Showoff::Compiler::Downloads.getFiles(11)

    expect(files.size).to eq(1)
    expect(files[0][:file]).to eq('path/to/deep/file.txt')
  end

  it "handles empty download paragraphs gracefully" do
    doc = Nokogiri::HTML::DocumentFragment.parse('<p class="download"></p>')

    Showoff::State.reset()
    Showoff::State.set(:slide_count, 10)

    result = Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    expect(result).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(doc.search('p').length).to eq(0)
  end

  it "handles enableFiles with non-existent records" do
    Showoff::State.reset()

    # This should not raise an error
    Showoff::Compiler::Downloads.enableFiles(999)

    expect(Showoff::Compiler::Downloads.getFiles(999)).to eq([])
  end

  it "properly handles multiple download paragraphs" do
    doc = Nokogiri::HTML::DocumentFragment.parse(<<-EOF
      <p class="download">.download file1.txt next</p>
      <p>Regular paragraph</p>
      <p class="download">.download file2.txt next</p>
    EOF
    )

    Showoff::State.reset()
    Showoff::State.set(:slide_count, 10)

    Showoff::Compiler::Downloads.scanForFiles!(doc, :name => 'test')

    expect(doc.search('p').length).to eq(1)
    expect(doc.search('p').text).to eq('Regular paragraph')

    Showoff::Compiler::Downloads.enableFiles(11)
    files = Showoff::Compiler::Downloads.getFiles(11)

    expect(files.size).to eq(2)
    expect(files.map{|f| f[:file]}).to eq(['file1.txt', 'file2.txt'])
  end
end