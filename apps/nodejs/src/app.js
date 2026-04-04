const express = require('express');
const healthRoutes = require('./routes/health');
const infoRoutes = require('./routes/info');
const { jsonLogger } = require('./middleware/logging');

// Configure Application Insights before other imports
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const appInsights = require('applicationinsights');
  appInsights.setup()
    .setAutoCollectConsole(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectRequests(true)
    .setAutoCollectDependencies(true)
    .start();
}

const app = express();
const port = process.env.PORT || 8000;

// Middleware
app.use(express.json());
app.use(jsonLogger);

// Routes
app.use('/', healthRoutes);
app.use('/', infoRoutes);

// Home page
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Azure Container Apps Node.js Guide</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
            h1 { color: #68a063; }
            .endpoint { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 8px; }
            .method { background: #68a063; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
            code { background: #e8e8e8; padding: 2px 6px; border-radius: 4px; }
        </style>
    </head>
    <body>
        <h1>🚀 Azure Container Apps Node.js Guide</h1>
        <p>Reference implementation for Express on Azure Container Apps.</p>
        
        <h2>Endpoints</h2>
        <div class="endpoint"><span class="method">GET</span> <code>/health</code> - Health check</div>
        <div class="endpoint"><span class="method">GET</span> <code>/info</code> - Application info</div>
    </body>
    </html>
  `);
});

// Graceful shutdown
let server;

const shutdown = (signal) => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: `${signal} received, shutting down gracefully...`
  }));
  
  if (server) {
    server.close(() => {
      console.log(JSON.stringify({
        timestamp: new Date().toISOString(),
        level: 'INFO',
        message: 'Server closed'
      }));
      process.exit(0);
    });
    
    // Force close after 30 seconds
    setTimeout(() => {
      console.log(JSON.stringify({
        timestamp: new Date().toISOString(),
        level: 'WARN',
        message: 'Forcing shutdown after timeout'
      }));
      process.exit(1);
    }, 30000);
  }
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Start server
server = app.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: `Server started on port ${port}`
  }));
});

module.exports = app;
