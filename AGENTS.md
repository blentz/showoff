# AGENTS.md

## Project Overview

**Showoff** - Sinatra-based slideshow presentation server. Markdown → HTML slides with live presenter mode, audience sync, code execution, PDF export.

**Version:** 0.24.0
**Ruby:** >= 1.9 (targets 2.x)

## Tech Stack

| Component | Tech |
|-----------|------|
| Web | Sinatra (~> 2.1), Rack, Thin |
| Markdown | Redcarpet (default), CommonMarker, others |
| HTML | Nokogiri, Tilt, ERB |
| CLI | GLI (~> 2.20) |
| Real-time | sinatra-websocket |
| i18n | I18n (~> 1.8) |

## Project Structure

```
lib/
├── showoff_ng.rb        # Main orchestrator - serves `static`/`pdf`
├── showoff_utils.rb     # Utilities, MarkdownConfig
├── commandline_parser.rb # Parslet parser for shell blocks
└── showoff/
    ├── compiler.rb      # Markdown→HTML orchestrator
    ├── config.rb        # showoff.json loader
    ├── presentation.rb  # Presentation model
    ├── state.rb         # Global state singleton
    ├── server.rb        # Sinatra::Base server
    ├── server_adapter.rb # CLI compatibility layer
    ├── compiler/        # Pipeline stages (notes, forms, i18n, etc.)
    ├── presentation/    # Section/Slide models
    └── server/          # Server components (managers, routes)
```

## Commands

```bash
bundle install                # Install deps
showoff serve                 # Run server (port 9090)
showoff static                # Static HTML
showoff pdf                   # PDF generation
showoff serve -x              # Enable code execution
rake spec                     # Run RSpec tests
```

## Architecture

The modular architecture provides clean separation of concerns:

1. **Compilation Pipeline:**
   Markdown → Variables → i18n → Tilt → Nokogiri DOM → Forms → Fixups → Glossary → Downloads → Notes

2. **State:** `Showoff::State` singleton manages slide count, section numbers, output format.

3. **Config:** `showoff.json` in presentation root defines sections, styles, templates.

4. **Server Components:**
   - `Showoff::Server` - Sinatra::Base subclass with modular routes
   - `Showoff::ServerAdapter` - CLI compatibility layer
   - `SessionState` - Thread-safe session management
   - `StatsManager` - Statistics tracking with JSON persistence
   - `FormManager` - Form response storage and aggregation
   - `CacheManager` - LRU cache with hit/miss tracking
   - `WebSocketManager` - Real-time slide synchronization
   - `FeedbackManager` - Audience feedback collection

## Testing

- **Framework:** RSpec
- **Location:** `spec/unit/showoff/`
- **Fixtures:** `spec/fixtures/`
- **Run:** `rake spec` or `rspec spec/unit/`
- **Coverage:** 500+ examples, 100% on server components

## Key Files by Task

| Task | Files |
|------|-------|
| CLI | `bin/showoff` |
| Routes | `lib/showoff_ng.rb`, `lib/showoff/server.rb` |
| Markdown | `lib/showoff/compiler.rb`, `lib/showoff/compiler/*.rb` |
| Slides | `lib/showoff/presentation/slide.rb`, `views/slide.erb` |
| Config | `lib/showoff/config.rb` |
| Static/PDF | `Showoff.do_static()` in showoff_ng.rb |
| Server | `lib/showoff/server.rb`, `lib/showoff/server_adapter.rb` |
| WebSocket | `lib/showoff/server/websocket_manager.rb` |

## Conventions

- Slide syntax: `<!SLIDE [options] classes #id>`
- Speaker notes: `~~~SECTION:notes~~~...~~~ENDSECTION~~~`
- Section = directory, file, array, or external JSON include
- CSS classes control behavior: `bullets`, `incremental`, `commandline`, `execute`, `form=name`
- i18n: UI in `locales/*.yml`, content in `locales/<lang>/` subdirs

## Security Scanning
- bundler-audit: Checks for vulnerable gem dependencies
- Run: `bundle exec bundler-audit check`
- Update database: `bundle exec bundler-audit update`
