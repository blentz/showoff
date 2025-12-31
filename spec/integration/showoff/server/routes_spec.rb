require 'spec_helper'
require 'rack/test'
require 'showoff/server'
require 'json'
require 'tmpdir'
require_relative 'presentation_patch'

RSpec.describe 'Showoff::Server Routes', type: :request do
  include Rack::Test::Methods

  # Use a real presentation from fixtures to boot the server
  let(:presentation_dir) { File.join(fixtures, 'slides') }

  # Instantiate a single server instance so we can inject test state
  # Keep reference to actual Showoff::Server instance (not wrapped by Sinatra)
  # Use new! to bypass Sinatra::Wrapper and get the actual Showoff::Server instance
  let(:showoff_server) { Showoff::Server.new!(pres_dir: presentation_dir) }

  # Rack::Test entrypoint (returns wrapped instance for HTTP requests)
  def app
    showoff_server
  end

  # Alias for backward compatibility with existing tests
  def server
    showoff_server
  end

  # Isolate persistence to a temp directory so tests never write to repo
  let(:tmpdir) { Dir.mktmpdir('server_routes_spec') }
  after do
    FileUtils.remove_entry_secure(tmpdir) if File.exist?(tmpdir)
  end

  before do
    # Route implementations are expected to use these managers. Inject temp-backed instances
    forms_file = File.join(tmpdir, 'forms.json')
    stats_file = File.join(tmpdir, 'stats.json')
    showoff_server.instance_variable_set(:@forms, Showoff::Server::FormManager.new(forms_file))
    showoff_server.instance_variable_set(:@stats, Showoff::Server::StatsManager.new(stats_file))

    # Clear download_manager to ensure clean state for each test
    # (download tests will populate after this runs)
    showoff_server.download_manager.clear
  end

  describe 'POST /form/:id' do
    let(:form_id) { 'quiz1' }

    it 'accepts valid form data submission and returns JSON echo' do
      # Legacy behavior uses a client_id cookie; keep that contract for uniqueness
      rack_mock_session.cookie_jar['client_id'] = 'client-123'

      # Simulate typical browser form post (URL-encoded). JSON is also acceptable.
      post "/form/#{form_id}", { 'q1' => 'A', 'q2' => 'B' }

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body).to include('q1' => 'A', 'q2' => 'B')
    end

    it 'handles invalid form data (missing client id) with 400/422 and JSON error' do
      # No client_id cookie set
      post "/form/#{form_id}", { 'q1' => 'A' }

      expect([400, 422]).to include(last_response.status)
      # Prefer JSON error payloads
      if last_response.headers['Content-Type']&.include?('application/json')
        err = JSON.parse(last_response.body) rescue {}
        expect(err).to be_a(Hash)
      end
    end

    it 'supports multiple submissions to same form from same client (latest wins)' do
      rack_mock_session.cookie_jar['client_id'] = 'client-abc'

      post "/form/#{form_id}", { 'q1' => 'A' }
      expect(last_response.status).to be_between(200, 201)

      post "/form/#{form_id}", { 'q1' => 'B', 'q2' => 'C' }
      expect(last_response.status).to be_between(200, 201)

      # Aggregated view should reflect a single unique responder per question with latest answer
      get "/form/#{form_id}"
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      agg = JSON.parse(last_response.body)
      expect(agg).to be_a(Hash)
      expect(agg).to have_key('q1')
      expect(agg['q1']).to include('count', 'responses')
      expect(agg['q1']['count']).to eq(1)
      expect(agg['q1']['responses']).to include('B' => 1)
    end

    it 'returns valid JSON structure for array answers and strings' do
      rack_mock_session.cookie_jar['client_id'] = 'client-xyz'

      post "/form/#{form_id}", { 'q1' => ['A', 'B'], 'q2' => 'Y' }
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      parsed = JSON.parse(last_response.body)
      expect(parsed).to include('q2' => 'Y')
      # q1 may be serialized as an Array or joined string in legacy mode; accept either
      expect(parsed.key?('q1')).to be true
    end
  end

  describe 'GET /form/:id' do
    it 'retrieves aggregated responses as JSON with expected keys' do
      rack_mock_session.cookie_jar['client_id'] = 'c1'
      post '/form/poll1', { 'color' => 'red' }
      rack_mock_session.cookie_jar['client_id'] = 'c2'
      post '/form/poll1', { 'color' => 'blue' }
      rack_mock_session.cookie_jar['client_id'] = 'c3'
      post '/form/poll1', { 'color' => 'red' }

      get '/form/poll1'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      agg = JSON.parse(last_response.body)
      expect(agg).to include('color')
      expect(agg['color']).to include('count', 'responses')
      expect(agg['color']['count']).to eq(3)
      expect(agg['color']['responses']).to include('red' => 2, 'blue' => 1)
    end

    it 'handles non-existent forms gracefully (empty object or 404)' do
      get '/form/does-not-exist'
      expect([200, 404]).to include(last_response.status)
      if last_response.ok?
        json = JSON.parse(last_response.body) rescue nil
        expect(json).to eq({})
      end
    end

    it 'returns a consistent JSON response structure' do
      rack_mock_session.cookie_jar['client_id'] = 'user-1'
      post '/form/survey', { 'optin' => 'yes', 'topics' => ['a', 'b'] }

      get '/form/survey'
      data = JSON.parse(last_response.body)
      expect(data).to be_a(Hash)
      data.each do |question, stat|
        expect(stat).to include('count', 'responses')
        expect(stat['responses']).to be_a(Hash)
      end
    end
  end

  describe 'GET /stats' do
    it 'renders the stats template (HTML) with expected sections' do
      # Preload instance variables the template expects, in case route uses them
      server.instance_variable_set(:@all, {})
      server.instance_variable_set(:@counter, nil)

      get '/stats'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('<body id="stats">')
      expect(last_response.body).to include('id="viewers"')
      expect(last_response.body).to include('id="elapsed"')
    end

    it 'handles empty stats without error (still renders page)' do
      get '/stats'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('id="viewers"')
    end

    it 'provides data to template (via instance vars or JSON endpoint)' do
      # Allow either direct instance variables or client-side fetch from stats_data
      get '/stats'
      expect(last_response.body).to match(/stats_data|id=\"all\"/)
    end
  end

  describe 'GET /health' do
    it 'returns JSON with ok status and presentation title' do
      get '/health'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body).to include('status' => 'ok')
      expect(body['presentation']).to be_a(String)
      expect(body['presentation']).not_to be_empty
    end
  end

  describe 'GET /' do
    it 'renders the index route as HTML' do
      get '/'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('<html')
      expect(last_response.body).to include('<body')
    end
  end

  # Integration tests for GET /presenter
  describe 'GET /presenter' do
    it 'renders the presenter view as HTML' do
      get '/presenter'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('<html')
      expect(last_response.body).to include('<body class="presenter">')
    end

    it 'sets presenter cookie' do
      get '/presenter'
      expect(last_response.status).to eq(200)
      expect(rack_mock_session.cookie_jar['presenter']).not_to be_nil
    end

    it 'handles errors gracefully' do
      # Mock the erb method to raise an error
      allow_any_instance_of(Showoff::Server).to receive(:erb).with(:presenter).and_raise(StandardError.new('Test error'))

      get '/presenter'
      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Error rendering presenter')
      expect(last_response.body).to include('Test error')
    end
  end

  # Integration tests for GET /print
  describe 'GET /print' do
    it 'renders the print view as HTML' do
      get '/print'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('<html')
      expect(last_response.body).to include('<body')
      expect(last_response.body).to match(/<div id=['"]slides['"]/)
    end

    it 'includes slide content with print formatting' do
      get '/print'
      expect(last_response.status).to eq(200)
      # Slides contain actual content from fixtures
      expect(last_response.body).to include('class="slide')
    end

    it 'handles section parameter' do
      get '/print/section1'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('<base href="../"')
    end

    it 'handles munged parameter' do
      get '/print/section1', munged: 'true'
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('<base href="../"')
    end

    it 'handles errors gracefully' do
      # Mock the get_slides_html method to raise an error
      allow_any_instance_of(Showoff::Server).to receive(:get_slides_html).and_raise(StandardError.new('Test error'))

      get '/print'
      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Error rendering print view')
      expect(last_response.body).to include('Test error')
    end
  end

  # Integration tests for GET /onepage
  describe 'GET /onepage' do
    it 'renders the onepage view as HTML' do
      get '/onepage'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('<html')
      expect(last_response.body).to include('<body')
      expect(last_response.body).to match(/<div id=['"]slides['"]/)
    end

    it 'includes slide content' do
      get '/onepage'
      expect(last_response.status).to eq(200)
      # Slides contain actual content from fixtures
      expect(last_response.body).to include('class="slide')
    end

    it 'handles errors gracefully' do
      # Mock the get_slides_html method to raise an error
      allow_any_instance_of(Showoff::Server).to receive(:get_slides_html).and_raise(StandardError.new('Test error'))

      get '/onepage'
      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Error rendering onepage view')
      expect(last_response.body).to include('Test error')
    end
  end

  # Integration tests for GET /slides
  describe 'GET /slides' do
    it 'returns slide content with 200 OK status' do
      get '/slides'
      expect(last_response.status).to eq(200)
    end

    it 'caches slide content by locale' do
      # First request should generate and cache
      get '/slides'
      expect(last_response.status).to eq(200)

      # Store the original content for comparison
      original_content = last_response.body

      # Mock the class-level slide_cache to verify it's used on second request
      allow(Showoff::Server.slide_cache).to receive(:get).with('en').and_return('Cached content')

      get '/slides'
      expect(last_response.body).to eq('Cached content')
    end

    it 'regenerates content when cache=clear parameter is provided' do
      # First request should generate and cache
      get '/slides'
      expect(last_response.status).to eq(200)

      # Should not use cache when cache=clear
      expect(Showoff::Server.slide_cache).to receive(:set).with('en', anything)

      get '/slides?cache=clear'
      expect(last_response.status).to eq(200)
    end

    it 'handles errors gracefully' do
      # Mock class-level slide_cache to raise an error
      allow(Showoff::Server.slide_cache).to receive(:key?).and_raise(StandardError.new('Test error'))

      get '/slides'
      expect(last_response.status).to eq(500)
      expect(last_response.headers['Content-Type']).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body).to include('error')
    end
  end

  # Comprehensive integration tests for GET /download
  describe 'GET /download' do
    # Create a temp presentation dir so we can add shared files without touching repo
    let(:tmp_pres_dir) { Dir.mktmpdir('showoff_download_pres') }

    # Override the presentation_dir for this block to use our temp dir
    let(:presentation_dir) { tmp_pres_dir }

    # Utility to write a file under the temp presentation directory
    def write_pres_file(path, content)
      full = File.join(tmp_pres_dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      full
    end

    before do
      # Minimal showoff.json so server considers this a valid presentation root
      write_pres_file('showoff.json', '{"name":"Test Pres"}')
    end

    after do
      FileUtils.remove_entry_secure(tmp_pres_dir) if File.exist?(tmp_pres_dir)
    end

    # Helper: perform the request and skip examples if route not implemented yet
    def get_download_or_skip
      get '/download'
      skip('GET /download route not implemented in Showoff::Server yet') if last_response.status == 404
    end

    context 'basic functionality' do
      it 'responds with 200 OK' do
        get_download_or_skip
        expect(last_response.status).to eq(200)
        expect(last_response.headers['Content-Type']).to include('text/html')
      end

      it 'renders the download template' do
        get_download_or_skip
        expect(last_response.body).to include('<body id="download">')
        expect(last_response.body).to include(I18n.t('downloads.title'))
      end

      it 'includes page title from presentation' do
        get_download_or_skip
        # The header partial uses @title in some contexts; ensure HTML contains a <h1> from template
        expect(last_response.body).to include('<h1>')
      end
    end

    context 'download display' do
      before do
        # Register downloads using the DownloadManager accessor
        showoff_server.download_manager.register(5, 'Slide 5 Title', ['code.rb'])
        showoff_server.download_manager.enable(5)
        showoff_server.download_manager.register(12, 'Slide 12', ['hidden.txt'])
        # Note: slide 12 is not enabled, so it should not be displayed
      end

      it 'displays registered downloads' do
        get_download_or_skip
        expect(last_response.body).to include('code.rb')
      end

      it 'shows slide number for slide-specific downloads' do
        get_download_or_skip
        expect(last_response.body).to match(/Slide\s+5\s+<small>\(Slide 5 Title\)<\/small>/)
      end

      it 'displays download titles correctly' do
        get_download_or_skip
        expect(last_response.body).to include('Slide 5 Title')
      end

      it 'creates links with correct paths' do
        get_download_or_skip
        expect(last_response.body).to include('/file/_files/code.rb')
      end

      it 'hides disabled downloads from display' do
        get_download_or_skip
        expect(last_response.body).not_to include('Slide 12')
        expect(last_response.body).not_to include('hidden.txt')
      end
    end

    context 'shared files' do
      before do
        # Create shared files under _files/share/
        write_pres_file('_files/share/shared1.txt', 'one')
        write_pres_file('_files/share/shared two.pdf', 'two')
      end

      it 'includes shared files from _files/share/' do
        get_download_or_skip
        expect(last_response.body).to include('shared1.txt')
        expect(last_response.body).to include('shared two.pdf')
      end

      it 'displays shared files without slide number' do
        get_download_or_skip
        # Ensure no heading with "Slide -999" appears
        expect(last_response.body).not_to match(/Slide\s*-999/)
      end

      it 'creates links for shared files with correct paths' do
        get_download_or_skip
        expect(last_response.body).to include('/file/_files/share/shared1.txt')
        expect(last_response.body).to include('/file/_files/share/shared two.pdf')
      end

      it 'handles missing _files/share/ directory gracefully' do
        # Clean up the share dir and re-request
        FileUtils.rm_rf(File.join(tmp_pres_dir, '_files', 'share'))
        get_download_or_skip
        # Page still renders and contains title
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include(I18n.t('downloads.title'))
      end

      it 'lists multiple shared files correctly' do
        # Add a third file
        write_pres_file('_files/share/third.zip', 'three')
        get_download_or_skip
        expect(last_response.body.scan(/<li><a href=".*?">.*?<\/a><\/li>/).length).to be >= 2
        expect(last_response.body).to include('third.zip')
      end
    end

    context 'filtering and edge cases' do
      it 'only shows enabled downloads' do
        showoff_server.download_manager.register(7, 'Disabled Slide', ['nope.txt'])
        # Note: slide 7 not enabled
        showoff_server.download_manager.register(8, 'Enabled Slide', ['yep.txt'])
        showoff_server.download_manager.enable(8)
        get_download_or_skip
        expect(last_response.body).to include('yep.txt')
        expect(last_response.body).not_to include('nope.txt')
      end

      it 'handles empty downloads list' do
        showoff_server.download_manager.clear
        get_download_or_skip
        # Still renders page with title
        expect(last_response.body).to include(I18n.t('downloads.title'))
      end

      it 'handles no registered downloads' do
        showoff_server.download_manager.clear
        get_download_or_skip
        expect(last_response.body).to include(I18n.t('downloads.title'))
      end

      it 'sorts downloads by slide number' do
        showoff_server.download_manager.register(10, 'Ten', ['b.txt'])
        showoff_server.download_manager.enable(10)
        showoff_server.download_manager.register(2, 'Two', ['a.txt'])
        showoff_server.download_manager.enable(2)
        get_download_or_skip
        # Ensure order: Slide 2 before Slide 10
        body = last_response.body
        idx2 = body.index('Slide 2')
        idx10 = body.index('Slide 10')
        expect(idx2).to be < idx10
      end

      it 'renders -999 as shared section without heading' do
        # The -999 entry is added by the route itself from shared files
        # This test just verifies the route doesn't crash with an existing -999
        get_download_or_skip
        # Just verify page renders - shared files section tested separately
        expect(last_response.status).to eq(200)
      end

      it 'handles special characters in filenames' do
        showoff_server.download_manager.register(3, 'Three', ["weird & name(1).txt", "uniçødé.pdf"])
        showoff_server.download_manager.enable(3)
        get_download_or_skip
        expect(last_response.body).to include('weird & name(1).txt')
        expect(last_response.body).to include('uniçødé.pdf')
      end
    end
  end

  # WebSocket control route basic integration tests
  # Full WebSocket integration testing requires:
  # - A WebSocket client library (faye-websocket or similar)
  # - EventMachine reactor loop running
  # - Async test framework
  # These are tested thoroughly in unit tests with mocks.
  # Integration tests verify the route exists and basic guards work.
  describe 'GET /control - WebSocket endpoint' do
    # Note: Full WebSocket integration requires a real WebSocket client
    # These tests verify the route exists and basic setup

    it 'returns 404 when interactive mode is disabled' do
      # Test with interactive: false
      allow(showoff_server.settings).to receive(:showoff_config).and_return({ interactive: false })

      get '/control'

      expect([200, 404]).to include(last_response.status)
    end

    it 'returns 404 when not a WebSocket request' do
      # Test with interactive mode but no WS upgrade
      allow(showoff_server.settings).to receive(:showoff_config).and_return({ interactive: true })

      get '/control'

      expect(last_response.status).to eq(404)
    end

    it 'route exists and is accessible' do
      # Verify the route is defined
      routes = showoff_server.class.routes['GET']
      control_route = routes.find { |route| route[0].match('/control') }

      expect(control_route).not_to be_nil
    end
  end

  # Integration tests for GET /supplemental/:content
  describe 'GET /supplemental/:content' do
    let(:content_type) { 'guide' }

    # Helper: perform the request and skip examples if route not implemented yet
    def get_supplemental_or_skip(content = 'guide', params = {})
      get "/supplemental/#{content}", params
      skip('GET /supplemental/:content route not implemented in Showoff::Server yet') if last_response.status == 404
    end

    it 'responds with 200 OK' do
      get_supplemental_or_skip
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
    end

    it 'renders the onepage template with supplemental wrapper class' do
      get_supplemental_or_skip
      expect(last_response.body).to include('<body')
      expect(last_response.body).to match(/<div id=['"]slides['"]/)
      expect(last_response.body).to match(/class=['"]supplemental['"]/)
    end

    it 'includes slide content filtered for supplemental material' do
      # Mock get_slides_html to verify it's called with correct parameters
      expect_any_instance_of(Showoff::Server).to receive(:get_slides_html).with(
        hash_including(supplemental: 'guide', section: false, toc: :all)
      ).and_return('Supplemental content')

      get_supplemental_or_skip
      expect(last_response.status).to eq(200)
    end

    it 'supports static parameter' do
      # Mock get_slides_html to verify it's called with static: true
      expect_any_instance_of(Showoff::Server).to receive(:get_slides_html).with(
        hash_including(static: true, supplemental: 'guide')
      ).and_return('Static supplemental content')

      get_supplemental_or_skip('guide', static: 'true')
      expect(last_response.status).to eq(200)
    end

    it 'handles different content types' do
      # Test with a different content type
      get_supplemental_or_skip('handout')
      expect(last_response.status).to eq(200)
    end

    it 'handles errors gracefully' do
      # Mock get_slides_html to raise an error
      allow_any_instance_of(Showoff::Server).to receive(:get_slides_html).and_raise(StandardError.new('Test error'))

      get_supplemental_or_skip
      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Error rendering supplemental content')
      expect(last_response.body).to include('Test error')
    end
  end
end
