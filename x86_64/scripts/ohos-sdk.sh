#!/bin/sh
set -ex

URL=https://repo.huaweicloud.com/openharmony/os/7.0-Beta1/ohos-sdk-windows_linux-public.tar.gz

curl -fL -o /tmp/ohos-sdk-full.tar.gz $URL
tar -zxf /tmp/ohos-sdk-full.tar.gz -C /opt
rm /tmp/ohos-sdk-full.tar.gz

cd /opt/ohos-sdk

# 仅删除 Windows 组件，保留 linux 和 ohos
rm -rf windows

# 解压 Linux 主机工具链（交叉编译器 clang、lld 等）
cd linux
unzip -q native-linux-x64-*.zip
unzip -q toolchains-linux-x64-*.zip 2>/dev/null || true
rm -rf *.zip

# 创建兼容符号链接: /opt/ohos-sdk/native -> linux/native
ln -sf linux/native /opt/ohos-sdk/native

cd ../ohos
unzip -q native-*.zip
unzip -q toolchains-*.zip 2>/dev/null || true
rm -rf *.zip
