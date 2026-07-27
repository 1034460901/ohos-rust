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

# ========================================
# 构建选项（可通过环境变量覆盖）
# ========================================
# DRY_RUN: 跳过编译，生成模拟产物测试流程
DRY_RUN=${DRY_RUN:-false}

# CLEAN_BUILD: 完全清理后重新构建（Docker/CI 场景使用）
# 默认 false，保留源码和编译缓存，支持增量编译
CLEAN_BUILD=${CLEAN_BUILD:-false}

# Bootstrap 下载镜像（USE_MIRROR=true 时使用 USTC 镜像，否则使用官方源）
if [ "$USE_MIRROR" = "true" ]; then
    export RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER:-https://mirrors.ustc.edu.cn/rust-static}
else
    export RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER:-https://static.rust-lang.org}
fi

# ========================================
# 本地环境检测与设置
# ========================================
# Docker 构建时环境已由 Dockerfile 设置好，本地构建时自动检测并补全
SDK_DIR=${SDK_DIR:-/opt/ohos-sdk}
OPENSSL_DIR=${OPENSSL_DIR:-/opt/ohos-openssl/prelude/arm64-v8a}
CLANG_WRAPPER_DIR=/usr/local/bin

if [ ! -d "$SDK_DIR/native" ]; then
    if [ -f "$WORKDIR/x86_64/scripts/ohos-sdk.sh" ]; then
        echo "=== 设置 OHOS SDK ==="
        sh "$WORKDIR/x86_64/scripts/ohos-sdk.sh"
    else
        echo "错误: OHOS SDK 未安装 ($SDK_DIR/native 不存在)"
        echo "请先运行 x86_64/scripts/ohos-sdk.sh 或通过 Docker 构建"
        exit 1
    fi
fi

if [ ! -f "$OPENSSL_DIR/lib/libssl.a" ]; then
    if [ -f "$WORKDIR/x86_64/scripts/ohos-openssl.sh" ]; then
        echo "=== 构建 OHOS OpenSSL ==="
        # 先确保 clang wrapper 存在
        if [ ! -f "$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang.sh" ]; then
            cp "$WORKDIR/x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh" "$CLANG_WRAPPER_DIR/"
            cp "$WORKDIR/x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh" "$CLANG_WRAPPER_DIR/"
            chmod +x "$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang.sh" "$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang++.sh"
        fi
        sh "$WORKDIR/x86_64/scripts/ohos-openssl.sh"
    else
        echo "错误: OHOS OpenSSL 未构建 ($OPENSSL_DIR/lib/libssl.a 不存在)"
        echo "请先运行 x86_64/scripts/ohos-openssl.sh 或通过 Docker 构建"
        exit 1
    fi
fi

# 确保 clang wrapper 存在
if [ ! -f "$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang.sh" ]; then
    cp "$WORKDIR/x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh" "$CLANG_WRAPPER_DIR/"
    cp "$WORKDIR/x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh" "$CLANG_WRAPPER_DIR/"
    chmod +x "$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang.sh" "$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang++.sh"
fi

# 设置交叉编译环境变量
export TARGETS=${TARGETS:-aarch64-unknown-linux-ohos}
export CC_aarch64_unknown_linux_ohos="$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang.sh"
export CXX_aarch64_unknown_linux_ohos="$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang++.sh"
export AR_aarch64_unknown_linux_ohos="$SDK_DIR/native/llvm/bin/llvm-ar"
export AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_DIR="$OPENSSL_DIR"
export AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_NO_VENDOR=1
export AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_STATIC=1
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$CLANG_WRAPPER_DIR/aarch64-unknown-linux-ohos-clang.sh"

# ========================================
# 缓存配置（sccache + ccache）
# ========================================
# sccache: C/C++ 编译缓存（通过 --enable-sccache 启用，bootstrap 自动设置 build.ccache=sccache）
# 注意: 不设置 RUSTC_WRAPPER=sccache，因为 sccache 不支持自定义构建的 stage2 rustc
# --enable-sccache 已在 bootstrap.toml 中设置 build.ccache=sccache 用于 C/C++ 编译缓存
export SCCACHE_DIR=${SCCACHE_DIR:-$WORKDIR/.sccache}
export SCCACHE_IDLE_TIMEOUT=${SCCACHE_IDLE_TIMEOUT:-10800}
mkdir -p "$SCCACHE_DIR"

# ccache: C/C++ 编译缓存（LLVM 等原生代码编译）
export CCACHE_DIR=${CCACHE_DIR:-$WORKDIR/.ccache}
mkdir -p "$CCACHE_DIR"
ccache --set-config=max_size=5G 2>/dev/null || true
ccache --set-config=compression=true 2>/dev/null || true

