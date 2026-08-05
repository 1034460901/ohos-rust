#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"
CLEAN_BUILD=false DRY_RUN=false USE_MIRROR=true sh x86_64/build.sh > build_new.log 2>&1
