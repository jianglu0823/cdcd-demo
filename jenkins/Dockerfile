# 定制 Jenkins 镜像:在官方 LTS(JDK21)基础上装 docker CLI 和 kubectl。
# 为什么需要:流水线的 Build Image / Push / Deploy 阶段要在 Jenkins 容器内直接调
# docker 和 kubectl,官方镜像默认没有这两个命令。
FROM jenkins/jenkins:lts-jdk21

USER root

# docker CLI(只要客户端,daemon 复用宿主的,通过挂载 docker.sock)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# 让 jenkins 用户能访问挂进来的 docker.sock。宿主 docker.sock 的 gid 因平台而异,
# 这里加一个 docker 组并把 jenkins 加进去;20-jenkins.sh 启动时会用 --group-add 兜底。
RUN groupadd -f docker && usermod -aG docker jenkins

USER jenkins
