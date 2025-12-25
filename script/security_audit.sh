#!/bin/bash
set -e

# Try bundle exec first, fall back to direct
if bundle exec bundler-audit --version 2>/dev/null; then
  bundle exec bundler-audit update
  bundle exec bundler-audit check
else
  bundler-audit update
  bundler-audit check
fi