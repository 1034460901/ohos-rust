# OHOS Rust 工具链测试方案

## 1. 背景

OpenHarmony（OHOS）是基于musl libc的ARM64操作系统，其内核对原生ELF二进制实施了**强制代码签名机制**：
所有可执行文件和共享库必须包含 `.codesign` 节区（4096字节PROGBITS，存储SHA-256内容哈希），链接时由
OHOS LLD通过 `-Wl,--code-sign` 自动计算并写入。内核在 `execve()` 时验证此签名，任何链接后修改（如
`patchelf`、`strip`）都会使签名失效导致二进制被拒绝执行。

此外，OHOS二进制还携带 `.note.ohos.ident` NOTE节区作为系统标识。

本次工作为OHOS aarch64平台构建了完整的Rust工具链，包括：
- **rustc** — Rust编译器（稳定版1.95.0 + nightly）
- **cargo** — 包管理器（静态链接OpenSSL，动态依赖libz.so）
- **rust-analyzer** — IDE语言服务器（依赖librustc_driver，需单独注入）
- **llvm-tools** — LLVM工具集（llvm-objdump, llvm-profdata等）
- **clippy / rustfmt** — 代码检查和格式化工具
- **rustup** — 工具链安装器（静态链接OpenSSL，仅依赖libc.so）
- **rust-src / rust-docs** — 源码和文档

## 2. 本次修改内容

### 2.1 新增Stable通道编译

此前仅有nightly通道编译。本次新增 `CHANNEL=stable` 编译，产出版本号 `1.95.0` 的tarball：
- stable通道下miri自动跳过（miri依赖nightly特性）
- 复用了nightly编译的LLVM缓存（6.7GB）、sccache缓存（787MB）、host编译缓存（17GB）

### 2.2 pack-tarballs.sh 双通道修复

修复了 `pack-tarballs.sh` 中的 `PKG_VERSION` 计算逻辑：
- **修复前**：`PKG_VERSION="${CHANNEL}"`，stable通道下查找 `rust-stable-*.tar.xz`（错误）
- **修复后**：stable通道使用 `$RUST_VERSION`（即 `1.95.0`），nightly通道使用 `nightly`

### 2.3 5个Homebrew Formula

| Formula | 版本 | 用途 | keg-only |
|---------|------|------|----------|
| `rust@1.95.0` | 1.95.0 | 稳定版Rust工具链 | 否 |
| `rust-nightly` | nightly | nightly Rust工具链 | 是 |
| `rust-analyzer@1.95.0` | 1.95.0 | 稳定版rust-analyzer | 否 |
| `rust-analyzer-nightly` | nightly | nightly rust-analyzer | 是 |
| `rustup` | 1.30.0 | 工具链安装器 | 否 |

关键设计：
- **禁用patchelf/strip**：formula仅使用 `cp`/`mv`/wrapper脚本，避免破坏 `.codesign`
- **cargo wrapper**：设置 `SSL_CERT_FILE` 指向brew的ca-certificates
- **rust-analyzer依赖rust**：确保librustc_driver的RUNPATH `$ORIGIN/../lib` 能正确解析
- **rustup post_install**：在 `~/.cargo/bin/` 创建symlink指向brew安装的rustup

### 2.4 5个Tarball产物

| Tarball | 大小 | SHA256 | 通道 |
|---------|------|--------|------|
| `rust-1.95.0-aarch64-unknown-linux-ohos.tar.xz` | 206M | `537c7077...` | stable |
| `rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.xz` | 68M | `399261c7...` | stable |
| `rust-nightly-aarch64-unknown-linux-ohos.tar.xz` | 208M | `9c98c896...` | nightly |
| `rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.xz` | 68M | `27629d26...` | nightly |
| `rustup-1.30.0-aarch64.tar.xz` | 4.4M | `c404902b...` | - |

