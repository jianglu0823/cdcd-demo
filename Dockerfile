# 多阶段构建:第一阶段用 maven 镜像编译打包,第二阶段只带精简 JRE 运行。
# 好处:最终镜像不含 maven / 源码 / .m2 缓存,体积小、攻击面小。

# ---------- 构建阶段 ----------
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src

# 先只拷 pom.xml 并预下载依赖,利用 Docker layer 缓存:
# 只要 pom.xml 没变,即使改了源码,这一层也命中缓存,不用重新下依赖。
# 注意:构建上下文是仓库根目录,所以源码路径带 app/ 前缀。
COPY app/pom.xml .
RUN mvn -B dependency:go-offline

# 再拷源码编译。源码变动只会让下面这层失效,依赖层依旧命中缓存。
COPY app/src ./src
RUN mvn -B clean package -DskipTests

# ---------- 运行阶段 ----------
FROM eclipse-temurin:21-jre
WORKDIR /app

# finalName=app,所以产物固定叫 app.jar
COPY --from=build /src/target/app.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
