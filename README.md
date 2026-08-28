# ohos-rust

为 OpenHarmony 平台交叉编译 Rust 工具链。

## 项目结构

```
ohos-rust/
├── x86_64/            # x86_64 交叉编译构建配置（Dockerfile + build.sh）
├── arm64/             # arm64 原生构建配置（-Wl,--code-sign 链接时签名）
├── patches/           # Rust 源码补丁（按版本分目录）
│   ├── 1.89.0/        # Rust 1.89.0 stable 补丁（5 个）
│   ├── 1.95.0/        # Rust 1.95.0 stable 补丁（5 个）
│   └── 1.100.0/       # Rust 1.100.0 nightly 补丁（5 个）
├── tmp/               # 分析文档（CI 对比、rpath、编译过程）
└── .github/workflows/ # CI 构建流程
```

## 支持版本

三个版本共存于 main 分支，通过 `RUST_VERSION` + `CHANNEL` 变量区分：

| 版本 | Channel | 补丁目录 | 说明 |
|------|---------|----------|------|
| 1.89.0 | stable | `patches/1.89.0/` | 1.89.0 已内置 OHOS target spec；0001 使用 `-Wl,--code-sign` 链接器标志 |
| 1.95.0 | stable | `patches/1.95.0/` | 0001 使用 `-Wl,--code-sign` 链接器标志 |
| 1.100.0 | nightly | `patches/1.100.0/` | 1.95.0 基础上移植，含 f128/f16 cfg 修复（0005 patch） |

> **注意：** 后续修复需同步更新所有受影响版本的补丁目录。

## 构建

### 方式 1：Docker 构建（推荐，无需手动准备环境）

Docker 镜像自动安装所有依赖（OHOS SDK、OpenSSL、sccache、系统包）：

```bash
# 1. 构建 Docker 镜像（约 5 分钟，首次需要下载 SDK ~500MB）
docker build -f x86_64/Dockerfile -t rust-ohos-x86_64 .

# 2. 构建 Rust 工具链（约 3 小时）
# stable 1.89.0
docker run --rm -v $(pwd):/workspace -w /workspace \
  -e RUST_VERSION=1.89.0 -e CHANNEL=stable -e CLEAN_BUILD=true \
  rust-ohos-x86_64 ./x86_64/build.sh

# stable 1.95.0
docker run --rm -v $(pwd):/workspace -w /workspace \
  -e RUST_VERSION=1.95.0 -e CHANNEL=stable -e CLEAN_BUILD=true \
  rust-ohos-x86_64 ./x86_64/build.sh

# nightly 1.100.0
docker run --rm -v $(pwd):/workspace -w /workspace \
  -e RUST_VERSION=1.100.0 -e CHANNEL=nightly -e CLEAN_BUILD=true \
  rust-ohos-x86_64 ./x86_64/build.sh
```

CI 使用的就是这种方式。

### 方式 2：本地编译（WSL / Linux）

适合需要调试或增量编译的场景。

#### 环境依赖

| 依赖 | 版本/来源 | 安装方式 |
|------|----------|---------|
| Ubuntu | 24.04 (推荐) 或 WSL2 | — |
| 系统包 | g++, make, ninja-build, file, curl, ca-certificates, python3, git, cmake, pkg-config, xz-utils, unzip, patch, perl, ccache | `sudo apt-get install -y g++ make ninja-build file curl ca-certificates python3 git cmake pkg-config xz-utils unzip patch perl ccache` |
| OHOS SDK | 7.0-Beta1 (clang 15.0.4) | `sudo bash x86_64/scripts/ohos-sdk.sh` |
| OHOS OpenSSL | 3.6.1（交叉编译） | `sudo bash x86_64/scripts/ohos-openssl.sh` |
| sccache | v0.10.0（可选，加速 C/C++ 编译） | `sudo bash x86_64/scripts/sccache.sh` |
| clang wrapper | `aarch64-unknown-linux-ohos-clang.sh` | `sudo cp x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang*.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/aarch64-unknown-linux-ohos-clang*.sh` |

