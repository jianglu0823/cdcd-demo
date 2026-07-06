#!/usr/bin/env bash
# 构建并启动 Jenkins 容器:
#   - 挂宿主 docker.sock,复用宿主 docker daemon 构建/推送镜像(docker-outside-of-docker)
#   - 装了 docker CLI + kubectl(见 jenkins/Dockerfile)
#   - 挂一份改写过 server 地址的 kubeconfig,让容器内 kubectl 能连到 kind
#   - 接到 cicd-net,能用容器名访问 Harbor 和 kind
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # 仓库根目录
NET=cicd-net
NAME=jenkins
CLUSTER=cicd
NODE="${CLUSTER}-control-plane"

# ---------- 1. 构建定制镜像 ----------
docker build -t cicd-jenkins:local "$HERE/jenkins"

# ---------- 2. 生成给 Jenkins 容器用的 kubeconfig ----------
# 宿主的 kubeconfig 里 kind 的 server 是 https://127.0.0.1:<随机端口>,
# 这个地址在 Jenkins 容器里不通。改成 https://<kind容器名>:6443(同在 cicd-net)。
mkdir -p "$HERE/.jenkins"
KUBECONF="$HERE/.jenkins/kubeconfig"
kind get kubeconfig --name "$CLUSTER" > "$KUBECONF"

# 把 server 地址换成容器名:6443,并跳过证书校验(证书 SAN 不含容器名,demo 简化处理)
# 用 kubectl 就地改,避免 sed 处理证书行
KUBECONFIG="$KUBECONF" kubectl config set-cluster "kind-${CLUSTER}" \
  --server="https://${NODE}:6443" >/dev/null
KUBECONFIG="$KUBECONF" kubectl config set-cluster "kind-${CLUSTER}" \
  --insecure-skip-tls-verify=true >/dev/null
# 删掉与 insecure 冲突的 CA 数据
KUBECONFIG="$KUBECONF" kubectl config unset "clusters.kind-${CLUSTER}.certificate-authority-data" >/dev/null 2>&1 || true

# ---------- 3. 启动容器 ----------
# --group-add 传入 docker.sock 的 gid,确保 jenkins 用户能用 docker.sock。
# 注意:宿主 stat 看到的 gid(如 1)与容器内看到的 gid 可能不同 —— Docker Desktop
# 的 VM 会把挂进容器的 docker.sock 呈现为 root:root(gid 0)。因此这里用一个临时容器
# 探测「容器内真实看到的 gid」,避免宿主/容器 gid 不一致导致 permission denied。
DOCKER_GID="$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine \
  stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 0)"
echo "容器内 docker.sock 的 gid = $DOCKER_GID(将用 --group-add 授权)"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "已存在同名容器 $NAME,先删除再重建"
  docker rm -f "$NAME"
fi

# 注意:宿主 8080 常被其他应用占用,这里映射到 8081。容器内仍是 8080。
docker run -d --name "$NAME" \
  --network "$NET" \
  --group-add "$DOCKER_GID" \
  -p 8081:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$KUBECONF":/var/jenkins_home/.kube/config:ro \
  -e KUBECONFIG=/var/jenkins_home/.kube/config \
  cicd-jenkins:local

echo "Jenkins 启动中。等待约 30s 后访问 http://localhost:8081"
echo "初始管理员密码:"
echo "  docker exec $NAME cat /var/jenkins_home/secrets/initialAdminPassword"
