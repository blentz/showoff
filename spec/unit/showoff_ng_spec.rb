require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe Showoff do
  describe '.do_static' do
    it 'generates a static presentation' do
      Dir.mktmpdir('showoff_static_spec') do |dir|
        Dir.chdir(dir) do
          # Minimal presentation with one slide
          File.write('showoff.json', JSON.dump({ 'name' => 'Spec Pres', 'sections' => ['.'] }))
          File.write('first.md', "# Hello\n\nThis is a test.")

          # Force config reload from this directory
          Showoff::Config.load('showoff.json')

          # Run static generation
          expect {
            Showoff.do_static(['web'], {})
          }.not_to raise_error

          # Validate files
          expect(File.exist?(File.join('static', 'index.html'))).to be true
          html = File.read(File.join('static', 'index.html'))
          expect(html).to include('Spec Pres')
          expect(html).to match(/<div id=['"]slides['"]/)

          # Validate asset directories copied
          expect(Dir.exist?(File.join('static', 'js'))).to be true
          expect(Dir.exist?(File.join('static', 'css'))).to be true
        end
      end
    end

    it 'defaults format to web when no args provided' do
      Dir.mktmpdir('showoff_static_spec') do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.dump({ 'name' => 'Default Format', 'sections' => ['.'] }))
          File.write('slide.md', "# Default\n\nTest.")

          Showoff::Config.load('showoff.json')

          expect {
            Showoff.do_static([], {})
          }.not_to raise_error

          expect(File.exist?(File.join('static', 'index.html'))).to be true
        end
      end
    end

    it 'sets supplemental format when specified' do
      Dir.mktmpdir('showoff_static_spec') do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.dump({ 'name' => 'Supplemental', 'sections' => ['.'] }))
          File.write('slide.md', "# Supp\n\nTest.")

          Showoff::Config.load('showoff.json')

          expect {
            Showoff.do_static(['supplemental', 'notes'], {})
          }.not_to raise_error
        end
      end
    end

    it 'handles language option for locale' do
      Dir.mktmpdir('showoff_static_spec') do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.dump({ 'name' => 'Locale Test', 'sections' => ['.'] }))
          File.write('slide.md', "# Locale\n\nTest.")

          Showoff::Config.load('showoff.json')

          expect {
            Showoff.do_static(['web'], { language: 'en' })
          }.not_to raise_error

          expect(File.exist?(File.join('static', 'index.html'))).to be true
        end
      end
    end
  end

  describe '.makeSnapshot' do
    it 'creates static directory and copies assets' do
      Dir.mktmpdir('showoff_snapshot_spec') do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.dump({ 'name' => 'Snapshot', 'sections' => ['.'] }))
          File.write('slide.md', "# Snapshot Test")

          Showoff::Config.load('showoff.json')
          Showoff::State.set(:format, 'web')

          presentation = Showoff::Presentation.new({})
          Showoff.makeSnapshot(presentation)

          expect(Dir.exist?('static')).to be true
          expect(File.exist?(File.join('static', 'index.html'))).to be true
          expect(Dir.exist?(File.join('static', 'js'))).to be true
          expect(Dir.exist?(File.join('static', 'css'))).to be true
        end
      end
    end

    it 'handles missing assets gracefully' do
      Dir.mktmpdir('showoff_snapshot_spec') do |dir|
        Dir.chdir(dir) do
          File.write('showoff.json', JSON.dump({ 'name' => 'Missing Assets', 'sections' => ['.'] }))
          # Reference a non-existent image
          File.write('slide.md', "# Missing\n\n![missing](nonexistent.png)")

          Showoff::Config.load('showoff.json')
          Showoff::State.set(:format, 'web')

          presentation = Showoff::Presentation.new({})

          # Should not raise - just warn about missing files
          expect {
            Showoff.makeSnapshot(presentation)
          }.not_to raise_error
        end
      end
    end
  end

  describe 'GEMROOT' do
    it 'points to the gem root directory' do
      expect(Showoff::GEMROOT).to be_a(String)
      expect(File.exist?(Showoff::GEMROOT)).to be true
      expect(File.exist?(File.join(Showoff::GEMROOT, 'public'))).to be true
    end
  end
end
