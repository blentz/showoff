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
├── showoff.rb           # Monolithic Sinatra app (2000+ LOC) - serves `serve` command
├── showoff_ng.rb        # Clean orchestrator (100 LOC) - serves `static`/`pdf` via --dev
├── showoff_utils.rb     # Utilities, MarkdownConfig
├── commandline_parser.rb # Parslet parser for shell blocks
└── showoff/
    ├── compiler.rb      # Markdown→HTML orchestrator (showoff_ng)
    ├── config.rb        # showoff.json loader
    ├── presentation.rb  # Presentation model
    ├── state.rb         # Global state singleton
    ├── compiler/        # Pipeline stages (notes, forms, i18n, etc.)
    └── presentation/    # Section/Slide models
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
   - **Legacy code will be removed in v0.23.0. All new code must follow showoff_ng patterns.**

2. **Compilation Pipeline (showoff_ng):**
   Markdown → Variables → i18n → Tilt → Nokogiri DOM → Forms → Fixups → Glossary → Downloads → Notes

3. **State:** `Showoff::State` singleton manages slide count, section numbers, output format.

4. **Config:** `showoff.json` in presentation root defines sections, styles, templates.

## Testing

- **Framework:** RSpec
- **Location:** `spec/unit/showoff/`
- **Fixtures:** `spec/fixtures/`
- **Run:** `rake spec` or `rspec spec/unit/`

## Key Files by Task

| Task | Files |
|------|-------|
| CLI | `bin/showoff` |
| Routes | `lib/showoff.rb`, `lib/showoff_ng.rb` |
| Markdown | `lib/showoff/compiler.rb`, `lib/showoff/compiler/*.rb` |
| Slides | `lib/showoff/presentation/slide.rb`, `views/slide.erb` |
| Config | `lib/showoff/config.rb` |
| Static/PDF | `Showoff.do_static()` in main app |

## Conventions

- Slide syntax: `<!SLIDE [options] classes #id>`
- Speaker notes: `~~~SECTION:notes~~~...~~~ENDSECTION~~~`
- Section = directory, file, array, or external JSON include
- CSS classes control behavior: `bullets`, `incremental`, `commandline`, `execute`, `form=name`
- i18n: UI in `locales/*.yml`, content in `locales/<lang>/` subdirs
