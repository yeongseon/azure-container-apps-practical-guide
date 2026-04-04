package com.example.demo.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;

@Controller
public class HomeController {
    
    @GetMapping("/")
    @ResponseBody
    public String home() {
        return """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Azure Container Apps Java Guide</title>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
                    h1 { color: #f89820; }
                    .endpoint { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 8px; }
                    .method { background: #f89820; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
                    code { background: #e8e8e8; padding: 2px 6px; border-radius: 4px; }
                </style>
            </head>
            <body>
                <h1>☕ Azure Container Apps Java Guide</h1>
                <p>Reference implementation for Spring Boot on Azure Container Apps.</p>
                
                <h2>Endpoints</h2>
                <div class="endpoint"><span class="method">GET</span> <code>/health</code> - Health check</div>
                <div class="endpoint"><span class="method">GET</span> <code>/info</code> - Application info</div>
                <div class="endpoint"><span class="method">GET</span> <code>/actuator/health</code> - Spring Actuator health</div>
            </body>
            </html>
            """;
    }
}