> **注意：** OHOS SDK 安装到 `/opt/ohos-sdk`，OpenSSL 安装到 `/opt/ohos-openssl`，sccache 安装到 `/usr/local/bin/sccache`。clang wrapper 安装到 `/usr/local/bin/`。这些路径被 build.sh 和 patches 硬编码引用，不要更改。

#### 安装依赖

```bash
# 1. 安装系统包
sudo apt-get update
sudo apt-get install -y g++ make ninja-build file curl ca-certificates python3 git cmake pkg-config xz-utils unzip patch perl ccache

# 2. 安装 OHOS SDK（下载到 /opt/ohos-sdk，约 500MB）
sudo bash x86_64/scripts/ohos-sdk.sh

# 3. 安装 clang wrapper（OHOS SDK 的 clang 交叉编译包装脚本）
sudo cp x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh /usr/local/bin/
sudo cp x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/aarch64-unknown-linux-ohos-clang*.sh

# 4. 交叉编译 OpenSSL（需要 clang wrapper 已安装）
sudo bash x86_64/scripts/ohos-openssl.sh

# 5. 安装 sccache（可选，加速 C/C++ 编译缓存）
sudo bash x86_64/scripts/sccache.sh
```

#### 开始编译

**使用封装脚本：**

```bash
# stable 1.89.0
RUST_VERSION=1.89.0 CHANNEL=stable CLEAN_BUILD=true bash start_build.sh

# stable 1.95.0（start_build.sh 默认版本，镜像加速）
CLEAN_BUILD=true bash start_build.sh

# nightly 1.100.0（使用 start_nightly_build.sh）
bash start_nightly_build.sh
```

> **注意：** `start_build.sh` 默认使用 build.sh 的默认版本（1.100.0），构建 stable 需通过环境变量指定 `RUST_VERSION` 和 `CHANNEL`。`start_nightly_build.sh` 已内置 `CHANNEL=nightly`，默认版本 1.100.0。

**直接调用 build.sh：**

```bash
# stable 1.89.0
RUST_VERSION=1.89.0 CHANNEL=stable CLEAN_BUILD=true ./x86_64/build.sh

# stable 1.95.0
RUST_VERSION=1.95.0 CHANNEL=stable CLEAN_BUILD=true ./x86_64/build.sh

# nightly 1.100.0（源码用 dated nightly tarball，默认日期 2026-08-20）
RUST_VERSION=1.100.0 CHANNEL=nightly CLEAN_BUILD=true ./x86_64/build.sh
```

#### build.sh 常用参数

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `RUST_VERSION` | `1.100.0` | Rust 版本号，对应 `patches/` 目录名 |
| `CHANNEL` | `nightly` | 发布通道（`stable` 或 `nightly`） |
| `CLEAN_BUILD` | `false` | `true` 时删除旧源码和编译缓存，从全新状态构建 |
| `USE_MIRROR` | `false` | `true` 时使用 USTC 镜像加速下载（源码 + stage0） |
| `NIGHTLY_DATE` | `2026-08-20` | nightly 源码 tarball 的日期 |
| `DRY_RUN` | `false` | `true` 时跳过编译，仅生成模拟产物（测试流程用） |
| `SCCACHE_DIR` | `$WORKDIR/.sccache` | sccache 缓存目录 |
| `CCACHE_DIR` | `$WORKDIR/.ccache` | ccache 缓存目录 |

> **首次构建**建议设置 `CLEAN_BUILD=true`，确保从全新源码开始。增量编译（`CLEAN_BUILD=false`）可复用 `build/` 目录，跳过已编译的 LLVM/rustc。

#### 构建产物

