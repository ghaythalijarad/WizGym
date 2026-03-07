#!/bin/bash

# WizGym Quick Build Script
# Builds all components in the correct order

set -e

echo "🔨 Building WizGym Components..."
echo ""

# Build Contracts first (API depends on it)
echo "📦 Building Contracts..."
cd packages/contracts
npm run build
echo "✓ Contracts built"
echo ""

# Build API
echo "🔌 Building API..."
cd ../../apps/api
npm run build
echo "✓ API built"
echo ""

echo "✅ All components built successfully!"
