#!/bin/sh
exec /opt/ohos-sdk/native/llvm/bin/clang \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/native/sysroot \
  -D__MUSL__ \
  -L/opt/ohos-sdk/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos \
  "$@" \
  -lclang_rt.builtins
