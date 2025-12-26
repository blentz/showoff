require 'spec_helper'
require 'rack/test'
require 'showoff/server'

describe 'Showoff::Server execute route' do
  include Rack::Test::Methods

  let(:app) do
    Showoff::Server.new(
      pres_dir: File.join(File.dirname(__FILE__), '..', '..', '..', 'fixtures', 'slides'),
      execute: true,
      verbose: false
    )
  end

  let(:execution_manager) { instance_double(Showoff::Server::ExecutionManager) }

  before do
    allow_any_instance_of(Showoff::Server).to receive(:execution_manager).and_return(execution_manager)
  end

  describe 'GET /execute/:lang' do
    context 'when code execution is enabled' do
      before do
        allow(execution_manager).to receive(:get_code_from_slide).with('test/slide', '0').and_return('puts "Hello, World!"')
        allow(execution_manager).to receive(:execute).with('ruby', 'puts "Hello, World!"').and_return('Hello, World!')
      end

      it 'executes code and returns the result' do
        # Set host-related headers to permitted values
        get '/execute/ruby', { path: 'test/slide', index: '0' }, { 'HTTP_HOST' => 'localhost' }

        expect(last_response).to be_ok
        expect(last_response.body).to include('Hello, World!')
      end
    end

    context 'when code execution is disabled' do
      let(:app) do
        Showoff::Server.new(
          pres_dir: File.join(File.dirname(__FILE__), '..', '..', '..', 'fixtures', 'slides'),
          execute: false,
          verbose: false
        )
      end

      it 'returns an error message' do
        # Set host-related headers to permitted values
        get '/execute/ruby', { path: 'test/slide', index: '0' }, { 'HTTP_HOST' => 'localhost' }
        expect(last_response).to be_ok
        expect(last_response.body).to include('Run showoff with -x or --executecode to enable code execution')
      end
    end
  end
end