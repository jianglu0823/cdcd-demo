# 本地 CI/CD 学习 Demo

一条完整跑通的流水线,全部运行在你这台 Mac(Docker Desktop)上:

> **改一行代码 push 到 GitHub → Jenkins 自动构建镜像 → 推到本地 Harbor → 自动部署到本地 K8s(kind)→ 浏览器看到新版本。**

用一个极简 Spring Boot 应用当被部署对象,聚焦「流水线本身」而不是业务复杂度。

---

## 架构

```
  你改代码                                                   浏览器
     │                                                          ▲
     ▼  git push                                                │ localhost:30080
 ┌─────────┐   webhook(cloudflared 隧道)   ┌──────────┐        │
 │ GitHub  │ ─────────────────────────────▶│ Jenkins  │        │
 └─────────┘                                │ (容器)   │        │
                                            └────┬─────┘        │
                            ①mvn ②docker build ③push ④kubectl  │
                    ┌────────────────┼───────────────┼──────────┼───────┐
                    │                ▼               ▼          │       │
                    │          ┌──────────┐   ┌───────────┐    │       │
                    │          │  Harbor  │◀──│  kind K8s │────┘       │
                    │          │ (镜像仓) │拉 │  (容器)   │  NodePort  │
                    │          └──────────┘   └───────────┘            │
                    └── 三者同在 docker 网络 cicd-net,用容器名/主机名互访 ─┘
```

**核心设计**:Jenkins / Harbor / kind 三个容器接到同一个 docker 网络 `cicd-net`,用容器名和 `harbor.cicd.local` 主机名互访 —— 绕开 macOS 上「容器间 localhost 不通」这个最常见的坑。

---

## 目录结构

```
.
├── app/                       # 极简 Spring Boot 应用
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/demo/
│       │   ├── DemoApplication.java
│       │   └── HelloController.java   # 改这里的 VERSION 验证部署生效
│       └── resources/application.properties
├── Dockerfile                 # 多阶段构建(maven → jre)
├── Jenkinsfile                # 5 阶段流水线
├── k8s/
│   ├── deployment.yaml        # 指向 Harbor 镜像 + imagePullSecret + 探针
│   └── service.yaml           # NodePort 30080
├── jenkins/
│   └── Dockerfile             # 定制 Jenkins(装 docker CLI + kubectl)
├── harbor/
│   └── README.md              # Harbor 安装/配置备忘
└── scripts/
    ├── 00-network.sh          # 建 cicd-net 网络
    ├── 10-kind.sh             # 建 kind 集群 + 信任 Harbor
    ├── 20-jenkins.sh          # 起 Jenkins 容器
    └── 30-registry-secret.sh  # K8s 里建 Harbor 拉取凭据
```

---

## 前置准备(你本人执行一次)

```bash
brew install kind kubectl cloudflared
# Docker Desktop:Settings → Resources 给到 ≥6GB 内存(Harbor 较吃资源)
```

- 一个 GitHub 账号 + 一个新建仓库(把本目录 push 上去)。
- 后面会让 Docker Desktop 信任 HTTP 的 Harbor(见第 2 步)。

---

## 操作手册(按顺序做,每步都能独立验证)

### 第 1 步:验证应用本身能跑

```bash
docker build -t app:local .
docker run --rm -p 8080:8080 app:local
# 另开终端:
curl localhost:8080/         # 期望:hello v1 (from ...)
```

### 第 2 步:网络 + Harbor

```bash
./scripts/00-network.sh                 # 建 cicd-net
# 按 harbor/README.md 安装 Harbor、改 harbor.yml(HTTP + hostname + data_volume 指到 /Users 下)
# 建 demo project(public)
# 别忘:/etc/hosts 加 127.0.0.1 harbor.cicd.local
#      Docker Engine 配 insecure-registries: ["harbor.cicd.local","harbor.cicd.local:80"] 后重启 Docker
docker login harbor.cicd.local:80 -u admin -p Harbor12345   # 注意带 :80,验证登录成功
./scripts/05-harbor-proxy.sh            # 起代理,让集群内也能用 :80 访问 Harbor
```

> **为什么要带 `:80` 和代理**:Harbor 的 nginx 内部只监听 8080,宿主靠 80→8080 映射;不带端口时 docker 会强制走 HTTPS(443)导致失败。全链路镜像地址统一为 `harbor.cicd.local:80`;`05-harbor-proxy.sh` 起一个反代容器,让 kind 集群内也能用 `:80` 连到 Harbor。详见 harbor/README.md。

