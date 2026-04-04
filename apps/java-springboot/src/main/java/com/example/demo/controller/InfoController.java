package com.example.demo.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

@RestController
public class InfoController {
    
    @Value("${CONTAINER_APP_NAME:local}")
    private String containerAppName;
    
    @Value("${CONTAINER_APP_REVISION:local}")
    private String revision;
    
    @Value("${HOSTNAME:local}")
    private String hostname;
    
    @GetMapping("/info")
    public ResponseEntity<Map<String, Object>> info() {
        return ResponseEntity.ok(Map.of(
            "app", "azure-container-apps-java-guide",
            "version", "1.0.0",
            "runtime", Map.of(
                "java", System.getProperty("java.version"),
                "vendor", System.getProperty("java.vendor")
            ),
            "environment", Map.of(
                "container_app_name", containerAppName,
                "revision", revision,
                "replica", hostname
            ),
            "timestamp", Instant.now().toString()
        ));
    }
}
