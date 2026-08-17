# OHOS Rust 1.95.0 交叉编译工具链 — 变更说明

> 分支：`refactor/code-sign-linker-approach` → `main` → `nightly`
> 时间：2026-07-25 ~ 2026-07-28
> 涉及提交：23 个（含 2 个 Merge PR）

---

## 一、提交总览

| # | Commit | 标题 | 改动文件 | +/- |
|---|--------|------|----------|-----|
| 1 | `3279a91` | patch: 使用 -Wl,--code-sign 替代 binary-sign-tool 后签名 | 0001 patch | +22 / -75 |
| 2 | `510e572` | patch: 添加 openssl-probe 证书路径修复 | 0002 patch (新增) | +22 |
| 3 | `d662428` | build: 重构构建脚本，移除后签名步骤，添加 checksum 更新 | build.sh | +32 / -64 |
| 4 | `b927db0` | docker: 重排 clang wrapper 顺序，添加 perl 依赖 | Dockerfile | +6 / -12 |
| 5 | `dd7cc23` | openssl: 从源码构建静态库 (no-shared) | ohos-openssl.sh | +25 / -3 |
| 6 | `ea2e961` | Merge pull request #1 | — | — |
| 7 | `5051692` | Add 0003-ohos-native-build-support.patch | 0003 patch (新增) | +792 |
| 8 | `478b884` | build: enable rust-docs/llvm-tools, fix cross-compile, add incremental build | 6 files | +258 / -117 |
| 9 | `85a2b1c` | patch: merge 0004 cross-compile fix into 0003 | 0003 patch +删 0004 | +27 / -28 |
| 10 | `bd05462` | Merge pull request #2 | — | — |
| 11 | `9789e37` | ci: add sccache/ccache cross-run caching and clean_build option | ci.yml + Dockerfile | +34 / -32 |
| 12 | `3fea811` | docs: remove CHANGELOG from git (not intended for commit) | CHANGELOG.md | -299 |
| 13 | `f9177ad` | fix: use official Rust download URLs for CI, add USE_MIRROR | build.sh + 0003 patch + start_build.sh | +33 / -16 |
| 14 | `43ebc57` | chore: gitignore docs/CHANGELOG.md (local only) | .gitignore | +1 / -299 |
| 15 | `69c87fc` | fix: replace bash array with POSIX sh syntax | build.sh | +3 / -3 |
| 16 | `300c20f` | fix: add missing newline between f128.rs and doc.rs diffs | 0003 patch | +2 / -1 |
| 17 | `edb6fc0` | fix: correct hunk line counts in 0003 patch | 0003 patch | +2 / -2 |
| 18 | `5a73f34` | build: align with reference script, remove redundant static linking params | build.sh + Dockerfile + .gitignore | +1 / -5 |
|   | **— main 分支以上，nightly 分支以下 —** |   |   |   |
| 19 | `91b6740` | build: add nightly channel support with miri | ci.yml + Dockerfile + build.sh | +59 / -25 |
| 20 | `b0aaf05` | fix: add ohos OS support to libffi-sys config.sub | 0004 patch + build.sh | +24 / -2 |
| 21 | `7041db1` | fix: link libclang_rt.builtins for __clear_cache on aarch64-ohos | clang.sh + clang++.sh | +6 / -2 |
| 22 | `8ce1746` | fix: use PKG_VERSION for nightly tarball naming | build.sh | +18 / -16 |
| 23 | `d142354` | fix: use pkg_version for CI artifact naming | ci.yml | +10 / -6 |

---

## 二、Patch 详细说明

当前 `patches/1.95.0/` 目录下共 4 个 patch 文件，按序号顺序应用。

### 0001-rustc-ohos-auto-sign-fix.patch（改写）

**改动性质**：完全重写，从"编译后签名"方案改为"链接时自动签名"方案。

**原方案（已删除）**：
- 修改 `compiler/rustc_codegen_ssa/src/back/link.rs`，在 `link_natively` 函数末尾插入 `ohos_auto_resign` 调用
- 新增 `ohos_auto_resign` 函数（51 行），通过 `std::process::Command` 调用外部 `binary-sign-tool` 对生成的 ELF 文件逐一签名
- 需要设置环境变量 `OHOS_BINARY_SIGN_TOOL` 指向签名工具路径
- 缺点：编译后还需外部工具签名，构建流程复杂；需额外打包 `binary-sign-tool`

