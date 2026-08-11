#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Layer 1: 宿主机静态验证
# 不依赖OHOS设备，仅检查tarball的SHA256、ELF节区、依赖链
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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

# 期望的SHA256值
declare -A EXPECTED_SHA
EXPECTED_SHA["rust-1.95.0-aarch64-unknown-linux-ohos.tar.xz"]="537c70779c8fa4c28cc3df52cb0221615deefecba58bc518487e58b79e692b5b"
EXPECTED_SHA["rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.xz"]="399261c7c8c65b2015e044767c450108d17347c723a707f2d539c81b6164e684"
EXPECTED_SHA["rust-nightly-aarch64-unknown-linux-ohos.tar.xz"]="9c98c896344f4d93928ab335c11b6c9901a32d0956abfdba224654570e311426"
EXPECTED_SHA["rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.xz"]="27629d260138c1ab3adedf46d27824cc67142a5fdd98f05914c88337036de311"
EXPECTED_SHA["rustup-1.30.0-aarch64.tar.xz"]="c404902b77e506341802243cc8001e38c6f810c7cd47075c4914084bcbfd15d1"

# tarball位置
RUST_DIR="${WORKDIR}"
RUSTUP_DIR="${WORKDIR}/../rustup-ohos/dist"
if [[ ! -d "$RUSTUP_DIR" ]]; then
    RUSTUP_DIR="/tmp/rustup-ohos/dist"
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=========================================="
echo "  Layer 1: 宿主机静态验证"
echo "=========================================="
echo ""

# ── 1.1 SHA256校验 ──
info "=== 1.1 SHA256 校验 ==="

check_sha256() {
    local filename="$1"
    local filepath="$2"
    local expected="${EXPECTED_SHA[$filename]}"

    if [[ ! -f "$filepath" ]]; then
        warn "$filename (文件不存在: $filepath)"
        return
    fi

    local actual
    actual=$(sha256sum "$filepath" | awk '{print $1}')
    if [[ "$actual" == "$expected" ]]; then
        pass "$filename SHA256 匹配"
    else
        fail "$filename SHA256 不匹配 (期望: ${expected:0:16}..., 实际: ${actual:0:16}...)"
    fi
}

check_sha256 "rust-1.95.0-aarch64-unknown-linux-ohos.tar.xz" "$RUST_DIR/rust-1.95.0-aarch64-unknown-linux-ohos.tar.xz"
check_sha256 "rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.xz" "$RUST_DIR/rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.xz"
check_sha256 "rust-nightly-aarch64-unknown-linux-ohos.tar.xz" "$RUST_DIR/rust-nightly-aarch64-unknown-linux-ohos.tar.xz"
check_sha256 "rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.xz" "$RUST_DIR/rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.xz"
check_sha256 "rustup-1.30.0-aarch64.tar.xz" "$RUSTUP_DIR/rustup-1.30.0-aarch64.tar.xz"
echo ""

# ── 1.2 ELF节区检查 ──
info "=== 1.2 ELF 节区检查 ==="

# 检查.codesign和.note.ohos.ident
check_elf_sections() {
    local elf="$1"
    local label="$2"

    if [[ ! -f "$elf" ]]; then
        fail "$label: 文件不存在 ($elf)"
        return
    fi

    local has_codesign has_ohos_ident
    has_codesign=$(readelf -SW "$elf" 2>/dev/null | grep -c '\.codesign' || true)
    has_ohos_ident=$(readelf -SW "$elf" 2>/dev/null | grep -c '\.note\.ohos\.ident' || true)

    if [[ "$has_codesign" -gt 0 ]] && [[ "$has_ohos_ident" -gt 0 ]]; then
        pass "$label: .codesign + .note.ohos.ident 均存在"
    else
        if [[ "$has_codesign" -eq 0 ]]; then
            fail "$label: .codesign 缺失"
        fi
        if [[ "$has_ohos_ident" -eq 0 ]]; then
            fail "$label: .note.ohos.ident 缺失"
        fi
    fi
}

