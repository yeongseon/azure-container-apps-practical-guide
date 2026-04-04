using Microsoft.AspNetCore.Mvc;
using System.Runtime.InteropServices;

namespace AzureContainerApps.Controllers;

[ApiController]
public class InfoController : ControllerBase
{
    [HttpGet("/info")]
    public IActionResult Info()
    {
        return Ok(new
        {
            app = "azure-container-apps-dotnet-guide",
            version = "1.0.0",
            runtime = new
            {
                dotnet = RuntimeInformation.FrameworkDescription,
                os = RuntimeInformation.OSDescription,
                arch = RuntimeInformation.OSArchitecture.ToString()
            },
            environment = new
            {
                container_app_name = Environment.GetEnvironmentVariable("CONTAINER_APP_NAME") ?? "local",
                revision = Environment.GetEnvironmentVariable("CONTAINER_APP_REVISION") ?? "local",
                replica = Environment.GetEnvironmentVariable("HOSTNAME") ?? "local"
            },
            timestamp = DateTime.UtcNow.ToString("o")
        });
    }
}