**新方案**：
- 修改 `compiler/rustc_target/src/spec/base/linux_ohos.rs`，在 OHOS target spec 中添加预链接参数
- 对 `LinkerFlavor::Gnu(Cc::Yes, Lld::No)` 添加 `-Wl,--code-sign` 参数
- 链接器（lld）在链接阶段自动完成代码签名，无需后处理
- 优点：签名在编译时自动完成，无需外部工具，构建流程简洁

```rust
// 核心改动（linux_ohos.rs）
pub(crate) fn opts() -> TargetOptions {
    let mut opts = TargetOptions {
        env: Env::Ohos,
        crt_static_default: false,
        tls_model: TlsModel::Emulated,
        has_thread_local: false,
        ..base::linux::opts()
    };
    opts.add_pre_link_args(
        LinkerFlavor::Gnu(Cc::Yes, Lld::No),
        &["-Wl,--code-sign"],
    );
    opts
}
```

### 0002-openssl-probe-cert-fix.patch（新增）

**目的**：修复 OpenSSL 证书探测路径，使 `openssl-probe` crate 能在 OHOS 系统上找到 CA 证书。

**改动**：在 `vendor/openssl-probe-0.1.5/src/lib.rs` 和 `vendor/openssl-probe-0.1.6/src/lib.rs` 的证书文件名列表中添加 `"certs/cacert.pem"`。

```rust
// 修改前
"tls-ca-bundle.pem",

// 修改后
"tls-ca-bundle.pem",
"certs/cacert.pem",
```

OHOS 系统将 CA 证书放在 `/etc/certs/cacert.pem`，原列表中不包含此路径，导致 HTTPS 请求失败。

### 0003-ohos-native-build-support.patch（新增 + 合并 + 修复）

**改动性质**：最初在 commit `5051692` 中创建（792 行），后在 commit `85a2b1c` 中合并了原 0004 patch 的交叉编译修复（+27 行），后在 commits `f9177ad` + `300c20f` + `edb6fc0` 中修复 patch 格式问题，最终 807 行。

该 patch 修改 10 个文件，涵盖 5 大类改动：

#### (1) Bootstrap 平台识别 — `src/bootstrap/bootstrap.py`

使 Rust bootstrap 能识别 HarmonyOS 系统，支持在 OHOS 设备上原生构建：

```python
# kernel 检测：将 HarmonyOS 映射为 unknown-linux-ohos
elif kernel == "Linux" or kernel == "HarmonyOS":
    ostype = require(["uname", "-o"], exit=required)
    if ostype == "Android":
        kernel = "linux-android"
    elif kernel == "HarmonyOS":
        kernel = "unknown-linux-ohos"    # 新增
    else:
        ...

# 二进制兼容性检测：允许 HarmonyOS 运行 Linux 二进制
if ostype not in ("Linux", "HarmonyOS"):  # 原为 != "Linux"
    return False
```

#### (2) Stage0 std 构建去重 — `src/bootstrap/src/bin/rustc.rs` + `src/bootstrap/src/core/build_steps/test.rs`

**问题**：stage 0 的 sysroot 包含预编译的 std（core、alloc 等），从源码构建 std 会产生重复 lang items。

**方案**：借用 Miri 测试机制——在 stage 0 构建非测试目标时，将 `lib.rs` 替换为 `lib.miri.rs`（re-export sysroot crate），同时将 `--extern` 路径替换为 sysroot 的 `.rmeta` 文件。

- `rustc.rs`：新增 ~110 行逻辑，通过环境变量 `STAGE0_REPLACE_LIBRS_IF_NOT_TEST` 触发
- `test.rs`：当 `build_compiler.stage == 0` 时设置该环境变量

#### (3) 下载镜像加速 — `src/stage0`（已在 commit `f9177ad` 中移除）

> **注意**：此改动最初将 bootstrap 下载源改为 USTC 镜像，但在 CI 环境中 GitHub Actions runner（海外）被 USTC 镜像返回 403。已在 commit `f9177ad` 中从 patch 移除，恢复为官方源。镜像加速改由 build.sh 的 `USE_MIRROR` 环境变量在运行时通过 `sed` 覆盖实现。

#### (4) f128 浮点支持 — `compiler/rustc_codegen_llvm/src/llvm_util.rs` + `library/std/src/num/f128.rs`

- `llvm_util.rs`：OHOS 使用 musl libc，缺少 f128 数学符号，在 `has_reliable_f128_math` 判断中加入 `Env::Ohos` 返回 `false`
- `f128.rs`：36 处 doctest 的 `#[cfg]` 条件从 `target_has_reliable_f128_math` 改为 `all(target_has_reliable_f128_math, not(target_env = "ohos"))`，跳过 OHOS 上的 f128 doctest

