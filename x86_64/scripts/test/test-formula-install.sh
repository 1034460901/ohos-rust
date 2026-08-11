#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Layer 2: Homebrew Formula 安装测试
# 在Harmonybrew环境中运行，验证5个formula能正确安装
# 前置条件：5个tarball已上传到gitcode releases
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

echo "=========================================="
echo "  Layer 2: Homebrew Formula 安装测试"
echo "=========================================="
echo ""

# ── 前置检查 ──
info "=== 前置检查 ==="

if ! command -v brew >/dev/null 2>&1; then
    fail "brew命令不可用，请在Harmonybrew环境中运行"
    echo -e "${RED}请先安装Harmonybrew${NC}"
    exit 1
fi
pass "brew命令可用: $(brew --version | head -1)"

if ! command -v ruby >/dev/null 2>&1; then
    fail "ruby命令不可用"
    exit 1
fi
pass "ruby命令可用: $(ruby --version)"
echo ""

# ── 2.1 添加tap ──
info "=== 2.1 添加 homebrew-ohos tap ==="
if brew tap | grep -q 'ohos'; then
    pass "homebrew-ohos tap已存在"
else
    info "添加tap: gitcode.com/zqz979/homebrew-ohos"
    if brew tap ohos https://gitcode.com/zqz979/homebrew-ohos.git 2>&1; then
        pass "homebrew-ohos tap添加成功"
    else
        fail "homebrew-ohos tap添加失败"
        exit 1
    fi
fi
echo ""

# ── 2.2 安装 ca-certificates（rust的依赖）──
info "=== 2.2 安装 ca-certificates ==="
if brew list ca-certificates >/dev/null 2>&1; then
    pass "ca-certificates 已安装"
else
    if brew install ca-certificates 2>&1; then
        pass "ca-certificates 安装成功"
    else
        fail "ca-certificates 安装失败"
    fi
fi
echo ""

# ── 2.3 安装 rust@1.95.0 ──
info "=== 2.3 安装 rust@1.95.0 ==="
if brew list rust@1.95.0 >/dev/null 2>&1; then
    info "rust@1.95.0 已安装，先卸载..."
    brew uninstall rust@1.95.0 2>/dev/null || true
fi

if brew install rust@1.95.0 2>&1; then
    pass "rust@1.95.0 安装成功"

    # 验证版本
    RUSTC_PATH=$(brew --prefix rust@1.95.0)/bin/rustc
    if [[ -x "$RUSTC_PATH" ]]; then
        RUSTC_VER=$("$RUSTC_PATH" --version 2>&1)
        if echo "$RUSTC_VER" | grep -q '1.95.0'; then
            pass "rustc版本正确: $RUSTC_VER"
        else
            fail "rustc版本不匹配: $RUSTC_VER"
        fi
    else
        fail "rustc不可执行: $RUSTC_PATH"
    fi

    # 验证cargo wrapper
    CARGO_PATH=$(brew --prefix rust@1.95.0)/bin/cargo
    if [[ -f "$CARGO_PATH" ]] && head -1 "$CARGO_PATH" | grep -q 'sh'; then
        pass "cargo wrapper存在（shell脚本）"
        CARGO_REAL=$(brew --prefix rust@1.95.0)/bin/cargo.real
        if [[ -f "$CARGO_REAL" ]]; then
            CARGO_VER=$("$CARGO_REAL" --version 2>&1)
            if echo "$CARGO_VER" | grep -q 'cargo'; then
                pass "cargo.real可执行: $CARGO_VER"
            else
                fail "cargo.real执行失败"
            fi
        fi
    else
        fail "cargo wrapper不存在或不是shell脚本"
    fi

    # 验证.codesign（如果readelf可用）
    if command -v readelf >/dev/null 2>&1; then
        if readelf -SW "$RUSTC_PATH" 2>/dev/null | grep -q '\.codesign'; then
            pass "rustc .codesign 节区存在"
        else
            fail "rustc .codesign 节区缺失"
        fi
    else
        warn "readelf不可用，跳过.codesign检查"
    fi
else
    fail "rust@1.95.0 安装失败"
fi
echo ""

# ── 2.4 安装 rust-analyzer@1.95.0 ──
info "=== 2.4 安装 rust-analyzer@1.95.0 ==="
if brew list rust-analyzer@1.95.0 >/dev/null 2>&1; then
    info "rust-analyzer@1.95.0 已安装，先卸载..."
    brew uninstall rust-analyzer@1.95.0 2>/dev/null || true
fi

if brew install rust-analyzer@1.95.0 2>&1; then
    pass "rust-analyzer@1.95.0 安装成功"

    RA_PATH=$(brew --prefix rust-analyzer@1.95.0)/bin/rust-analyzer
    if [[ -x "$RA_PATH" ]]; then
        RA_VER=$("$RA_PATH" --version 2>&1)
        if echo "$RA_VER" | grep -q 'rust-analyzer'; then
            pass "rust-analyzer版本: $RA_VER"
        else
            fail "rust-analyzer版本输出异常: $RA_VER"
        fi
    else
        fail "rust-analyzer不可执行: $RA_PATH"
    fi

    # 验证librustc_driver
    RA_LIB=$(brew --prefix rust-analyzer@1.95.0)/lib
    DRIVER=$(find "$RA_LIB" -name 'librustc_driver-*.so' -type f 2>/dev/null | head -1)
    if [[ -n "$DRIVER" ]]; then
        pass "librustc_driver存在: $(basename "$DRIVER")"
    else
        fail "librustc_driver缺失"
    fi
