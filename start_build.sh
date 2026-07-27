#!/bin/bash
cd /home/zqz/OpenHarmony/ohos-rust
CLEAN_BUILD=false DRY_RUN=false sh x86_64/build.sh > build_new.log 2>&1
