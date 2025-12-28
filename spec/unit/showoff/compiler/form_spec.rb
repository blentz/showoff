RSpec.describe Showoff::Compiler::Form do
  describe '.render!' do
    it 'returns early when no form option provided' do
      doc = Nokogiri::HTML::DocumentFragment.parse('<p>No form</p>')
      result = described_class.render!(doc, {})
      expect(result).to be_nil
    end

    it 'creates form wrapper with correct attributes' do
      content = '<p>name = ___</p>'
      doc = Nokogiri::HTML::DocumentFragment.parse(content)
      described_class.render!(doc, form: 'testform')

      form = doc.at('form')
      expect(form).not_to be_nil
      expect(form['id']).to eq('testform')
      expect(form['action']).to eq('form/testform')
      expect(form['method']).to eq('POST')
    end

    it 'creates tools div with display and save buttons' do
      content = '<p>name = ___</p>'
      doc = Nokogiri::HTML::DocumentFragment.parse(content)
      described_class.render!(doc, form: 'testform')

      tools = doc.at('div.tools')
      expect(tools).not_to be_nil

      display_btn = tools.at('input.display')
      expect(display_btn).not_to be_nil
      expect(display_btn['type']).to eq('button')

      save_btn = tools.at('input.save')
      expect(save_btn).not_to be_nil
      expect(save_btn['type']).to eq('submit')
      expect(save_btn['disabled']).to eq('disabled')
    end
  end

  describe '.form_element_text' do
    it 'creates text input with size' do
      result = described_class.form_element_text('q1', 'name', '50')
      expect(result).to include("type='text'")
      expect(result).to include("size='50'")
      expect(result).to include("name='name'")
    end
  end

  describe '.form_element_textarea' do
    it 'creates textarea with specified rows' do
      result = described_class.form_element_textarea('q1', 'comments', '10')
      expect(result).to include('textarea')
      expect(result).to include("rows='10'")
      expect(result).to include("name='comments'")
    end

    it 'defaults to 3 rows when empty' do
      result = described_class.form_element_textarea('q1', 'comments', '')
      expect(result).to include("rows='3'")
    end
  end

  describe '.form_element_select' do
    it 'creates select with options' do
      result = described_class.form_element_select('q1', 'choice', ['one', 'two', 'three'])
      expect(result).to include('<select')
      expect(result).to include('</select>')
      expect(result).to include("value='one'")
      expect(result).to include("value='two'")
      expect(result).to include("value='three'")
    end

    it 'marks parentheses-wrapped item as selected' do
      result = described_class.form_element_select('q1', 'choice', ['one', '(two)', 'three'])
      expect(result).to match(/value='two'.*selected/)
    end

    it 'marks bracket-wrapped item as correct' do
      result = described_class.form_element_select('q1', 'choice', ['one', '[two]', 'three'])
      expect(result).to match(/value='two'.*class='correct'/)
    end
  end

  describe '.form_checked?' do
    it 'returns checked attribute when x present' do
      expect(described_class.form_checked?('x')).to eq("checked='checked'")
      expect(described_class.form_checked?('X')).to eq("checked='checked'")
    end

    it 'returns empty string when no x' do
      expect(described_class.form_checked?('')).to eq('')
      expect(described_class.form_checked?('=')).to eq('')
    end
  end

  describe '.form_classes' do
    it 'includes response class always' do
      expect(described_class.form_classes('')).to include('response')
    end

    it 'includes correct class when = present' do
      expect(described_class.form_classes('=')).to include('correct')
      expect(described_class.form_classes('x=')).to include('correct')
    end

    it 'excludes correct class when no =' do
      expect(described_class.form_classes('x')).not_to include('correct')
    end
  end

  describe '.form_element_radio' do
    it 'creates radio inputs' do
      items = [['', 'yes'], ['=', 'no']]
      result = described_class.form_element_radio('q1', 'answer', items)
      expect(result).to include("type='radio'")
      expect(result).to include("value='yes'")
      expect(result).to include("value='no'")
    end
  end

  describe '.form_element_checkboxes' do
    it 'creates checkbox inputs with array name' do
      items = [['', 'a'], ['x', 'b']]
      result = described_class.form_element_checkboxes('q1', 'opts', items)
      expect(result).to include("type='checkbox'")
      expect(result).to include("name='opts[]'")
      expect(result).to include("checked='checked'")
    end
  end

  # This is a pretty boring quick "integration" test of the full form.
  # The individual widgets should each be tested individually.
  it "renders examples of all elements" do
#     markdown = File.read(File.join(fixtures, 'forms', 'elements.md'))
#     content  = Tilt[:markdown].new(nil, nil, {}) { markdown }.render
    content = <<-EOF