#### (5) 标准库测试适配 — `library/std/src/fs/tests.rs` + `library/std/src/os/unix/fs/tests.rs` + `library/std/src/os/unix/net/tests.rs`

针对 OHOS 系统特性调整测试：

| 文件 | 测试 | OHOS 行为 | 适配方式 |
|------|------|-----------|----------|
| `fs/tests.rs` | `set_permissions` | hmmac 覆盖目录权限为 `0o2771` | 修改断言期望值 |
| `fs/tests.rs` | `copy_file_preserves_perm_bits` | hmmac 强制组写，阻止 readonly | 断言 mode 为 `0o660` |
| `fs/tests.rs` | `chmod_works` / `fchmod_works` | 同上 | 同上 |
| `fs/tests.rs` | `links_work` / `symlink_hard_link` | hmdfs 不支持硬链接 | `#[cfg_attr(target_env = "ohos", ignore)]` |
| `os/unix/fs/tests.rs` | `test_mkfifo` | hmdfs 不支持 mkfifo | `ignore` |
| `os/unix/net/tests.rs` | 16 个 Unix socket 测试 | hmdfs 不支持 Unix socket 路径绑定 | `ignore` |
| `os/unix/net/tests.rs` | `test_abstract_datagram_connect_addr` | OHOS 内核 abstract socket sender 地址与 Linux 不同 | `ignore` |

#### (6) 交叉编译修复（原 0004，已合并）— `src/bootstrap/src/core/build_steps/doc.rs` + `src/bootstrap/src/core/build_steps/dist.rs`

**问题**：在 x86_64 上交叉编译 aarch64-unknown-linux-ohos 时，两个构建步骤会生成 aarch64 二进制并在 x86_64 上执行，导致失败。

**修复**：

- `doc.rs` — `ErrorIndex::make_run`：当 `run.target != run.builder.host_target` 时跳过 error_index_generator（该工具标记为 `IS_HOST`，会为目标平台编译但需在宿主机执行）
- `dist.rs` — `Extended::run`：当 `target != builder.host_target` 时跳过 `JsonDocs` 组件（`target_compiler` 是 aarch64 stage2，无法在 x86_64 上运行生成 JSON 文档）

#### (7) Patch 格式修复（commits `300c20f` + `edb6fc0`）

在 CI 全新构建（`CLEAN_BUILD=true`）时暴露的三个 patch 格式问题（本地增量构建因 `PATCH_MARKER` 跳过 patch 应用而未发现）：

| 问题 | 原因 | 修复 |
|------|------|------|
| f128.rs 与 doc.rs 之间缺少换行符 | commit `85a2b1c` 合并 0004 时，原 0003 文件无尾部换行，新内容直接拼接在同一行 | 添加换行符分隔 |
| doc.rs hunk 行数统计错误 | `@@ -1239,6 +1239,10 @@` 中 new count 应为 12（6 context + 6 added），原为 10 | 修正为 `+1239,12` |
| dist.rs hunk 行数统计错误 | `@@ -1879,8 +1879,11 @@` 中 old count 应为 4（3 context + 1 removed），new count 应为 8（3 context + 5 added），原为 8/11 | 修正为 `-1879,4 +1879,8` |

### 0004-asan-ohos-39bit-va-fix.patch（新增，commit `e6119dc`，重建于 2026-08-14）

**目的**：修复 ASAN/HWASAN 在 OHOS 39-bit VA 上的 allocator size 问题，同时修复 sysinfo 和 clang sysroot 路径。

**背景**：OHOS aarch64 使用 39-bit 虚拟地址空间（512GB 用户空间），而 ASAN 默认使用 4TB allocator（`kAllocatorSize=0x40000000000`），超出 OHOS 地址空间限制导致崩溃。

**改动**（5 个文件）：
1. `compiler/rt/cmake/configure_asan.cmake`：ASAN 使用 128GB allocator（`kAllocatorSize=0x2000000000`）
2. `compiler/rt/cmake/configure_hwasan.cmake`：HWASAN 跳过 4TB，fall through 到 128GB 路径
3. `compiler/rt/lib/sanitizer_common/sanitizer_platform.h`：添加 `SANITIZER_OHOS` 宏定义
4. `compiler/rt/lib/sanitizer_common/sanitizer_platform_limits_posix.cpp`：修复 OHOS sysinfo 调用
5. `compiler/rustc_llvm/llvm.rs`：修复 clang sysroot 路径

