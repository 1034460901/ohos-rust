# OHOS Rust 1.95.0 交叉编译工具链 — 构建报告

> 仓库：`https://github.com/1034460901/ohos-rust`
> 分支：`main`（stable） + `nightly`（nightly）
> 最新提交：`de5961d`（main） / `7424783`（nightly）
> 日期：2026-08-14（ASAN 0004 patch 重建）

---

## 一、构建结果总览

### stable channel（main 分支）

| 构建方式 | 状态 | 耗时 | 产物大小 |
|----------|:----:|------|----------|
| CI（GitHub Actions） | ✅ 成功 | ~4h15m | rust 369M / rust-analyzer 15M |
| 本地（WSL 增量） | ✅ 成功 | ~1h13m | rust 375M / rust-analyzer 16M |

dist 阶段产出 15 个 tarball（不含 miri）。

### nightly channel（nightly 分支）

| 构建方式 | 状态 | 耗时 | 产物大小 |
|----------|:----:|------|----------|
| CI（GitHub Actions） | ⏳ 进行中 | — | — |
| 本地（WSL 增量） | ✅ 成功 | ~18m50s（dist 阶段） | rust 376M / rust-analyzer 16M |

dist 阶段产出 16 个 tarball（含 miri 2.5M）。

---

## 二、Stable CI 构建详情

- **Run ID**：`30336040340`
- **Job ID**：`89954151329`
- **分支**：`main`
- **提交**：`5a73f34`（build: align with reference script, remove redundant static linking params）
- **开始时间**：2026-07-28 14:48 CST（`06:48:10Z`）
- **结束时间**：2026-07-28 19:03 CST（`11:03:00Z`）
- **结论**：`success`

### CI 产物

| 产物 | 大小 | 说明 |
|------|------|------|
| `rust-1.95.0-aarch64-unknown-linux-ohos-cross` | 369M | 全家桶：rustc + cargo + rust-src + rust-docs + llvm-tools + rust-analyzer |
| `rust-analyzer-1.95.0-aarch64-unknown-linux-ohos-cross` | 15M | 独立 rust-analyzer |

### CI 步骤摘要

| 步骤 | 名称 | 结果 |
|------|------|:----:|
| 6 | Build Docker image with cache | ✅ |
| 8 | Cache sccache | ✅ |
| 9 | Cache ccache | ✅ |
| 10 | Build | ✅ |
| 12 | Upload toolchain artifact | ✅ |
| 13 | Upload rust-analyzer artifact | ✅ |

---

## 三、Nightly CI 构建详情

nightly 分支有 5 个提交（`91b6740` → `d142354`），逐步解决 nightly channel 构建中的三个问题。CI 触发了多个 run：

| Run ID | 提交 | 状态 | 说明 |
|--------|------|:----:|------|
| `30356174843` | `7041db1` | ⏳ 进行中 | 3 个修复（libffi + clang_rt + PKG_VERSION 未含），可能因 tarball 命名不匹配在安装步骤失败 |
| `30357711509` | `8ce1746` | ⏳ 进行中 | 4 个修复（含 PKG_VERSION），CI artifact 命名未修正 |
| `30359072122` | `d142354` | ⏳ 进行中 | **全部 5 个修复**，预期成功 |

> **注**：`91b6740`（首次 nightly 支持）和 `b0aaf05`（libffi 修复）的 CI run 未出现在列表中，可能因 CI workflow 文件在 `91b6740` 才添加 `nightly` 分支触发，GitHub 可能未及时识别。

### 预期 CI 产物（`d142354` 成功后）

| 产物 | 大小 | 说明 |
|------|------|------|
| `rust-nightly-aarch64-unknown-linux-ohos-cross` | ~376M | 全家桶：rustc + cargo + rust-src + rust-docs + llvm-tools + rust-analyzer + **miri** |
| `rust-analyzer-nightly-aarch64-unknown-linux-ohos-cross` | ~16M | 独立 rust-analyzer |

---

## 四、本地构建详情

### 4.1 Stable 本地构建

