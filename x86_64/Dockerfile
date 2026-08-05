FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    make \
    ninja-build \
    file \
    curl \
    ca-certificates \
    python3 \
    git \
    cmake \
    sudo \
    gdb \
    libssl-dev \
    pkg-config \
    xz-utils \
    unzip \
    patch \
    perl \
    ccache \
    && rm -rf /var/lib/apt/lists/*

# Fix git safe directory for CI
RUN git config --global --add safe.directory /workspace

COPY x86_64/scripts/ohos-sdk.sh /scripts/
RUN sh /scripts/ohos-sdk.sh

# clang wrapper scripts must be installed before ohos-openssl.sh
# because ohos-openssl.sh uses them to cross-compile OpenSSL
COPY x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh /usr/local/bin/
COPY x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh /usr/local/bin/

COPY x86_64/scripts/ohos-openssl.sh /scripts/
RUN sh /scripts/ohos-openssl.sh

# env
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR=/opt/ohos-openssl/prelude/arm64-v8a
ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_NO_VENDOR=1

ENV TARGETS=aarch64-unknown-linux-ohos
ENV CHANNEL=nightly

ENV \
    CC_aarch64_unknown_linux_ohos=/usr/local/bin/aarch64-unknown-linux-ohos-clang.sh \
    AR_aarch64_unknown_linux_ohos=/opt/ohos-sdk/native/llvm/bin/llvm-ar \
    CXX_aarch64_unknown_linux_ohos=/usr/local/bin/aarch64-unknown-linux-ohos-clang++.sh

ENV SCRIPT="python3 ../x.py dist --host=$TARGETS --target $TARGETS"

COPY x86_64/scripts/sccache.sh /scripts/
RUN sh /scripts/sccache.sh
