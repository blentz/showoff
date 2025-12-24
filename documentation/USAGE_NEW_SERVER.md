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

### Step 1: Test with Feature Flag

To test your presentations with the new server architecture:

```bash
# Run with new architecture
SHOWOFF_USE_NEW_SERVER=true showoff serve

# Run with legacy architecture (default)
showoff serve
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

### Step 3: Prepare for Default Switch

In version 0.22.0 (approximately 3 months from now), the new architecture will become the default. To prepare:

1. Test all your presentations with the new architecture
2. Update any custom templates or plugins to work with both architectures
3. If you need to continue using the legacy architecture, you'll be able to use:
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

## Rollback

If you encounter issues:
```bash
# Unset the flag
unset SHOWOFF_USE_NEW_SERVER
showoff serve
```

## Benefits of the New Architecture

- **Maintainability**: Clean, modular code structure
- **Reliability**: Comprehensive test coverage
- **Performance**: Optimized caching and resource usage
- **Security**: Improved input validation and error handling
- **Future-proof**: Foundation for new features

## Timeline

- **v0.21.0** (Current): Opt-in via `SHOWOFF_USE_NEW_SERVER=true`
- **v0.22.0** (+3 months): New architecture becomes default
- **v0.23.0** (+6 months): Legacy architecture deprecated with warnings
- **v0.24.0** (+9 months): Legacy architecture removed

## Technical Details

The new architecture uses a `ServerAdapter` compatibility layer to bridge between the CLI interface and the new `Showoff::Server` class. This ensures backward compatibility while providing a clean, modular implementation.

Key components:
- `Showoff::Server`: Sinatra::Base subclass with modular routes
- `Showoff::ServerAdapter`: Compatibility layer for CLI integration
- Thread-safe state managers for sessions, stats, forms, etc.
- Improved error handling and logging