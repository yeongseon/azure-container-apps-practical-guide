using Microsoft.AspNetCore.Mvc;

namespace AzureContainerApps.Controllers;

[ApiController]
public class HealthController : ControllerBase
{
    [HttpGet("/health")]
    public IActionResult Health()
    {
        return Ok(new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow.ToString("o")
        });
    }
}
