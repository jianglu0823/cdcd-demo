#!/usr/bin/env bash
# 建一个单节点 kind 集群,并让它:
#   1. 把 NodePort 30080 映射到宿主 localhost:30080(浏览器可直接访问)
#   2. 信任 HTTP 的私有 Harbor(harbor.cicd.local)
#   3. 接到 cicd-net 网络,从而能用容器名/主机名访问 Harbor
set -euo pipefail

CLUSTER=cicd
NET=cicd-net
HARBOR_HOST=harbor.cicd.local

# ---------- 1. 建集群(带端口映射 + containerd 信任 insecure registry) ----------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "kind 集群 $CLUSTER 已存在,跳过创建"
else
  cat <<EOF | kind create cluster --name "$CLUSTER" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      # 把节点 30080 暴露到宿主,浏览器访问 http://localhost:30080/
      - containerPort: 30080
        hostPort: 30080
        protocol: TCP
containerdConfigPatches:
  # 告诉集群内的 containerd:harbor.cicd.local 走 HTTP(insecure),镜像从这里拉
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
EOF
fi

# ---------- 2. 把 kind 节点接到 cicd-net,使其能解析并访问 Harbor 容器 ----------
NODE="${CLUSTER}-control-plane"
if docker network inspect "$NET" | grep -q "\"$NODE\""; then
  echo "$NODE 已在 $NET 网络中"
else
  docker network connect "$NET" "$NODE"
  echo "已把 $NODE 接入 $NET"
fi

# ---------- 3. 在节点内写 containerd 的 hosts.toml,指向 Harbor 容器,声明 HTTP ----------
# 注意:harbor.cicd.local 在 cicd-net 内会解析到 Harbor 的 nginx 容器名。
# 这里显式把 registry host 指到该主机名,并标注 skip TLS。
docker exec "$NODE" mkdir -p "/etc/containerd/certs.d/${HARBOR_HOST}"
docker exec "$NODE" bash -c "cat > /etc/containerd/certs.d/${HARBOR_HOST}/hosts.toml <<'TOML'
server = \"http://${HARBOR_HOST}\"

[host.\"http://${HARBOR_HOST}\"]
  capabilities = [\"pull\", \"resolve\"]
  skip_verify = true
TOML"

echo "kind 集群就绪。kubeconfig 已写入 ~/.kube/config(context: kind-${CLUSTER})"
echo "提示:20-jenkins.sh 会导出一份供 Jenkins 容器使用的 kubeconfig。"
