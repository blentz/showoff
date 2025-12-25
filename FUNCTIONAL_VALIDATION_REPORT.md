# Functional Validation Report - v0.24.0

## Test Date
Thu Dec 25 2025

## Container Tests
- Build: PASS (showoff:latest, showoff:test built)
- RSpec Suite: FAIL (failures present; nokogiri mismatch initially, then spec failures in config and others)
- Serve Command: PARTIAL PASS (container default CMD 54321 runs; host port forward returned empty replies, but in-container HTTP ok)
- Info Command: PASS
- Validate Command: PASS (0 errors)
- Static Command: FAIL (error initializing sections; attempted write to read-only presentation; no output generated)
- Heroku Command: FAIL (heroku CLI not available in container)

## Web Validation (crawl4ai)
- Homepage crawl: FAIL (container API reachable on 8000->11235, but could not reach Showoff via host/bridge; ERR_CONNECTION_REFUSED)
- Presenter crawl: FAIL (same as above)
- Health check: FAIL via crawl4ai; direct in-container request returned {"status":"ok","presentation":"Something"}
- Screenshot capture: FAIL (connection refused from crawler to showoff)
- HTML structure: PARTIAL (homepage contains <div id="preso">, but no <div class="slide"> without JS execution; showoff.js present)
- JavaScript execution: FAIL (not executed due to crawler connectivity)

## Integration Tests
- Slide navigation: FAIL (GET /slides returns placeholder; /slides/1 and /slides/2 returned 404)
- Static assets: PASS (css/showoff.css and js/showoff.js returned 200 OK)
- Stats endpoints: PASS (HTML for /stats; JSON for /stats_data)

## Issues Found
1) RSpec test suite failures:
   - Initial bundler gem mismatch for nokogiri on aarch64; resolved by `bundle update nokogiri` inside container
   - Multiple spec failures observed (e.g., Showoff::Config expected keys; includes new key `favicon`). Full test summary truncated in console; needs review and spec updates.
2) Serve on host: Port-forwarded access (9090->54321) returned "Empty reply from server" from host curl, while in-container HTTP was OK. Likely Podman macOS port proxy quirk with Thin. Functional serving validated via `podman exec`.
3) Static generation: `showoff static /output` tried to create a local `static/` under presentation; with read-only volume it failed. With writable volume, still failed after "Error initializing sections". Needs investigation.
4) Heroku command requires heroku gem/CLI in the container; not present. Either adjust container or skip in containerized validation.
5) crawl4ai service networking: Required mapping is 8000(host)->11235(container). Even with correct mapping, crawler could not reach showoff via host.docker.internal/host.containers.internal or by container name. Direct access to container IP:54321 also refused. Likely Podman networking isolation on macOS. As a result, all crawl4ai acquisition steps failed in this environment.
6) Slide navigation endpoints: The documented /slides/:id endpoints returned 404; /slides (no id) returned placeholder HTML. Confirm intended route shape or update docs/tests.

## Conclusion
This validation gate did NOT pass. Core blockers:
- RSpec suite has failing examples (must be 507/507 green per criteria)
- crawl4ai validation cannot reach the running server under current Podman (macOS) networking; needs network config or alternative approach
- Static site generation failed; requires fix
- Heroku command unusable in current container image

Next actions recommended:
- Fix/align specs with current config keys (e.g., `favicon`) or update implementation to match spec
- Investigate Thin + Podman port-proxy behavior on macOS causing "Empty reply"; alternatively, switch to Puma/WEBrick or use host networking
- Update `showoff static` to respect explicit output dir without writing to presentation root; ensure sections init error is addressed
- Either include Heroku CLI in test image or modify `showoff heroku` to operate offline (file generation only) in container
- For crawl4ai, consider creating a custom user-defined podman network and running both containers in it; use container DNS names or explicit IPs
