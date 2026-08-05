#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RUST_VERSION=${RUST_VERSION:-1.95.0}
STAGE0_DATE=${STAGE0_DATE:-2026-03-05}
CACHE_DIR="$SCRIPT_DIR/rustc-$RUST_VERSION-src/build/cache/$STAGE0_DATE"
STAGE0="$SCRIPT_DIR/rustc-$RUST_VERSION-src/src/stage0"

cd "$CACHE_DIR" || exit 1

echo "=== Files ==="
ls -lh *.tar.xz

echo ""
echo "=== Hash Verification ==="
grep 'tar.xz=' "$STAGE0" | grep 'x86_64-unknown-linux-gnu' | while IFS='=' read -r path expected; do
    file=$(basename "$path")
    if [ -f "$file" ]; then
        actual=$(sha256sum "$file" | awk '{print $1}')
        if [ "$actual" = "$expected" ]; then
            echo "OK    $file"
        else
            echo "FAIL  $file (got ${actual:0:16}... want ${expected:0:16}...)"
        fi
    else
        echo "MISS  $file"
    fi
done
