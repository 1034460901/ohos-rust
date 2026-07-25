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

# Bootstrap 下载镜像（国内构建可设置为 https://mirrors.ustc.edu.cn/rust-static）
export RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER:-https://static.rust-lang.org}

# 如果存在旧的目录和文件，就清理掉
rm -rf *.tar.gz \
    *.tgz \
    deps \
    rustc-* \
    rust-$RUST_VERSION-ohos-arm64

# ========================================
# 下载 Rust 源码
# ========================================
echo "=== 下载 Rust 源码 ==="
curl -fLO https://static.rust-lang.org/dist/rustc-$RUST_VERSION-src.tar.gz
tar -zxf rustc-$RUST_VERSION-src.tar.gz
cd rustc-$RUST_VERSION-src

# ========================================
# 应用 patches
# ========================================
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
        patch -p1 --forward < "$PATCH_FILE"
    fi
done

# ========================================
# 更新 vendored crate checksum
# ========================================
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

# ========================================
# 完全模拟官方 CI 的 configure 步骤
# 参考：src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
# ========================================
echo "=== 配置 Rust 构建 ==="
./configure \
    --enable-profiler \
    --enable-sanitizers \
    --enable-extended \
    --enable-cargo-native-static \
    --disable-docs \
    --set rust.rpath=true \
    \
    --tools=\
cargo,\
clippy,\
rustdoc,\
rustfmt,\
rust-analyzer,\
rust-analyzer-proc-macro-srv,\
src,\
rust-demangler

# === 参数详细说明 ===
# 目标：构建 OHOS 交叉编译工具链（在 x86_64 上编译，产物为 aarch64）
#
# 1. 构建特性控制:
#    --enable-extended:          构建扩展工具链（不仅是编译器，还包括 Cargo、Stdlib 等）。
#    --enable-profiler:          启用性能分析工具支持 (perf)。
#    --enable-sanitizers:        启用内存/线程错误检查器 (ASAN/LSAN 等)。
#    --enable-cargo-native-static: 尝试静态链接 Cargo 的原生依赖（如 OpenSSL），减少产物依赖。
#    --disable-docs:             禁用文档生成。交叉编译时 host 工具（如 error_index_generator）
#                               编译为 aarch64 格式，无法在 x86_64 上运行生成文档。
#    --set rust.rpath=true:      设置运行时库搜索路径，确保二进制能正确找到动态库。
#
# 2. 工具组件列表 (--tools) - 对齐标准发行版:
#    cargo:                      包管理器 (必选)。
#    clippy:                     静态代码分析工具。
#    rustdoc:                    文档生成工具 (支持 `cargo doc`)。
#    rustfmt:                    代码格式化工具。
#    rust-analyzer:              IDE 语言服务器核心。
#    rust-analyzer-proc-macro-srv: 宏处理服务进程 (RA 必须组件)。
#    src:                        标准库源码 (支持 `cargo build-std` 交叉编译)。
#    rust-demangler:             符号还原工具，用于解析 Panic/Backtrace 中的混淆符号 (如 `_RINv...`)。
#
# 3. 代码签名:
#    通过 patch 0001-rustc-ohos-auto-sign-fix.patch 在 OHOS target spec 中添加
#    -Wl,--code-sign 预链接参数，编译时由 lld 链接器自动完成签名。
#    无需在构建后使用 binary-sign-tool 进行签名。

# ========================================
# 完全模拟官方 CI 的构建步骤
# 参考：src/ci/docker/host-x86_64/dist-ohos-aarch64/Dockerfile
# ========================================

if [ "$DRY_RUN" = "true" ]; then
    echo ">>> [DRY RUN MODE] 跳过编译，生成模拟产物"
    
    # DRY RUN 逻辑：生成模拟文件
    cd $WORKDIR
    
    # 关键修复：必须显式创建 build/dist 目录，因为 x.py dist 被跳过了
    BUILD_DIST="$WORKDIR/rustc-$RUST_VERSION-src/build/dist"
    MOCK_DIR="$BUILD_DIST/mock-install"
    TARGET_NAME="rust-$RUST_VERSION-aarch64-unknown-linux-ohos"
    TARGET_DIR="$BUILD_DIST/$TARGET_NAME"

    # 清理旧目录
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
    # 重命名目录
    mv "$MOCK_DIR" "$TARGET_DIR"

    # 生成模拟 install.sh
    cat > "$TARGET_DIR/install.sh" << 'EOF'
#!/bin/sh
# 模拟安装脚本，将 bin/lib 目录拷贝到 --prefix 指定的位置
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
EOF
    chmod +x "$TARGET_DIR/install.sh"

    # 打包
    cd "$BUILD_DIST"
    tar -czf "$TARGET_NAME.tar.gz" "$TARGET_NAME"
    ls -lh "$TARGET_NAME.tar.gz"
    cd $WORKDIR
    
    echo "模拟产物已生成"