> **注意**：libffi-sys config.sub 的 ohos 支持（原 commit `b0aaf05`）已合并进 0003 patch。
+ | fiwix* | mlibc* | cos* | mbr* | ironclad* | ohos* )

# 第 1832 行：kernel-OS 组合检查添加 linux-ohos*-
- | linux-relibc*- | linux-uclibc*- )
+ | linux-relibc*- | linux-uclibc*- | linux-ohos*- )
```

---

## 三、构建脚本改动

### 3.1 build.sh（commit `d662428` + `478b884` + `f9177ad` + `69c87fc` + `5a73f34` + `91b6740` + `b0aaf05` + `8ce1746`）

#### commit `d662428` — 重构构建脚本

- **移除后签名步骤**：删除 build.sh 中调用 `binary-sign-tool` 对 ELF 文件逐一签名的代码（~60 行），以及打包 `binary-sign-tool` 到产物的步骤
- **添加 checksum 更新**：patch 修改了 `vendor/openssl-probe-*/src/lib.rs`，需要重置 `.cargo-checksum.json` 的 `files` 字段为 `{}`，否则 cargo 校验失败
- **patch 应用改为 `--forward`**：`patch -p1` → `patch -p1 --forward`，避免已应用的 patch 产生交互式提示
- **添加 `RUSTUP_DIST_SERVER`**：支持通过环境变量配置 bootstrap 下载镜像

#### commit `478b884` — 全面升级构建脚本

**新增组件**：
- 移除 `--disable-docs`，启用 rust-docs（HTML + JSON）生成
- `--tools=` 列表添加 `llvm-tools` 和 `miri`
- 添加附加组件包安装循环：`rust-src`、`rust-docs`、`llvm-tools`、`miri`

**新增配置项**：
- `--enable-sccache`：启用 sccache C/C++ 编译缓存
- `--set dist.vendor=false`：跳过 `cargo vendor`（stage0 cargo 无法在受限网络环境更新 crates.io index）
- `CLEAN_BUILD` 选项（默认 `false`）：支持增量编译 vs 全量清理

**环境检测与自动配置**：
- 自动检测 OHOS SDK（`/opt/ohos-sdk/native`）、OpenSSL（`/opt/ohos-openssl/prelude/arm64-v8a`）、clang wrappers
- 缺失时自动调用对应脚本安装
- 设置交叉编译环境变量：`CC_*`、`CXX_*`、`AR_*`、`CARGO_TARGET_*_LINKER`、`*_OPENSSL_*`

**缓存配置**：
- `SCCACHE_DIR`、`CCACHE_DIR` 目录创建
- `ccache --set-config=max_size=5G`、`compression=true`
- `CARGO_NET_RETRY=10`、`CARGO_NET_TIMEOUT=120` 网络重试

**增量构建支持**：
- `PATCH_MARKER` 文件标记 patch 是否已应用，避免重复应用
- 源码已存在时跳过下载
- `rm -f bootstrap.toml` 确保配置文件重新生成

**Bug 修复**：
- clang wrapper sysroot 路径：`/opt/ohos-sdk/ohos/native/sysroot` → `/opt/ohos-sdk/native/sysroot`

#### commit `f9177ad` — CI 下载源修复 + USE_MIRROR 机制

**问题**：CI 中 GitHub Actions runner（海外）访问 USTC 镜像下载 Rust 源码时返回 403 Forbidden。

**修复**：
- 新增 `USE_MIRROR` 环境变量（默认不设置）：
  - `USE_MIRROR=true`：使用 USTC 镜像（本地国内构建加速）
  - 未设置：使用官方源 `static.rust-lang.org`（CI 海外环境）
- 源码下载改为多源 fallback 逻辑：根据 `USE_MIRROR` 决定优先顺序，依次尝试直到成功
- `RUSTUP_DIST_SERVER` 根据 `USE_MIRROR` 动态设置
- patch 应用后，若 `USE_MIRROR=true`，通过 `sed` 将 `src/stage0` 中的官方 URL 替换为 USTC 镜像 URL
- CI 不设置 `USE_MIRROR`，默认走官方源

#### commit `69c87fc` — POSIX sh 兼容性修复

**问题**：build.sh shebang 为 `#!/bin/sh`（dash），但 `f9177ad` 中使用了 bash 数组语法 `RUST_SRC_URLS=(...)`，导致 `Syntax error: "(" unexpected`。

