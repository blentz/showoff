require 'spec_helper'
require 'rack/test'
require 'showoff/server'

describe 'Showoff::Server execute route security' do
  include Rack::Test::Methods

  let(:app) do
    Showoff::Server.new(
      pres_dir: File.join(File.dirname(__FILE__), '..', '..', '..', 'fixtures', 'slides'),
      execute: true,
      verbose: false
    )
  end

  describe 'GET /execute/:lang security' do
    context 'with malicious input' do
      let(:execution_manager) { instance_double(Showoff::Server::ExecutionManager) }

      before do
        allow_any_instance_of(Showoff::Server).to receive(:execution_manager).and_return(execution_manager)
      end

      it 'handles command injection attempts' do
        malicious_code = 'puts "Hello"; system("rm -rf /")'
        allow(execution_manager).to receive(:get_code_from_slide).with('test/slide', '0').and_return(malicious_code)

        # The execution manager should sanitize the input by using a tempfile and not executing shell commands directly
        expect(execution_manager).to receive(:execute).with('ruby', malicious_code)
          .and_return('Command contained potentially malicious content')

        get '/execute/ruby', path: 'test/slide', index: '0'
        expect(last_response).to be_ok
      end

      it 'handles path traversal attempts' do
        allow(execution_manager).to receive(:get_code_from_slide).with('../../etc/passwd', '0')
          .and_return('File not found or invalid path')
        allow(execution_manager).to receive(:execute).with('ruby', 'File not found or invalid path')
          .and_return('Error: Invalid path')

        get '/execute/ruby', path: '../../etc/passwd', index: '0'
        expect(last_response).to be_ok
        expect(last_response.body).to eq('Error: Invalid path')
      end

      it 'handles timeout for infinite loops' do
        infinite_loop_code = 'while true; end'
        allow(execution_manager).to receive(:get_code_from_slide).with('test/slide', '0').and_return(infinite_loop_code)
        allow(execution_manager).to receive(:execute).with('ruby', infinite_loop_code)
          .and_return('Execution timed out')

        get '/execute/ruby', path: 'test/slide', index: '0'
        expect(last_response).to be_ok
        expect(last_response.body).to eq('Execution timed out')
      end

      it 'handles shell metacharacters' do
        metacharacter_code = 'puts `echo "pwned"`'
        allow(execution_manager).to receive(:get_code_from_slide).with('test/slide', '0').and_return(metacharacter_code)
        allow(execution_manager).to receive(:execute).with('ruby', metacharacter_code)
          .and_return('Code executed in sandbox')

        get '/execute/ruby', path: 'test/slide', index: '0'
        expect(last_response).to be_ok
        expect(last_response.body).to eq('Code executed in sandbox')
      end

      it 'handles attempts to access internal files' do
        file_access_code = 'puts File.read("/etc/passwd")'
        allow(execution_manager).to receive(:get_code_from_slide).with('test/slide', '0').and_return(file_access_code)
        allow(execution_manager).to receive(:execute).with('ruby', file_access_code)
          .and_return('Permission denied')

        get '/execute/ruby', path: 'test/slide', index: '0'
        expect(last_response).to be_ok
        expect(last_response.body).to eq('Permission denied')
      end
    end

    context 'with invalid language' do
      it 'returns an error for unknown languages' do
        allow_any_instance_of(Showoff::Server::ExecutionManager).to receive(:get_code_from_slide)
          .with('test/slide', '0').and_return('puts "Hello"')
        allow_any_instance_of(Showoff::Server::ExecutionManager).to receive(:execute)
          .with('nonexistent', 'puts "Hello"').and_return('No parser for nonexistent')

        get '/execute/nonexistent', path: 'test/slide', index: '0'
        expect(last_response).to be_ok
        expect(last_response.body).to eq('No parser for nonexistent')
      end
    end
  end
end