require 'spec_helper'
require 'showoff/server/execution_manager'

describe Showoff::Server::ExecutionManager do
  let(:logger) { double('Logger').as_null_object }
  let(:options) do
    {
      pres_dir: File.join(File.dirname(__FILE__), '..', '..', '..', 'fixtures', 'slides'),
      timeout: 5,
      parsers: {
        'ruby' => 'ruby',
        'python' => 'python',
        'shell' => 'sh'
      },
      logger: logger
    }
  end

  subject { described_class.new(options) }

  describe '#initialize' do
    it 'sets default values when options are not provided' do
      manager = described_class.new
      expect(manager.instance_variable_get(:@pres_dir)).to eq(Dir.pwd)
      expect(manager.instance_variable_get(:@timeout)).to eq(15)
      expect(manager.instance_variable_get(:@parsers)).to eq({})
      expect(manager.instance_variable_get(:@logger)).to be_nil
    end

    it 'uses provided options' do
      expect(subject.instance_variable_get(:@pres_dir)).to eq(options[:pres_dir])
      expect(subject.instance_variable_get(:@timeout)).to eq(options[:timeout])
      expect(subject.instance_variable_get(:@parsers)).to eq(options[:parsers])
      expect(subject.instance_variable_get(:@logger)).to eq(options[:logger])
    end
  end

  describe '#execute' do
    context 'when no parser is available for the language' do
      it 'returns an error message' do
        expect(subject.execute('nonexistent', 'puts "Hello"')).to eq('No parser for nonexistent')
      end
    end

    context 'when a parser is available' do
      before do
        allow(Tempfile).to receive(:open).and_yield(double('Tempfile', path: '/tmp/showoff-execution'))
        allow(File).to receive(:write)
        allow(Open3).to receive(:capture2e).and_return(['Command output', double('Status', success?: true)])
      end

      it 'creates a temporary file with the code' do
        expect(File).to receive(:write).with('/tmp/showoff-execution', 'puts "Hello"')
        subject.execute('ruby', 'puts "Hello"')
      end

      it 'executes the code with the appropriate parser using argv array' do
        expect(Open3).to receive(:capture2e).with('ruby', '/tmp/showoff-execution')
        subject.execute('ruby', 'puts "Hello"')
      end

      it 'logs debug information' do
        expect(logger).to receive(:debug).with('Evaluating: ruby /tmp/showoff-execution')
        subject.execute('ruby', 'puts "Hello"')
      end

      it 'returns the command output with newlines converted to <br />' do
        allow(Open3).to receive(:capture2e).and_return(["Line 1\nLine 2", double('Status', success?: true)])
        expect(subject.execute('ruby', 'puts "Hello"')).to eq('Line 1<br />Line 2')
      end

      context 'when the command fails' do
        before do
          allow(Open3).to receive(:capture2e).and_return(['Error message', double('Status', success?: false)])
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with('Command execution failed')
          expect(logger).to receive(:warn).with('Error message')
          subject.execute('ruby', 'puts "Hello"')
        end

        it 'still returns the output' do
          expect(subject.execute('ruby', 'puts "Hello"')).to eq('Error message')
        end
      end

      context 'when execution times out' do
        before do
          allow(Timeout).to receive(:timeout).and_raise(Timeout::Error.new('Execution timed out'))
        end

        it 'returns the error message' do
          expect(subject.execute('ruby', 'puts "Hello"')).to eq('Execution timed out')
        end
      end

      context 'when other exceptions occur' do
        before do
          allow(Timeout).to receive(:timeout).and_raise(StandardError.new('Something went wrong'))
        end

        it 'returns the error message' do
          expect(subject.execute('ruby', 'puts "Hello"')).to eq('Something went wrong')
        end
      end
    end
  end

  describe '#get_code_from_slide' do
    # This is a simplified test since the actual implementation would require
    # more complex fixtures and markdown processing
    let(:slide_content) { '<div><code class="execute language-ruby">puts "Hello"</code></div>' }
    let(:multi_code_slide) do
      '<div>
        <code class="execute language-ruby">puts "Ruby code"</code>
        <code class="execute language-python">print("Python code")</code>
        <code class="execute language-shell">echo "Shell code"</code>
      </div>'
    end
    let(:non_executable_slide) do
      '<div>
        <code class="language-ruby">puts "Non-executable Ruby"</code>
      </div>'
    end
    let(:multi_slide_content) do
      "<!SLIDE\nFirst slide\n<!SLIDE\nSecond slide with code\n<!SLIDE\nThird slide"
    end

    before do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('Slide content')
      allow(subject).to receive(:process_markdown).and_return(slide_content)
    end

    it 'extracts code from a slide' do
      expect(subject.get_code_from_slide('test', 0)).to eq('puts "Hello"')
    end

    it 'returns an empty array if the slide file does not exist' do
      allow(File).to receive(:exist?).and_return(false)
      expect(subject.get_code_from_slide('nonexistent', 0)).to eq([])
    end

    it 'returns an empty array if the slide content is empty' do
      allow(File).to receive(:read).and_return('')
      expect(subject.get_code_from_slide('empty', 0)).to eq([])
    end

    it 'returns an empty array if the slide content is nil' do
      allow(File).to receive(:read).and_return(nil)
      expect(subject.get_code_from_slide('nil_content', 0)).to eq([])
    end

    it 'returns an error message if the code block index is invalid' do
      expect(subject.get_code_from_slide('test', 1)).to eq('Invalid code block index')
    end

    context 'when index is "all"' do
      it 'returns an array of all code blocks with their languages and classes' do
        expect(subject.get_code_from_slide('test', 'all')).to eq([[nil, 'puts "Hello"', ['language-ruby']]])
      end

      it 'returns multiple code blocks with their languages and classes' do
        allow(subject).to receive(:process_markdown).and_return(multi_code_slide)
        # After shift, the 'execute' class is consumed, leaving 'language-xxx'
        # The regex matches on the shifted value ('execute') which doesn't match, so lang=nil
        expected_result = [
          [nil, 'puts "Ruby code"', ['language-ruby']],
          [nil, 'print("Python code")', ['language-python']],
          [nil, 'echo "Shell code"', ['language-shell']]
        ]
        expect(subject.get_code_from_slide('test', 'all')).to eq(expected_result)
      end
    end

    context 'when path includes a slide number' do
      it 'extracts the path and slide number correctly' do
        allow(File).to receive(:read).and_return(multi_slide_content)
        allow(subject).to receive(:process_markdown) do |_name, _section, content, _opts|
          if content.include?('Second slide with code')
            '<div><code class="execute language-ruby">puts "Slide 2 code"</code></div>'
          else
            '<div>No code here</div>'
          end
        end

        expect(subject.get_code_from_slide('test:2', 0)).to eq('puts "Slide 2 code"')
      end

      it 'defaults to slide 1 when no number is specified' do
        allow(File).to receive(:read).and_return(multi_slide_content)
        allow(subject).to receive(:process_markdown) do |_name, _section, content, _opts|
          if content.include?('First slide')
            '<div><code class="execute language-ruby">puts "Slide 1 code"</code></div>'
          else
            '<div>No code here</div>'
          end
        end

        expect(subject.get_code_from_slide('test', 0)).to eq('puts "Slide 1 code"')
      end
    end

    context 'when executable parameter is false' do
      it 'searches for all code blocks, not just executable ones' do
        allow(subject).to receive(:process_markdown).and_return(non_executable_slide)

        # When executable=true (default), it should find no code blocks
        expect(subject.get_code_from_slide('test', 0, true)).to eq('Invalid code block index')

        # When executable=false, it should find the non-executable code block
        expect(subject.get_code_from_slide('test', 0, false)).to eq('puts "Non-executable Ruby"')
      end

      it 'returns all code blocks when index is "all"' do
        allow(subject).to receive(:process_markdown).and_return(non_executable_slide)
        # After shift, 'language-ruby' is consumed, lang=ruby, classes=[]
        expected_result = [['ruby', 'puts "Non-executable Ruby"', []]]
        expect(subject.get_code_from_slide('test', 'all', false)).to eq(expected_result)
      end
    end

    context 'when code blocks have special formatting' do
      it 'removes leading "* " from code lines' do
        special_code = '<div><code class="execute language-ruby">* puts "Hello"
* puts "World"</code></div>'
        allow(subject).to receive(:process_markdown).and_return(special_code)

        expect(subject.get_code_from_slide('test', 0)).to eq(' puts "Hello"
 puts "World"')
      end
    end
  end

  describe '#process_markdown' do
    it 'wraps content in a code block for extraction' do
      result = subject.send(:process_markdown, 'test.md', 'section', 'puts "Hello"')
      expect(result).to eq('<div><code class=\'execute language-ruby\'>puts "Hello"</code></div>')
    end
  end
end