<h1>This is a slide with some questions</h1>
<p>correct -&gt; This question has a correct answer. =
(=) True
() False</p>
<p>none -&gt; This question has no correct answer. =
() True
() False</p>
<p>named -&gt; This question has named answers. =
() one -&gt; the first answer
(=) two -&gt; the second answer
() three -&gt; the third answer</p>
<p>correctcheck -&gt; This question has a correct answer. =
[=] True
[] False</p>
<p>nonecheck -&gt; This question has no correct answer. =
[] True
[] False</p>
<p>namedcheck -&gt; This question has named answers. =
[] one -&gt; the first answer
[=] two -&gt; the second answer
[] three -&gt; the third answer</p>
<p>name = ___</p>
<p>namelength = ___[50]</p>
<p>nametoken -&gt; What is your name? = ___[50]</p>
<p>comments = [   ]</p>
<p>commentsrows = [   5]</p>
<p>smartphone = () iPhone () Android () other -&gt; Any other phone not listed</p>
<p>awake -&gt; Are you paying attention? = (x) No () Yes</p>
<p>smartphonecheck = [] iPhone [] Android [x] other -&gt; Any other phone not listed</p>
<p>phoneos -&gt; Which phone OS is developed by Google? = {iPhone, [Android], Other }</p>
<p>smartphonecombo = {iPhone, Android, (Other) }</p>
<p>smartphonetoken = {iPhone, Android, (other -&gt; Any other phone not listed) }</p>
<p>cuisine -&gt; What is your favorite cuisine? = { American, Italian, French }</p>
<p>cuisinetoken -&gt; What is your favorite cuisine? = {
US -&gt; American
IT -&gt; Italian
FR -&gt; French
}</p>
EOF

    doc = Nokogiri::HTML::DocumentFragment.parse(content)

    # This call mutates the passed in object
    Showoff::Compiler::Form.render!(doc, :form => 'foo')

    expect(doc).to be_a(Nokogiri::HTML::DocumentFragment)
    expect(doc.search('ul').size).to eq(6)      # each long form radio/check question
    expect(doc.search('li').size).to eq(14)     # all long form radio/check answers
    expect(doc.search('label').size).to eq(41)  # labels for every question/response widget
    expect(doc.search('input').size).to eq(27)  # answers, plus the tool buttons
    expect(doc.search('input[type=radio]').size).to eq(12)    # includes the single line widget
    expect(doc.search('input[type=checkbox]').size).to eq(10) # includes the single line widget
    expect(doc.search('input[type=text]').size).to eq(3)
    expect(doc.search('textarea').size).to eq(2)
    expect(doc.search('select').size).to eq(5)
  end

  describe '.form_element_select_multiline' do
    it 'parses multiline select options' do
      text = "question = {\n   US -> American\n   IT -> Italian\n   FR -> French\n}"
      result = described_class.form_element_select_multiline('q1', 'country', text)
      expect(result).to include('<select')
      expect(result).to include("value='US'")
      expect(result).to include('>American</option>')
    end

    it 'handles selected option with parentheses' do
      text = "question = {\n   (US -> United States)\n}"
      result = described_class.form_element_select_multiline('q1', 'country', text)
      expect(result).to include('selected')
    end

    it 'handles correct option with brackets' do
      text = "question = {\n   [US -> United States]\n}"
      result = described_class.form_element_select_multiline('q1', 'country', text)
      expect(result).to include("class='correct'")
    end
  end

  describe '.form_element_multiline' do
    it 'creates list of radio inputs' do
      text = "question =\n(=) yes -> Yes\n() no -> No"
      result = described_class.form_element_multiline('q1', 'answer', text)
      expect(result).to include('<ul>')
      expect(result).to include('<li>')
      expect(result).to include("type='radio'")
    end

    it 'creates list of checkbox inputs' do
      text = "question =\n[=] opt1 -> Option 1\n[] opt2 -> Option 2"
      result = described_class.form_element_multiline('q1', 'opts', text)
      expect(result).to include("type='checkbox'")
    end
  end

  describe '.form_element_check_or_radio_set' do
    it 'handles items with arrow notation' do
      items = [['', 'yes -> Yes option'], ['=', 'no -> No option']]
      result = described_class.form_element_check_or_radio_set('radio', 'q1', 'answer', items)
      expect(result).to include("value='yes'")
      expect(result).to include('>Yes option</label>')
    end

    it 'handles items without arrow notation' do
      items = [['', 'simple']]
      result = described_class.form_element_check_or_radio_set('radio', 'q1', 'answer', items)
      expect(result).to include("value='simple'")
      expect(result).to include('>simple</label>')
    end
  end

  describe '.form_element' do
    it 'creates text input element' do
      result = described_class.form_element('q1', 'name', 'Name', false, '___[50]', 'name = ___[50]')
      expect(result).to include('form element')
      expect(result).to include("type='text'")
    end

    it 'creates textarea element' do
      result = described_class.form_element('q1', 'comments', 'Comments', false, '[   5]', 'comments = [   5]')
      expect(result).to include('textarea')
      expect(result).to include("rows='5'")
    end

    it 'marks required elements' do
      result = described_class.form_element('q1', 'name', 'Name', true, '___', 'name *= ___')
      expect(result).to include('required')
    end
  end
end