**修复**：将数组改为空格分隔字符串遍历，兼容 POSIX sh。

#### commit `5a73f34` — 移除冗余静态链接参数（main 分支）

OpenSSL 使用 `no-shared` 编译只产生 `.a` 静态库，链接器自动使用静态链接，无需额外参数。移除三项冗余配置：

| 移除项 | 位置 | 原因 |
|--------|------|------|
| `AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_STATIC=1` | build.sh 环境变量 + Dockerfile ENV | 无动态库时自动静态链接 |
| `--enable-cargo-native-static` | configure 参数 | 同上 |
| `--set rust.rpath=true` | configure 参数 | 无动态库时不需要 rpath |

同时将 `.gitignore` 中 `docs/CHANGELOG.md` 改为 `docs/`（忽略整个 docs 目录）。

#### commit `91b6740` — nightly channel 支持（nightly 分支）

**新增变量**：

```sh
CHANNEL=${CHANNEL:-nightly}    # 默认 nightly（nightly 分支）
# stable: "1.95.0", nightly: "1.95.0-nightly"
if [ "$CHANNEL" = "stable" ]; then
    RELEASE="$RUST_VERSION"
else
    RELEASE="$RUST_VERSION-$CHANNEL"
fi
```

**configure 新增**：`--release-channel=$CHANNEL`，使 bootstrap 按指定 channel 构建。nightly channel 使 `unstable_features()` 返回 `true`，解锁 miri dist 打包。

**文件名变量替换**：所有 `$RUST_VERSION` 替换为 `$RELEASE`（dist tarball 名、安装目录、最终产物名），使 nightly 产物命名为 `rust-nightly-*` 而非 `rust-1.95.0-*`。

#### commit `b0aaf05` — libffi-sys checksum + patch 容错

配合 0004 patch 的三项 build.sh 改动：

- checksum 重置列表添加 `vendor/libffi-sys-4.1.0`（patch 修改了其 config.sub）
- patch 命令添加 `|| true`：增量构建时 patch 可能已应用，避免 `--forward` 仍返回非零退出码导致脚本中断
- configure 添加 `--set rust.deny-warnings=false`：安全网，防止 vendor crate 中的 warning 升级为 error 中断构建

#### commit `8ce1746` — PKG_VERSION 变量

**问题**：nightly channel 下 `x.py dist` 产出的 tarball 命名用 channel 名（如 `rust-nightly-*`），而非 release 版本字符串（`rust-1.95.0-nightly-*`）。commit `91b6740` 中用 `$RELEASE`（= `1.95.0-nightly`）匹配 tarball 名，导致 build.sh 安装阶段找不到文件。

**修复**：新增 `PKG_VERSION` 变量：

```sh
if [ "$CHANNEL" = "stable" ]; then
    RELEASE="$RUST_VERSION"        # "1.95.0"
    PKG_VERSION="$RUST_VERSION"    # "1.95.0"
else
    RELEASE="$RUST_VERSION-$CHANNEL"  # "1.95.0-nightly"（用于 configure）
    PKG_VERSION="$CHANNEL"            # "nightly"（用于 tarball 文件名）
fi
```

所有 tarball 文件名引用从 `$RELEASE` 改为 `$PKG_VERSION`，与 `x.py dist` 的实际输出一致。

### 3.2 ohos-openssl.sh（commit `dd7cc23`）

**原方案**：从 `github.com/ohos-rs/ohos-openssl` 下载预编译包。

**新方案**：从 OpenSSL 官方源码交叉编译静态库：
- 下载 `openssl-3.6.1.tar.gz` 源码
- 使用 OHOS clang wrapper 交叉编译：`./Configure no-shared no-tests linux-aarch64 --prefix=... CC=... AR=... CFLAGS="-fPIC"`
- `make -j$(nproc) && make install_sw`
- 生成 `libssl.a` / `libcrypto.a` 静态库

### 3.3 Dockerfile（commit `b927db0` + `9789e37` + `5a73f34` + `91b6740`）

#### commit `b927db0` — 重排构建顺序

- **添加 `perl` 依赖**：OpenSSL 编译需要 perl
- **重排 clang wrapper 顺序**：clang wrappers 必须在 `ohos-openssl.sh` 之前安装，因为 OpenSSL 交叉编译依赖它们
  - 原顺序：SDK → OpenSSL → clang wrappers
  - 新顺序：SDK → clang wrappers → OpenSSL

