# 定制 Jenkins 镜像:在官方 LTS(JDK21)基础上装 docker CLI 和 kubectl。
# 为什么需要:流水线的 Build Image / Push / Deploy 阶段要在 Jenkins 容器内直接调
# docker 和 kubectl,官方镜像默认没有这两个命令。
FROM jenkins/jenkins:lts-jdk21

USER root

# docker CLI:装静态二进制(单个 tar 包,免 apt 源 / GPG,构建更稳)。
# 只要客户端,daemon 复用宿主的(通过挂载 docker.sock)。
# 用阿里云镜像站,国内网络下比 download.docker.com 稳定。
ARG DOCKER_CLI_VERSION=27.3.1
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) dockerarch=x86_64 ;; \
      arm64) dockerarch=aarch64 ;; \
      *) echo "unsupported arch: $arch" && exit 1 ;; \
    esac; \
    curl -fsSL "https://mirrors.aliyun.com/docker-ce/linux/static/stable/${dockerarch}/docker-${DOCKER_CLI_VERSION}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    docker --version

# kubectl:从官方 dl.k8s.io 拉指定版本(该 host 实测可达),版本对齐 kind 集群。
ARG KUBECTL_VERSION=v1.31.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    kubectl version --client

# 让 jenkins 用户能访问挂进来的 docker.sock。宿主 docker.sock 的 gid 因平台而异,
# 这里加一个 docker 组并把 jenkins 加进去;20-jenkins.sh 启动时会用 --group-add 兜底。
RUN groupadd -f docker && usermod -aG docker jenkins

USER jenkins
