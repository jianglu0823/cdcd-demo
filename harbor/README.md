# Harbor 私有镜像仓库 —— 本地 demo 安装备忘

Harbor 用官方 offline/online installer 以 docker-compose 形态跑。这里记录本 demo 的关键配置项。

## 1. 下载 installer

到 https://github.com/goharbor/harbor/releases 下载 `harbor-online-installer-vX.Y.Z.tgz`(online 版小,首次 install 时拉镜像)。解压到本目录旁边,例如:

```bash
cd /Users/jianglu/claudeProject/CI:DI-demo/harbor
curl -fsSLO https://github.com/goharbor/harbor/releases/download/v2.11.1/harbor-online-installer-v2.11.1.tgz
tar xzf harbor-online-installer-v2.11.1.tgz   # 解出 harbor/ 目录
cd harbor
cp harbor.yml.tmpl harbor.yml
```

## 2. 改 harbor.yml(demo 关键项)

```yaml
hostname: harbor.cicd.local        # 用主机名而非 IP,配合 /etc/hosts 和 cicd-net

http:
  port: 80

# --- 关键:demo 用 HTTP,把整个 https: 段注释掉,省去自签证书 ---
# https:
#   port: 443
#   certificate: ...
#   private_key: ...

harbor_admin_password: Harbor12345  # 默认管理员密码,登录后可改

data_volume: /data                  # Harbor 数据存放目录(容器内)
```

其余保持默认即可。

## 3. 安装并接入统一网络

```bash
sudo ./install.sh                   # 首次会拉起一组 harbor 容器(nginx/core/db/registry...)

# 把 harbor 的入口容器接到 cicd-net,让 kind/Jenkins 能用容器名访问。
# 入口容器名通常是 nginx(docker ps 里找 goharbor/nginx-photon)。
docker network connect cicd-net nginx
```

## 4. 宿主 hosts + Docker 信任 HTTP 仓库

```bash
# a) /etc/hosts 加一行,让宿主能解析 harbor 主机名
echo "127.0.0.1 harbor.cicd.local" | sudo tee -a /etc/hosts

# b) Docker Desktop → Settings → Docker Engine,加 insecure-registries 后 Apply&Restart:
#    {
#      "insecure-registries": ["harbor.cicd.local", "harbor.cicd.local:80"]
#    }
```

## 5. 建 project 并验证

1. 浏览器打开 http://harbor.cicd.local,用 `admin / Harbor12345` 登录。
2. 新建 project,名字填 `demo`(与 Jenkinsfile 里的 `harbor.cicd.local/demo/app` 对应)。
3. 命令行验证登录与推送:

```bash
docker login harbor.cicd.local -u admin -p Harbor12345
docker pull hello-world
docker tag hello-world harbor.cicd.local/demo/hello:test
docker push harbor.cicd.local/demo/hello:test
# 回到 Harbor UI 的 demo project,能看到 hello:test 即成功
```

## 常见问题

- **push 报 http: server gave HTTP response to HTTPS client** → Docker 没配 insecure-registries,或没重启 Docker。
- **kind 里 Pod ImagePullBackOff** → 见 `scripts/10-kind.sh` 写的 hosts.toml;确认 kind 节点已 `docker network connect cicd-net`。
- **harbor.cicd.local 解析不了** → 宿主看 /etc/hosts;容器内看是否同在 cicd-net。
