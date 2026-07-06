#!/usr/bin/env bash
# 建一个单节点 kind 集群,并让它:
#   1. 把 NodePort 30080 映射到宿主 localhost:30080(浏览器可直接访问)
#   2. 信任 HTTP 的私有 Harbor(harbor.cicd.local)
#   3. 接到 cicd-net 网络,从而能用容器名/主机名访问 Harbor
set -euo pipefail

CLUSTER=cicd
NET=cicd-net
# 带 :80:containerd 按镜像引用的 host:port 精确匹配 certs.d 目录名,必须与
# Jenkins push、deployment.yaml、registry-secret 里的地址完全一致。
HARBOR_HOST=harbor.cicd.local:80

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

# ---------- 2b. 确保 Harbor 的 nginx 在 cicd-net 上有别名 harbor.cicd.local ----------
# kind 内 containerd 要用域名访问 Harbor,靠 Docker 内嵌 DNS 解析到 nginx 容器。
# nginx 容器名是 "nginx",必须加网络别名 harbor.cicd.local 才能被解析到。
# 注意:动态 connect 后需重启 nginx 才能恢复宿主端口映射(Docker Desktop 已知行为)。
if ! docker inspect nginx --format '{{range .NetworkSettings.Networks.cicd-net.Aliases}}{{.}} {{end}}' 2>/dev/null | grep -q "harbor.cicd.local"; then
  docker network disconnect "$NET" nginx 2>/dev/null || true
  docker network connect --alias harbor.cicd.local "$NET" nginx
  docker restart nginx >/dev/null
  echo "已为 nginx 添加 cicd-net 别名 harbor.cicd.local 并重启"
else
  echo "nginx 已有别名 harbor.cicd.local"
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