#### commit `9789e37` — 添加 ccache

- apt 安装列表添加 `ccache`

#### commit `5a73f34` — 移除冗余 ENV

移除 `ENV AARCH64_UNKNOWN_LINUX_OHOS_OPENSSL_STATIC=1`（静态链接由 `no-shared` 自动完成）。

#### commit `91b6740` — nightly ENV

新增 `ENV CHANNEL=nightly`，使 Docker 容器内 build.sh 默认使用 nightly channel。

### 3.4 clang wrapper 修复（commit `478b884` + `7041db1`）

#### commit `478b884` — sysroot 路径修复

`x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh` 和 `clang++.sh`：

```diff
-  --sysroot=/opt/ohos-sdk/ohos/native/sysroot \
+  --sysroot=/opt/ohos-sdk/native/sysroot \
```

修复了 sysroot 路径，与 `ohos-sdk.sh` 中的实际安装路径一致。

#### commit `7041db1` — 链接 libclang_rt.builtins（nightly 分支）

**问题**：miri 依赖 libffi，libffi 使用 JIT 闭包，在 aarch64 上需要 `__clear_cache` 函数刷新指令缓存。该函数由 compiler-rt（`libclang_rt.builtins.a`）提供，但 Rust 使用 `-nodefaultlibs` 排除了默认库搜索路径，导致链接 miri 时报 `undefined reference to '__clear_cache'`。

**修复**：在两个 clang wrapper 脚本中添加 compiler-rt 库搜索路径和链接参数：

```sh
# aarch64-unknown-linux-ohos-clang.sh 和 clang++.sh
exec /opt/ohos-sdk/native/llvm/bin/clang \
  -target aarch64-linux-ohos \
  --sysroot=/opt/ohos-sdk/native/sysroot \
  -D__MUSL__ \
  -L/opt/ohos-sdk/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos \  # 新增
  "$@" \
  -lclang_rt.builtins                                                  # 新增
```

`-L` 指定 compiler-rt 所在目录，`-lclang_rt.builtins` 链接 `libclang_rt.builtins.a`（提供 `__clear_cache` 符号）。放在 `"$@"` 之后确保不影响用户传入的参数优先级。

---

## 四、CI 流水线改动（commit `9789e37` + `91b6740` + `d142354`）

### 新增缓存层

