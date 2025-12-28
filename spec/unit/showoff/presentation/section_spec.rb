RSpec.describe Showoff::Presentation::Section do
  before(:each) do
    Showoff::State.reset
  end

  it 'loads files from disk and splits them into slides' do
    Showoff::Config.load(File.join(fixtures, 'slides', 'showoff.json'))
    name, files = Showoff::Config.sections.first
    section = Showoff::Presentation::Section.new(name, files)

    expect(section.name).to eq('.')
    expect(section.slides.size).to eq(5)
    expect(section.slides.map {|slide| slide.id }).to eq(["first", "content1", "content2", "content3", "last"])
  end

  describe 'loadSlides method' do
    it 'skips non-markdown files' do
      allow(File).to receive(:read).and_return("content")
      allow(File).to receive(:join) do |*args|
        args.join('/')
      end

      section = Showoff::Presentation::Section.new('test', ['file.txt'])
      expect(section.slides.size).to eq(0)
    end

    it 'converts H1s to slides when no !SLIDE markers exist' do
      content = "# First Slide\nContent\n\n# Second Slide\nMore content"
      allow(File).to receive(:read).and_return(content)
      allow(File).to receive(:join) do |*args|
        args.join('/')
      end
      allow(Showoff::Locale).to receive(:contentPath).and_return('/path')

      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(2)
      expect(section.slides[0].markdown).to include("# First Slide")
      expect(section.slides[1].markdown).to include("# Second Slide")
    end

    it 'properly splits content by !SLIDE markers' do
      content = "<!SLIDE>\nFirst slide\n\n<!SLIDE>\nSecond slide"
      allow(File).to receive(:read).and_return(content)
      allow(File).to receive(:join) do |*args|
        args.join('/')
      end
      allow(Showoff::Locale).to receive(:contentPath).and_return('/path')

      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(2)
      expect(section.slides[0].markdown.strip).to eq("First slide")
      expect(section.slides[1].markdown.strip).to eq("Second slide")
    end

    it 'assigns sequence numbers to slides when multiple slides exist in a file' do
      content = "<!SLIDE>\nFirst slide\n\n<!SLIDE>\nSecond slide\n\n<!SLIDE>\nThird slide"
      allow(File).to receive(:read).and_return(content)
      allow(File).to receive(:join) do |*args|
        args.join('/')
      end
      allow(Showoff::Locale).to receive(:contentPath).and_return('/path')

      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(3)
      expect(section.slides[0].seq).to eq(1)
      expect(section.slides[1].seq).to eq(2)
      expect(section.slides[2].seq).to eq(3)
    end

    it 'does not assign sequence numbers when only one slide exists in a file' do
      content = "<!SLIDE>\nSingle slide"
      allow(File).to receive(:read).and_return(content)
      allow(File).to receive(:join) do |*args|
        args.join('/')
      end
      allow(Showoff::Locale).to receive(:contentPath).and_return('/path')

      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(1)
      expect(section.slides[0].seq).to be_nil
    end
  end

  describe 'filtering logic' do
    before(:each) do
      allow(File).to receive(:join) do |*args|
        args.join('/')
      end
      allow(Showoff::Locale).to receive(:contentPath).and_return('/path')
    end

    it 'filters out supplemental slides by default' do
      content = "<!SLIDE>\nRegular slide\n\n<!SLIDE supplemental>\nSupplemental slide"
      allow(File).to receive(:read).and_return(content)

      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(1)
      expect(section.slides[0].markdown.strip).to eq("Regular slide")
    end

    it 'includes only specified supplemental slides when supplemental is set' do
      content = "<!SLIDE>\nRegular slide\n\n<!SLIDE supplemental foo>\nSupplemental foo\n\n<!SLIDE supplemental bar>\nSupplemental bar"
      allow(File).to receive(:read).and_return(content)

      Showoff::State.set(:supplemental, 'foo')
      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(1)
      expect(section.slides[0].markdown.strip).to eq("Supplemental foo")
    end

    it 'filters slides based on web format' do
      content = "<!SLIDE>\nRegular slide\n\n<!SLIDE toc>\nTOC slide\n\n<!SLIDE printonly>\nPrint-only slide"
      allow(File).to receive(:read).and_return(content)

      Showoff::State.set(:format, 'web')
      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(1)
      expect(section.slides[0].markdown.strip).to eq("Regular slide")
    end

    it 'filters slides based on print format' do
      content = "<!SLIDE>\nRegular slide\n\n<!SLIDE noprint>\nNo-print slide"
      allow(File).to receive(:read).and_return(content)

      Showoff::State.set(:format, 'print')
      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(1)
      expect(section.slides[0].markdown.strip).to eq("Regular slide")
    end

    it 'does not filter slides when merged is set' do
      content = "<!SLIDE>\nRegular slide\n\n<!SLIDE supplemental>\nSupplemental slide\n\n<!SLIDE toc>\nTOC slide\n\n<!SLIDE printonly>\nPrint-only slide\n\n<!SLIDE noprint>\nNo-print slide"
      allow(File).to receive(:read).and_return(content)

      Showoff::State.set(:merged, true)
      section = Showoff::Presentation::Section.new('test', ['slides.md'])
      expect(section.slides.size).to eq(5)
    end
  end

  describe 'render method' do
    it 'calls render on each slide and joins the results' do
      slide1 = double('slide1')
      slide2 = double('slide2')
      allow(slide1).to receive(:render).and_return('<div>Slide 1</div>')
      allow(slide2).to receive(:render).and_return('<div>Slide 2</div>')

      section = Showoff::Presentation::Section.new('test', [])
      section.instance_variable_set(:@slides, [slide1, slide2])

      expect(section.render).to eq("<div>Slide 1</div>\n<div>Slide 2</div>")
    end
  end
end