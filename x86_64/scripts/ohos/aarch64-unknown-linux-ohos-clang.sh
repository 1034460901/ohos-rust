#!/bin/sh
CLANG_VER=$(ls /opt/ohos-sdk/native/llvm/lib/clang/ 2>/dev/null | head -1)
exec /opt/ohos-sdk/native/llvm/bin/clang \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/native/sysroot \
  -D__MUSL__ \
  -L/opt/ohos-sdk/native/llvm/lib/clang/${CLANG_VER}/lib/aarch64-linux-ohos \
  "$@" \
  -lclang_rt.builtins
