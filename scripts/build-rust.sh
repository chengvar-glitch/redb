#!/usr/bin/env bash
# build-rust.sh – Build Rust static library & generate uniffi Swift bindings.
# Usage: ./scripts/build-rust.sh [release|debug]
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_DIR="$PROJECT_ROOT/rust-core"
SWIFT_OUT="$PROJECT_ROOT/swift-ui/RedB/Generated"

PROFILE="${1:-release}"

echo "==> Building redb-core ($PROFILE) ..."
cd "$PROJECT_ROOT"
cargo build --profile "$PROFILE" -p redb-core --features all-dbs

# Locate the built library
case "$PROFILE" in
    release) LIB_DIR="release" ;;
    *)       LIB_DIR="debug" ;;
esac
LIB_PATH="$PROJECT_ROOT/target/$LIB_DIR/libredb_core.a"

echo "==> Generating Swift bindings ..."
mkdir -p "$SWIFT_OUT"

cargo run --release -p gen-bindings -- \
    "$LIB_PATH" \
    "$SWIFT_OUT"

echo "==> Done! Bindings written to $SWIFT_OUT"
echo "    Add $SWIFT_OUT to your Xcode project's 'Build Settings > Import Paths'."
