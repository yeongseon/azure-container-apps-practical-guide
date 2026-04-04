using Azure.Monitor.OpenTelemetry.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
}

var app = builder.Build();

app.UseRouting();
app.MapControllers();

app.MapGet("/", () => Results.Content("""
<!DOCTYPE html>
<html>
<head>
    <title>Azure Container Apps .NET Guide</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #512bd4; }
        .endpoint { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 8px; }
        .method { background: #512bd4; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
        code { background: #e8e8e8; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>💜 Azure Container Apps .NET Guide</h1>
    <p>Reference implementation for ASP.NET Core on Azure Container Apps.</p>
    
    <h2>Endpoints</h2>
    <div class="endpoint"><span class="method">GET</span> <code>/health</code> - Health check</div>
    <div class="endpoint"><span class="method">GET</span> <code>/info</code> - Application info</div>
</body>
</html>
""", "text/html"));

app.Lifetime.ApplicationStopping.Register(() =>
{
    app.Logger.LogInformation("Application stopping, performing graceful shutdown...");
});

var port = Environment.GetEnvironmentVariable("PORT") ?? "8000";
app.Run($"http://0.0.0.0:{port}");