# 检查RUNPATH和NEEDED
check_runpath_needed() {
    local elf="$1"
    local label="$2"
    local expected_runpath="$3"
    shift 3
    local expected_needed=("$@")

    if [[ ! -f "$elf" ]]; then
        fail "$label RUNPATH: 文件不存在"
        return
    fi

    local runpath
    runpath=$(readelf -dW "$elf" 2>/dev/null | grep 'RUNPATH' | sed 's/.*Library runpath: \[\(.*\)\]/\1/' | tr -d '[:space:]' || true)
    if [[ "$runpath" == "$expected_runpath" ]]; then
        pass "$label: RUNPATH=$runpath"
    else
        fail "$label: RUNPATH不匹配 (期望: $expected_runpath, 实际: $runpath)"
    fi

    local needed
    needed=$(readelf -dW "$elf" 2>/dev/null | grep 'NEEDED' | awk -F'Shared library:' '{print $2}' | tr -d '[]' || true)

    local all_found=true
    for lib in "${expected_needed[@]}"; do
        if echo "$needed" | grep -qF "$lib"; then
            :
        else
            fail "$label: NEEDED缺少 $lib"
            all_found=false
        fi
    done
    if $all_found; then
        pass "$label: NEEDED 依赖链正确 ($(echo "$needed" | tr '\n' ','))"
    fi
}

# 解压stable rust tarball
info "--- 解压 stable rust tarball ---"
cd "$TMPDIR"
tar -xf "$RUST_DIR/rust-1.95.0-aarch64-unknown-linux-ohos.tar.xz"
RUST_PKG="$TMPDIR/rust-1.95.0-aarch64-unknown-linux-ohos"

check_elf_sections "$RUST_PKG/rustc/bin/rustc" "stable rustc"
check_elf_sections "$RUST_PKG/cargo/bin/cargo" "stable cargo"
check_elf_sections "$RUST_PKG/rustc/lib/librustc_driver-b27142bdb796e0ae.so" "stable librustc_driver"
check_elf_sections "$RUST_PKG/rustfmt-preview/bin/rustfmt" "stable rustfmt"
check_elf_sections "$RUST_PKG/clippy-preview/bin/clippy-driver" "stable clippy-driver"

check_runpath_needed "$RUST_PKG/rustc/bin/rustc" "stable rustc" '$ORIGIN/../lib' "librustc_driver" "libc.so"
check_runpath_needed "$RUST_PKG/cargo/bin/cargo" "stable cargo" '$ORIGIN/../lib' "libz.so" "libc.so"
check_runpath_needed "$RUST_PKG/rustc/lib/librustc_driver-b27142bdb796e0ae.so" "stable librustc_driver" '$ORIGIN/../lib' "libc.so"

# 检查install.sh存在
if [[ -f "$RUST_PKG/install.sh" ]]; then
    pass "stable rust: install.sh 存在"
else
    fail "stable rust: install.sh 缺失"
fi
echo ""

# 解压stable rust-analyzer tarball
info "--- 解压 stable rust-analyzer tarball ---"
cd "$TMPDIR"
tar -xf "$RUST_DIR/rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.xz"
RA_PKG="$TMPDIR/rust-analyzer-1.95.0-aarch64-unknown-linux-ohos"

check_elf_sections "$RA_PKG/rust-analyzer-preview/bin/rust-analyzer" "stable rust-analyzer"
RA_DRIVER=$(find "$RA_PKG" -name 'librustc_driver-*.so' -type f 2>/dev/null | head -1)
if [[ -n "$RA_DRIVER" ]]; then
    check_elf_sections "$RA_DRIVER" "stable rust-analyzer librustc_driver"
    check_runpath_needed "$RA_PKG/rust-analyzer-preview/bin/rust-analyzer" "stable rust-analyzer" '$ORIGIN/../lib' "librustc_driver" "libc++_shared.so" "libc.so"
    pass "stable rust-analyzer: librustc_driver 已注入"
else
    fail "stable rust-analyzer: librustc_driver 未注入"
fi

if [[ -f "$RA_PKG/install.sh" ]]; then
    pass "stable rust-analyzer: install.sh 存在"
else
    fail "stable rust-analyzer: install.sh 缺失"
fi
echo ""

# 解压nightly rust tarball
info "--- 解压 nightly rust tarball ---"
cd "$TMPDIR"
tar -xf "$RUST_DIR/rust-nightly-aarch64-unknown-linux-ohos.tar.xz"
RUST_NIGHTLY_PKG="$TMPDIR/rust-nightly-aarch64-unknown-linux-ohos"

check_elf_sections "$RUST_NIGHTLY_PKG/rustc/bin/rustc" "nightly rustc"
check_elf_sections "$RUST_NIGHTLY_PKG/cargo/bin/cargo" "nightly cargo"
NIGHTLY_DRIVER=$(find "$RUST_NIGHTLY_PKG/rustc/lib" -name 'librustc_driver-*.so' -type f 2>/dev/null | head -1)
if [[ -n "$NIGHTLY_DRIVER" ]]; then
    check_elf_sections "$NIGHTLY_DRIVER" "nightly librustc_driver"
fi
check_runpath_needed "$RUST_NIGHTLY_PKG/rustc/bin/rustc" "nightly rustc" '$ORIGIN/../lib' "librustc_driver" "libc.so"
echo ""