```
ohos-rust/
├── rust-1.89.0-aarch64-unknown-linux-ohos.tar.gz          ← 主工具链包（含 install.sh）
├── rust-analyzer-1.89.0-aarch64-unknown-linux-ohos.tar.gz  ← rust-analyzer（注入 librustc_driver）
└── rustc-1.89.0-src/build/dist/
    ├── rustc-1.89.0-aarch64-unknown-linux-ohos.tar.gz      ← rustc 编译器
    ├── cargo-1.89.0-aarch64-unknown-linux-ohos.tar.gz      ← cargo 包管理器
    ├── rust-std-1.89.0-aarch64-unknown-linux-ohos.tar.gz   ← 标准库
    ├── rustfmt-1.89.0-aarch64-unknown-linux-ohos.tar.gz    ← 代码格式化工具
    ├── clippy-1.89.0-aarch64-unknown-linux-ohos.tar.gz     ← lint 工具
    ├── rust-src-1.89.0.tar.gz                              ← 源码（供 IDE 使用）
    ├── rust-docs-1.89.0-aarch64-unknown-linux-ohos.tar.gz  ← 文档
    ├── llvm-tools-1.89.0-aarch64-unknown-linux-ohos.tar.gz ← LLVM 工具链
    ├── rustc-dev-1.89.0-aarch64-unknown-linux-ohos.tar.gz  ← 编译器开发库
    └── rust-docs-json-1.89.0-*.tar.gz                       ← JSON 格式文档
```

构建完成后输出 `=== Build Fingerprint ===`，包含输入和产物的 SHA256。

### GitHub Actions CI

| 触发方式 | 分支 | Channel | Version | 说明 |
|----------|------|---------|---------|------|
| push | `main` | stable | 1.95.0 | 门禁检查 |
| push | `1.89.0` | stable | 1.89.0 | 门禁检查 |
| push | `nightly` | nightly | 1.100.0 | 门禁检查 |
| workflow_dispatch | 任意 | stable | 手选 1.89.0 / 1.95.0 | 手动构建 stable |
| workflow_dispatch | 任意 | nightly | 1.100.0（自动默认） | 手动构建 nightly |

## 补丁说明

每个版本 5 个补丁，按编号顺序应用：

| 编号 | 名称 | 说明 |
|------|------|------|
| 0001 | rustc-ohos-auto-sign-fix | `linux_ohos.rs` 添加 `-Wl,--code-sign` 链接器标志，链接时自动生成 `.codesign` 节区 |
| 0002 | openssl-probe-cert-fix | 添加 `certs/cacert.pem` 到证书搜索路径（OHOS musl 缺少默认证书路径） |
| 0003 | ohos-native-build-support | bootstrap.py HarmonyOS 检测、rustc.rs 交叉编译 shim、dist.rs/doc.rs/test.rs OHOS 适配、llvm.rs OHOS SDK clang 覆盖 + cflags/ldflags、libffi config.sub |
| 0004 | asan-ohos-39bit-va-fix | SANITIZER_OHOS 宏、ASAN/HWASAN/LSAN 128GB allocator、`-fno-emulated-tls`、`-gz=none`、`__gcc_personality_v0` stub、sanitizer CMake clang/sysroot 覆盖 |
| 0005 | f128-f16-ohos-cfg | `#[cfg(target_has_reliable_f128_math)]` → `#[cfg(all(target_has_reliable_f128_math, not(target_env = "ohos")))]`（OHOS musl 缺少 f128/f16 数学符号） |

> 补丁是版本特定的：针对每个版本的源码结构适配，非跨版本盲目拷贝。

## Build Fingerprint

构建完成后，`build.sh` 输出 `=== Build Fingerprint ===`，包含：
- 输入指纹：源码版本、tarball SHA256、OHOS SDK 版本、各 patch SHA256
- 产物指纹：主 tarball 和各组件的 SHA256

用于验证 CI 与本地构建的产物一致性（输入相同但产物 hash 可能因编译器/路径差异而不同）。
