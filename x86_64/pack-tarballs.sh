#!/usr/bin/env bash
set -euo pipefail

# Pack formula-ready .tar.xz tarballs from build/dist/ output
#
# Input:
#   build/dist/rust-analyzer-*-aarch64-unknown-linux-ohos.tar.xz  (rust-installer v3, no librustc_driver)
#   build/dist/rust-*-aarch64-unknown-linux-ohos.tar.xz           (already formula-ready)
#   installed toolchain tree with librustc_driver-*.so
#
# Output: Repacked .tar.xz with librustc_driver injected + .sha256 files
#
# Usage:
#   ./pack-tarballs.sh [--src-dir <build-src>] [--install-dir <rust-install>] [--channel nightly]
#
# Defaults:
#   --src-dir     ../rustc-1.95.0-src/build/dist
#   --install-dir /tmp/rust-install
#   --channel     nightly

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_DIR=""
INSTALL_DIR="/tmp/rust-install"
CHANNEL="nightly"
RUST_VERSION="1.95.0"
TARGET="aarch64-unknown-linux-ohos"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-dir)      SRC_DIR="$2"; shift 2;;
        --install-dir)  INSTALL_DIR="$2"; shift 2;;
        --channel)      CHANNEL="$2"; shift 2;;
        --rust-version) RUST_VERSION="$2"; shift 2;;
        --target)       TARGET="$2"; shift 2;;
        -h|--help)
            cat <<HELP
Usage: $0 [OPTIONS]
  --src-dir       Path to rustc-*-src/build/dist
                  (default: ../rustc-${RUST_VERSION}-src/build/dist)
  --install-dir   Path to installed toolchain tree (default: /tmp/rust-install)
  --channel       Release channel (default: nightly)
  --rust-version  Rust version (default: 1.95.0)
  --target        Target triple (default: aarch64-unknown-linux-ohos)
HELP
            exit 0;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
done

if [[ -z "$SRC_DIR" ]]; then
    SRC_DIR="${WORKDIR}/rustc-${RUST_VERSION}-src/build/dist"
fi

PKG_VERSION="${CHANNEL}"
RA_TARBALL="${SRC_DIR}/rust-analyzer-${PKG_VERSION}-${TARGET}.tar.xz"
RUST_TARBALL="${SRC_DIR}/rust-${PKG_VERSION}-${TARGET}.tar.xz"
OUTPUT_DIR="${WORKDIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Verify .codesign on an ELF file
verify_codesign() {
    local f="$1"
    local label="$2"
    if readelf -SW "$f" 2>/dev/null | grep -q '\.codesign'; then
        info "${label}: .codesign OK"
    else
        error "${label}: .codesign MISSING — binary will be rejected by OHOS kernel"
    fi
}

# ── 1. rust tarball: verify as-is ──
info "=== Checking rust tarball ==="
RUST_OUTPUT="${OUTPUT_DIR}/rust-${PKG_VERSION}-${TARGET}.tar.xz"
if [[ -f "$RUST_TARBALL" ]]; then
    info "rust tarball: $(basename "$RUST_TARBALL") ($(du -h "$RUST_TARBALL" | cut -f1))"
    info "rust tarball already in rust-installer v3 format with install.sh — no repack needed"
    # Copy to output dir if not already there
    if [[ "$RUST_TARBALL" != "$RUST_OUTPUT" ]]; then
        cp -a "$RUST_TARBALL" "$RUST_OUTPUT"
        info "Copied to: ${RUST_OUTPUT}"
    fi
    RUST_HASH=$(sha256sum "$RUST_OUTPUT" | awk '{print $1}')
    info "rust SHA-256: ${RUST_HASH}"
    echo "${RUST_HASH}" > "${OUTPUT_DIR}/rust-${PKG_VERSION}-${TARGET}.tar.xz.sha256"
else
    error "rust tarball not found: $RUST_TARBALL"
fi

# ── 2. rust-analyzer tarball: inject librustc_driver, repack ──
info "=== Repacking rust-analyzer tarball ==="
[[ -f "$RA_TARBALL" ]] || error "rust-analyzer tarball not found: $RA_TARBALL"
info "rust-analyzer tarball: $(basename "$RA_TARBALL") ($(du -h "$RA_TARBALL" | cut -f1))"

# Find librustc_driver in install tree
DRIVER_SO=$(find "$INSTALL_DIR/lib" -name 'librustc_driver-*.so' -type f 2>/dev/null | head -1)
[[ -n "$DRIVER_SO" ]] || error "librustc_driver-*.so not found in $INSTALL_DIR/lib"
info "Found librustc_driver: $(basename "$DRIVER_SO") ($(du -h "$DRIVER_SO" | cut -f1))"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "${TMP_DIR}"
tar -xf "$RA_TARBALL"
cd - >/dev/null

PKG_DIR="${TMP_DIR}/rust-analyzer-${PKG_VERSION}-${TARGET}"
RA_PREVIEW_DIR="${PKG_DIR}/rust-analyzer-preview"
[[ -d "$RA_PREVIEW_DIR" ]] || error "rust-analyzer-preview/ not found in tarball"

# Create lib/ and copy librustc_driver
mkdir -p "${RA_PREVIEW_DIR}/lib"
cp -a "$DRIVER_SO" "${RA_PREVIEW_DIR}/lib/"
info "Injected librustc_driver into rust-analyzer-preview/lib/"

# Update manifest.in to include librustc_driver
MANIFEST="${RA_PREVIEW_DIR}/manifest.in"
if [[ -f "$MANIFEST" ]]; then
    echo "file:lib/$(basename "$DRIVER_SO")" >> "$MANIFEST"
    info "Updated manifest.in with librustc_driver entry"
fi

# Verify .codesign on both binaries
verify_codesign "${RA_PREVIEW_DIR}/bin/rust-analyzer" "rust-analyzer"
verify_codesign "${RA_PREVIEW_DIR}/lib/$(basename "$DRIVER_SO")" "librustc_driver"

# Repack as .tar.xz (use -0 for fast compression, librustc_driver is 273MB)
RA_OUTPUT="${OUTPUT_DIR}/rust-analyzer-${PKG_VERSION}-${TARGET}.tar.xz"
info "Packing: $(basename "$RA_OUTPUT") (xz -0)"
cd "${TMP_DIR}"
XZ_OPT=-0 tar -cJf "$RA_OUTPUT" "rust-analyzer-${PKG_VERSION}-${TARGET}"
cd - >/dev/null

RA_HASH=$(sha256sum "$RA_OUTPUT" | awk '{print $1}')
info "rust-analyzer SHA-256: ${RA_HASH}"
echo "${RA_HASH}" > "${OUTPUT_DIR}/rust-analyzer-${PKG_VERSION}-${TARGET}.tar.xz.sha256"

info "=== Summary ==="
info "rust:             ${OUTPUT_DIR}/rust-${PKG_VERSION}-${TARGET}.tar.xz"
info "  SHA-256:         ${RUST_HASH}"
info "rust-analyzer:    ${RA_OUTPUT}"
info "  SHA-256:         ${RA_HASH}"
info "  librustc_driver: $(basename "$DRIVER_SO")"
info "Done."
