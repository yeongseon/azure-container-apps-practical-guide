'use strict';

const PII_RULES = [
  {
    pattern: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
    replacement: '00000000-0000-0000-0000-000000000000',
  },
  {
    pattern: /MCAPS[-A-Za-z0-9_]*/g,
    replacement: 'Visual Studio Enterprise Subscription',
  },
  {
    pattern: /[A-Za-z0-9._%+-]+@microsoft\.com/gi,
    replacement: 'user@example.com',
  },
  {
    pattern: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.onmicrosoft\.com/gi,
    replacement: 'user@example.com',
  },
  {
    pattern: /[A-Za-z0-9-]+\.onmicrosoft\.com/g,
    replacement: 'contoso.onmicrosoft.com',
  },
  {
    pattern: /ychoe/gi,
    replacement: 'demouser',
  },
  {
    pattern: /Yeongseon\s+Choe/g,
    replacement: 'Demo User',
  },
];

const PORTAL_BLUE = '#0078d4';

const PII_REPLACEMENT_SCRIPT = (() => {
  const serialized = PII_RULES
    .map(({ pattern, replacement }) => `{ re: ${pattern.toString()}, val: ${JSON.stringify(replacement)} }`)
    .join(', ');

  return `(() => {
    const subs = [${serialized}];
    let count = 0;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    const nodes = [];
    let n;
    while ((n = walker.nextNode())) nodes.push(n);
    for (const node of nodes) {
      let txt = node.textContent || '';
      let changed = false;
      for (const { re, val } of subs) {
        re.lastIndex = 0;
        if (re.test(txt)) {
          re.lastIndex = 0;
          txt = txt.replace(re, val);
          changed = true;
        }
      }
      if (changed) {
        node.textContent = txt;
        count++;
      }
    }
    document.querySelectorAll('[aria-label]').forEach(el => {
      const orig = el.getAttribute('aria-label') || '';
      let updated = orig;
      for (const { re, val } of subs) {
        re.lastIndex = 0;
        updated = updated.replace(re, val);
      }
      if (updated !== orig) el.setAttribute('aria-label', updated);
    });
    return count;
  })()`;
})();

async function applyPiiReplacements(page) {
  let total = await page.evaluate(PII_REPLACEMENT_SCRIPT);
  for (const frame of page.frames()) {
    try {
      total += await frame.evaluate(PII_REPLACEMENT_SCRIPT);
    } catch (_) {
      continue;
    }
  }
  return total;
}

async function capturePortalScreenshot(page, outputPath, options = {}) {
  const { fullPage = false } = options;

  const replacements = await applyPiiReplacements(page);
  await page.waitForTimeout(400);

  const accountBtn = page.locator('button[aria-label*="Account menu"]');
  const masks = (await accountBtn.count()) > 0 ? [accountBtn.first()] : [];

  await page.screenshot({
    path: outputPath,
    fullPage,
    mask: masks,
    maskColor: PORTAL_BLUE,
  });

  return { replacements, path: outputPath };
}

module.exports = {
  PII_RULES,
  PII_REPLACEMENT_SCRIPT,
  PORTAL_BLUE,
  applyPiiReplacements,
  capturePortalScreenshot,
};
