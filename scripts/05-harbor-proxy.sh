#!/usr/bin/env bash
# 启动 harbor-proxy:让宿主和 kind 集群内都能用 harbor.cicd.local:80 访问 Harbor。
#
# 背景:Harbor 的 nginx 容器内部只 listen 8080,宿主靠 80->8080 端口映射对外。
# kind 容器间直连走容器真实端口(8080),拿不到宿主映射;而直接给 nginx 加 cicd-net
# 别名会破坏 Docker Desktop 的宿主端口转发。所以用一个独立的轻量 nginx 反代:
#   - 接 harbor_harbor 网络 → 能连到 Harbor 的 nginx:8080
#   - 接 cicd-net 网络,持别名 harbor.cicd.local,listen 80 → kind 内可达
# 这样镜像地址统一用 harbor.cicd.local:80,push(宿主)/pull(集群)端口一致。
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
NAME=harbor-proxy
NET=cicd-net
HARBOR_NET=harbor_harbor   # Harbor compose 默认网络名
# 复用本地已有的 Harbor 自带 nginx 镜像,避免额外拉取
IMAGE=goharbor/nginx-photon:v2.11.1

# 前置:Harbor 必须已在运行
if ! docker ps --filter name=nginx --format '{{.Names}}' | grep -qx nginx; then
  echo "❌ 未发现 Harbor 的 nginx 容器,请先安装并启动 Harbor(见 harbor/README.md)" >&2
  exit 1
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true

# 先接 Harbor 网络(才能 proxy_pass 到 nginx:8080)
docker run -d --name "$NAME" \
  --network "$HARBOR_NET" \
  -v "$HERE/harbor/proxy.conf":/etc/nginx/nginx.conf:ro \
  "$IMAGE"

# 再接 cicd-net,带别名 harbor.cicd.local(kind 内靠此别名解析)
docker network connect --alias harbor.cicd.local "$NET" "$NAME"

sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]; then
  echo "❌ harbor-proxy 未正常运行,日志:" >&2
  docker logs "$NAME" 2>&1 | tail -10 >&2
  exit 1
fi
echo "✅ harbor-proxy 就绪:cicd-net 内 harbor.cicd.local:80 → nginx:8080"