- **环境**：WSL Ubuntu 22.04，12 核 / 23GB RAM
- **命令**：`CLEAN_BUILD=false USE_MIRROR=false sh x86_64/build.sh`
- **开始时间**：2026-07-28 00:10 CST
- **结束时间**：2026-07-28 01:23 CST
- **模式**：增量构建（`CLEAN_BUILD=false`，复用 `build/` 目录）

### 4.2 Nightly 本地构建

- **环境**：WSL Ubuntu 22.04，12 核 / 23GB RAM
- **命令**：`CHANNEL=nightly CLEAN_BUILD=false USE_MIRROR=false sh x86_64/build.sh`
- **dist 阶段耗时**：~18m50s（19:47 → 20:06 CST）
- **模式**：增量构建（复用 stable 构建的 `build/` 目录，仅重新编译 channel 相关部分）
- **结果**：✅ 成功，产出 16 个 dist tarball（含 miri）

### 本地产物

| 产物 | stable | nightly |
|------|--------|---------|
| `rust-*-aarch64-unknown-linux-ohos.tar.gz` | 375M | 376M |
| `rust-analyzer-*-aarch64-unknown-linux-ohos.tar.gz` | 16M | 16M |
| `miri-*-aarch64-unknown-linux-ohos.tar.gz` | — | 2.5M |

---

## 五、Dist 阶段产物清单

### Stable（15 个 tarball）

