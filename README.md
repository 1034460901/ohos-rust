# ohos-rust

为 OpenHarmony 平台交叉编译 Rust 工具链。

## 项目结构

```
ohos-rust/
├── x86_64/            # x86_64 交叉编译构建配置（Dockerfile + build.sh）
├── arm64/             # arm64 原生构建配置（-Wl,--code-sign 链接时签名）
├── patches/           # Rust 源码补丁（按版本分目录）
│   ├── 1.89.0/        # Rust 1.89.0 stable 补丁（4 个）
│   ├── 1.95.0/        # Rust 1.95.0 stable 补丁（4 个）
│   └── 1.100.0/       # Rust 1.100.0 nightly 补丁（4 个）
├── tmp/               # 分析文档（CI 对比、rpath、编译过程）
└── .github/workflows/ # CI 构建流程
```

## 支持版本

三个版本共存于 main 分支，通过 `RUST_VERSION` + `CHANNEL` 变量区分：

| 版本 | Channel | 补丁目录 | 说明 |
|------|---------|----------|------|
| 1.89.0 | stable | `patches/1.89.0/` | 0001 post-link auto-sign，1.89.0 已内置 OHOS target spec |
| 1.95.0 | stable | `patches/1.95.0/` | 0001 改用 `-Wl,--code-sign` 链接器标志 |
| 1.100.0 | nightly | `patches/1.100.0/` | 1.95.0 基础上移植，含 f128/f16 cfg 修复 |

> **注意：** 后续修复需同步更新所有受影响版本的补丁目录。

## 构建

### GitHub Actions CI

| 触发方式 | Channel | Version | 说明 |
|----------|---------|---------|------|
| push 到 main | stable | 1.95.0 | 门禁检查 |
| workflow_dispatch | stable | 手选 1.89.0 / 1.95.0 | 手动构建 stable |
| workflow_dispatch | nightly | 1.100.0（自动默认） | 手动构建 nightly |

### 本地编译（WSL / Linux）

```bash
# stable 1.89.0
RUST_VERSION=1.89.0 CHANNEL=stable ./x86_64/build.sh

# stable 1.95.0
RUST_VERSION=1.95.0 CHANNEL=stable ./x86_64/build.sh

# nightly 1.100.0
RUST_VERSION=1.100.0 CHANNEL=nightly ./x86_64/build.sh
```

### 本地 Docker 构建

```bash
docker build -f x86_64/Dockerfile -t rust-ohos-x86_64 .
docker run --rm -v $(pwd):/workspace -w /workspace \
  -e RUST_VERSION=1.89.0 -e CHANNEL=stable \
  rust-ohos-x86_64 ./x86_64/build.sh
```

详见 `x86_64/build.sh`。

## 补丁说明

每个版本 4 个补丁，按编号顺序应用：

| 编号 | 名称 | 说明 |
|------|------|------|
| 0001 | rustc-ohos-auto-sign-fix | OHOS ELF 自动签名（1.89.0: post-link 工具；1.95.0+: `-Wl,--code-sign` 链接器标志） |
| 0002 | openssl-probe-cert-fix | 添加 `certs/cacert.pem` 到证书搜索路径 |
| 0003 | ohos-native-build-support | bootstrap.py HarmonyOS 检测、dist.rs JSON 文档、libffi config.sub |
| 0004 | asan-ohos-39bit-va-fix | SANITIZER_OHOS 宏、ASAN/HWASAN 128GB allocator、OHOS SDK clang 覆盖 |

> 补丁是版本特定的：针对每个版本的源码结构适配，非跨版本盲目拷贝。
