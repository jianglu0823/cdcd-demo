#!/usr/bin/env bash
# 创建一个统一的 docker 网络,让 Jenkins / Harbor / kind 三方能用容器名互访。
#
# 为什么需要:macOS 上容器里的 localhost 指向容器自己,不是宿主,也不是别的容器。
# 把所有组件接到同一个自定义网络后,它们能用「容器名」当主机名互相访问,绕开这个坑。
set -euo pipefail

NET=cicd-net

if docker network inspect "$NET" >/dev/null 2>&1; then
  echo "网络 $NET 已存在,跳过"
else
  docker network create "$NET"
  echo "已创建网络 $NET"
fi