else
    fail "rust-analyzer@1.95.0 安装失败"
fi
echo ""

# ── 2.5 安装 rust-nightly ──
info "=== 2.5 安装 rust-nightly ==="
if brew list rust-nightly >/dev/null 2>&1; then
    info "rust-nightly 已安装，先卸载..."
    brew uninstall rust-nightly 2>/dev/null || true
fi

if brew install rust-nightly 2>&1; then
    pass "rust-nightly 安装成功"

    RUSTC_NIGHTLY=$(brew --prefix rust-nightly)/bin/rustc
    if [[ -x "$RUSTC_NIGHTLY" ]]; then
        NIGHTLY_VER=$("$RUSTC_NIGHTLY" --version 2>&1)
        if echo "$NIGHTLY_VER" | grep -q 'nightly'; then
            pass "rustc nightly版本: $NIGHTLY_VER"
        else
            fail "rustc nightly版本输出异常: $NIGHTLY_VER"
        fi
    else
        fail "rustc nightly不可执行"
    fi
else
    fail "rust-nightly 安装失败"
fi
echo ""

# ── 2.6 安装 rust-analyzer-nightly ──
info "=== 2.6 安装 rust-analyzer-nightly ==="
if brew list rust-analyzer-nightly >/dev/null 2>&1; then
    info "rust-analyzer-nightly 已安装，先卸载..."
    brew uninstall rust-analyzer-nightly 2>/dev/null || true
fi

if brew install rust-analyzer-nightly 2>&1; then
    pass "rust-analyzer-nightly 安装成功"

    RA_NIGHTLY=$(brew --prefix rust-analyzer-nightly)/bin/rust-analyzer
    if [[ -x "$RA_NIGHTLY" ]]; then
        RA_NIGHTLY_VER=$("$RA_NIGHTLY" --version 2>&1)
        pass "rust-analyzer nightly版本: $RA_NIGHTLY_VER"
    else
        fail "rust-analyzer nightly不可执行"
    fi
else
    fail "rust-analyzer-nightly 安装失败"
fi
echo ""

# ── 2.7 安装 rustup ──
info "=== 2.7 安装 rustup ==="
if brew list rustup >/dev/null 2>&1; then
    info "rustup 已安装，先卸载..."
    brew uninstall rustup 2>/dev/null || true
fi

if brew install rustup 2>&1; then
    pass "rustup 安装成功"

    RUSTUP_PATH=$(brew --prefix rustup)/bin/rustup
    if [[ -x "$RUSTUP_PATH" ]]; then
        RUSTUP_VER=$("$RUSTUP_PATH" --version 2>&1)
        if echo "$RUSTUP_VER" | grep -q 'rustup'; then
            pass "rustup版本: $RUSTUP_VER"
        else
            fail "rustup版本输出异常: $RUSTUP_VER"
        fi
    else
        fail "rustup不可执行"
    fi

    # 验证rustup-init symlink
    RUSTUP_INIT=$(brew --prefix rustup)/bin/rustup-init
    if [[ -L "$RUSTUP_INIT" ]]; then
        pass "rustup-init symlink存在"
    else
        fail "rustup-init symlink缺失"
    fi
else
    fail "rustup 安装失败"
fi
echo ""

# ── 2.8 rustup toolchain link 测试 ──
info "=== 2.8 rustup toolchain link 测试 ==="
RUSTUP_BIN=$(brew --prefix rustup)/bin/rustup
RUST_PREFIX=$(brew --prefix rust@1.95.0)

if "$RUSTUP_BIN" toolchain link system-test "$RUST_PREFIX" 2>&1; then
    pass "rustup toolchain link system-test 成功"

    # 验证toolchain可被rustup识别
    if "$RUSTUP_BIN" toolchain list 2>&1 | grep -q 'system-test'; then
        pass "rustup能识别 linked toolchain"

        # 验证通过rustup调用rustc
        LINKED_RUSTC=$("$RUSTUP_BIN" which --toolchain system-test rustc 2>/dev/null || true)
        if [[ -n "$LINKED_RUSTC" ]] && [[ -x "$LINKED_RUSTC" ]]; then
            pass "rustup能调用linked rustc: $LINKED_RUSTC"
        else
            fail "rustup无法调用linked rustc"
        fi
    else
        fail "rustup无法识别linked toolchain"
    fi

    # 清理
    "$RUSTUP_BIN" toolchain uninstall system-test 2>/dev/null || true
else
    fail "rustup toolchain link失败"
fi
echo ""

# ── 汇总 ──
echo "=========================================="
echo "  Layer 2 测试结果汇总"
echo "=========================================="
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}SKIP${NC}: $SKIP"
echo "=========================================="

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}存在失败项${NC}"
    exit 1
else
    echo -e "${GREEN}全部通过${NC}"
    exit 0
fi