| # | tarball | 说明 |
|---|---------|------|
| 1 | `cargo-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | Cargo 包管理器 |
| 2 | `clippy-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | Clippy linter |
| 3 | `llvm-tools-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | LLVM 工具链 |
| 4 | `rust-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 全家桶打包 |
| 5 | `rust-analyzer-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | rust-analyzer |
| 6 | `rust-dev-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 开发组件 |
| 7 | `rust-docs-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 文档 |
| 8 | `rust-docs-json-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 文档（JSON） |
| 9 | `rust-src-1.95.0.tar.gz` | 标准库源码 |
| 10 | `rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 标准库 |
| 11 | `rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 编译器 |
| 12 | `rustc-1.95.0-src-gpl.tar.gz` | 编译器源码（GPL） |
| 13 | `rustc-1.95.0-src.tar.gz` | 编译器源码 |
| 14 | `rustc-dev-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 编译器开发组件 |
| 15 | `rustfmt-1.95.0-aarch64-unknown-linux-ohos.tar.gz` | 代码格式化工具 |

### Nightly（16 个 tarball，比 stable 多 miri）

| # | tarball | 大小 | 说明 |
|---|---------|------|------|
| 1 | `cargo-nightly-aarch64-unknown-linux-ohos.tar.gz` | 16M | Cargo 包管理器 |
| 2 | `clippy-nightly-aarch64-unknown-linux-ohos.tar.gz` | 5.5M | Clippy linter |
| 3 | `llvm-tools-nightly-aarch64-unknown-linux-ohos.tar.gz` | 121M | LLVM 工具链 |
| 4 | `rust-nightly-aarch64-unknown-linux-ohos.tar.gz` | 376M | 全家桶打包 |
| 5 | `rust-analyzer-nightly-aarch64-unknown-linux-ohos.tar.gz` | 16M | rust-analyzer |
| 6 | `rust-dev-nightly-aarch64-unknown-linux-ohos.tar.gz` | 709M | 开发组件 |
| 7 | `rust-docs-nightly-aarch64-unknown-linux-ohos.tar.gz` | 78M | 文档 |
| 8 | `rust-docs-json-nightly-aarch64-unknown-linux-ohos.tar.gz` | 8.7M | 文档（JSON） |
| 9 | `rust-src-nightly.tar.gz` | 5.6M | 标准库源码 |
| 10 | `rust-std-nightly-aarch64-unknown-linux-ohos.tar.gz` | 39M | 标准库 |
| 11 | `rustc-nightly-aarch64-unknown-linux-ohos.tar.gz` | 100M | 编译器 |
| 12 | `rustc-nightly-src-gpl.tar.gz` | 214M | 编译器源码（GPL） |
| 13 | `rustc-nightly-src.tar.gz` | 214M | 编译器源码 |
| 14 | `rustc-dev-nightly-aarch64-unknown-linux-ohos.tar.gz` | 208M | 编译器开发组件 |
| 15 | `rustfmt-nightly-aarch64-unknown-linux-ohos.tar.gz` | 2.9M | 代码格式化工具 |
| **16** | **`miri-nightly-aarch64-unknown-linux-ohos.tar.gz`** | **2.5M** | **UB 检测工具（nightly 独有）** |

---

## 六、已安装组件

`build.sh` 将以下组件安装到最终产物包中：

| 组件 | stable CI | stable 本地 | nightly 本地 | 状态 |
|------|:--:|:--:|:--:|:----:|
| rustc | ✅ | ✅ | ✅ | 已安装 |
| cargo | ✅ | ✅ | ✅ | 已安装 |
| rust-src | ✅ | ✅ | ✅ | 已安装 |
| rust-docs | ✅ | ✅ | ✅ | 已安装 |
| llvm-tools | ✅ | ✅ | ✅ | 已安装 |
| rust-analyzer | ✅ | ✅ | ✅ | 已安装 |
| **miri** | ❌ | ❌ | ✅ | **stable 跳过 / nightly 已安装** |

### Stable 安装日志

```
--- 安装: rust-src-1.95.0.tar.gz ---
--- rust-src-1.95.0.tar.gz 安装完成 ---
--- 安装: rust-docs-1.95.0-aarch64-unknown-linux-ohos.tar.gz ---
--- rust-docs-1.95.0-aarch64-unknown-linux-ohos.tar.gz 安装完成 ---
--- 安装: llvm-tools-1.95.0-aarch64-unknown-linux-ohos.tar.gz ---
--- llvm-tools-1.95.0-aarch64-unknown-linux-ohos.tar.gz 安装完成 ---
--- 跳过 (未找到): miri-1.95.0-aarch64-unknown-linux-ohos.tar.gz ---
```

### Nightly 安装日志

```
--- 安装: rust-src-nightly.tar.gz ---
--- rust-src-nightly.tar.gz 安装完成 ---
--- 安装: rust-docs-nightly-aarch64-unknown-linux-ohos.tar.gz ---
--- rust-docs-nightly-aarch64-unknown-linux-ohos.tar.gz 安装完成 ---
--- 安装: llvm-tools-nightly-aarch64-unknown-linux-ohos.tar.gz ---
--- llvm-tools-nightly-aarch64-unknown-linux-ohos.tar.gz 安装完成 ---
--- 安装: miri-nightly-aarch64-unknown-linux-ohos.tar.gz ---
--- miri-nightly-aarch64-unknown-linux-ohos.tar.gz 安装完成 ---
```

---

## 七、Miri 构建问题与解决

### 7.1 Stable channel 不包含 miri（设计行为）

Miri 是 Rust 的 **nightly-only 工具**。Rust bootstrap 在 dist 阶段对 miri 有硬编码的 channel 门控检查，stable/beta channel 直接跳过 miri 的打包。

**门控代码**：`src/bootstrap/src/core/build_steps/dist.rs`

```rust
fn run(self, builder: &Builder<'_>) -> Option<GeneratedTarball> {
    if !builder.build.unstable_features() {
        return None;  // stable/beta channel 直接返回 None
    }
    // ...
}
```

**调用链**：

```
src/ci/channel = "stable"
  → unstable_features() 返回 false
    → dist.rs: return None
      → 不生成 miri dist tarball
```

这是 Rust 官方 bootstrap 的设计行为，非 bug。stable channel 不包含 miri 符合 Rust 官方一致性。

### 7.2 Nightly channel miri 构建问题与修复

切换到 nightly channel 后，miri 构建遇到两个问题，已分别修复：

#### 问题 1：libffi-sys config.sub 不识别 ohos

**现象**：`x.py dist` 编译 miri 时，其 C 依赖 libffi-sys v4.1.0 的 `config.sub` 报错：

```
checking build system type... Invalid configuration `aarch64-unknown-linux-ohos':
system `ohos' not recognized
```

**修复**：新增 `0004-libffi-config-sub-ohos.patch`，在 config.sub 的 OS 验证列表和 kernel-OS 组合检查中添加 `ohos*`。

#### 问题 2：`__clear_cache` 链接错误

**现象**：libffi 使用 JIT 闭包，在 aarch64 上需要 `__clear_cache` 函数（由 compiler-rt 提供）。Rust 使用 `-nodefaultlibs` 排除了默认库搜索路径，导致链接 miri 时报：

```
undefined reference to `__clear_cache'
```

