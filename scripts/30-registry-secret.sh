#!/usr/bin/env bash
# 在 K8s 里创建拉取私有 Harbor 镜像所需的 docker-registry secret。
# deployment.yaml 里通过 imagePullSecrets: harbor-cred 引用它。
#
# 用法:HARBOR_USER=admin HARBOR_PASS=Harbor12345 ./scripts/30-registry-secret.sh
set -euo pipefail

HARBOR_HOST=harbor.cicd.local
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_PASS="${HARBOR_PASS:-Harbor12345}"   # Harbor 默认管理员密码,生产务必改掉

# 用宿主的 kubeconfig(kind context)操作集群
kubectl create secret docker-registry harbor-cred \
  --docker-server="${HARBOR_HOST}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "已创建/更新 imagePullSecret: harbor-cred(server=${HARBOR_HOST}, user=${HARBOR_USER})"
