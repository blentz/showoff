# Migration Guide: Showoff v0.23.0

This guide describes the modular architecture introduced in Showoff v0.21.0 and made the default in v0.22.0. As of v0.23.0, the legacy architecture has been completely removed.

## Overview

Starting with v0.22.0, Showoff uses a completely refactored server architecture by default. This new architecture provides:

- **Modular codebase**: Clean separation of concerns
- **Thread-safe state management**: Improved reliability
- **Better error handling**: More informative error messages
- **Comprehensive test coverage**: 507 tests, 100% coverage on new components

## Quick Start

### For Most Users

**No action required.** The new architecture is fully backward compatible. Simply upgrade to v0.22.0 and run your presentations as usual:

```bash
gem update showoff
showoff serve
```

### If You Encounter Issues

If you experience any problems with the architecture, please report them:

1. **Gather information**:
   - Showoff version (`showoff --version`)
   - Ruby version (`ruby --version`)
   - Operating system
   - Error messages (full stack trace if available)
   - Minimal reproduction case

2. **Report on GitHub**: https://github.com/puppetlabs/showoff/issues

## Timeline

| Version | Status | Notes |
|---------|--------|-------|
| v0.21.0 | Released | New architecture opt-in via `SHOWOFF_USE_NEW_SERVER=true` |
| v0.22.0 | Released | New architecture is default |
| v0.23.0 | **Current** | Legacy architecture removed |

## What Changed

### Architecture Changes

The monolithic `lib/showoff.rb` (2000+ LOC) has been replaced with a modular architecture:

| Old | New |
|-----|-----|
| `Showoff` class (Sinatra::Application) | `Showoff::Server` (Sinatra::Base) |
| Class variables for state | Thread-safe state managers |
| Inline WebSocket handling | `WebSocketManager` class |
| Inline form handling | `FormManager` class |
| Inline stats tracking | `StatsManager` class |
| Inline caching | `CacheManager` class |

### New Components

- `Showoff::Server` - Modular Sinatra::Base server
- `Showoff::ServerAdapter` - CLI compatibility layer
- `Showoff::Server::SessionState` - Thread-safe session management
- `Showoff::Server::StatsManager` - Statistics tracking
- `Showoff::Server::FormManager` - Form response storage
- `Showoff::Server::CacheManager` - LRU cache
- `Showoff::Server::WebSocketManager` - Real-time synchronization
- `Showoff::Server::FeedbackManager` - Audience feedback

## Compatibility

### Features

The modular architecture supports all Showoff features:

- All presentation formats (Markdown, showoff.json)
- Slide syntax (`<!SLIDE>`, notes, forms, etc.)
- Presenter mode
- Audience synchronization
- Code execution (`-x` flag)
- SSL/HTTPS support
- Static HTML generation
- PDF generation
- All CLI options

## Troubleshooting

### Server Won't Start

1. **Check the error message** - The new architecture provides more detailed error messages
2. **Verify showoff.json** - Ensure your presentation config is valid JSON
3. **Check file permissions** - Ensure all presentation files are readable
4. **Try verbose mode** - Run with `-v` for more information:
   ```bash
   showoff serve -v
   ```

### WebSocket Connection Issues

If slides aren't syncing between presenter and audience:

1. **Check browser console** - Look for WebSocket errors
2. **Verify network** - Ensure WebSocket connections aren't blocked
3. **Try different browser** - Some browsers handle WebSockets differently
4. **Check firewall** - Ensure port 9090 (or your configured port) is open

### SSL/HTTPS Issues

```bash
# With certificate files
showoff serve -s --ssl_certificate=cert.pem --ssl_private_key=key.pem

# Auto-generated certificates (development only)
showoff serve -s
```

### Form Submission Issues

If forms aren't working:

1. **Check browser console** - Look for JavaScript errors
2. **Verify form syntax** - Ensure form markup is correct
3. **Check server logs** - Run with `-v` for verbose output

## Reporting Issues

If you encounter any issues:

1. **Gather information**:
   - Showoff version (`showoff --version`)
   - Ruby version (`ruby --version`)
   - Operating system
   - Error messages (full stack trace if available)
   - Minimal reproduction case

2. **Report on GitHub**: https://github.com/puppetlabs/showoff/issues

## For Developers

### Custom Plugins/Extensions

If you've written custom code that interacts with Showoff internals:

1. **Check for class variable usage** - The architecture uses instance-based state managers instead of class variables
2. **Update Sinatra::Application references** - Use `Showoff::Server` instead
3. **Test thoroughly** - Run your custom code with the current architecture

### API Changes

The public API (CLI, showoff.json format, slide syntax) is unchanged. Internal APIs have changed:

| Old | New |
|-----|-----|
| `@@forms` | `FormManager.instance` |
| `@@cache` | `CacheManager.instance` |
| `@@counter` | `StatsManager.instance` |
| `@@cookie`, `@@master` | `SessionState.instance` |

## FAQ

### Q: Do I need to change my presentations?

**A:** No. The new architecture is fully backward compatible with existing presentations.

### Q: Has the legacy server been removed?

**A:** Yes, as of v0.23.0, the legacy server has been completely removed.

### Q: Is the new architecture faster?

**A:** Performance is comparable. The main benefits are maintainability and reliability.

### Q: Can I contribute to the new architecture?

**A:** Yes! See [CONTRIB.md](../CONTRIB.md) for contribution guidelines.

## Additional Resources

- [USAGE.rdoc](../USAGE.rdoc) - Detailed usage guide
- [REFACTOR.rdoc](../REFACTOR.rdoc) - Technical refactoring details
- [PHASE5_COMPLETION.md](PHASE5_COMPLETION.md) - Phase 5 completion report
- [SERVER_ARCHITECTURE.md](../SERVER_ARCHITECTURE.md) - Architecture documentation
