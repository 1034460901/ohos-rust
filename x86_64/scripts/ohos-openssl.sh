#!/bin/sh
set -ex

OPENSSL_VERSION=${OPENSSL_VERSION:-3.6.1}
OPENSSL_PREFIX=/opt/ohos-openssl/prelude/arm64-v8a
OPENSSL_SRC=/tmp/openssl-$OPENSSL_VERSION

CC=/usr/local/bin/aarch64-unknown-linux-ohos-clang.sh
AR=/opt/ohos-sdk/native/llvm/bin/llvm-ar

curl -fL -o /tmp/openssl-$OPENSSL_VERSION.tar.gz \
    https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz

tar -zxf /tmp/openssl-$OPENSSL_VERSION.tar.gz -C /tmp
cd "$OPENSSL_SRC"

./Configure no-shared no-tests linux-aarch64 \
    --prefix="$OPENSSL_PREFIX" \
    CC="$CC" \
    AR="$AR" \
    CFLAGS="-fPIC"

make -j$(nproc)
make install_sw

cp LICENSE.txt /opt/ohos-openssl/LICENSE 2>/dev/null || cp LICENSE /opt/ohos-openssl/LICENSE 2>/dev/null || true

cd /
rm -rf "$OPENSSL_SRC" /tmp/openssl-$OPENSSL_VERSION.tar.gz
