#!/bin/bash
set -e

SHOWOFF_DIR="/Users/blentz/git/showoff"
SHOWOFF_CMD="cd $SHOWOFF_DIR && bundle exec bin/showoff"

# Test with minimal config
echo "Testing with minimal config..."
mkdir -p /tmp/test-minimal
cd /tmp/test-minimal
echo '{"name": "Test", "sections": ["."]}' > showoff.json
echo '# Test Slide' > slides.md
rm -rf static
eval "$SHOWOFF_CMD static"
ls -la static/
echo "Minimal config test passed!"

# Test with missing config
echo "Testing with missing config..."
mkdir -p /tmp/test-noconfig
cd /tmp/test-noconfig
echo '# Test Slide' > slides.md
rm -rf static
eval "$SHOWOFF_CMD static"
ls -la static/
echo "Missing config test passed!"

# Test with example presentation
echo "Testing with example presentation..."
cd $SHOWOFF_DIR/example
rm -rf static
eval "$SHOWOFF_CMD static"
ls -la static/
echo "Example presentation test passed!"

echo "All tests passed!"