# 网络重试配置（加速 cargo vendor 等网络操作）
export CARGO_NET_RETRY=${CARGO_NET_RETRY:-10}
export CARGO_NET_TIMEOUT=${CARGO_NET_TIMEOUT:-120}

# ========================================
# 目录定义
# ========================================
SRC_DIR="$WORKDIR/rustc-$RUST_VERSION-src"
PATCH_DIR="$WORKDIR/patches/$RUST_VERSION"
PATCH_MARKER="$SRC_DIR/.patches-applied"

# ========================================
# 清理策略
# ========================================
# 始终清理输出产物
rm -f "$WORKDIR"/rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz
rm -rf "$WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos"

# CLEAN_BUILD=true 时完全清理源码和编译缓存
if [ "$CLEAN_BUILD" = "true" ]; then
    echo "=== 完全清理 (CLEAN_BUILD=true) ==="
    rm -rf "$SRC_DIR"
    rm -f "$WORKDIR"/rustc-$RUST_VERSION-src.tar.gz
fi

# ========================================
# 下载 Rust 源码（已存在则跳过）
# ========================================
if [ ! -d "$SRC_DIR" ]; then
    echo "=== 下载 Rust 源码 ==="
    if [ ! -f "$WORKDIR/rustc-$RUST_VERSION-src.tar.gz" ]; then
        OFFICIAL_URL="https://static.rust-lang.org/dist/rustc-$RUST_VERSION-src.tar.gz"
        MIRROR_URL="https://mirrors.ustc.edu.cn/rust-static/dist/rustc-$RUST_VERSION-src.tar.gz"
        if [ "$USE_MIRROR" = "true" ]; then
            RUST_SRC_URLS=("$MIRROR_URL" "$OFFICIAL_URL")
        else
            RUST_SRC_URLS=("$OFFICIAL_URL" "$MIRROR_URL")
        fi
        for url in "${RUST_SRC_URLS[@]}"; do
            echo "  尝试下载: $url"
            if curl -fLO "$url"; then
                break
            fi
        done
        if [ ! -f "$WORKDIR/rustc-$RUST_VERSION-src.tar.gz" ]; then
            echo "错误: 所有下载源均失败" >&2
            exit 1
        fi
    fi
    tar -zxf "rustc-$RUST_VERSION-src.tar.gz" -C "$WORKDIR"
else
    echo "=== 源码已存在，跳过下载: $SRC_DIR ==="
fi

cd "$SRC_DIR"