else
    echo ">>> [FULL BUILD MODE] 执行真实编译"

    # 步骤 1: 跳过 make prepare（OHOS 不是官方支持的平台）
    # make prepare  # OHOS 没有官方预构建工具链，跳过此步骤

    # 步骤 2: 启动 sccache
    echo "=== 启动 sccache 服务器 ==="
    SCCACHE_IDLE_TIMEOUT=10800 sccache --start-server || true

    # 步骤 3: 运行构建脚本
    echo "=== 运行官方构建脚本 ==="
    echo "=== SCRIPT: python3 ../x.py dist --host=$TARGETS --target $TARGETS ==="
    python3 x.py dist --host=$TARGETS --target $TARGETS -j$(nproc)

    # 步骤 4: 显示 sccache 统计信息
    echo "=== 显示 sccache 统计信息 ==="
    sccache --show-adv-stats || true
fi

cd $WORKDIR

# ========================================
# 提取主要的 Rust 分发包
# ========================================
echo "=== 提取 Rust 分发包 ==="
echo "=== 检查构建产物 ==="
ls -la rustc-$RUST_VERSION-src/build/dist/ || echo "dist 目录不存在"
echo "=== 查找 tar.gz 文件 ==="
find rustc-$RUST_VERSION-src/build/dist/ -name "*.tar.gz" || echo "没有找到 tar.gz 文件"

# 调用 install.sh 安装到临时目录
echo "RUST_INSTALL_DIR=/tmp/rust-install"
export RUST_INSTALL_DIR="/tmp/rust-install"
rm -rf "$RUST_INSTALL_DIR"
mkdir -p "$RUST_INSTALL_DIR"

echo "===RUST_INSTALL_DIR 安装 rustc ==="
cd rustc-$RUST_VERSION-src/build/dist/
tar -zxf rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz
cd rust-$RUST_VERSION-aarch64-unknown-linux-ohos

# 直接安装到指定路径（扁平结构）
sh install.sh --prefix="$RUST_INSTALL_DIR" --verbose

echo "=== 产物位置: $RUST_INSTALL_DIR ==="
ls -la "$RUST_INSTALL_DIR/" || echo "目录不存在"

# 履行开源义务
echo "=== 生成 license 文件 ==="
cat <<EOF > "$RUST_INSTALL_DIR/licenses.txt"
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

rust
==========
$(cat rustc-$RUST_VERSION-src/LICENSE-MIT)
$(cat rustc-$RUST_VERSION-src/LICENSE-APACHE)

ohos-openssl
==========
==license==
$(cat /opt/ohos-openssl/LICENSE 2>/dev/null || echo "License file not found")
EOF

# 打包最终产物
echo "=== 打包最终产物 ==="
FINAL_DIR="$WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos"
rm -rf "$FINAL_DIR"

# 直接复制安装目录
cp -r "$RUST_INSTALL_DIR" "$FINAL_DIR"

tar -zcf rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz rust-$RUST_VERSION-aarch64-unknown-linux-ohos

# ========================================
# 处理 rust-analyzer 独立包
# ========================================
echo "=== 处理 rust-analyzer 独立包 ==="
RA_PACKAGE="rust-analyzer-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
if [ -f "rustc-$RUST_VERSION-src/build/dist/$RA_PACKAGE" ]; then
    RA_INSTALL_DIR="/tmp/rust-analyzer-install"
    rm -rf "$RA_INSTALL_DIR"
    mkdir -p "$RA_INSTALL_DIR"

    cd rustc-$RUST_VERSION-src/build/dist/
    tar -zxf "$RA_PACKAGE"
    # 进入解压后的目录
    if [ -d "rust-analyzer-$RUST_VERSION-aarch64-unknown-linux-ohos" ]; then
        cd rust-analyzer-$RUST_VERSION-aarch64-unknown-linux-ohos
        
        # 安装（提取）到临时目录
        if [ -f "install.sh" ]; then
            sh install.sh --prefix="$RA_INSTALL_DIR" --verbose
        else
            # 如果没有 install.sh，手动复制
            mkdir -p "$RA_INSTALL_DIR/bin"
            cp -r bin/* "$RA_INSTALL_DIR/bin/" 2>/dev/null || true
        fi
        
        # 打包
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
echo "  RUSTUP_DIST_SERVER: $RUSTUP_DIST_SERVER"
echo ""
echo "产物位置: $WORKDIR/rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz"
ls -lh rust-$RUST_VERSION-aarch64-unknown-linux-ohos.tar.gz
