require 'spec_helper'
require 'tempfile'
require 'fileutils'
require 'erb'
require 'showoff_utils'

RSpec.describe ShowoffUtils do
  describe '.create_erb' do
    let(:template) { "Hello <%= 'world' %>" }

    it 'uses keyword trim_mode on Ruby >= 2.6' do
      stub_const('RUBY_VERSION', '2.6.0')
      erb = described_class.create_erb(template, '-')
      expect(erb).to be_a(ERB)
      expect(erb.result).to include('Hello world')
    end

    it 'uses positional args on Ruby < 2.6' do
      stub_const('RUBY_VERSION', '2.5.9')
      erb = described_class.create_erb(template, '-')
      expect(erb).to be_a(ERB)
      expect(erb.result).to include('Hello world')
    end
  end

  describe '.parse_options' do
    it 'parses key=value pairs' do
      expect(described_class.parse_options('tpl=hpi,title=Over the rainbow')).to eq({'tpl'=>'hpi','title'=>'Over the rainbow'})
    end

    it 'handles missing values' do
      expect(described_class.parse_options('flag')).to eq({'flag'=>nil})
    end

    it 'returns empty hash for nil' do
      expect(described_class.parse_options(nil)).to eq({})
    end

    it 'returns empty hash for empty string' do
      expect(described_class.parse_options('')).to eq({})
    end
  end

  describe '.presentation_config_file accessor' do
    it 'gets and sets the filename' do
      original = described_class.presentation_config_file
      begin
        described_class.presentation_config_file = 'custom.json'
        expect(described_class.presentation_config_file).to eq('custom.json')
      ensure
        described_class.presentation_config_file = original
      end
    end
  end

  describe '.make_slide' do
    it 'creates a basic slide with title' do
      out = described_class.make_slide('Title')
      expect(out).to include('<!SLIDE')
      expect(out).to include('# Title')
    end

    it 'creates a slide with bullets when content is an array' do
      out = described_class.make_slide('T', '', %w[a b])
      expect(out).to include('* a')
      expect(out).to include('* b')
    end

    it 'embeds string content verbatim' do
      out = described_class.make_slide('T', '', 'body')
      expect(out).to include('body')
    end
  end

  describe '.determine_title' do
    it 'prefers explicit title' do
      expect(described_class.determine_title('X', 'name', nil)).to eq('X')
    end

    it 'uses slide_name when title blank' do
      expect(described_class.determine_title('  ', 'slide_name', nil)).to eq('slide_name')
    end

    it 'uses code filename when provided' do
      expect(described_class.determine_title(nil, nil, '/tmp/foo.rb')).to eq('foo.rb')
    end

    it 'falls back to "Title here" when all blank' do
      expect(described_class.determine_title('', '', nil)).to eq('Title here')
    end
  end

  describe '.blank?' do
    it 'detects nil and whitespace-only strings' do
      expect(described_class.blank?(nil)).to be true
      expect(described_class.blank?('   ')).to be true
      expect(described_class.blank?('x')).to be false
    end
  end

  describe '.determine_size_and_source and .adjust_size' do
    it 'reads code and adjusts size and warnings for big files' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'code.rb')
        long_line = 'x' * 70
        content = ([long_line] * 25).join("\n")
        File.write(path, content)

        size, source = described_class.determine_size_and_source(path)
        expect(source).to include('@@@ ruby')
        expect(size).to eq('smaller')
      end
    end
  end

  describe '.read_code' do
    it 'returns code with language header and correct counts' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'foo.rb')
        File.write(path, "line1\nline2\n")
        code, lines, width = described_class.read_code(path)
        expect(code).to start_with('    @@@ ruby')
        expect(lines).to eq(2)
        expect(width).to be >= 5
      end
    end
  end

  describe '.lang' do
    it 'maps known extensions and falls back to ext' do
      expect(described_class.lang('f.rb')).to eq('ruby')
      expect(described_class.lang('f.pl')).to eq('perl')
      expect(described_class.lang('f.xyz')).to eq('xyz')
    end
  end

  describe '.create_file_if_needed' do
    it 'creates file when missing and does not overwrite by default' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'file.txt')
        created = described_class.create_file_if_needed(path, false) { |f| f.puts 'one' }
        expect(created).to be true
        content1 = File.read(path)

        created2 = described_class.create_file_if_needed(path, false) { |f| f.puts 'two' }
        expect(created2).to be false
        expect(File.read(path)).to eq(content1)
      end
    end

    it 'overwrites when force is true' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'file.txt')
        described_class.create_file_if_needed(path, false) { |f| f.puts 'one' }
        described_class.create_file_if_needed(path, true) { |f| f.puts 'two' }
        expect(File.read(path)).to include('two')
      end
    end
  end

  describe '.command' do
    it 'raises when system fails' do
      allow(described_class).to receive(:system).and_return(false)
      expect { described_class.command('false', 'oops') }.to raise_error('oops')
    end

    it 'executes when system returns true' do
      allow(described_class).to receive(:system).and_return(true)
      expect { described_class.command('true', 'oops') }.not_to raise_error
    end
  end

  describe '.determine_filename and .find_next_number' do
    it 'builds numbered filenames and finds next number' do
      Dir.mktmpdir do |dir|
        # seed two files with numbers
        File.write(File.join(dir, '01_a.md'), '')
        File.write(File.join(dir, '02_b.md'), '')

        next_num = described_class.find_next_number(dir)
        expect(next_num).to eq('03')

        filename = described_class.determine_filename(dir, 'name', true)
        expect(filename).to end_with('/03_name.md')
      end
    end

    it 'raises when slide_name is missing' do
      expect { described_class.determine_filename(nil, nil, false) }.to raise_error('Slide name is required')
    end
  end
end
