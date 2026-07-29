#!/bin/sh
set -ex

URL=https://repo.huaweicloud.com/openharmony/os/7.0-Beta1/ohos-sdk-windows_linux-public.tar.gz

curl -fL -o /tmp/ohos-sdk-full.tar.gz $URL
tar -zxf /tmp/ohos-sdk-full.tar.gz -C /opt
rm /tmp/ohos-sdk-full.tar.gz

cd /opt/ohos-sdk

# 仅删除 Windows 组件，保留 ohos 目录
rm -rf windows

# SDK 7.0 结构: ohos/ 目录包含 native-ohos-x64-*.zip 和 toolchains-ohos-x64-*.zip
# 解压 native SDK（含 LLVM/clang 主机工具 + 目标 sysroot）
cd ohos
unzip -q native-ohos-x64-*.zip
unzip -q toolchains-ohos-x64-*.zip 2>/dev/null || true
rm -rf *.zip

# 创建兼容符号链接: /opt/ohos-sdk/native -> ohos/native
ln -sf ohos/native /opt/ohos-sdk/native