# 解压nightly rust-analyzer tarball
info "--- 解压 nightly rust-analyzer tarball ---"
cd "$TMPDIR"
tar -xf "$RUST_DIR/rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.xz"
RA_NIGHTLY_PKG="$TMPDIR/rust-analyzer-nightly-aarch64-unknown-linux-ohos"

check_elf_sections "$RA_NIGHTLY_PKG/rust-analyzer-preview/bin/rust-analyzer" "nightly rust-analyzer"
RA_NIGHTLY_DRIVER=$(find "$RA_NIGHTLY_PKG" -name 'librustc_driver-*.so' -type f 2>/dev/null | head -1)
if [[ -n "$RA_NIGHTLY_DRIVER" ]]; then
    check_elf_sections "$RA_NIGHTLY_DRIVER" "nightly rust-analyzer librustc_driver"
    pass "nightly rust-analyzer: librustc_driver 已注入"
else
    fail "nightly rust-analyzer: librustc_driver 未注入"
fi
echo ""

# 解压rustup tarball
info "--- 解压 rustup tarball ---"
cd "$TMPDIR"
mkdir -p rustup-extract
cd rustup-extract
tar -xf "$RUSTUP_DIR/rustup-1.30.0-aarch64.tar.xz"
RUSTUP_BIN=$(find . -name 'rustup-init' -type f 2>/dev/null | head -1)
if [[ -n "$RUSTUP_BIN" ]]; then
    check_elf_sections "$RUSTUP_BIN" "rustup-init"
    check_runpath_needed "$RUSTUP_BIN" "rustup-init" '' "libc.so"
    # rustup应该没有RUNPATH（静态链接OpenSSL）
    local_rustup_runpath=$(readelf -dW "$RUSTUP_BIN" 2>/dev/null | grep 'RUNPATH' || true)
    if [[ -z "$local_rustup_runpath" ]]; then
        pass "rustup-init: 无RUNPATH（静态链接，符合预期）"
    fi
else
    fail "rustup-init: 文件不存在"
fi
echo ""

# ── 1.3 Ruby Formula语法检查 ──
info "=== 1.3 Ruby Formula 语法检查 ==="
FORMULA_DIR="${WORKDIR}/../homebrew-ohos/Formula"
if [[ ! -d "$FORMULA_DIR" ]]; then
    FORMULA_DIR="/tmp/homebrew-ohos/Formula"
fi

if [[ -d "$FORMULA_DIR" ]]; then
    for f in "$FORMULA_DIR"/*.rb; do
        if ruby -c "$f" >/dev/null 2>&1; then
            pass "$(basename "$f"): Ruby语法OK"
        else
            fail "$(basename "$f"): Ruby语法错误"
            ruby -c "$f" 2>&1 | head -3
        fi
    done
else
    warn "Formula目录不存在: $FORMULA_DIR"
fi
echo ""

# ── 1.4 Formula SHA256一致性检查 ──
info "=== 1.4 Formula SHA256 一致性检查 ==="

check_formula_sha() {
    local formula="$1"
    local url_line sha_line

    url_line=$(grep -E '^\s*url "' "$formula" | head -1)
    sha_line=$(grep -E '^\s*sha256 "' "$formula" | head -1)

    local filename
    filename=$(echo "$url_line" | sed 's|.*/||; s|".*||')
    local formula_sha
    formula_sha=$(echo "$sha_line" | sed 's/.*sha256 "//; s/".*//')

    local expected="${EXPECTED_SHA[$filename]}"
    if [[ -z "$expected" ]]; then
        warn "$filename: 不在期望列表中"
        return
    fi

    if [[ "$formula_sha" == "$expected" ]]; then
        pass "$(basename "$formula"): SHA256与tarball一致"
    else
        fail "$(basename "$formula"): SHA256不一致 (formula: ${formula_sha:0:16}..., tarball: ${expected:0:16}...)"
    fi
}

if [[ -d "$FORMULA_DIR" ]]; then
    for f in "$FORMULA_DIR"/*.rb; do
        check_formula_sha "$f"
    done
fi
echo ""

# ── 汇总 ──
echo "=========================================="
echo "  Layer 1 测试结果汇总"
echo "=========================================="
echo -e "  ${GREEN}PASS${NC}: $PASS"
echo -e "  ${RED}FAIL${NC}: $FAIL"
echo -e "  ${YELLOW}SKIP${NC}: $SKIP"
echo "=========================================="

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}存在失败项，请修复后再继续Layer 2/3测试${NC}"
    exit 1
else
    echo -e "${GREEN}全部通过，可继续Layer 2/3测试${NC}"
    exit 0
fi
