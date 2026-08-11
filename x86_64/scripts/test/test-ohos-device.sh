#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Layer 3: OHOS设备功能验证
# 通过hdc将Rust工具链推送到OHOS设备并执行功能测试
# 前置条件：
#   1. hdc已安装且设备已连接（hdc list targets非空）
#   2. Layer 1/2已通过
#   3. 设备有足够空间（至少500MB可用）
# ============================================================

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
pass()  { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn()  { echo -e "${YELLOW}[SKIP]${NC} $1"; SKIP=$((SKIP+1)); }

# 设备上的工作目录
DEVICE_PREFIX="/data/local/tmp/ohos-rust-test"
DEVICE_RUST_DIR="${DEVICE_PREFIX}/rust"
DEVICE_RA_DIR="${DEVICE_PREFIX}/rust-analyzer"
DEVICE_RUSTUP_DIR="${DEVICE_PREFIX}/rustup"
DEVICE_WORKSPACE="${DEVICE_PREFIX}/workspace"

# 本地tarball路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOCAL_RUST_TARBALL="${WORKDIR}/rust-1.95.0-aarch64-unknown-linux-ohos.tar.xz"
LOCAL_RA_TARBALL="${WORKDIR}/rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.xz"
LOCAL_RUSTUP_TARBALL="${WORKDIR}/../rustup-ohos/dist/rustup-1.30.0-aarch64.tar.xz"
if [[ ! -f "$LOCAL_RUSTUP_TARBALL" ]]; then
    LOCAL_RUSTUP_TARBALL="/tmp/rustup-ohos/dist/rustup-1.30.0-aarch64.tar.xz"
fi

# hdc命令封装
hdc_cmd() {
    hdc shell "$@" 2>&1
}

hdc_file_exists() {
    local path="$1"
    hdc shell "test -e '$path' && echo YES || echo NO" 2>&1 | tr -d '\r'
}

hdc_push() {
    local local="$1"
    local remote="$2"
    hdc file send "$local" "$remote" 2>&1
}

hdc_exec() {
    hdc shell "$@" 2>&1 | tr -d '\r'
}

echo "=========================================="
echo "  Layer 3: OHOS设备功能验证"
echo "=========================================="
echo ""

# ── 前置检查 ──
info "=== 前置检查 ==="

if ! command -v hdc >/dev/null 2>&1; then
    fail "hdc命令不可用，请安装OHOS SDK工具链"
    exit 1
fi
pass "hdc可用: $(hdc --version 2>/dev/null || echo 'version unknown')"

# 检查设备连接
DEVICES=$(hdc list targets 2>/dev/null | tr -d '\r')
if [[ -z "$DEVICES" ]] || echo "$DEVICES" | grep -q 'Empty'; then
    fail "无OHOS设备连接，请通过USB连接设备并开启调试模式"
    echo -e "${RED}运行 'hdc list targets' 查看设备列表${NC}"
    exit 1
fi
pass "设备已连接: $DEVICES"

# 检查tarball文件
for f in "$LOCAL_RUST_TARBALL" "$LOCAL_RA_TARBALL" "$LOCAL_RUSTUP_TARBALL"; do
    if [[ ! -f "$f" ]]; then
        fail "tarball不存在: $f"
        exit 1
    fi
done
pass "所有tarball文件就绪"
echo ""

# ── 3.1 清理设备旧文件 ──
info "=== 3.1 清理设备旧文件 ==="
hdc_exec "rm -rf ${DEVICE_PREFIX}" 2>/dev/null || true
hdc_exec "mkdir -p ${DEVICE_RUST_DIR} ${DEVICE_RA_DIR} ${DEVICE_RUSTUP_DIR} ${DEVICE_WORKSPACE}"
pass "设备目录已创建: ${DEVICE_PREFIX}"
echo ""

# ── 3.2 推送并安装Rust工具链 ──
info "=== 3.2 推送 Rust 工具链 tarball ==="
info "推送 rust-1.95.0 tarball ($(du -h "$LOCAL_RUST_TARBALL" | cut -f1))..."
hdc_push "$LOCAL_RUST_TARBALL" "${DEVICE_PREFIX}/rust.tar.xz"
pass "rust tarball已推送"

info "解压到 ${DEVICE_RUST_DIR}..."
hdc_exec "cd ${DEVICE_PREFIX} && tar -xJf rust.tar.xz -C ${DEVICE_RUST_DIR} --strip-components=1"
pass "rust工具链已解压"

# 验证关键文件存在
if [[ "$(hdc_file_exists "${DEVICE_RUST_DIR}/bin/rustc")" == "YES" ]]; then
    pass "rustc存在"
else
    fail "rustc不存在于 ${DEVICE_RUST_DIR}/bin/rustc"
fi

if [[ "$(hdc_file_exists "${DEVICE_RUST_DIR}/bin/cargo")" == "YES" ]]; then
    pass "cargo存在"
else
    fail "cargo不存在于 ${DEVICE_RUST_DIR}/bin/cargo"
fi

# 检查librustc_driver
DRIVER_CHECK=$(hdc_exec "ls ${DEVICE_RUST_DIR}/lib/librustc_driver-*.so 2>/dev/null" || true)
if [[ -n "$DRIVER_CHECK" ]] && ! echo "$DRIVER_CHECK" | grep -q 'No such'; then
    DRIVER_NAME=$(basename "$DRIVER_CHECK" | tr -d '\r')
    pass "librustc_driver存在: $DRIVER_NAME"
else
    fail "librustc_driver不存在"
fi
echo ""

# ── 3.3 推送并安装rust-analyzer ──
info "=== 3.3 推送 rust-analyzer tarball ==="
info "推送 rust-analyzer-1.95.0 tarball ($(du -h "$LOCAL_RA_TARBALL" | cut -f1))..."
hdc_push "$LOCAL_RA_TARBALL" "${DEVICE_PREFIX}/rust-analyzer.tar.xz"
pass "rust-analyzer tarball已推送"

info "解压到 ${DEVICE_RA_DIR}..."
hdc_exec "cd ${DEVICE_PREFIX} && tar -xJf rust-analyzer.tar.xz -C ${DEVICE_RA_DIR} --strip-components=1"
pass "rust-analyzer已解压"

if [[ "$(hdc_file_exists "${DEVICE_RA_DIR}/bin/rust-analyzer")" == "YES" ]]; then
    pass "rust-analyzer存在"
else
    fail "rust-analyzer不存在"
fi

# 检查rust-analyzer的librustc_driver
RA_DRIVER_CHECK=$(hdc_exec "ls ${DEVICE_RA_DIR}/lib/librustc_driver-*.so 2>/dev/null" || true)
if [[ -n "$RA_DRIVER_CHECK" ]] && ! echo "$RA_DRIVER_CHECK" | grep -q 'No such'; then
    pass "rust-analyzer librustc_driver存在"
else
    fail "rust-analyzer librustc_driver不存在"
fi
echo ""

# ── 3.4 推送rustup ──
info "=== 3.4 推送 rustup ==="
hdc_push "$LOCAL_RUSTUP_TARBALL" "${DEVICE_PREFIX}/rustup.tar.xz"
hdc_exec "cd ${DEVICE_PREFIX} && tar -xJf rustup.tar.xz -C ${DEVICE_RUSTUP_DIR}"
RUSTUP_INIT_CHECK=$(hdc_exec "ls ${DEVICE_RUSTUP_DIR}/rustup-init 2>/dev/null || ls ${DEVICE_RUSTUP_DIR}/rustup 2>/dev/null" || true)
if [[ -n "$RUSTUP_INIT_CHECK" ]] && ! echo "$RUSTUP_INIT_CHECK" | grep -q 'No such'; then
    pass "rustup-init存在"
    hdc_exec "chmod +x ${DEVICE_RUSTUP_DIR}/rustup-init 2>/dev/null || true"
else
    fail "rustup-init不存在"
fi
echo ""

# ── 3.5 rustc版本检查 ──
info "=== 3.5 rustc 版本检查 ==="
RUSTC_VER=$(hdc_exec "export LD_LIBRARY_PATH=${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH && ${DEVICE_RUST_DIR}/bin/rustc --version" 2>&1 || true)
if echo "$RUSTC_VER" | grep -q 'rustc'; then
    pass "rustc可执行: $RUSTC_VER"
else
    fail "rustc执行失败: $RUSTC_VER"
fi
echo ""

# ── 3.6 .codesign内核验证（核心测试）──
info "=== 3.6 .codesign 内核验证（execve成功=签名通过）==="

# 如果rustc能成功执行，说明.codesign被内核接受
if echo "$RUSTC_VER" | grep -q 'rustc'; then
    pass ".codesign内核验证通过（rustc成功execve）"
else
    fail ".codesign内核验证失败（rustc被内核拒绝）"
fi

# 同样验证cargo
CARGO_VER=$(hdc_exec "export LD_LIBRARY_PATH=${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH && ${DEVICE_RUST_DIR}/bin/cargo --version" 2>&1 || true)
if echo "$CARGO_VER" | grep -q 'cargo'; then
    pass ".codesign内核验证通过（cargo成功execve）"
else
    fail ".codesign内核验证失败（cargo被内核拒绝）"
fi
echo ""

# ── 3.7 rustc编译Hello World ──
info "=== 3.7 rustc 编译 Hello World ==="

# 在设备上创建hello.rs
hdc_exec "cat > ${DEVICE_WORKSPACE}/hello.rs << 'RUSTEOF'
fn main() {
    println!(\"Hello OHOS from Rust!\");
}
RUSTEOF"

if [[ "$(hdc_file_exists "${DEVICE_WORKSPACE}/hello.rs")" == "YES" ]]; then
    pass "hello.rs已创建"
else
    fail "hello.rs创建失败"
fi

# 编译
info "编译 hello.rs..."
COMPILE_OUTPUT=$(hdc_exec "export LD_LIBRARY_PATH=${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH && cd ${DEVICE_WORKSPACE} && ${DEVICE_RUST_DIR}/bin/rustc hello.rs -o hello 2>&1" || true)
if [[ "$(hdc_file_exists "${DEVICE_WORKSPACE}/hello")" == "YES" ]]; then
    pass "编译成功，hello二进制已生成"

    # 运行
    RUN_OUTPUT=$(hdc_exec "${DEVICE_WORKSPACE}/hello" 2>&1 || true)
    if echo "$RUN_OUTPUT" | grep -q 'Hello OHOS from Rust'; then
        pass "Hello World运行成功: $RUN_OUTPUT"
        pass ".codesign验证通过（hello二进制成功execve）"
    else
        fail "Hello World运行失败: $RUN_OUTPUT"
    fi
else
    fail "编译失败: $COMPILE_OUTPUT"
fi
echo ""

# ── 3.8 cargo new + build + run ──
info "=== 3.8 cargo new + build + run ==="

CARGO_ENV="export LD_LIBRARY_PATH=${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH && export RUSTUP_HOME=${DEVICE_PREFIX}/.rustup && export CARGO_HOME=${DEVICE_PREFIX}/.cargo"

# cargo new
info "cargo new hello_cargo..."
NEW_OUTPUT=$(hdc_exec "$CARGO_ENV && cd ${DEVICE_WORKSPACE} && ${DEVICE_RUST_DIR}/bin/cargo new hello_cargo --bin 2>&1" || true)
if [[ "$(hdc_file_exists "${DEVICE_WORKSPACE}/hello_cargo/Cargo.toml")" == "YES" ]]; then
    pass "cargo new成功"

    # 修改main.rs
    hdc_exec "cat > ${DEVICE_WORKSPACE}/hello_cargo/src/main.rs << 'RUSTEOF'
fn main() {
    println!(\"Hello OHOS from Cargo!\");
}
RUSTEOF"

    # cargo build
    info "cargo build..."
    BUILD_OUTPUT=$(hdc_exec "$CARGO_ENV && cd ${DEVICE_WORKSPACE}/hello_cargo && ${DEVICE_RUST_DIR}/bin/cargo build 2>&1" || true)
    if [[ "$(hdc_file_exists "${DEVICE_WORKSPACE}/hello_cargo/target/debug/hello_cargo")" == "YES" ]]; then
        pass "cargo build成功"

        # cargo run
        info "cargo run..."
        RUN_OUTPUT=$(hdc_exec "$CARGO_ENV && cd ${DEVICE_WORKSPACE}/hello_cargo && ${DEVICE_RUST_DIR}/bin/cargo run 2>&1" || true)
        if echo "$RUN_OUTPUT" | grep -q 'Hello OHOS from Cargo'; then
            pass "cargo run成功: $RUN_OUTPUT"
        else
            fail "cargo run失败: $RUN_OUTPUT"
        fi
    else
        fail "cargo build失败: $BUILD_OUTPUT"
    fi
else
    fail "cargo new失败: $NEW_OUTPUT"
fi
echo ""

# ── 3.9 rust-analyzer LSP协议测试 ──
info "=== 3.9 rust-analyzer LSP 协议测试 ==="

# 构造LSP initialize请求
LSP_REQUEST="Content-Length: 166\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file:/dev/null\",\"capabilities\":{}}}"
LSP_SHUTDOWN="Content-Length: 58\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"shutdown\",\"params\":null}"
LSP_EXIT="Content-Length: 39\r\n\r\n{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":{}}"

# 在设备上运行rust-analyzer
RA_ENV="export LD_LIBRARY_PATH=${DEVICE_RA_DIR}/lib:${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH"

info "启动rust-analyzer并发送LSP请求..."
RA_OUTPUT=$(hdc_exec "echo -ne '${LSP_REQUEST}${LSP_SHUTDOWN}${LSP_EXIT}' | $RA_ENV && ${DEVICE_RA_DIR}/bin/rust-analyzer 2>&1" 2>&1 || true)

if echo "$RA_OUTPUT" | grep -q 'Content-Length'; then
    pass "rust-analyzer LSP响应包含Content-Length"
    pass "rust-analyzer .codesign验证通过（成功execve）"
else
    # rust-analyzer可能因为stdin管道问题失败，尝试另一种方式
    info "第一次尝试失败，使用文件管道方式重试..."
    hdc_exec "cat > ${DEVICE_WORKSPACE}/lsp_input.bin << 'EOF'
$(printf '%b' "${LSP_REQUEST}${LSP_SHUTDOWN}${LSP_EXIT}")
EOF"

    RA_OUTPUT2=$(hdc_exec "$RA_ENV && ${DEVICE_RA_DIR}/bin/rust-analyzer < ${DEVICE_WORKSPACE}/lsp_input.bin 2>&1" 2>&1 || true)
    if echo "$RA_OUTPUT2" | grep -q 'Content-Length'; then
        pass "rust-analyzer LSP响应包含Content-Length"
        pass "rust-analyzer .codesign验证通过"
    else
        fail "rust-analyzer LSP测试失败: $RA_OUTPUT2"
    fi
fi
echo ""

# ── 3.10 rustup功能测试 ──
info "=== 3.10 rustup 功能测试 ==="

RUSTUP_BIN="${DEVICE_RUSTUP_DIR}/rustup-init"
if [[ "$(hdc_file_exists "$RUSTUP_BIN")" == "YES" ]]; then
    RUSTUP_VER=$(hdc_exec "$RUSTUP_BIN --version 2>&1" || true)
    if echo "$RUSTUP_VER" | grep -q 'rustup'; then
        pass "rustup可执行: $RUSTUP_VER"
        pass "rustup .codesign验证通过"
    else
        fail "rustup执行失败: $RUSTUP_VER"
    fi

    # 测试toolchain link
    info "rustup toolchain link测试..."
    LINK_OUTPUT=$(hdc_exec "export RUSTUP_HOME=${DEVICE_PREFIX}/.rustup && export CARGO_HOME=${DEVICE_PREFIX}/.cargo && $RUSTUP_BIN toolchain link ohos-test ${DEVICE_RUST_DIR} 2>&1" || true)
    if echo "$LINK_OUTPUT" | grep -q 'installed' || echo "$LINK_OUTPUT" | grep -q 'linked'; then
        pass "rustup toolchain link成功"

        # 验证toolchain list
        LIST_OUTPUT=$(hdc_exec "export RUSTUP_HOME=${DEVICE_PREFIX}/.rustup && $RUSTUP_BIN toolchain list 2>&1" || true)
        if echo "$LIST_OUTPUT" | grep -q 'ohos-test'; then
            pass "rustup toolchain list包含ohos-test"
        else
            fail "rustup toolchain list不包含ohos-test: $LIST_OUTPUT"
        fi
    else
        fail "rustup toolchain link失败: $LINK_OUTPUT"
    fi
else
    fail "rustup-init不存在"
fi
echo ""

# ── 3.11 交叉编译验证（使用llvm-tools）──
info "=== 3.11 llvm-tools 验证 ==="
LLVM_OBJDUMP="${DEVICE_RUST_DIR}/lib/rustlib/aarch64-unknown-linux-ohos/bin/llvm-objdump"
if [[ "$(hdc_file_exists "$LLVM_OBJDUMP")" == "YES" ]]; then
    OBJDUMP_OUTPUT=$(hdc_exec "$LLVM_OBJDUMP --version 2>&1" || true)
    if echo "$OBJDUMP_OUTPUT" | grep -q 'LLVM'; then
        pass "llvm-objdump可执行"
        pass "llvm-objdump .codesign验证通过"

        # 用llvm-objdump检查hello二进制
        info "用llvm-objdump检查hello二进制节区..."
        SECTION_OUTPUT=$(hdc_exec "$LLVM_OBJDUMP -h ${DEVICE_WORKSPACE}/hello 2>&1" || true)
        if echo "$SECTION_OUTPUT" | grep -q 'codesign'; then
            pass "hello二进制包含.codesign节区"
        else
            fail "hello二进制不包含.codesign节区"
        fi
        if echo "$SECTION_OUTPUT" | grep -q 'note.ohos'; then
            pass "hello二进制包含.note.ohos.ident节区"
        else
            fail "hello二进制不包含.note.ohos.ident节区"
        fi
    else
        fail "llvm-objdump执行失败"
    fi
else
    warn "llvm-objdump不存在，跳过llvm-tools验证"
fi
echo ""

# ── 3.12 clippy验证 ──
info "=== 3.12 clippy 验证 ==="
CLIPPY="${DEVICE_RUST_DIR}/bin/clippy-driver"
if [[ "$(hdc_file_exists "$CLIPPY")" == "YES" ]]; then
    CLIPPY_ENV="export LD_LIBRARY_PATH=${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH"
    CLIPPY_OUTPUT=$(hdc_exec "$CLIPPY_ENV && cd ${DEVICE_WORKSPACE}/hello_cargo && ${DEVICE_RUST_DIR}/bin/cargo-clippy 2>&1" || true)
    if echo "$CLIPPY_OUTPUT" | grep -q 'Finished' || echo "$CLIPPY_OUTPUT" | grep -q 'warning'; then
        pass "clippy可执行"
    else
        fail "clippy执行失败: $CLIPPY_OUTPUT"
    fi
else
    warn "clippy-driver不存在"
fi
echo ""

# ── 3.13 rustfmt验证 ──
info "=== 3.13 rustfmt 验证 ==="
RUSTFMT="${DEVICE_RUST_DIR}/bin/rustfmt"
if [[ "$(hdc_file_exists "$RUSTFMT")" == "YES" ]]; then
    RUSTFMT_ENV="export LD_LIBRARY_PATH=${DEVICE_RUST_DIR}/lib:\$LD_LIBRARY_PATH"
    FMT_OUTPUT=$(hdc_exec "$RUSTFMT_ENV && ${DEVICE_RUST_DIR}/bin/rustfmt --version 2>&1" || true)
    if echo "$FMT_OUTPUT" | grep -q 'rustfmt'; then
        pass "rustfmt可执行: $FMT_OUTPUT"
    else
        fail "rustfmt执行失败: $FMT_OUTPUT"
    fi
else
    warn "rustfmt不存在"
fi
echo ""

# ── 清理 ──
info "=== 清理设备文件 ==="
hdc_exec "rm -rf ${DEVICE_PREFIX}" 2>/dev/null || true
pass "设备文件已清理"
echo ""

# ── 汇总 ──
echo "=========================================="
echo "  Layer 3 OHOS设备测试结果汇总"
echo "=========================================="
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}SKIP${NC}: $SKIP"
echo "=========================================="

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}存在失败项，请检查设备环境${NC}"
    exit 1
else
    echo -e "${GREEN}全部通过，OHOS Rust工具链功能正常${NC}"
    exit 0
fi
