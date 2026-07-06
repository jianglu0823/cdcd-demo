package com.demo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    // 改这里的版本号并 push,就能在浏览器里肉眼确认「新版本部署生效」。
    // 这是验证整条 CI/CD 是否真的跑通最直观的信号。
    private static final String VERSION = "v1";

    // 由部署环境(K8s Deployment env)注入,用来观察是哪个 Pod 在响应。
    @Value("${HOSTNAME:local}")
    private String hostname;

    @GetMapping("/")
    public String hello() {
        return "hello " + VERSION + " (from " + hostname + ")\n";
    }
}