### 第 3 步:kind 集群 + 拉取凭据

```bash
./scripts/10-kind.sh                     # 建集群 + 信任 Harbor + 接入 cicd-net
./scripts/30-registry-secret.sh          # 建 imagePullSecret(harbor-cred)
kubectl get nodes                        # 期望:cicd-control-plane Ready
```

### 第 4 步:起 Jenkins

```bash
./scripts/20-jenkins.sh
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword   # 拿初始密码
# 浏览器 http://localhost:8080 → 用密码解锁 → 装推荐插件 + 额外装 "Docker Pipeline"
```

进 Jenkins 后:

1. **Manage Jenkins → Credentials** 添加两条 Username/Password 凭据:
   - ID `harbor-cred`:Harbor 的 admin / Harbor12345(Jenkinsfile 里用它 push)。
   - GitHub 凭据(私有仓库才需要):你的 GitHub 用户名 + Personal Access Token。
2. **New Item → Pipeline**,命名 `cicd-demo`:
   - Pipeline → Definition 选 **Pipeline script from SCM**。
   - SCM 选 Git,填你的 GitHub 仓库地址,选上面的 GitHub 凭据(私有仓库)。
   - Script Path 填 `Jenkinsfile`。

### 第 5 步:手动跑一次流水线

在 job 页面点 **Build Now**,看 5 个 stage 全绿:
`Checkout → Build & Test → Build Image → Push → Deploy`

```bash
curl localhost:30080/        # 期望:hello v1 (from cicd-demo-xxxx)
```

### 第 6 步:GitHub push 自动触发

```bash
cloudflared tunnel --url http://localhost:8080     # 拿到一个 https://xxx.trycloudflare.com
```

- GitHub 仓库 **Settings → Webhooks → Add webhook**:
  - Payload URL:`https://xxx.trycloudflare.com/github-webhook/`(末尾斜杠不能少)
  - Content type:`application/json`,事件选 `Just the push event`。
- Jenkins job **Configure → Build Triggers** 勾选 **GitHub hook trigger for GITScm polling**。

**端到端验证**:把 `HelloController.java` 里的 `VERSION` 改成 `v2` → `git push` → 不碰 Jenkins,几秒后自动构建 → `curl localhost:30080/` 显示 `hello v2`。**这一步成功,整条 CI/CD 就通了。**

> **零依赖退化方案**:不想用隧道,就跳过第 6 步的 webhook,改在 job 的 Build Triggers 里勾 **Poll SCM** 填 `* * * * *`(每分钟轮询)。效果一样,只是有最多 1 分钟延迟。

---

## 验证清单

| 层级 | 动作 | 期望 |
|------|------|------|
| 应用 | `docker run` 本地镜像 | `curl localhost:8080` 返回 hello |
| 仓库 | `docker push` 到 Harbor | Harbor UI 的 demo project 有镜像 |
| 集群 | `./scripts/30-...` + apply | Pod Running,无 ImagePullBackOff |
| CI | Jenkins Build Now | 5 stage 全绿 |
| CD | `curl localhost:30080` | 显示当前版本号 |
| 端到端 | 改 VERSION 后 push | 全自动走完,版本号变化 |

---

## 常见坑速查

| 现象 | 原因 / 解决 |
|------|------|
| push 报 `HTTP response to HTTPS client` | Docker 没配 `insecure-registries` 或没重启 Docker |
| Pod `ImagePullBackOff` | kind 没写 hosts.toml(重跑 10-kind.sh)/ 没建 harbor-cred secret / kind 没接入 cicd-net |
| Jenkins stage 报 `docker: not found` | Jenkins 容器没装 docker CLI(用 jenkins/Dockerfile 重建) |
| Jenkins `kubectl` 连不上集群 | kubeconfig 的 server 没改成 kind 容器名(20-jenkins.sh 已处理,确认 Jenkins 和 kind 同在 cicd-net) |
| GitHub webhook 不触发 | 隧道 URL 变了要更新 webhook;或直接用 Poll SCM 退化方案 |
| `harbor.cicd.local` 解析不了 | 宿主看 /etc/hosts;容器内确认同在 cicd-net |

---

## 清理

```bash
docker rm -f jenkins
kind delete cluster --name cicd
cd harbor/harbor && sudo docker compose down    # 停 Harbor
docker network rm cicd-net
docker volume rm jenkins_home
```
