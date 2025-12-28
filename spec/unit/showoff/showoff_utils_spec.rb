require 'spec_helper'
require 'tempfile'
require 'fileutils'
require 'erb'
require 'json'
require 'logger'
require 'open3'
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

    it 'applies classes to slide tag' do
      out = described_class.make_slide('Title', 'center smaller')
      expect(out).to include('<!SLIDE center smaller')
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

  describe '.determine_size_and_source' do
    it 'returns empty size and source when no code' do
      size, source = described_class.determine_size_and_source(nil)
      expect(size).to eq('')
      expect(source).to eq('')
    end

    it 'reads code and returns size and source' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'code.rb')
        File.write(path, "puts :ok\n")
        size, source = described_class.determine_size_and_source(path)
        expect(source).to include('@@@ ruby')
        expect(source).to include('puts :ok')
      end
    end
  end

  describe '.adjust_size' do
    it 'returns empty for small files' do
      expect(described_class.adjust_size(10, 40)).to eq('')
    end

    it 'returns small for wide or tall files' do
      expect(described_class.adjust_size(16, 40)).to eq('small')
      expect(described_class.adjust_size(10, 55)).to eq('small')
    end

    it 'returns smaller for very wide or tall files' do
      expect(described_class.adjust_size(20, 40)).to eq('smaller')
      expect(described_class.adjust_size(10, 60)).to eq('smaller')
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
      expect(described_class.lang('f.erl')).to eq('erlang')
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

  describe '.determine_filename' do
    it 'raises when slide_name is missing' do
      expect { described_class.determine_filename(nil, nil, false) }.to raise_error('Slide name is required')
    end

    it 'generates filename without number' do
      expect(described_class.determine_filename('dir', 'name', false)).to eq('dir/name.md')
    end

    it 'generates filename without dir' do
      expect(described_class.determine_filename(nil, 'name', false)).to eq('name.md')
    end
  end

  describe '.find_next_number' do
    it 'finds next number in sequence' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '01_a.md'), '')
        File.write(File.join(dir, '02_b.md'), '')

        next_num = described_class.find_next_number(dir)
        expect(next_num).to eq('03')
      end
    end

    it 'returns 01 for empty directory' do
      Dir.mktmpdir do |dir|
        next_num = described_class.find_next_number(dir)
        expect(next_num).to eq('01')
      end
    end
  end

  describe '.create' do
    it 'creates a new presentation skeleton with samples and config' do
      Dir.mktmpdir do |dir|
        described_class.presentation_config_file = 'showoff.json'
        described_class.create(dir, true, 'one,two')

        # Verify directories and sample slides
        expect(Dir.exist?(File.join(dir, 'one'))).to be true
        expect(Dir.exist?(File.join(dir, 'two'))).to be true
        expect(File.exist?(File.join(dir, 'one', '00_section.md'))).to be true
        expect(File.exist?(File.join(dir, 'one', '01_slide.md'))).to be true
        expect(File.exist?(File.join(dir, 'one', '02_slide.md'))).to be true

        # Assets
        expect(Dir.exist?(File.join(dir, '_files', 'share'))).to be true
        expect(Dir.exist?(File.join(dir, '_images'))).to be true

        # Config
        json = JSON.parse(File.read(File.join(dir, 'showoff.json')))
        expect(json['name']).to eq('My Preso')
        expect(json['sections'].map { |h| h['section'] }).to contain_exactly('one', 'two')
      end
    end

    it 'creates without samples and still writes assets and config' do
      Dir.mktmpdir do |dir|
        described_class.create(dir, false, 'alpha')

        # With create_samples false, the directory is not created; ensure assets and config exist
        expect(Dir.exist?(File.join(dir, '_files', 'share'))).to be true
        expect(Dir.exist?(File.join(dir, '_images'))).to be true
        json = JSON.parse(File.read(File.join(dir, 'showoff.json')))
        expect(json['sections'].map { |h| h['section'] }).to eq(['alpha'])
      end
    end
  end

  describe '.skeleton' do
    it 'copies external config into cwd and creates missing files/dirs' do
      Dir.mktmpdir do |root|
        src = File.join(root, 'src')
        work = File.join(root, 'work')
        FileUtils.mkdir_p(src)
        FileUtils.mkdir_p(work)
        cfg_path = File.join(src, 'external.json')
        File.write(cfg_path, JSON.pretty_generate({ 'sections' => ['one/section.md', 'two/slide.md'] }))

        Dir.chdir(work) do
          begin
            described_class.skeleton(cfg_path)
            expect(File.exist?(File.join(work, 'external.json'))).to be true
            expect(Dir.exist?(File.join(work, '_files', 'share'))).to be true
            expect(Dir.exist?(File.join(work, '_images'))).to be true
            expect(File.exist?(File.join(work, 'one', 'section.md'))).to be true
            expect(File.exist?(File.join(work, 'two', 'slide.md'))).to be true
            expect(File.read(File.join(work, 'one', 'section.md'))).to include('center subsection')
          ensure
            described_class.presentation_config_file = 'showoff.json'
          end
        end
      end
    end
  end

  describe '.heroku' do
    it 'creates Heroku files with password-protected rack' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          result = described_class.heroku('appname', 'secret', false)
          expect(result).to be true

          expect(File.exist?(ShowoffUtils::HEROKU_GEMS_FILE)).to be true
          expect(File.exist?(ShowoffUtils::HEROKU_PROCFILE)).to be true
          expect(File.exist?(ShowoffUtils::HEROKU_CONFIG_FILE)).to be true

          cfg = File.read(ShowoffUtils::HEROKU_CONFIG_FILE)
          expect(cfg).to include("Rack::Auth::Basic")
          expect(cfg).to include("password == 'secret'")

          gems = File.read(ShowoffUtils::HEROKU_GEMS_FILE)
          expect(gems).to include("gem 'showoff'")
          expect(gems).to include("gem 'rack'")

          # Second run without force should not modify anything
          result2 = described_class.heroku('appname', 'secret', false)
          expect(result2).to be false
        end
      end
    end

    it 'creates Heroku files without password when password is nil' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          described_class.heroku('appname', nil, true)
          cfg = File.read(ShowoffUtils::HEROKU_CONFIG_FILE)
          expect(cfg).to include('run Showoff::Server.new')
          expect(cfg).not_to include('Rack::Auth::Basic')
        end
      end
    end
  end

  describe '.write_file' do
    it 'writes file and prints message' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'slide.md')
        expect {
          described_class.write_file(path, 'content')
        }.to output(/Wrote/).to_stdout
        expect(File.read(path)).to include('content')
      end
    end
  end

  describe '.showoff_legacy_sections' do
    it 'handles directories by expanding markdown files' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('dirx')
          File.write('dirx/a.md', '')
          File.write('dirx/b.md', '')
          sections = described_class.showoff_legacy_sections(Dir.pwd, [{ 'section' => 'dirx' }])
          expect(sections['dirx']).to include('dirx/a.md', 'dirx/b.md')
        end
      end
    end

    it 'handles simple string entries' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('slides')
          File.write('slides/01.md', '')
          data = ['slides/01.md']
          sections = described_class.showoff_legacy_sections(Dir.pwd, data)
          expect(sections['slides']).to include('slides/01.md')
        end
      end
    end
  end

  describe '.showoff_sections' do
    it 'parses sections from data Hash with external file lists' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('x')
          File.write('x/list.json', JSON.generate(['f1.md', 'f2.md']))
          data = { 'sections' => { 'group1' => 'x/list.json' } }
          sections = described_class.showoff_sections(Dir.pwd, data)
          expect(sections['group1']).to eq(['x/f1.md', 'x/f2.md'])
        end
      end
    end

    it 'handles Array sections' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('slides')
          File.write('slides/01.md', '')
          data = { 'sections' => [{ 'section' => 'slides' }] }
          sections = described_class.showoff_sections(Dir.pwd, data)
          expect(sections['slides']).to include('slides/01.md')
        end
      end
    end
  end

  describe 'config getters' do
    it 'reads title from config' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          config = { 'name' => 'My Title' }
          File.write('showoff.json', JSON.pretty_generate(config))
          expect(described_class.showoff_title).to eq('My Title')
        end
      end
    end

    it 'falls back to defaults when config missing' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(described_class.showoff_title).to eq('Presentation')
          expect(described_class.pause_msg).to eq('PAUSED')
          expect(described_class.default_style).to eq('')
        end
      end
    end

    it 'reads pdf options with symbol keys' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          config = { 'pdf_options' => { 'page_size' => 'A4' } }
          File.write('showoff.json', JSON.pretty_generate(config))
          pdf = described_class.showoff_pdf_options
          expect(pdf[:page_size]).to eq('A4')
        end
      end
    end

    it 'reads markdown renderer setting' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          config = { 'markdown' => 'bluecloth' }
          File.write('showoff.json', JSON.pretty_generate(config))
          expect(described_class.showoff_markdown).to eq('bluecloth')
        end
      end
    end

    it 'default_style? checks if style matches default' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          config = { 'style' => 'dark' }
          File.write('showoff.json', JSON.pretty_generate(config))
          expect(described_class.default_style?('foo/dark.css')).to be true
          expect(described_class.default_style?('foo/light.css')).to be false
        end
      end
    end

    it 'get_config_option returns value or default' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.pretty_generate({ 'val' => 5 }))
          expect(described_class.get_config_option('.', 'val', 9)).to eq(5)
          expect(described_class.get_config_option('.', 'missing', 9)).to eq(9)
        end
      end
    end

    it 'get_config_option merges hash defaults' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.pretty_generate({ 'opts' => { 'a' => 1 } }))
          merged = described_class.get_config_option('.', 'opts', { 'a' => 0, 'b' => 2 })
          expect(merged).to eq({ 'a' => 1, 'b' => 2 })
        end
      end
    end
  end

  describe 'TYPES constant' do
    it 'includes default slide type' do
      expect(described_class::TYPES).to have_key(:default)
    end

    it 'includes title slide type' do
      expect(described_class::TYPES).to have_key('title')
    end

    it 'includes bullets slide type' do
      expect(described_class::TYPES).to have_key('bullets')
    end

    it 'includes code slide type' do
      expect(described_class::TYPES).to have_key('code')
    end

    it 'includes commandline slide type' do
      expect(described_class::TYPES).to have_key('commandline')
    end

    it 'includes full-page slide type' do
      expect(described_class::TYPES).to have_key('full-page')
    end
  end

  describe 'constants' do
    it 'defines HEROKU_PROCFILE' do
      expect(described_class::HEROKU_PROCFILE).to eq('Procfile')
    end

    it 'defines HEROKU_GEMS_FILE' do
      expect(described_class::HEROKU_GEMS_FILE).to eq('Gemfile')
    end

    it 'defines HEROKU_CONFIG_FILE' do
      expect(described_class::HEROKU_CONFIG_FILE).to eq('config.ru')
    end

    it 'defines REQUIRED_GEMS' do
      expect(described_class::REQUIRED_GEMS).to include('showoff', 'redcarpet')
    end

    it 'defines EXTENSIONS mapping' do
      expect(described_class::EXTENSIONS).to include('rb' => 'ruby', 'pl' => 'perl')
    end
  end
end
