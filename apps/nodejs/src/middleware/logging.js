const jsonLogger = (req, res, next) => {
  const startTime = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - startTime;
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      level: 'INFO',
      logger: 'http',
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      durationMs: duration,
      userAgent: req.get('user-agent') || '-'
    }));
  });
  
  next();
};

module.exports = { jsonLogger };
