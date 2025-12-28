# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'
require 'showoff/monkeypatches'

RSpec.describe 'Monkeypatches' do
  describe 'Hash#dig' do
    # Note: Ruby 2.3+ has Hash#dig natively, but we test the behavior regardless
    # since the monkeypatch only applies if the method doesn't exist

    it 'retrieves nested values with multiple keys' do
      hash = { a: { b: { c: 'value' } } }
      expect(hash.dig(:a, :b, :c)).to eq('value')
    end

    it 'returns nil for missing keys' do
      hash = { a: { b: 1 } }
      expect(hash.dig(:a, :c)).to be_nil
    end

    it 'raises TypeError when intermediate value is not enumerable' do
      # Ruby's native dig raises TypeError when trying to dig into non-enumerable
      hash = { a: 'string' }
      expect { hash.dig(:a, :b) }.to raise_error(TypeError)
    end

    it 'returns nil for empty path on non-existent key' do
      hash = { a: 1 }
      expect(hash.dig(:b)).to be_nil
    end

    it 'works with string keys' do
      hash = { 'a' => { 'b' => 'value' } }
      expect(hash.dig('a', 'b')).to eq('value')
    end

    it 'works with mixed key types' do
      hash = { 'a' => { b: 'value' } }
      expect(hash.dig('a', :b)).to eq('value')
    end

    it 'requires at least one argument' do
      # Ruby's native dig requires at least one argument
      hash = { a: 1 }
      expect { hash.dig }.to raise_error(ArgumentError)
    end

    it 'handles arrays as intermediate values' do
      hash = { a: [1, 2, 3] }
      expect(hash.dig(:a, 0)).to eq(1)
    end

    it 'returns nil when digging into nil' do
      hash = { a: nil }
      expect(hash.dig(:a, :b)).to be_nil
    end
  end

  describe 'Nokogiri::XML::Element#add_class' do
    let(:doc) { Nokogiri::HTML::DocumentFragment.parse('<div class="existing">content</div>') }
    let(:element) { doc.at('div') }

    it 'adds a class to an element with existing classes' do
      element.add_class('new-class')
      expect(element[:class]).to eq('existing new-class')
    end

    it 'adds multiple classes at once' do
      element.add_class('class1 class2')
      expect(element[:class]).to eq('existing class1 class2')
    end

    context 'with element having no class' do
      let(:doc) { Nokogiri::HTML::DocumentFragment.parse('<div>content</div>') }

      it 'adds class to element without existing class attribute' do
        element.add_class('new-class')
        # Nokogiri's native add_class handles nil class attribute gracefully
        expect(element[:class]).to include('new-class')
      end
    end
  end

  describe 'Nokogiri::XML::Element#classes' do
    let(:doc) { Nokogiri::HTML::DocumentFragment.parse('<div class="foo bar baz">content</div>') }
    let(:element) { doc.at('div') }

    it 'returns an array of class names' do
      expect(element.classes).to eq(['foo', 'bar', 'baz'])
    end

    it 'returns an empty array for element with no classes' do
      doc = Nokogiri::HTML::DocumentFragment.parse('<div>content</div>')
      element = doc.at('div')
      expect(element.classes).to eq([])
    end

    it 'handles single class' do
      doc = Nokogiri::HTML::DocumentFragment.parse('<div class="single">content</div>')
      element = doc.at('div')
      expect(element.classes).to eq(['single'])
    end

    it 'handles empty class attribute' do
      doc = Nokogiri::HTML::DocumentFragment.parse('<div class="">content</div>')
      element = doc.at('div')
      # Empty string split returns empty array
      expect(element.classes).to eq([])
    end
  end
end