| 缓存 | 路径 | Key 策略 | 作用 |
|------|------|----------|------|
| Docker layers | `/tmp/.buildx-cache` | hash(Dockerfile + scripts/*.sh) | 缓存 SDK/OpenSSL/sccache 安装层 |
| sccache | `.sccache/` | `sccache-{version}-{hash(patches)}` | 跨 CI 运行持久化 C/C++ 编译缓存 |
| ccache | `.ccache/` | `ccache-{version}-{hash(patches)}` | 备用 C/C++ 编译缓存 |

### 新增选项

- `clean_build` 手动触发输入（默认 `true`）：控制是否全量清理重建
- `SCCACHE_CACHE_SIZE=5G`：限制 sccache 缓存大小
- `timeout-minutes: 360`：6 小时超时防止挂死
- sccache 优雅关闭步骤（`if: always()`）

### 清理

- 移除注释掉的 arm64 job（保持文件整洁）

### nightly 分支 CI 支持（commit `91b6740` + `d142354`）

#### commit `91b6740` — nightly 分支触发 + channel 自动检测

- **触发分支**：`push.branches` 从 `[ "main" ]` 扩展为 `[ "main", "nightly" ]`
- **channel 自动检测**：根据 `github.ref_name` 判断——`nightly` 分支 → `CHANNEL=nightly`，其他 → `CHANNEL=stable`
- **release 字符串**：`stable` → `1.95.0`，`nightly` → `1.95.0-nightly`
- **传递 CHANNEL**：`docker run` 添加 `-e CHANNEL="${{ steps.version.outputs.channel }}"`
- **产物命名**：artifact name 从 `rust-{rust_version}-*-cross` 改为 `rust-{release}-*-cross`

#### commit `d142354` — pkg_version 产物命名修正

**问题**：commit `91b6740` 中 CI 用 `$RELEASE`（`1.95.0-nightly`）命名 artifact，但 build.sh 在 commit `8ce1746` 后用 `$PKG_VERSION`（`nightly`）命名 tarball。CI 找不到 `rust-1.95.0-nightly-*.tar.gz`，只找到 `rust-nightly-*.tar.gz`。

**修复**：CI workflow 新增 `pkg_version` output（与 build.sh 的 `PKG_VERSION` 逻辑一致），所有 artifact 上传步骤的 path 和 name 从 `release` 改为 `pkg_version`：

```yaml
# 修正前
name: rust-${{ steps.version.outputs.release }}-aarch64-unknown-linux-ohos-cross
# 修正后
name: rust-${{ steps.version.outputs.pkg_version }}-aarch64-unknown-linux-ohos-cross
```

---

## 五、最终构建产物

### stable channel（main 分支）

构建成功后产出 15 个 dist tarball：

| 产物 | 大小 | 说明 |
|------|------|------|
| `rust-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 373M | **全家桶**（rustc + std + cargo + tools） |
| `rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 100M | 编译器 |
| `rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 39M | 标准库 |
| `rustc-dev-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 208M | 编译器开发文件 |
| `rust-src-1.95.0.tar.gz` | 5.6M | 标准库源码 |
| `rust-docs-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 78M | HTML 文档 |
| `rust-docs-json-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 8.7M | JSON 文档 |
| `llvm-tools-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 121M | LLVM 工具 |
| `cargo-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 16M | 包管理器 |
| `rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 16M | IDE 语言服务器 |
| `rustfmt-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 2.9M | 格式化工具 |
| `clippy-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 5.5M | 静态分析工具 |
| `rust-dev-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 709M | 开发套件 |
| `rustc-1.95.0-src.tar.gz` | 214M | 源码包 |
| `rustc-1.95.0-src-gpl.tar.gz` | 214M | GPL 源码包 |

CI 上传产物：
- `rust-1.95.0-aarch64-unknown-linux-ohos-cross`（369M）— 全家桶打包
- `rust-analyzer-1.95.0-aarch64-unknown-linux-ohos-cross`（15M）— 独立 rust-analyzer

### nightly channel（nightly 分支）

构建成功后产出 16 个 dist tarball（比 stable 多 miri）：

| 产物 | 大小 | 说明 |
|------|------|------|
| `rust-nightly-aarch64-unknown-linux-ohos.tar.gz` | 376M | **全家桶**（rustc + std + cargo + tools + miri） |
| `rustc-nightly-aarch64-unknown-linux-ohos.tar.gz` | 100M | 编译器 |
| `rust-std-nightly-aarch64-unknown-linux-ohos.tar.gz` | 39M | 标准库 |
| `rustc-dev-nightly-aarch64-unknown-linux-ohos.tar.gz` | 208M | 编译器开发文件 |
| `rust-src-nightly.tar.gz` | 5.6M | 标准库源码 |
| `rust-docs-nightly-aarch64-unknown-linux-ohos.tar.gz` | 78M | HTML 文档 |
| `rust-docs-json-nightly-aarch64-unknown-linux-ohos.tar.gz` | 8.7M | JSON 文档 |
| `llvm-tools-nightly-aarch64-unknown-linux-ohos.tar.gz` | 121M | LLVM 工具 |
| `cargo-nightly-aarch64-unknown-linux-ohos.tar.gz` | 16M | 包管理器 |
| `rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.gz` | 16M | IDE 语言服务器 |
| `rustfmt-nightly-aarch64-unknown-linux-ohos.tar.gz` | 2.9M | 格式化工具 |
| `clippy-nightly-aarch64-unknown-linux-ohos.tar.gz` | 5.5M | 静态分析工具 |
| `miri-nightly-aarch64-unknown-linux-ohos.tar.gz` | 2.5M | **UB 检测工具（nightly 独有）** |
| `rust-dev-nightly-aarch64-unknown-linux-ohos.tar.gz` | 709M | 开发套件 |
| `rustc-nightly-src.tar.gz` | 214M | 源码包 |
| `rustc-nightly-src-gpl.tar.gz` | 214M | GPL 源码包 |

CI 上传产物（预期）：
- `rust-nightly-aarch64-unknown-linux-ohos-cross`（~376M）— 全家桶打包
- `rust-analyzer-nightly-aarch64-unknown-linux-ohos-cross`（~16M）— 独立 rust-analyzer

---

## 六、文件变更清单

| 文件 | 改动提交 | 说明 |
|------|----------|------|
| `patches/1.95.0/0001-rustc-ohos-auto-sign-fix.patch` | `3279a91` | 重写：后签名 → 链接时签名 |
| `patches/1.95.0/0002-openssl-probe-cert-fix.patch` | `510e572` | 新增：证书路径修复 |
| `patches/1.95.0/0003-ohos-native-build-support.patch` | `5051692` + `85a2b1c` + `f9177ad` + `300c20f` + `edb6fc0` + `b0aaf05` | 新增 + 合并交叉编译修复 + 移除 stage0 镜像 + 修复格式 + 合并 libffi config.sub ohos 支持 |
| `patches/1.95.0/0004-asan-ohos-39bit-va-fix.patch` | `e6119dc`（重建 2026-08-14） | **新增**：ASAN/HWASAN 39-bit VA 修复 + sysinfo + clang sysroot（5 文件） |
| `x86_64/build.sh` | `d662428` + `478b884` + `f9177ad` + `69c87fc` + `5a73f34` + `91b6740` + `b0aaf05` + `8ce1746` | 重构 + 全面升级 + USE_MIRROR + POSIX sh + 移除冗余静态链接 + nightly channel + libffi checksum + PKG_VERSION |
| `x86_64/Dockerfile` | `b927db0` + `9789e37` + `5a73f34` + `91b6740` | 重排依赖顺序 + ccache + 移除 OPENSSL_STATIC + CHANNEL=nightly |
| `x86_64/scripts/ohos-openssl.sh` | `dd7cc23` | 改为源码交叉编译 |
| `x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh` | `478b884` + `7041db1` | 修复 sysroot 路径 + 链接 libclang_rt.builtins |
| `x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh` | `478b884` + `7041db1` | 修复 sysroot 路径 + 链接 libclang_rt.builtins |
| `.github/workflows/ci.yml` | `9789e37` + `91b6740` + `d142354` | 缓存层 + nightly 触发 + channel 检测 + pkg_version 命名 |
| `.gitignore` | `478b884` + `43ebc57` + `5a73f34` | 新增 + 忽略 docs/CHANGELOG.md → 忽略 docs/ |
| `start_build.sh` | `478b884` + `f9177ad` | 新增 + 添加 USE_MIRROR=true |

---

## 七、ASAN 0004 Patch 重建（2026-08-14）

> 分支：`main` + `nightly`
> 涉及仓库：`ohos-rust`、`rustup-ohos`、`homebrew-ohos`

### 根因

2026-08-13 构建 stable + nightly 时，`x86_64/build.sh` 第 303 行的 `.patches-applied` 标记文件（8月6日创建）导致 patch 步骤被跳过。0004 patch 在 16:06 应用到源码树，但 ASAN runtime 在 14:34 编译（patch 之前），导致 `.a` 文件不含 39-bit VA 修复。

### 修复步骤

1. 删除 `.patches-applied` 标记文件
2. 删除 `build/aarch64-unknown-linux-ohos/native/sanitizers/` 缓存
3. 删除旧 dist 产物（stable + nightly + rust-analyzer + miri）
4. 重新构建 stable：`CHANNEL=stable ./x86_64/build.sh`
5. 重新构建 nightly：`CHANNEL=nightly ./x86_64/build.sh`
6. 验证 ASAN runtime 含 128GB allocator（`0x2000000000` = 39-bit VA fix）
7. 重新打包 rust-analyzer `.tar.xz`（注入 librustc_driver + .codesign 验证）
8. 重新生成 manifest + 115 个 `.sha256` 文件
9. 上传 135 个文件到 gitcode（dist-1.95.0: 60, dist-nightly: 64, dist: 11）
10. 更新 homebrew 4 个 formula 的 SHA256
11. 推送：`rustup-ohos` `fa4ac60`、`homebrew-ohos` `04b2c9c`

### arm64/build.sh 清理

移除 `binary-sign-tool` 后签名方案，改为 `-Wl,--code-sign` 链接器标志（与 x86_64 一致）：
- 删除 lines 306-338 的 `binary-sign-tool` 签名块
- 删除 line 371 的 `binary-sign-tool` 复制步骤
- 在 clang/clang++ wrapper 脚本中添加 `-Wl,--code-sign` 参数

### 验证

- `libclang_rt.asan-aarch64.a` 构建时间 14:55（patch 14:54 应用之后）
- 二进制含 `0x2000000000`（128GB）allocator size，确认 39-bit VA fix
- rust-std tarball 含 `librustc-stable_rt.asan.a` + `librustc-stable_rt.hwasan.a`
- rust-analyzer `.tar.xz` 的 `.codesign` 节区验证通过
- gitcode 下载验证：`rust-docs-json-1.95.0` SHA-256 匹配
