require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe Showoff do
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
end
