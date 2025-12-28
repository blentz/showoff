require 'spec_helper'
require 'showoff/server/download_manager'
require 'tempfile'
require 'fileutils'

RSpec.describe Showoff::Server::DownloadManager do
  let(:manager) { Showoff::Server::DownloadManager.new }
  let(:slide_num) { 5 }
  let(:name) { 'Test Slide' }
  let(:files) { ['file1.txt', 'file2.pdf', 'file3.rb'] }

  describe '#initialize' do
    it 'creates an empty downloads hash' do
      expect(manager.all).to eq({})
    end
  end

  describe '#register' do
    it 'registers files for a slide' do
      manager.register(slide_num, name, files)
      expect(manager.all).to eq({ slide_num => [false, name, files] })
    end

    it 'overwrites existing entries' do
      manager.register(slide_num, name, files)
      new_files = ['new_file.txt']
      manager.register(slide_num, 'New Name', new_files)
      expect(manager.all).to eq({ slide_num => [false, 'New Name', new_files] })
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.register(-1, name, files) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.register('5', name, files) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end

    it 'validates name is a String' do
      expect { manager.register(slide_num, 123, files) }.to raise_error(ArgumentError, /name must be a String/)
    end

    it 'validates files is an Array' do
      expect { manager.register(slide_num, name, 'not_an_array') }.to raise_error(ArgumentError, /files must be an Array/)
    end

    it 'validates each file is a String' do
      expect { manager.register(slide_num, name, ['valid.txt', 123]) }.to raise_error(ArgumentError, /file must be a String/)
    end

    it 'makes a copy of the files array' do
      original = ['file1.txt', 'file2.pdf']
      manager.register(slide_num, name, original)
      original << 'file3.txt'
      expect(manager.all[slide_num][2]).to eq(['file1.txt', 'file2.pdf'])
    end
  end

  describe '#enable' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'enables downloads for a slide' do
      expect(manager.enable(slide_num)).to be true
      expect(manager.all[slide_num][0]).to be true
    end

    it 'returns false if slide not found' do
      expect(manager.enable(999)).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.enable(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.enable('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end
  end

  describe '#disable' do
    before do
      manager.register(slide_num, name, files)
      manager.enable(slide_num)
    end

    it 'disables downloads for a slide' do
      expect(manager.disable(slide_num)).to be true
      expect(manager.all[slide_num][0]).to be false
    end

    it 'returns false if slide not found' do
      expect(manager.disable(999)).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.disable(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.disable('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end
  end

  describe '#enabled?' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'returns false for newly registered slides' do
      expect(manager.enabled?(slide_num)).to be false
    end

    it 'returns true for enabled slides' do
      manager.enable(slide_num)
      expect(manager.enabled?(slide_num)).to be true
    end

    it 'returns false for disabled slides' do
      manager.enable(slide_num)
      manager.disable(slide_num)
      expect(manager.enabled?(slide_num)).to be false
    end

    it 'returns false for non-existent slides' do
      expect(manager.enabled?(999)).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.enabled?(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.enabled?('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end
  end

  describe '#name' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'returns the name for a slide' do
      expect(manager.name(slide_num)).to eq(name)
    end

    it 'returns nil for non-existent slides' do
      expect(manager.name(999)).to be_nil
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.name(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.name('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end
  end

  describe '#files' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'returns empty array for disabled slides' do
      expect(manager.files(slide_num)).to eq([])
    end

    it 'returns files for enabled slides' do
      manager.enable(slide_num)
      expect(manager.files(slide_num)).to eq(files)
    end

    it 'returns empty array for non-existent slides' do
      expect(manager.files(999)).to eq([])
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.files(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.files('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end

    it 'returns a copy of the files array' do
      manager.enable(slide_num)
      result = manager.files(slide_num)
      result << 'new_file.txt'
      expect(manager.files(slide_num)).to eq(files)
    end
  end

  describe '#all' do
    it 'returns all registered downloads' do
      manager.register(1, 'Slide 1', ['file1.txt'])
      manager.register(2, 'Slide 2', ['file2.txt'])
      expect(manager.all).to eq({
        1 => [false, 'Slide 1', ['file1.txt']],
        2 => [false, 'Slide 2', ['file2.txt']]
      })
    end

    it 'returns a copy of the downloads hash' do
      manager.register(1, 'Slide 1', ['file1.txt'])
      result = manager.all
      result[2] = [false, 'New Slide', ['new.txt']]
      expect(manager.all).to eq({ 1 => [false, 'Slide 1', ['file1.txt']] })
    end
  end

  describe '#enabled' do
    before do
      manager.register(1, 'Slide 1', ['file1.txt'])
      manager.register(2, 'Slide 2', ['file2.txt'])
      manager.register(3, 'Slide 3', ['file3.txt'])
      manager.enable(1)
      manager.enable(3)
    end

    it 'returns only enabled downloads' do
      expect(manager.enabled).to eq({
        1 => [true, 'Slide 1', ['file1.txt']],
        3 => [true, 'Slide 3', ['file3.txt']]
      })
    end
  end

  describe '#add_file' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'adds a file to an existing slide' do
      manager.add_file(slide_num, 'new_file.txt')
      expected_files = files + ['new_file.txt']
      expect(manager.all[slide_num][2]).to eq(expected_files)
    end

    it 'does not add duplicate files' do
      manager.add_file(slide_num, files.first)
      expect(manager.all[slide_num][2]).to eq(files)
    end

    it 'returns true if file was added' do
      expect(manager.add_file(slide_num, 'new_file.txt')).to be true
    end

    it 'returns false if slide not found' do
      expect(manager.add_file(999, 'new_file.txt')).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.add_file(-1, 'file.txt') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.add_file('5', 'file.txt') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end

    it 'validates file is a String' do
      expect { manager.add_file(slide_num, 123) }.to raise_error(ArgumentError, /file must be a String/)
    end
  end

  describe '#remove_file' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'removes a file from an existing slide' do
      manager.remove_file(slide_num, files.first)
      expect(manager.all[slide_num][2]).to eq(files[1..-1])
    end

    it 'returns true if file was removed' do
      expect(manager.remove_file(slide_num, files.first)).to be true
    end

    it 'returns false if slide not found' do
      expect(manager.remove_file(999, 'file.txt')).to be false
    end

    it 'returns false if file not found' do
      expect(manager.remove_file(slide_num, 'nonexistent.txt')).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.remove_file(-1, 'file.txt') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.remove_file('5', 'file.txt') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end

    it 'validates file is a String' do
      expect { manager.remove_file(slide_num, 123) }.to raise_error(ArgumentError, /file must be a String/)
    end
  end

  describe '#has_downloads?' do
    before do
      manager.register(slide_num, name, files)
    end

    it 'returns true if slide has registered downloads' do
      expect(manager.has_downloads?(slide_num)).to be true
    end

    it 'returns false if slide has no registered downloads' do
      expect(manager.has_downloads?(999)).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.has_downloads?(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.has_downloads?('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end
  end

  describe '#count' do
    it 'returns the number of slides with downloads' do
      expect(manager.count).to eq(0)
      manager.register(1, 'Slide 1', ['file1.txt'])
      expect(manager.count).to eq(1)
      manager.register(2, 'Slide 2', ['file2.txt'])
      expect(manager.count).to eq(2)
    end
  end

  describe '#clear' do
    before do
      manager.register(1, 'Slide 1', ['file1.txt'])
      manager.register(2, 'Slide 2', ['file2.txt'])
    end

    it 'clears all downloads' do
      manager.clear
      expect(manager.all).to eq({})
    end
  end

  describe '#clear_slide' do
    before do
      manager.register(1, 'Slide 1', ['file1.txt'])
      manager.register(2, 'Slide 2', ['file2.txt'])
    end

    it 'clears downloads for a specific slide' do
      manager.clear_slide(1)
      expect(manager.all).to eq({ 2 => [false, 'Slide 2', ['file2.txt']] })
    end

    it 'returns true if slide was cleared' do
      expect(manager.clear_slide(1)).to be true
    end

    it 'returns false if slide not found' do
      expect(manager.clear_slide(999)).to be false
    end

    it 'validates slide_num is an Integer >= 0' do
      expect { manager.clear_slide(-1) }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
      expect { manager.clear_slide('5') }.to raise_error(ArgumentError, /slide_num must be an Integer >= 0/)
    end
  end

  describe '#merge!' do
    before do
      manager.register(1, 'Slide 1', ['file1.txt'])
    end

    it 'merges another downloads hash' do
      other_downloads = {
        2 => [true, 'Slide 2', ['file2.txt']],
        3 => [false, 'Slide 3', ['file3.txt']]
      }
      manager.merge!(other_downloads)

      expect(manager.all).to eq({
        1 => [false, 'Slide 1', ['file1.txt']],
        2 => [true, 'Slide 2', ['file2.txt']],
        3 => [false, 'Slide 3', ['file3.txt']]
      })
    end

    it 'overwrites existing entries' do
      other_downloads = {
        1 => [true, 'New Slide 1', ['new_file.txt']]
      }
      manager.merge!(other_downloads)

      expect(manager.all).to eq({
        1 => [true, 'New Slide 1', ['new_file.txt']]
      })
    end

    it 'converts keys to integers' do
      other_downloads = {
        '2' => [true, 'Slide 2', ['file2.txt']]
      }
      manager.merge!(other_downloads)

      expect(manager.all).to eq({
        1 => [false, 'Slide 1', ['file1.txt']],
        2 => [true, 'Slide 2', ['file2.txt']]
      })
    end

    it 'validates other_downloads is a Hash' do
      expect { manager.merge!('not_a_hash') }.to raise_error(ArgumentError, /other_downloads must be a Hash/)
    end

    it 'skips invalid entries' do
      other_downloads = {
        2 => [true, 'Slide 2', ['file2.txt']],
        3 => 'not_an_array',
        4 => [true, 'Slide 4']  # Missing files array
      }
      manager.merge!(other_downloads)

      expect(manager.all).to eq({
        1 => [false, 'Slide 1', ['file1.txt']],
        2 => [true, 'Slide 2', ['file2.txt']]
      })
    end

    it 'converts values to appropriate types' do
      other_downloads = {
        2 => [1, 123, ['file2.txt']]  # Non-boolean enabled, non-string name
      }
      manager.merge!(other_downloads)

      expect(manager.all).to eq({
        1 => [false, 'Slide 1', ['file1.txt']],
        2 => [true, '123', ['file2.txt']]
      })
    end
  end

  # File existence and permission tests
  describe 'file existence and permissions' do
    let(:temp_dir) { Dir.mktmpdir }
    let(:existing_file) { File.join(temp_dir, 'existing.txt') }
    let(:missing_file) { File.join(temp_dir, 'missing.txt') }
    let(:no_read_file) { File.join(temp_dir, 'no_read.txt') }

    before do
      # Create test files
      File.write(existing_file, 'Test content')
      File.write(no_read_file, 'No read permission')

      # Remove read permission on no_read_file if not on Windows
      unless Gem.win_platform?
        FileUtils.chmod(0000, no_read_file)
      end
    end

    after do
      # Restore permissions for cleanup
      unless Gem.win_platform?
        FileUtils.chmod(0644, no_read_file) rescue nil
      end

      # Clean up temp directory
      FileUtils.remove_entry(temp_dir)
    end

    it 'handles existing files correctly' do
      manager.register(1, 'Existing Files', [existing_file])
      manager.enable(1)

      expect(manager.files(1)).to eq([existing_file])
      expect(File.exist?(manager.files(1).first)).to be true
    end

    it 'handles missing files gracefully' do
      manager.register(2, 'Missing Files', [missing_file])
      manager.enable(2)

      expect(manager.files(2)).to eq([missing_file])
      expect(File.exist?(manager.files(2).first)).to be false
    end

    # Skip on Windows and in containers running as root where permissions don't apply
    it 'handles permission issues gracefully', unless: Gem.win_platform? || Process.uid == 0 do
      manager.register(3, 'Permission Issues', [no_read_file])
      manager.enable(3)

      expect(manager.files(3)).to eq([no_read_file])
      expect(File.exist?(manager.files(3).first)).to be true
      expect { File.read(manager.files(3).first) }.to raise_error(Errno::EACCES)
    end
  end

  # Thread safety tests
  describe 'thread safety' do
    it 'handles concurrent registrations' do
      threads = []
      10.times do |i|
        threads << Thread.new do
          manager.register(i, "Slide #{i}", ["file#{i}.txt"])
        end
      end
      threads.each(&:join)

      expect(manager.count).to eq(10)
      10.times do |i|
        expect(manager.has_downloads?(i)).to be true
      end
    end

    it 'handles concurrent enables/disables' do
      manager.register(slide_num, name, files)

      threads = []
      100.times do
        threads << Thread.new do
          if rand > 0.5
            manager.enable(slide_num)
          else
            manager.disable(slide_num)
          end
        end
      end
      threads.each(&:join)

      # We can't predict the final state, but it should be either enabled or disabled
      expect([true, false]).to include(manager.enabled?(slide_num))
    end

    it 'handles concurrent file additions/removals' do
      manager.register(slide_num, name, [])

      threads = []
      files_to_add = (1..100).map { |i| "file#{i}.txt" }

      # Add files concurrently
      files_to_add.each do |file|
        threads << Thread.new do
          manager.add_file(slide_num, file)
        end
      end
      threads.each(&:join)

      # All files should have been added without duplicates
      result_files = manager.all[slide_num][2]
      expect(result_files.size).to eq(files_to_add.size)
      expect(result_files.sort).to eq(files_to_add.sort)

      # Now remove files concurrently
      threads = []
      files_to_add.each do |file|
        threads << Thread.new do
          manager.remove_file(slide_num, file)
        end
      end
      threads.each(&:join)

      # All files should have been removed
      expect(manager.all[slide_num][2]).to be_empty
    end

    it 'handles concurrent reads and writes' do
      # Set up initial data
      10.times do |i|
        manager.register(i, "Slide #{i}", ["file#{i}.txt"])
      end

      threads = []

      # Writers
      10.times do
        threads << Thread.new do
          10.times do |i|
            manager.enable(i) if rand > 0.7
            manager.add_file(i, "new_file_#{rand(100)}.txt") if rand > 0.7
            manager.remove_file(i, "file#{i}.txt") if rand > 0.9
          end
        end
      end

      # Readers
      10.times do
        threads << Thread.new do
          10.times do
            manager.all
            manager.enabled
            manager.files(rand(10))
            manager.has_downloads?(rand(10))
            manager.count
          end
        end
      end

      threads.each(&:join)

      # No assertions needed - if we got here without exceptions, the test passed
    end

    it 'handles concurrent merges' do
      threads = []

      5.times do |t|
        threads << Thread.new do
          other_downloads = {}
          20.times do |i|
            slide_num = t * 20 + i
            other_downloads[slide_num] = [rand > 0.5, "Slide #{slide_num}", ["file#{slide_num}.txt"]]
          end
          manager.merge!(other_downloads)
        end
      end

      threads.each(&:join)

      # Should have 100 slides registered
      expect(manager.count).to eq(100)
    end

    it 'handles concurrent clears and operations' do
      # Set up initial data
      10.times do |i|
        manager.register(i, "Slide #{i}", ["file#{i}.txt"])
      end

      threads = []

      # Operations threads
      5.times do
        threads << Thread.new do
          10.times do
            i = rand(10)
            case rand(4)
            when 0 then manager.enable(i)
            when 1 then manager.disable(i)
            when 2 then manager.add_file(i, "new_file.txt")
            when 3 then manager.files(i)
            end
          end
        end
      end

      # Clear threads
      threads << Thread.new do
        sleep 0.01  # Give operations a chance to start
        manager.clear
      end

      # Clear slide threads
      threads << Thread.new do
        sleep 0.01  # Give operations a chance to start
        5.times do |i|
          manager.clear_slide(i)
        end
      end

      threads.each(&:join)

      # No assertions needed - if we got here without exceptions, the test passed
    end
  end
end