所有tarball的URL目标为：`https://gitcode.com/OpenHarmonyPCDeveloper/rust/releases/download/dist/<filename>`
（需手动上传）

## 3. 测试分层架构

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: 宿主机静态验证（不依赖OHOS设备）            │
│  - SHA256校验                                       │
│  - ELF节区检查（.codesign / .note.ohos.ident）      │
│  - RUNPATH / NEEDED依赖链检查                       │
│  - Ruby formula语法检查                             │
│  - tarball结构检查（install.sh存在性）               │
├─────────────────────────────────────────────────────┤
│ Layer 2: Homebrew Formula安装测试（需Harmonybrew）   │
│  - brew install 5个formula                          │
│  - 版本号验证                                       │
│  - cargo wrapper正确性                              │
│  - rustup toolchain link                            │
├─────────────────────────────────────────────────────┤
│ Layer 3: OHOS设备功能验证（需hdc连接设备）           │
│  - 推送二进制到设备                                 │
│  - rustc编译+运行Hello World                        │
│  - cargo new + cargo build + cargo run              │
│  - rust-analyzer LSP协议测试                        │
│  - .codesign内核验证（execve成功=签名通过）         │
│  - rustup工具链管理测试                             │
└─────────────────────────────────────────────────────┘
```

## 4. 测试脚本

### 4.1 脚本清单

| 脚本 | 层级 | 运行位置 | 依赖 |
|------|------|----------|------|
| `verify-host.sh` | Layer 1 | WSL宿主机 | readelf, sha256sum, ruby |
| `test-formula-install.sh` | Layer 2 | Harmonybrew设备 | brew, ruby |
| `test-ohos-device.sh` | Layer 3 | OHOS设备（via hdc） | hdc, OHOS设备 |

### 4.2 运行顺序

```bash
# Layer 1: 宿主机验证（必须先通过）
./scripts/test/verify-host.sh

# Layer 2: Formula安装测试（Harmonybrew环境）
./scripts/test/test-formula-install.sh

# Layer 3: 设备功能验证（hdc连接OHOS设备后）
./scripts/test/test-ohos-device.sh
```

### 4.3 预期结果

| 测试项 | 预期 | 失败原因 |
|--------|------|----------|
| SHA256匹配 | 5个tarball的SHA256与formula一致 | tarball被修改/上传错误版本 |
| .codesign存在 | 所有ELF二进制都有.codesign节区 | 链接时未加 `--code-sign` |
| .note.ohos.ident存在 | 所有ELF二进制都有此节区 | 非OHOS工具链编译 |
| RUNPATH = `$ORIGIN/../lib` | rustc/cargo/rust-analyzer均有 | 链接参数错误 |
| rustc NEEDED librustc_driver | rustc依赖对应版本的driver | driver未注入或版本不匹配 |
| cargo NEEDED libz.so | cargo动态依赖zlib | vendored OpenSSL配置错误 |
| rustup NEEDED libc.so only | rustup仅依赖libc | OpenSSL未静态链接 |
| brew install成功 | 5个formula全部安装成功 | formula语法/URL/SHA错误 |
| rustc Hello World | 设备上编译运行输出"Hello World!" | .codesign无效/ABI不兼容 |
| cargo new + run | 设备上cargo项目可编译运行 | libz.so缺失/SSL配置问题 |
| rust-analyzer LSP | 返回Content-Length响应 | librustc_driver缺失/RUNPATH错误 |

## 5. 已知限制

- **Layer 3需要真机**：OHOS模拟器（qemu）不验证 `.codesign`，只有真机内核才强制检查
- **libc++_shared.so**：不打包在tarball中，依赖设备系统 `/system/lib64/libc++_shared.so`
- **libz.so**：cargo依赖设备的libz.so，OHOS系统自带
- **miri**：stable通道无miri，nightly通道有miri但未在设备测试范围内
- **tarball上传**：Layer 2/3测试前需先将5个tarball上传到gitcode releases