# ========================================
# 应用 patches（已应用则跳过）
# ========================================
if [ ! -d "$PATCH_DIR" ]; then
    echo "错误: 未找到版本 $RUST_VERSION 的 patches 目录"
    echo "请创建目录: patches/$RUST_VERSION/"
    echo "当前支持的版本:"
    ls -d "$WORKDIR"/patches/*/ 2>/dev/null || echo "  (无)"
    exit 1
fi

if [ ! -f "$PATCH_MARKER" ]; then
    echo "=== 应用 patches ==="
    echo "Patches 目录: $PATCH_DIR"
    ls -la "$PATCH_DIR/"

    for PATCH_FILE in "$PATCH_DIR"/*.patch; do
        if [ -f "$PATCH_FILE" ]; then
            echo "应用 patch: $(basename "$PATCH_FILE")"
            patch -p1 --forward < "$PATCH_FILE"
        fi
    done

    # 更新 vendored crate checksum
    # patch 修改了 vendor 目录下的源码，需要重置 .cargo-checksum.json
    # 否则 cargo 会因校验和不匹配而报错
    echo "=== 更新 vendored crate checksums ==="
    for crate in vendor/openssl-probe-0.1.5 vendor/openssl-probe-0.1.6; do
        checksum_file="$crate/.cargo-checksum.json"
        if [ -f "$checksum_file" ]; then
            echo "重置 checksum: $checksum_file"
            python3 -c "
import json
with open('$checksum_file') as f:
    d = json.load(f)
d['files'] = {}
with open('$checksum_file', 'w') as f:
    json.dump(d, f)
"
        fi
    done

    touch "$PATCH_MARKER"
    echo "=== Patches 应用完成 ==="
else
    echo "=== Patches 已应用（标记文件存在），跳过 ==="
fi

# ========================================
# 镜像源覆盖（可选，用于国内加速）
# ========================================
if [ "$USE_MIRROR" = "true" ]; then
    echo "=== 使用 USTC 镜像源加速 ==="
    sed -i 's|https://static.rust-lang.org|https://mirrors.ustc.edu.cn/rust-static|g' src/stage0
    sed -i 's|https://ci-artifacts.rust-lang.org/rustc-builds|https://mirrors.ustc.edu.cn/rust-static/rustc-builds|g' src/stage0
fi

# ========================================
# 配置 Rust 构建
# ========================================
# 参考：src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
echo "=== 配置 Rust 构建 ==="
rm -f bootstrap.toml
./configure \
    --enable-profiler \
    --enable-sanitizers \
    --enable-extended \
    --enable-cargo-native-static \
    --set rust.rpath=true \
    --enable-sccache \
    --set dist.vendor=false \
    \
    --tools=\
cargo,\
clippy,\
rustdoc,\
rustfmt,\
rust-analyzer,\
rust-analyzer-proc-macro-srv,\
src,\
rust-demangler,\
llvm-tools,\
miri

# ========================================
# 构建步骤
# ========================================

if [ "$DRY_RUN" = "true" ]; then
    echo ">>> [DRY RUN MODE] 跳过编译，生成模拟产物"
    
    cd $WORKDIR
    
    BUILD_DIST="$SRC_DIR/build/dist"
    MOCK_DIR="$BUILD_DIST/mock-install"
    TARGET_NAME="rust-$RUST_VERSION-aarch64-unknown-linux-ohos"
    TARGET_DIR="$BUILD_DIST/$TARGET_NAME"

    rm -rf "$MOCK_DIR" "$TARGET_DIR"

    echo "创建目录: $MOCK_DIR"
    mkdir -p "$BUILD_DIST"
    mkdir -p "$MOCK_DIR/bin"
    mkdir -p "$MOCK_DIR/lib"
    mkdir -p "$MOCK_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin"

    echo "复制模拟二进制文件..."
    cp /bin/ls "$MOCK_DIR/bin/cargo"
    cp /bin/ls "$MOCK_DIR/bin/rustc"
    cp /bin/ls "$MOCK_DIR/bin/rustfmt"
    cp /bin/ls "$MOCK_DIR/bin/clippy-driver"
    cp /bin/ls "$MOCK_DIR/lib/libtest.so"
    cp /bin/ls "$MOCK_DIR/lib/rustlib/aarch64-unknown-linux-ohos/bin/rust-lld"

    echo "打包模拟产物..."
    mv "$MOCK_DIR" "$TARGET_DIR"

    cat > "$TARGET_DIR/install.sh" << 'MOCK_EOF'
#!/bin/sh
PREFIX=""
for arg in "$@"; do
    case "$arg" in
        --prefix=*) PREFIX="${arg#*=}" ;;
    esac
done
if [ -n "$PREFIX" ]; then
    echo "Mock installing to $PREFIX..."
    mkdir -p "$PREFIX/bin" "$PREFIX/lib"
    cp -r bin/* "$PREFIX/bin/" 2>/dev/null || true
    cp -r lib/* "$PREFIX/lib/" 2>/dev/null || true
    echo "Mock installation complete."
fi
MOCK_EOF
    chmod +x "$TARGET_DIR/install.sh"

    cd "$BUILD_DIST"
    tar -czf "$TARGET_NAME.tar.gz" "$TARGET_NAME"
    ls -lh "$TARGET_NAME.tar.gz"
    cd $WORKDIR
    
    echo "模拟产物已生成"
else
    echo ">>> [FULL BUILD MODE] 执行编译"

    # 启动 sccache（如可用，用于 C/C++ 编译缓存）
    echo "=== 启动 sccache 服务器 ==="
    SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server 2>/dev/null || echo "sccache 不可用，跳过"

    # 运行构建（增量编译：保留 build/ 目录可复用 LLVM 等编译缓存）
    echo "=== 运行构建脚本 ==="
    echo "=== SCRIPT: python3 x.py dist --host=$TARGETS --target $TARGETS ==="
    python3 x.py dist --host=$TARGETS --target $TARGETS -j$(nproc)

    # 显示 sccache 统计信息
    echo "=== sccache 统计 ==="
    sccache --show-adv-stats 2>/dev/null || true
    echo "=== ccache 统计 ==="
    ccache --show-stats 2>/dev/null || true
fi

cd $WORKDIR

# ========================================
# 提取主要的 Rust 分发包
# ========================================
echo "=== 提取 Rust 分发包 ==="
echo "=== 检查构建产物 ==="
ls -la "$SRC_DIR/build/dist/" || echo "dist 目录不存在"
echo "=== 查找 tar.gz 文件 ==="
find "$SRC_DIR/build/dist/" -name "*.tar.gz" || echo "没有找到 tar.gz 文件"

# 安装到临时目录
echo "RUST_INSTALL_DIR=/tmp/rust-install"
export RUST_INSTALL_DIR="/tmp/rust-install"
rm -rf "$RUST_INSTALL_DIR"
mkdir -p "$RUST_INSTALL_DIR"

echo "===RUST_INSTALL_DIR 安装 rustc ==="
cd "$SRC_DIR/build/dist/"
tar -zxf "rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
cd "rust-$RUST_VERSION-aarch64-unknown-linux-ohos"

sh install.sh --prefix="$RUST_INSTALL_DIR" --verbose

# ========================================
# 安装附加组件包
# ========================================
echo "=== 安装附加组件包 ==="
for PKG_TGZ in \
    "rust-src-$RUST_VERSION.tar.gz" \
    "rust-docs-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz" \
    "llvm-tools-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz" \
    "miri-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
do
    PKG_NAME="${PKG_TGZ%.tar.gz}"
    if [ -f "$SRC_DIR/build/dist/$PKG_TGZ" ]; then
        echo "--- 安装: $PKG_TGZ ---"
        rm -rf "/tmp/extra-pkg-install"
        mkdir -p "/tmp/extra-pkg-install"
        cd "$SRC_DIR/build/dist/"
        tar -zxf "$PKG_TGZ"
        cd "$PKG_NAME"
        if [ -f "install.sh" ]; then
            sh install.sh --prefix="$RUST_INSTALL_DIR" --verbose
        else
            cp -r . "$RUST_INSTALL_DIR/" 2>/dev/null || true
        fi
        cd "$SRC_DIR/build/dist/"
        rm -rf "$PKG_NAME"
        echo "--- $PKG_TGZ 安装完成 ---"
    else
        echo "--- 跳过 (未找到): $PKG_TGZ ---"
    fi
done

echo "=== 产物位置: $RUST_INSTALL_DIR ==="
ls -la "$RUST_INSTALL_DIR/" || echo "目录不存在"

# 生成 license 文件
echo "=== 生成 license 文件 ==="
cat <<EOF > "$RUST_INSTALL_DIR/licenses.txt"
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

rust
==========
$(cat "$SRC_DIR/LICENSE-MIT")
$(cat "$SRC_DIR/LICENSE-APACHE")

ohos-openssl
==========
==license==
$(cat /opt/ohos-openssl/LICENSE 2>/dev/null || echo "License file not found")
EOF

# 打包最终产物
echo "=== 打包最终产物 ==="
cd "$WORKDIR"
FINAL_DIR="$WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos"
rm -rf "$FINAL_DIR"
cp -r "$RUST_INSTALL_DIR" "$FINAL_DIR"

tar -zcf "rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz" "rust-$RUST_VERSION-aarch64-unknown-linux-ohos"

# ========================================
# 处理 rust-analyzer 独立包
# ========================================
echo "=== 处理 rust-analyzer 独立包 ==="
RA_PACKAGE="rust-analyzer-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
if [ -f "$SRC_DIR/build/dist/$RA_PACKAGE" ]; then
    RA_INSTALL_DIR="/tmp/rust-analyzer-install"
    rm -rf "$RA_INSTALL_DIR"
    mkdir -p "$RA_INSTALL_DIR"

    cd "$SRC_DIR/build/dist/"
    tar -zxf "$RA_PACKAGE"
    if [ -d "rust-analyzer-$RUST_VERSION-aarch64-unknown-linux-ohos" ]; then
        cd "rust-analyzer-$RUST_VERSION-aarch64-unknown-linux-ohos"
        
        if [ -f "install.sh" ]; then
            sh install.sh --prefix="$RA_INSTALL_DIR" --verbose
        else
            mkdir -p "$RA_INSTALL_DIR/bin"
            cp -r bin/* "$RA_INSTALL_DIR/bin/" 2>/dev/null || true
        fi
        
        cd $WORKDIR
        tar -zcf "$RA_PACKAGE" -C "$RA_INSTALL_DIR" .
        echo "=== rust-analyzer 独立包处理完成: $RA_PACKAGE ==="
    else
        echo "✗ 未找到解压后的 rust-analyzer 目录"
    fi
    cd $WORKDIR
else
    echo "!!! 未找到 $RA_PACKAGE，跳过 !!!"
fi

sync

echo "=== 构建完成 ==="
echo ""
echo "构建选项汇总:"
echo "  DRY_RUN: $DRY_RUN"
echo "  CLEAN_BUILD: $CLEAN_BUILD"
echo "  RUSTUP_DIST_SERVER: $RUSTUP_DIST_SERVER"
echo "  SCCACHE_DIR: $SCCACHE_DIR"
echo "  CCACHE_DIR: $CCACHE_DIR"
echo ""
echo "产物位置: $WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
ls -lh "rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