**修复**：在 clang wrapper 脚本中添加 `-L/opt/ohos-sdk/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos` 和 `-lclang_rt.builtins`，使链接器能找到 `libclang_rt.builtins.a`。

#### 问题 3：Nightly tarball 命名不匹配

**现象**：nightly channel 下 `x.py dist` 产出的 tarball 用 channel 名命名（如 `rust-nightly-*`），但 build.sh 用 `$RELEASE`（`1.95.0-nightly`）匹配文件，导致安装阶段找不到 tarball。

**修复**：引入 `PKG_VERSION` 变量——stable 时为 `1.95.0`，nightly 时为 `nightly`——与 `x.py dist` 的实际输出一致。CI workflow 同步添加 `pkg_version` output。

### 7.3 最终结果

本地 nightly 构建成功产出 `miri-nightly-aarch64-unknown-linux-ohos.tar.gz`（2.5M）并安装到最终产物包中。miri 在 OHOS 设备上可原生运行，依赖 `librustc_driver-*.so` + `libc++_shared.so` + `libc.so`。

---

## 八、构建配置摘要

### 通用配置

| 配置项 | 值 |
|--------|-----|
| Rust 版本 | 1.95.0 |
| Target | `aarch64-unknown-linux-ohos` |
| Host | `x86_64-unknown-linux-gnu` |
| OHOS SDK | `/opt/ohos-sdk/native/`（clang 15.0.4） |
| OpenSSL | `/opt/ohos-openssl/prelude/arm64-v8a/`（静态库） |
| 链接器 | `aarch64-unknown-linux-ohos-clang{,++}.sh`（clang wrapper） |
| 代码签名 | 链接时 `-Wl,--code-sign`（lld 自动签名） |
| sccache | 启用（CI 跨 run 缓存） |
| ccache | 启用（CI 跨 run 缓存） |
| CI 超时 | 6 小时 |
| USE_MIRROR | CI 不使用镜像（官方源）；本地可选 USTC 镜像 |

### 分支差异

| 配置项 | main（stable） | nightly |
|--------|----------------|---------|
| Channel | `stable` | `nightly` |
| Patches | 4 个（0001-0004） | 4 个（0001-0004） |
| `--release-channel` | `stable` | `nightly` |
| tarball 命名 | `rust-1.95.0-*` | `rust-nightly-*` |
| miri | ❌ 不构建（channel 门控） | ✅ 构建（2.5M） |
| clang wrapper | 基础配置 | 额外 `-lclang_rt.builtins` |
| `deny-warnings` | 默认 | `false`（安全网） |
| dist tarball 数 | 15 | 16 |

### 二进制依赖关系

所有工具链二进制均为 aarch64 ELF（interpreter `/lib/ld-musl-aarch64.so.1`），RUNPATH `$ORIGIN/../lib`，在 OHOS 设备上原生运行。

| 二进制 | 依赖库 |
|--------|--------|
| rustc | `librustc_driver-*.so` + `libc.so` |
| cargo | `libz.so` + `libc.so` |
| miri | `librustc_driver-*.so` + `libc++_shared.so` + `libc.so` |
| rustfmt | `librustc_driver-*.so` + `libc++_shared.so` + `libc.so` |
| clippy | `librustc_driver-*.so` + `libc++_shared.so` + `libc.so` |
| rust-analyzer | `librustc_driver-*.so` + `libc++_shared.so` + `libc.so` |

> `libc++_shared.so` 位于 `/opt/ohos-sdk/native/llvm/lib/aarch64-linux-ohos/libc++_shared.so`，需推送到设备。
