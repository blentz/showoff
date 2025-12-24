# Using the Showoff Server Architecture

## Quick Start

The new architecture is now the default:

```bash
showoff serve
```

To use the legacy architecture (deprecated):

```bash
SHOWOFF_USE_LEGACY_SERVER=true showoff serve
```

## What's Different?

The new architecture provides:
- Modular, maintainable codebase
- Better error handling
- Thread-safe state management
- Same features as legacy

## Migration Guide

### Step 1: Test with Both Architectures

To test your presentations with both server architectures:

```bash
# Run with new architecture (default)
showoff serve

# Run with legacy architecture (deprecated)
SHOWOFF_USE_LEGACY_SERVER=true showoff serve
```

Compare the behavior between the two modes. The new architecture should be 100% compatible with existing presentations.

### Step 2: Report Issues

If you encounter any issues with the new architecture:

1. Check if the issue occurs with the legacy architecture as well
2. If it's specific to the new architecture, report it on GitHub:
   - Include the presentation file structure
   - Describe the expected vs. actual behavior
   - Include any error messages from the console
   - Mention that you're using `SHOWOFF_USE_NEW_SERVER=true`

### Step 3: Prepare for Legacy Removal

In version 0.23.0, the legacy architecture will be removed completely. To prepare:

1. Test all your presentations with the new architecture (now the default)
2. Update any custom templates or plugins to work with the new architecture
3. If you encounter issues, please report them promptly
4. The legacy architecture can still be used temporarily with:
   ```bash
   SHOWOFF_USE_LEGACY_SERVER=true showoff serve
   ```

## Troubleshooting

### Server Won't Start

If the server fails to start with the new architecture:

1. Check for error messages in the console
2. Verify that your presentation directory contains a valid `showoff.json` file
3. Try running with verbose mode: `SHOWOFF_USE_NEW_SERVER=true showoff serve -v`
4. If needed, fall back to legacy mode temporarily

### WebSocket Issues

If you experience WebSocket connection problems (slides not syncing between presenter and audience):

1. Check browser console for WebSocket errors
2. Verify that your network allows WebSocket connections
3. Try using a different browser
4. Report the issue with details about your environment

### SSL Configuration

If you're using SSL and encounter issues:

```bash
# With certificate and key files
SHOWOFF_USE_NEW_SERVER=true showoff serve -s --ssl_certificate=cert.pem --ssl_private_key=key.pem

# With auto-generated certificates (development only)
SHOWOFF_USE_NEW_SERVER=true showoff serve -s
```

## Temporary Rollback

If you encounter issues with the new architecture:
```bash
# Use the legacy server temporarily
SHOWOFF_USE_LEGACY_SERVER=true showoff serve
```

Note: The legacy server will display deprecation warnings and will be removed in v0.23.0.

## Benefits of the New Architecture

- **Maintainability**: Clean, modular code structure
- **Reliability**: Comprehensive test coverage
- **Performance**: Optimized caching and resource usage
- **Security**: Improved input validation and error handling
- **Future-proof**: Foundation for new features

## Timeline

- **v0.21.0**: Opt-in via `SHOWOFF_USE_NEW_SERVER=true`
- **v0.22.0** (Current): New architecture as default, legacy opt-out with `SHOWOFF_USE_LEGACY_SERVER=true`
- **v0.23.0** (+3 months): Legacy architecture removed
- **v0.24.0** (+6 months): Compatibility shims removed

## Technical Details

The new architecture uses a `ServerAdapter` compatibility layer to bridge between the CLI interface and the new `Showoff::Server` class. This ensures backward compatibility while providing a clean, modular implementation.

Key components:
- `Showoff::Server`: Sinatra::Base subclass with modular routes
- `Showoff::ServerAdapter`: Compatibility layer for CLI integration
- Thread-safe state managers for sessions, stats, forms, etc.
- Improved error handling and logging