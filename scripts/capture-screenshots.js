const { chromium } = require('playwright');
const path = require('path');

const BASE_URL = process.env.APP_URL || 'https://ca-pycontainer-zxyaw4an5c742.agreeablestone-8721f020.koreacentral.azurecontainerapps.io';
const SCREENSHOTS_DIR = path.join(__dirname, '..', 'docs', 'screenshots');

const endpoints = [
  { name: '01-health-endpoint', path: '/health', description: 'Health Check' },
  { name: '02-info-endpoint', path: '/info', description: 'App Info' },
  { name: '03-log-levels', path: '/api/requests/log-levels', description: 'Log Levels Demo' },
  { name: '04-external-dependency', path: '/api/dependencies/external', description: 'External API Call' },
  { name: '05-exception-endpoint', path: '/api/exceptions/test-error', description: 'Exception Handling' },
];

async function captureScreenshots() {
  console.log('Starting screenshot capture...');
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`Screenshots Dir: ${SCREENSHOTS_DIR}`);
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
  });
  const page = await context.newPage();

  for (const endpoint of endpoints) {
    const url = `${BASE_URL}${endpoint.path}`;
    console.log(`Capturing ${endpoint.name}: ${url}`);
    
    try {
      await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(1000);
      
      const screenshotPath = path.join(SCREENSHOTS_DIR, `${endpoint.name}.png`);
      await page.screenshot({ path: screenshotPath, fullPage: true });
      console.log(`  ✅ Saved: ${screenshotPath}`);
    } catch (error) {
      console.error(`  ❌ Failed: ${error.message}`);
    }
  }

  await browser.close();
  console.log('\nScreenshot capture complete!');
}

captureScreenshots().catch(console.error);
