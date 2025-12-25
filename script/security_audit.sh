#!/bin/bash
set -euo pipefail

echo "Updating vulnerability database..."
bundle exec bundler-audit update

echo "Running security audit..."
bundle exec bundler-audit check

echo "Security audit passed!"