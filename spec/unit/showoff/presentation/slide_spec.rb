RSpec.describe Showoff::Presentation::Slide do

  before(:each) do
    # Reset the Showoff::State before each test
    Showoff::State.reset
  end

  it 'parses class and form metadata settings' do
    context = {:section=>".", :name=>"first.md", :seq=>nil}
    options = "first title form=noodles"
    content = <<-EOF
# First slide

This little piggy went to market.
EOF

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["first", "title"])
    expect(subject.form).to eq('noodles')
    expect(subject.id).to eq('first')
    expect(subject.name).to eq('first')
    expect(subject.ref).to eq('first')
    expect(subject.section).to eq('.')
    expect(subject.section_title).to eq('.')
    expect(subject.seq).to be_nil
    expect(subject.transition).to eq('none')
  end

  it 'parses a background metadata setting' do
    context = {:section=>".", :name=>"content.md", :seq=>1}
    options = "[bg=bg.png] one"
    content = <<-EOF
# One

This little piggy stayed home.
EOF

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["one"])
    expect(subject.id).to eq('content1')
    expect(subject.name).to eq('content')
    expect(subject.ref).to eq('content:1')
    expect(subject.seq).to eq(1)
    expect(subject.background).to eq('bg.png')
  end

  it 'parses a slide class and sets section title' do
    context = {:section=>".", :name=>"content.md", :seq=>2}
    options = "two piggy subsection"
    content = <<-EOF
# Two

This little piggy had roast beef.
EOF

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["two", "piggy", "subsection"])
    expect(subject.id).to eq('content2')
    expect(subject.name).to eq('content')
    expect(subject.ref).to eq('content:2')
    expect(subject.section).to eq('.')
    expect(subject.section_title).to eq('Two')
    expect(subject.seq).to eq(2)
  end

  it 'parses a transition as an option and maintains section title' do
    # Set up a prior section title (simulating a prior subsection slide)
    Showoff::State.set(:section_title, 'Two')

    context = {:section=>".", :name=>"content.md", :seq=>3}
    options = "[transition=fade] three"
    content = <<-EOF
# Three

This little piggy had none.
EOF

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["three"])
    expect(subject.id).to eq('content3')
    expect(subject.name).to eq('content')
    expect(subject.ref).to eq('content:3')
    expect(subject.section).to eq('.')
    expect(subject.section_title).to eq('Two')
    expect(subject.seq).to eq(3)
    expect(subject.transition).to eq('fade')
  end

  it 'parses a transition as a weirdo class' do
    context = {:section=>".", :name=>"last.md", :seq=>nil}
    options = "last bigtext transition=fade"
    content = <<-EOF
# Last

This little piggy cried wee wee wee all the way home.
EOF

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["last", "bigtext"])
    expect(subject.id).to eq('last')
    expect(subject.name).to eq('last')
    expect(subject.ref).to eq('last')
    expect(subject.seq).to be_nil
    expect(subject.transition).to eq('fade')
  end

  it 'blacklists known bad classes' do
    context = {:section=>".", :name=>"last.md", :seq=>nil}
    options = "last bigtext transition=fade"
    content = <<-EOF
# Last

This little piggy cried wee wee wee all the way home.
EOF

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["last", "bigtext"])
    expect(subject.slideClasses).to eq(["last"])
  end

  it 'maintains proper slide counts' do
    content = <<-EOF
