#!/bin/sh
set -e

WORKDIR=$(pwd)

# ========================================
# 版本配置（可通过环境变量或命令行参数覆盖）
# ========================================
# 优先级: 命令行参数 > 环境变量 > 默认版本
if [ -n "$1" ]; then
    RUST_VERSION="$1"
elif [ -n "$RUST_VERSION" ]; then
    :
else
    RUST_VERSION="1.95.0"
fi

echo "=== 构建 Rust 版本: $RUST_VERSION ==="

# 如果存在旧的目录和文件，就清理掉
# 仅清理工作目录，不清理系统目录，因为默认用户每次使用新的容器进行构建（仓库中的构建指南是所以指导的）
rm -rf *.tar.gz \
    *.tgz \
    deps \
    rustc-* \
    rust-$RUST_VERSION-ohos-arm64

# 下载一些命令命令行工具，并将它们软链接到 bin 目录中
cd /opt
echo "coreutils 9.10
busybox 1.37.0
grep 3.12
gawk 5.3.2
make 4.4.1
tar 1.35
gzip 1.14
perl 5.42.0
python 3.14.3" >/tmp/tools.txt
while read -r name ver; do
    curl -fLO https://github.com/Harmonybrew/ohos-$name/releases/download/$ver/$name-$ver-ohos-arm64.tar.gz
done </tmp/tools.txt
ls | grep tar.gz$ | xargs -n 1 tar -zxf
rm -rf *.tar.gz
ln -sf $(pwd)/*-ohos-arm64/bin/* /bin/

# 准备 ohos-sdk
# ========================================
# 与官方 CI 不同点：
# 官方 CI 使用 OHOS SDK 5.0.0.71-Release
# 这里使用 OHOS SDK 6.1.0.31 (更新的版本)
# ========================================
curl -fL -o ohos-sdk-full_6.1-Release.tar.gz https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.1.0.31/20260311_020435/version-Master_Version-OpenHarmony_6.1.0.31-20260311_020435-ohos-sdk-full_6.1-Release.tar.gz
tar -zxf ohos-sdk-full_6.1-Release.tar.gz
rm -rf ohos-sdk-full_6.1-Release.tar.gz ohos-sdk/windows ohos-sdk/linux
cd ohos-sdk/ohos
busybox unzip -q native-*.zip
busybox unzip -q toolchains-*.zip
rm -rf *.zip
cd $WORKDIR

# 把 llvm 里面的命令封装一份放到 /bin 目录中，只封装必要的工具。
# 为了照顾 clang （clang 软链接到其他目录使用会找不到 sysroot），
# 对所有命令统一用这种封装的方案，而非软链接。
essential_tools="clang
clang++
clang-cpp
ld.lld
lldb
llvm-addr2line
llvm-ar
llvm-cxxfilt
llvm-nm
llvm-objcopy
llvm-objdump
llvm-ranlib
llvm-readelf
llvm-size
llvm-strings
llvm-strip"
for executable in $essential_tools; do
    cat <<EOF > /bin/$executable
#!/bin/sh
exec /opt/ohos-sdk/ohos/native/llvm/bin/$executable "\$@"
EOF
    chmod 0755 /bin/$executable
done

# 把 llvm 软链接成 cc、gcc 等命令
cd /bin
ln -s clang cc
ln -s clang gcc
ln -s clang++ c++
ln -s clang++ g++
ln -s ld.llvm ld
ln -s llvm-addr2line addr2line
ln -s llvm-ar ar
ln -s llvm-cxxfilt c++filt
ln -s llvm-nm nm
ln -s llvm-objcopy objcopy
ln -s llvm-objdump objdump
ln -s llvm-ranlib ranlib
ln -s llvm-readelf readelf
ln -s llvm-size size
ln -s llvm-strip strip

# ========================================
# 与官方 CI 不同点：
# 官方 CI 不编译 OpenSSL，而是使用预编译的 ohos-openssl
# 这里我们编译 OpenSSL 和 zlib 作为依赖
# ========================================
export CFLAGS="-fPIC"
export CPPFLAGS="-I/opt/deps/include"
export LDFLAGS="-L/opt/deps/lib"
export LD_LIBRARY_PATH="/opt/deps/lib"

mkdir $WORKDIR/deps
cd $WORKDIR/deps

# 编 openssl
curl -fLO https://github.com/openssl/openssl/releases/download/openssl-3.3.4/openssl-3.3.4.tar.gz
tar -zxf openssl-3.3.4.tar.gz
cd openssl-3.3.4
sed -i 's|OPENSSLDIR "/certs"|"/etc/ssl/certs"|g' include/internal/common.h
sed -i 's|OPENSSLDIR "/cert.pem"|"/etc/ssl/certs/cacert.pem"|g' include/internal/common.h
./Configure \
    --prefix=/opt/deps \
    --openssldir=/etc/ssl \
    no-legacy \
    no-module \
    no-engine \
    linux-aarch64
make -j$(nproc)
make install_sw
cd ..

# 编 zlib
curl -fLO https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
tar -zxf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure --prefix=/opt/deps
make -j$(nproc)
make install
cd ..

cd $WORKDIR

# 下载 Rust 源码
curl -fLO https://static.rust-lang.org/dist/rustc-$RUST_VERSION-src.tar.gz
tar -zxf rustc-$RUST_VERSION-src.tar.gz
cd rustc-$RUST_VERSION-src

# 应用 patches
echo "=== 应用 patches ==="

PATCH_DIR="$WORKDIR/patches/$RUST_VERSION"

if [ ! -d "$PATCH_DIR" ]; then
    echo "错误: 未找到版本 $RUST_VERSION 的 patches 目录"
    echo "请创建目录: patches/$RUST_VERSION/"
    echo "当前支持的版本:"
    ls -d "$WORKDIR/patches/*/ " 2>/dev/null || echo "  (无)"
    exit 1
