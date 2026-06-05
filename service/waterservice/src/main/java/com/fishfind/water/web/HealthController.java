package com.fishfind.water.web;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.lang.management.ManagementFactory;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
public class HealthController {

    private static final String VERSION = "1.0.0";
    private static final long START_TIME = ManagementFactory.getRuntimeMXBean().getStartTime();

    @GetMapping("/health")
    public Map<String, Object> health() {
        long uptimeSeconds = (System.currentTimeMillis() - START_TIME) / 1000;
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", "UP");
        body.put("version", VERSION);
        body.put("uptime", uptimeSeconds);
        return body;
    }
}