# First slide
EOF

    Showoff::State.reset
    Showoff::Presentation::Slide.new('', content, {:section=>".", :name=>"state.md", :seq=>1}).render
    Showoff::Presentation::Slide.new('', content, {:section=>".", :name=>"state.md", :seq=>2}).render
    Showoff::Presentation::Slide.new('', content, {:section=>".", :name=>"state.md", :seq=>3}).render
    Showoff::Presentation::Slide.new('', content, {:section=>".", :name=>"state.md", :seq=>4}).render

    expect(Showoff::State.get(:slide_count)).to eq(4)
  end

  # New tests for edge cases and untested methods

  it 'handles empty content' do
    context = {:section=>".", :name=>"empty.md", :seq=>nil}
    options = "empty"
    content = ""

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["empty"])
    expect(subject.markdown).to eq("")
    expect(subject.id).to eq('empty')
    expect(subject.name).to eq('empty')
    expect(subject.ref).to eq('empty')
  end

  it 'handles nil options' do
    context = {:section=>".", :name=>"no_options.md", :seq=>nil}
    options = nil
    content = "# No Options"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq([])
    expect(subject.id).to eq('no_options')
    expect(subject.name).to eq('no_options')
    expect(subject.ref).to eq('no_options')
    expect(subject.transition).to eq('none')
  end

  it 'handles missing classes' do
    context = {:section=>".", :name=>"no_classes.md", :seq=>nil}
    options = "[]"
    content = "# No Classes"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq([])
    expect(subject.id).to eq('no_classes')
  end

  it 'handles id specified in options' do
    context = {:section=>".", :name=>"content.md", :seq=>nil}
    options = "[id=custom_id]"
    content = "# Custom ID"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.id).to eq('custom_id')
  end

  it 'handles id specified in classes' do
    context = {:section=>".", :name=>"content.md", :seq=>nil}
    options = "slide #custom_id"
    content = "# Custom ID"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["slide"])
    expect(subject.id).to eq('custom_id')
  end

  it 'sanitizes id from name with special characters' do
    context = {:section=>".", :name=>"special!@#$%^&*().md", :seq=>nil}
    options = "slide"
    content = "# Special Characters"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    # Special characters are replaced with underscores
    expect(subject.id).to match(/^special_+$/)
    # Just verify it's sanitized (exact count depends on implementation)
    expect(subject.id).not_to include('!')
    expect(subject.id).not_to include('@')
  end

  it 'handles form specified in options' do
    context = {:section=>".", :name=>"form.md", :seq=>nil}
    options = "[form=survey]"
    content = "# Form"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.form).to eq('survey')
  end

  it 'handles form specified in classes' do
    context = {:section=>".", :name=>"form.md", :seq=>nil}
    options = "slide form=survey"
    content = "# Form"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.classes).to eq(["slide"])
    expect(subject.form).to eq('survey')
  end

  it 'handles template specified in options' do
    context = {:section=>".", :name=>"template.md", :seq=>nil}
    options = "[tpl=custom]"
    content = "# Template"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.instance_variable_get(:@template)).to eq('custom')
  end

  it 'handles template specified with full name in options' do
    context = {:section=>".", :name=>"template.md", :seq=>nil}
    options = "[template=custom]"
    content = "# Template"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.instance_variable_get(:@template)).to eq('custom')
  end

  it 'handles transition specified in options' do
    context = {:section=>".", :name=>"transition.md", :seq=>nil}
    options = "[transition=slide]"
    content = "# Transition"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.transition).to eq('slide')
  end

  it 'handles unknown options with a warning' do
    context = {:section=>".", :name=>"unknown.md", :seq=>nil}
    options = "[unknown=value]"
    content = "# Unknown"

    expect(Showoff::Logger).to receive(:warn).with("Unknown slide option: unknown=value")

    subject = Showoff::Presentation::Slide.new(options, content, context)
  end

  it 'handles subsection with a header' do
    context = {:section=>".", :name=>"has_header.md", :seq=>nil}
    options = "subsection"
    content = "# My Section Title\n\nContent here"

    subject = Showoff::Presentation::Slide.new(options, content, context)

    expect(subject.section_title).to eq('My Section Title')
  end

  describe '#render' do
    let(:content) { "# Test Slide" }
    let(:context) { {:section=>".", :name=>"test.md", :seq=>nil} }
    let(:options) { "test" }
    let(:slide) { Showoff::Presentation::Slide.new(options, content, context) }

    it 'increments the slide count' do
      expect(Showoff::State).to receive(:increment).with(:slide_count)
      slide.render
    end

    it 'creates a compiler and renders content' do
      # Just verify render produces output without crashing
      result = slide.render
      expect(result).to be_a(String)
      expect(result).to match(/class="slide[^"]*"/)
    end
  end
end