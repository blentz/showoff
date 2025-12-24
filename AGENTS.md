# AGENTS.md

## Project Overview

**Showoff** - Sinatra-based slideshow presentation server. Markdown → HTML slides with live presenter mode, audience sync, code execution, PDF export.

**Version:** 0.22.0
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
├── showoff.rb           # Legacy monolithic Sinatra app (DEPRECATED)
├── showoff_ng.rb        # Clean orchestrator - serves `static`/`pdf`
├── showoff_utils.rb     # Utilities, MarkdownConfig
├── commandline_parser.rb # Parslet parser for shell blocks
└── showoff/
    ├── compiler.rb      # Markdown→HTML orchestrator
    ├── config.rb        # showoff.json loader
    ├── presentation.rb  # Presentation model
    ├── state.rb         # Global state singleton
    ├── server.rb        # New modular Sinatra::Base server
    ├── server_adapter.rb # CLI compatibility layer
    ├── compiler/        # Pipeline stages (notes, forms, i18n, etc.)
    ├── presentation/    # Section/Slide models
    └── server/          # Server components (managers, routes)
```

## Commands

```bash
bundle install                # Install deps
showoff serve                 # Run server (port 9090) - uses new architecture
SHOWOFF_USE_LEGACY_SERVER=true showoff serve  # Run with legacy architecture (deprecated)
showoff static                # Static HTML
showoff pdf                   # PDF generation
showoff serve -x              # Enable code execution
rake spec                     # Run RSpec tests
```

## Architecture Notes

1. **Dual Codebase (Active Refactor - Phase 5b):**
   - `showoff.rb` = Monolithic god class (DEPRECATED). Routes, markdown, websockets, forms, stats inline.
   - `showoff_ng.rb` = Clean orchestrator delegating to modular `Showoff::*` classes.
   - `serve` command now uses new architecture by default.
   - **Legacy code will be removed in v0.24.0. All new code must follow showoff_ng patterns.**

2. **Compilation Pipeline (showoff_ng):**
   Markdown → Variables → i18n → Tilt → Nokogiri DOM → Forms → Fixups → Glossary → Downloads → Notes

3. **State:** `Showoff::State` singleton manages slide count, section numbers, output format.

4. **Config:** `showoff.json` in presentation root defines sections, styles, templates.

5. **Server Components (new architecture):**
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
- **Coverage:** 507 examples, 0 failures, 100% on new components

## Key Files by Task

| Task | Files |
|------|-------|
| CLI | `bin/showoff` |
| Routes | `lib/showoff.rb`, `lib/showoff_ng.rb` |
| Markdown | `lib/showoff/compiler.rb`, `lib/showoff/compiler/*.rb` |
| Slides | `lib/showoff/presentation/slide.rb`, `views/slide.erb` |
| Config | `lib/showoff/config.rb` |
| Static/PDF | `Showoff.do_static()` in main app |
| Server | `lib/showoff/server.rb`, `lib/showoff/server_adapter.rb` |
| WebSocket | `lib/showoff/server/websocket_manager.rb` |

## Conventions

- Slide syntax: `<!SLIDE [options] classes #id>`
- Speaker notes: `~~~SECTION:notes~~~...~~~ENDSECTION~~~`
- Section = directory, file, array, or external JSON include
- CSS classes control behavior: `bullets`, `incremental`, `commandline`, `execute`, `form=name`
- i18n: UI in `locales/*.yml`, content in `locales/<lang>/` subdirs
