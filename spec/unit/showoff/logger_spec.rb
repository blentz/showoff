# frozen_string_literal: true

require 'spec_helper'
require 'showoff/state'
require 'showoff/logger'

RSpec.describe Showoff::Logger do
  # Capture stderr for log output verification
  let(:original_stderr) { $stderr }

  describe 'class methods' do
    it 'responds to debug' do
      expect(described_class).to respond_to(:debug)
    end

    it 'responds to info' do
      expect(described_class).to respond_to(:info)
    end

    it 'responds to warn' do
      expect(described_class).to respond_to(:warn)
    end

    it 'responds to error' do
      expect(described_class).to respond_to(:error)
    end

    it 'responds to fatal' do
      expect(described_class).to respond_to(:fatal)
    end
  end

  describe 'logging output' do
    let(:string_io) { StringIO.new }

    before do
      # Access and reconfigure the class variable logger for testing
      # This is a bit hacky but necessary to test the output
      @original_logger = described_class.class_variable_get(:@@logger)
      test_logger = Logger.new(string_io)
      test_logger.progname = 'Showoff'
      test_logger.formatter = proc { |severity, datetime, progname, msg| "(#{progname}) #{severity}: #{msg}\n" }
      test_logger.level = Logger::DEBUG
      described_class.class_variable_set(:@@logger, test_logger)
    end

    after do
      described_class.class_variable_set(:@@logger, @original_logger)
    end

    it 'logs warn messages' do
      described_class.warn('test warning')
      expect(string_io.string).to include('WARN')
      expect(string_io.string).to include('test warning')
      expect(string_io.string).to include('Showoff')
    end

    it 'logs error messages' do
      described_class.error('test error')
      expect(string_io.string).to include('ERROR')
      expect(string_io.string).to include('test error')
    end

    it 'logs fatal messages' do
      described_class.fatal('test fatal')
      expect(string_io.string).to include('FATAL')
      expect(string_io.string).to include('test fatal')
    end

    it 'logs info messages' do
      described_class.info('test info')
      expect(string_io.string).to include('INFO')
      expect(string_io.string).to include('test info')
    end

    it 'logs debug messages' do
      described_class.debug('test debug')
      expect(string_io.string).to include('DEBUG')
      expect(string_io.string).to include('test debug')
    end

    it 'formats messages with progname and severity' do
      described_class.warn('formatted message')
      expect(string_io.string).to match(/\(Showoff\) WARN: formatted message/)
    end
  end

  describe 'log level configuration' do
    it 'has a logger configured' do
      logger = described_class.class_variable_get(:@@logger)
      expect(logger).to be_a(Logger)
    end

    it 'has progname set to Showoff' do
      logger = described_class.class_variable_get(:@@logger)
      expect(logger.progname).to eq('Showoff')
    end

    it 'has level set to WARN by default' do
      logger = described_class.class_variable_get(:@@logger)
      expect(logger.level).to eq(Logger::WARN)
    end
  end
end
