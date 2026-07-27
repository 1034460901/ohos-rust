# OHOS Rust 1.95.0 交叉编译工具链 — 变更说明

> 分支：`refactor/code-sign-linker-approach` → `main`
> 时间：2026-07-25 ~ 2026-07-27
> 涉及提交：11 个（含 2 个 Merge PR）

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

---

## 二、Patch 详细说明

当前 `patches/1.95.0/` 目录下共 3 个 patch 文件，按序号顺序应用。

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

### 0003-ohos-native-build-support.patch（新增 + 合并）

**改动性质**：最初在 commit `5051692` 中创建（792 行），后在 commit `85a2b1c` 中合并了原 0004 patch 的交叉编译修复（+27 行），最终 818 行。

该 patch 修改 9 个文件，涵盖 5 大类改动：

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

#### (3) 下载镜像加速 — `src/stage0`

将 bootstrap 下载源从官方服务器改为 USTC 镜像：

```
# 修改前
dist_server=https://static.rust-lang.org
artifacts_server=https://ci-artifacts.rust-lang.org/rustc-builds

# 修改后
dist_server=https://mirrors.ustc.edu.cn/rust-static
artifacts_server=https://mirrors.ustc.edu.cn/rust-static/rustc-builds
```

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

---

## 三、构建脚本改动

### 3.1 build.sh（commit `d662428` + `478b884`）

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

### 3.2 ohos-openssl.sh（commit `dd7cc23`）

**原方案**：从 `github.com/ohos-rs/ohos-openssl` 下载预编译包。

**新方案**：从 OpenSSL 官方源码交叉编译静态库：
- 下载 `openssl-3.6.1.tar.gz` 源码
- 使用 OHOS clang wrapper 交叉编译：`./Configure no-shared no-tests linux-aarch64 --prefix=... CC=... AR=... CFLAGS="-fPIC"`
- `make -j$(nproc) && make install_sw`
- 生成 `libssl.a` / `libcrypto.a` 静态库

### 3.3 Dockerfile（commit `b927db0` + `9789e37`）

#### commit `b927db0` — 重排构建顺序

- **添加 `perl` 依赖**：OpenSSL 编译需要 perl
- **重排 clang wrapper 顺序**：clang wrappers 必须在 `ohos-openssl.sh` 之前安装，因为 OpenSSL 交叉编译依赖它们
  - 原顺序：SDK → OpenSSL → clang wrappers
  - 新顺序：SDK → clang wrappers → OpenSSL

#### commit `9789e37` — 添加 ccache

- apt 安装列表添加 `ccache`

### 3.4 clang wrapper 修复（commit `478b884`）

`x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh` 和 `clang++.sh`：

```diff
-  --sysroot=/opt/ohos-sdk/ohos/native/sysroot \
+  --sysroot=/opt/ohos-sdk/native/sysroot \
```

修复了 sysroot 路径，与 `ohos-sdk.sh` 中的实际安装路径一致。

---

## 四、CI 流水线改动（commit `9789e37`）

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

---

## 五、最终构建产物

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

---

## 六、文件变更清单

| 文件 | 改动提交 | 说明 |
|------|----------|------|
| `patches/1.95.0/0001-rustc-ohos-auto-sign-fix.patch` | `3279a91` | 重写：后签名 → 链接时签名 |
| `patches/1.95.0/0002-openssl-probe-cert-fix.patch` | `510e572` | 新增：证书路径修复 |
| `patches/1.95.0/0003-ohos-native-build-support.patch` | `5051692` + `85a2b1c` | 新增：OHOS 原生构建支持 + 交叉编译修复 |
| `x86_64/build.sh` | `d662428` + `478b884` | 重构 + 全面升级 |
| `x86_64/Dockerfile` | `b927db0` + `9789e37` | 重排依赖顺序 + 添加 ccache |
| `x86_64/scripts/ohos-openssl.sh` | `dd7cc23` | 改为源码交叉编译 |
| `x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang.sh` | `478b884` | 修复 sysroot 路径 |
| `x86_64/scripts/ohos/aarch64-unknown-linux-ohos-clang++.sh` | `478b884` | 修复 sysroot 路径 |
| `.github/workflows/ci.yml` | `9789e37` | 添加缓存层 + clean_build 选项 |
| `.gitignore` | `478b884` | 新增：忽略构建产物和缓存 |
| `start_build.sh` | `478b884` | 新增：本地后台构建辅助脚本 |
