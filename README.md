# ohos-rust

为 OpenHarmony 平台交叉编译 Rust 工具链。

## 项目结构

```
ohos-rust/
├── x86_64/           # x86_64 交叉编译构建配置（Dockerfile + build.sh）
├── arm64/             # arm64 原生构建配置（未完成）(TODO)
├── patches/           # Rust 源码补丁（1.89.0 / 1.95.0）
├── tmp/               # 分析文档（CI 对比、rpath、编译过程）
└── .github/workflows/ # CI 构建流程
```

## 构建

通过 GitHub Actions CI 或本地 Docker 交叉编译。详见 `x86_64/build.sh`。
