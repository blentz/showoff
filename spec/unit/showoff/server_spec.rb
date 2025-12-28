# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'

RSpec.describe Showoff::Server do
  # The server helpers and route handlers are tested via integration tests.
  # This spec focuses on class-level constants and configuration that can be
  # unit tested without spinning up the full Sinatra app.

  describe 'constants' do
    it 'defines SHARED_FILES_SLIDE_NUM = -999' do
      expect(described_class::SHARED_FILES_SLIDE_NUM).to eq(-999)
    end
  end

  describe 'server component classes' do
    it 'has SessionState class defined' do
      expect(described_class::SessionState).to be_a(Class)
    end

    it 'has StatsManager class defined' do
      expect(described_class::StatsManager).to be_a(Class)
    end

    it 'has FormManager class defined' do
      expect(described_class::FormManager).to be_a(Class)
    end

    it 'has CacheManager class defined' do
      expect(described_class::CacheManager).to be_a(Class)
    end

    it 'has DownloadManager class defined' do
      expect(described_class::DownloadManager).to be_a(Class)
    end

    it 'has ExecutionManager class defined' do
      expect(described_class::ExecutionManager).to be_a(Class)
    end

    it 'has WebSocketManager class defined' do
      expect(described_class::WebSocketManager).to be_a(Class)
    end

    it 'has FeedbackManager class defined' do
      expect(described_class::FeedbackManager).to be_a(Class)
    end
  end

  describe 'Sinatra configuration' do
    it 'inherits from Sinatra::Base' do
      expect(described_class.superclass).to eq(Sinatra::Base)
    end

    it 'has views directory configured' do
      views_path = described_class.settings.views
      expect(views_path).to include('views')
    end

    it 'has public folder configured' do
      public_path = described_class.settings.public_folder
      expect(public_path).to include('public')
    end

    it 'uses puma server' do
      expect(described_class.settings.server).to eq('puma')
    end
  end

  describe 'filter_notes_sections helper method' do
    # Test the filter logic directly by extracting it to a testable form
    # This tests the Nokogiri manipulation logic used in the route

    def filter_notes_sections(html, section)
      return html if html.nil? || html.empty?

      doc = Nokogiri::HTML.fragment(html)

      if section.nil?
        doc.css('div.notes-section').each { |n| n.remove }
      else
        doc.css('div.notes-section').each do |note|
          classes = note.attr('class').split
          note.remove unless classes.include?(section)
        end
      end

      doc.to_html
    end

    let(:html) do
      <<~HTML
        <div class="slide">
          <div class="notes-section notes">NOTE A</div>
          <div class="notes-section handouts">HANDOUT B</div>
          <div class="content">CONTENT C</div>
        </div>
      HTML
    end

    it 'returns nil when html is nil' do
      expect(filter_notes_sections(nil, nil)).to be_nil
    end

    it 'returns empty string when html is empty' do
      expect(filter_notes_sections('', 'notes')).to eq('')
    end

    it 'removes all notes sections when section is nil' do
      filtered = filter_notes_sections(html, nil)
      expect(filtered).to include('CONTENT C')
      expect(filtered).not_to include('notes-section')
    end

    it "keeps only 'notes' sections when section='notes'" do
      filtered = filter_notes_sections(html, 'notes')
      expect(filtered).to include('NOTE A')
      expect(filtered).not_to include('HANDOUT B')
    end

    it "keeps only 'handouts' sections when section='handouts'" do
      filtered = filter_notes_sections(html, 'handouts')
      expect(filtered).to include('HANDOUT B')
      expect(filtered).not_to include('NOTE A')
    end
  end

  describe 'localhost? helper logic' do
    # Test the localhost detection logic

    def localhost?(remote_host, ip)
      remote_host == 'localhost' || ip == '127.0.0.1'
    end

    it 'returns true when REMOTE_HOST is localhost' do
      expect(localhost?('localhost', '10.0.0.2')).to be(true)
    end

    it 'returns true when ip is 127.0.0.1' do
      expect(localhost?('remote', '127.0.0.1')).to be(true)
    end

    it 'returns false otherwise' do
      expect(localhost?('remote', '10.0.0.3')).to be(false)
    end
  end

  describe 'locale helper logic' do
    # Test the locale selection logic

    def locale(preferred, available_locales)
      preferred ||= 'en'
      preferred = 'en' unless available_locales.include?(preferred)
      preferred
    end

    let(:available) { ['en', 'de', 'es'] }

    it 'defaults to en when preferred is nil' do
      expect(locale(nil, available)).to eq('en')
    end

    it 'returns en when preferred is not available' do
      expect(locale('fr', available)).to eq('en')
    end

    it 'returns preferred when available' do
      expect(locale('de', available)).to eq('de')
    end
  end

  describe 'mapped_keys helper logic' do
    # Test the key mapping logic

    def mapped_keys(action, keymap)
      return '' unless keymap && keymap[action]
      keymap[action].join(', ')
    end

    it 'returns empty string when no keymap present' do
      expect(mapped_keys('next', nil)).to eq('')
    end

    it 'returns empty string when action not in keymap' do
      expect(mapped_keys('next', { 'prev' => ['left'] })).to eq('')
    end

    it 'joins keys with commas when mapping exists' do
      keymap = { 'next' => ['right', 'space'] }
      expect(mapped_keys('next', keymap)).to eq('right, space')
    end
  end
end
