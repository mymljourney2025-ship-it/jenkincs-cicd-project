// =============================================================================
// Sample Express Server — Replace with your actual application
// =============================================================================

const http = require('http');

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || '1.0.0';

const server = http.createServer((req, res) => {
  // Health check endpoint
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      version: APP_VERSION,
      timestamp: new Date().toISOString(),
      uptime: process.uptime()
    }));
    return;
  }

  // Readiness probe
  if (req.url === '/ready') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ready: true }));
    return;
  }

  // Metrics endpoint (basic)
  if (req.url === '/metrics') {
    const memUsage = process.memoryUsage();
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end([
      `# HELP app_uptime_seconds Application uptime`,
      `# TYPE app_uptime_seconds gauge`,
      `app_uptime_seconds ${process.uptime()}`,
      `# HELP app_memory_rss_bytes RSS memory usage`,
      `# TYPE app_memory_rss_bytes gauge`,
      `app_memory_rss_bytes ${memUsage.rss}`,
    ].join('\n'));
    return;
  }

  // Default response
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: 'Jenkins K8s Pipeline — Application Running!',
    version: APP_VERSION,
    environment: process.env.NODE_ENV || 'development'
  }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => process.exit(0));
});
