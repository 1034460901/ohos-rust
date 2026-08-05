#!/bin/bash
set -ex
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
export CHANNEL=nightly
export USE_MIRROR=false
export BOOTSTRAP_SKIP_TARGET_SANITY=1

echo "=== Starting nightly build at $(date) ==="
echo "CHANNEL=$CHANNEL"

bash x86_64/build.sh
BUILD_EXIT=$?

echo "=== Build finished at $(date) with exit code $BUILD_EXIT ==="
exit $BUILD_EXIT
