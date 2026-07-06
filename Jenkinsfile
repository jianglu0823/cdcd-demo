// 本地 CI/CD 学习 demo 的流水线定义。
// 前提(见 scripts/20-jenkins.sh):Jenkins 容器内已装 docker CLI + kubectl,
// 挂了宿主的 /var/run/docker.sock,挂了 kind 的 kubeconfig,且和 Harbor/kind 同在 cicd-net 网络。

pipeline {
    // 直接在 Jenkins 主节点跑,不用额外 agent(demo 够用)
    agent any

    environment {
        // 必须带 :80 显式走 HTTP。不带端口时 docker 会强制走 HTTPS(443),
        // 而本地 Harbor 只监听 80,导致 push/pull 失败。
        REGISTRY    = 'harbor.cicd.local:80'
        IMAGE       = "${REGISTRY}/demo/app"
        // 每次构建用 Jenkins 内置的自增编号做镜像 tag,天然唯一、可追溯到具体构建
        TAG         = "${env.BUILD_NUMBER}"
        // 在 Jenkins 里配好的 Harbor 用户名/密码凭据(Manage Credentials 里 ID 填 harbor-cred)
        HARBOR_CRED = credentials('harbor-cred')
    }

    options {
        timestamps()
        // 拉代码时不要 checkout 两次
        skipDefaultCheckout(false)
    }

    stages {
        stage('Checkout') {
            steps {
                // Pipeline job 配了 SCM 时,Jenkins 会自动 checkout;这里显式声明便于阅读
                checkout scm
            }
        }

        stage('Build & Test') {
            steps {
                // 用 maven 容器构建,避免 Jenkins 容器里再装 JDK/maven。
                // -v $HOME/.m2 做依赖缓存,加速后续构建。
                sh '''
                    docker run --rm \
                      -v "$WORKSPACE":/src -w /src \
                      -v "$HOME/.m2":/root/.m2 \
                      maven:3.9-eclipse-temurin-21 \
                      mvn -B -f app/pom.xml clean package
                '''
            }
        }

        stage('Build Image') {
            steps {
                // 构建上下文是仓库根目录,Dockerfile 里的 COPY 路径带 app/ 前缀
                sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
            }
        }

        stage('Push') {
            steps {
                // HARBOR_CRED_USR / HARBOR_CRED_PSW 由 credentials() 自动拆出用户名和密码
                sh '''
                    echo "$HARBOR_CRED_PSW" | docker login $REGISTRY -u "$HARBOR_CRED_USR" --password-stdin
                    docker push $IMAGE:$TAG
                    docker push $IMAGE:latest
                '''
            }
        }

        stage('Deploy') {
            steps {
                // 首次确保 Deployment/Service 存在;之后 set image 触发滚动更新到本次 tag
                sh '''
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl set image deployment/cicd-demo app=$IMAGE:$TAG
                    kubectl rollout status deployment/cicd-demo --timeout=120s
                '''
            }
        }
    }

    post {
        success {
            echo "部署成功:$IMAGE:$TAG,访问 http://localhost:30080/ 验证版本号"
        }
        failure {
            echo '流水线失败,查看上面对应 stage 的日志定位问题'
        }
        always {
            // 清理登录态,避免凭据残留在容器里
            sh 'docker logout $REGISTRY || true'
        }
    }
}
