# frozen_string_literal: true

require 'spec_helper'
require 'showoff_utils'

RSpec.describe MarkdownConfig do
  let(:dir) { '/tmp/preso' }

  describe '.defaults' do
    it 'returns rdiscount defaults' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('rdiscount')

      expect(described_class.defaults(dir)).to eq({
        autolink: true
      })
    end

    it 'returns maruku defaults (empty hash)' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('maruku')

      expect(described_class.defaults(dir)).to eq({})
    end

    it 'returns bluecloth defaults' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('bluecloth')

      expect(described_class.defaults(dir)).to eq({
        auto_links: true,
        definition_lists: true,
        superscript: true,
        tables: true
      })
    end

    it 'returns kramdown defaults (empty hash)' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('kramdown')

      expect(described_class.defaults(dir)).to eq({})
    end

    it 'returns commonmarker defaults' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('commonmarker')

      expect(described_class.defaults(dir)).to eq({
        UNSAFE: true
      })
    end

    it 'returns redcarpet defaults when renderer is redcarpet' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('redcarpet')

      expect(described_class.defaults(dir)).to eq({
        autolink: true,
        no_intra_emphasis: true,
        superscript: true,
        tables: true,
        underline: true
      })
    end

    it 'falls back to redcarpet defaults for unknown renderer' do
      allow(ShowoffUtils).to receive(:showoff_markdown).with(dir).and_return('foobar_markdown')

      expect(described_class.defaults(dir)).to eq({
        autolink: true,
        no_intra_emphasis: true,
        superscript: true,
        tables: true,
        underline: true
      })
    end
  end

  # Note: Testing .setup is difficult because it modifies global Tilt state
  # and requires specific markdown gems to be installed. The .defaults method
  # covers the renderer selection logic, which is the core testable behavior.
  # The .setup method is tested indirectly through integration tests that
  # actually render markdown content.
end