fi

echo "Patches 目录: $PATCH_DIR"
ls -la "$PATCH_DIR/"

for PATCH_FILE in "$PATCH_DIR"/*.patch; do
    if [ -f "$PATCH_FILE" ]; then
        echo "应用 patch: $(basename "$PATCH_FILE")"
        patch -p1 < "$PATCH_FILE"
    fi
done

# ========================================
# 设置 stage0 预构建工具链
# 使用官方构建产物作为 stage0，避免重新编译
# ========================================
echo "=== 设置 stage0 预构建工具链 ==="
mkdir -p $WORKDIR/bootstrap-toolchain
tar -xzf $WORKDIR/arm64/stage0/rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz -C $WORKDIR/bootstrap-toolchain

# ========================================
# 与官方 CI 不同点：
# 官方 CI 使用 config.toml 配置
# 这里我们使用 ./configure 命令行参数（完全模拟官方 CI）
# ========================================

# 设置环境变量（模拟官方 Dockerfile）
export TARGETS="aarch64-unknown-linux-ohos"
export CC_aarch64_unknown_linux_ohos="/opt/aarch64-unknown-linux-ohos-clang.sh"
export AR_aarch64_unknown_linux_ohos="/opt/ohos-sdk/ohos/native/llvm/bin/llvm-ar"
export CXX_aarch64_unknown_linux_ohos="/opt/aarch64-unknown-linux-ohos-clang++.sh"

# 设置 Rust 工具链环境变量（使用 stage0）
export RUSTC="$WORKDIR/bootstrap-toolchain/rustc"
export CARGO="$WORKDIR/bootstrap-toolchain/cargo"
export RUSTC_BOOTSTRAP=1

# 创建 OHOS 编译器包装脚本（模拟官方 Dockerfile）
cat <<'EOF' > /opt/aarch64-unknown-linux-ohos-clang.sh
#!/bin/sh
exec /opt/ohos-sdk/ohos/native/llvm/bin/clang \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/ohos/native/sysroot \
  -D__MUSL__ \
  -Wl,--code-sign \
  "$@"
EOF
chmod +x /opt/aarch64-unknown-linux-ohos-clang.sh

cat <<'EOF' > /opt/aarch64-unknown-linux-ohos-clang++.sh
#!/bin/sh
exec /opt/ohos-sdk/ohos/native/llvm/bin/clang++ \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/ohos/native/sysroot \
  -D__MUSL__ \
  -Wl,--code-sign \
  "$@"
EOF
chmod +x /opt/aarch64-unknown-linux-ohos-clang++.sh

# ========================================
# 完完全模拟官方 CI 的 configure 步骤
# 参考：src/ci/run.sh 和 src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
# ========================================

# 在鸿蒙容器中，使用默认构建系统检测
# OHOS 不是官方支持的平台，但 ARM64 本地编译可以使用默认检测
./configure \
    --build=aarch64-unknown-linux-ohos \
    --enable-profiler \
    --disable-docs \
    --tools=cargo,clippy,rustdocs,rustfmt,rust-analyzer,rust-analyzer-proc-macro-srv,analysis,src,wasm-component-ld \
    --enable-extended \
    --enable-sanitizers \
    --set build.print-step-timings \
    --enable-verbose-tests \
    --set build.metrics \
    --enable-verbose-configure \
    --enable-sccache \
    --disable-manage-submodules \
    --enable-locked-deps \
    --enable-cargo-native-static \
    --set rust.codegen-units-std=1 \
    --set dist.compression-profile=balanced \
    --dist-compression-formats=xz \
    --set build.optimized-compiler-builtins \
    --disable-llvm-static-stdcpp \
    --set rust.remap-debuginfo \
    --debuginfo-level-std=1 \
    --set rust.codegen-backends=llvm \
    --set rust.rpath=true \
    --release-channel=stable
    # --set rust.lto=full
    # Rust 链接时间优化（LTO），完整优化耗时长，先不设置

# ========================================
# 完全模拟官方 CI 的构建步骤
# 参考：src/ci/run.sh
# ========================================

# 步骤 1: 跳过 make prepare（OHOS 不是官方支持的平台）
echo "=== 跳过 make prepare（OHOS 没有预构建工具链）==="
# make prepare  # OHOS 没有官方预构建工具链，跳过此步骤

# 步骤 2: 启动 sccache
echo "=== 启动 sccache 服务器 ==="
SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server || true

# 步骤 3: 运行构建脚本（完全模拟官方 Dockerfile 的 SCRIPT）
echo "=== 运行官方构建脚本 ==="
echo "=== SCRIPT: python3 ../x.py dist --host=$TARGETS --target $TARGETS ==="

# ========================================
# 与官方 CI 不同点：
# 官方 CI 的 SCRIPT: python3 ../x.py dist --host=$TARGETS --target $TARGETS
# 这里我们使用相同命令
# ========================================
python3 x.py dist --host=$TARGETS --target $TARGETS -j$(nproc)

# 步骤 4: 显示 sccache 统计信息
echo "=== 显示 sccache 统计信息 ==="
sccache --show-adv-stats || true

cd $WORKDIR

# ========================================
# 提取主要的 Rust 分发包
# ========================================
echo "=== 查找 tar.gz 文件 ==="
find rustc-$RUST_VERSION-src/build/dist/ -name "*.tar.gz" || echo "没有找到 tar.gz 文件"

# 调用 install.sh 安装到临时目录
echo "RUST_INSTALL_DIR=/tmp/rust-install"
export RUST_INSTALL_DIR="/tmp/rust-install"
rm -rf "$RUST_INSTALL_DIR"
mkdir -p "$RUST_INSTALL_DIR"

echo "=== 安装 rustc ==="
cd rustc-$RUST_VERSION-src/build/dist/rust-$RUST_VERSION-aarch64-unknown-linux-ohos
sh install.sh --destdir="$RUST_INSTALL_DIR" --verbose

echo "=== 复制依赖库到安装目录 ==="
cp /opt/deps/lib/*so* "$RUST_INSTALL_DIR/lib/"
cp /opt/deps/lib/*so* /opt/rust-$RUST_VERSION-ohos-arm64/lib

echo "=== .codesign 已通过 -Wl,--code-sign 链接器标志自动生成 ==="

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
echo "=== 生成 license 文件 ==="
cat <<EOF > "$RUST_INSTALL_DIR/licenses.txt"
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

rust
==========
$(cat rustc-$RUST_VERSION-src/LICENSE-MIT)
$(cat rustc-$RUST_VERSION-src/LICENSE-APACHE)

openssl
==========
==license==
$(cat deps/openssl-3.3.4/LICENSE.txt)
==authors==
$(cat deps/openssl-3.3.4/AUTHORS.md)

zlib
==========
$(cat deps/zlib-1.3.1/LICENSE)
EOF

# 打包最终产物
echo "=== 打包最终产物 ==="
cp -r "$RUST_INSTALL_DIR" ./

tar -zcf rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz rust-$RUST_VERSION-ohos-arm64

sync
