#!/usr/bin/env bash
set -e

# Jump to repository root
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/.."

OS="$(uname)"
if [ "$OS" = "Darwin" ]; then
  LOCK_FILE="ci/belowc_identity_macos.lock"
else
  LOCK_FILE="ci/belowc_identity_linux.lock"
fi

echo "X-04: Cleaning and Rebuilding for Reproducible Identity Check..."
cargo clean -p belowc_bin
if [ "$OS" = "Darwin" ]; then
  cargo build --release -p belowc_bin
else
  RUSTFLAGS="-C link-arg=-nostartfiles" cargo build --release -p belowc_bin
fi

EXE="target/release/belowc_bin"
if [ ! -f "$EXE" ]; then
  echo "Error: $EXE not built."
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  HASH="$(sha256sum "$EXE" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  HASH="$(shasum -a 256 "$EXE" | awk '{print $1}')"
else
  echo "Error: No sha256 utility found."
  exit 1
fi

echo "Built Hash: $HASH"

if [ ! -f "$LOCK_FILE" ]; then
  echo "Lock file $LOCK_FILE not found. Creating it..."
  echo "$HASH" > "$LOCK_FILE"
  echo "You must commit $LOCK_FILE."
  exit 1
fi

LOCKED_HASH="$(cat "$LOCK_FILE" | tr -d ' \n\r')"
if [ "$HASH" = "$LOCKED_HASH" ]; then
  echo "X-04 Repro Build MATCH! ($HASH)"
  exit 0
else
  echo "X-04 Repro Build MISMATCH!"
  echo "Expected: $LOCKED_HASH"
  echo "Got     : $HASH"
  exit 1
fi
