const express = require('express');
const router = express.Router();

router.get('/info', (req, res) => {
  res.json({
    app: 'azure-container-apps-nodejs-guide',
    version: '1.0.0',
    runtime: {
      node: process.version,
      platform: process.platform,
      arch: process.arch
    },
    environment: {
      container_app_name: process.env.CONTAINER_APP_NAME || 'local',
      revision: process.env.CONTAINER_APP_REVISION || 'local',
      replica: process.env.HOSTNAME || 'local'
    },
    timestamp: new Date().toISOString()
  });
});

module.exports = router;
