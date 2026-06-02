'use strict';

const PII_RULES = [
  {
    pattern: /(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])/gi,
    replacement: '00000000-0000-0000-0000-000000000000',
  },
  {
    pattern: /\bMCAPS[-A-Za-z0-9_]*\b/g,
    replacement: 'Visual Studio Enterprise Subscription',
  },
  {
    pattern: /Microsoft\s+Non-Production/gi,
    replacement: 'Contoso',
  },
  {
    pattern: /\b[A-Za-z0-9._%+-]+@microsoft\.com\b/gi,
    replacement: 'user@example.com',
  },
  {
    pattern: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.onmicrosoft\.com\b/gi,
    replacement: 'user@example.com',
  },
  {
    pattern: /\b[A-Za-z0-9-]+\.onmicrosoft\.com\b/gi,
    replacement: 'contoso.onmicrosoft.com',
  },
  {
    pattern: /\bychoe\b/gi,
    replacement: 'demouser',
  },
  {
    pattern: /Yeongseon\s+Choe/g,
    replacement: 'Demo User',
  },
];

const PORTAL_BLUE = '#0078d4';

const ACCOUNT_AVATAR_SELECTORS = [
  'button[aria-label*="Account menu"]',
  'button.fxs-menu-account',
];

const PII_REPLACEMENT_SCRIPT = (() => {
  const serialized = PII_RULES
    .map(({ pattern, replacement }) => `{ re: ${pattern.toString()}, val: ${JSON.stringify(replacement)} }`)
    .join(', ');

  return `(() => {
    const subs = [${serialized}];
    let count = 0;
    const applySubs = (input) => {
      let out = input;
      for (const { re, val } of subs) {
        re.lastIndex = 0;
        out = out.replace(re, val);
      }
      return out;
    };
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    const nodes = [];
    let n;
    while ((n = walker.nextNode())) nodes.push(n);
    for (const node of nodes) {
      const orig = node.textContent || '';
      const next = applySubs(orig);
      if (next !== orig) {
        node.textContent = next;
        count++;
      }
    }
    document.querySelectorAll('[aria-label]').forEach((el) => {
      const orig = el.getAttribute('aria-label') || '';
      const next = applySubs(orig);
      if (next !== orig) el.setAttribute('aria-label', next);
    });
    document.querySelectorAll('input, textarea').forEach((el) => {
      const orig = el.value || '';
      const next = applySubs(orig);
      if (next !== orig) {
        el.value = next;
        count++;
      }
    });
    document.querySelectorAll('[title]').forEach((el) => {
      const orig = el.getAttribute('title') || '';
      const next = applySubs(orig);
      if (next !== orig) el.setAttribute('title', next);
    });
    return count;
  })()`;
})();

async function applyPiiReplacements(page) {
  const mainFrame = page.mainFrame();
  let total = await mainFrame.evaluate(PII_REPLACEMENT_SCRIPT);
  for (const frame of page.frames()) {
    if (frame === mainFrame) continue;
    try {
      total += await frame.evaluate(PII_REPLACEMENT_SCRIPT);
    } catch (_) {
      continue;
    }
  }
  return total;
}

async function resolveAccountAvatarMask(page) {
  for (const selector of ACCOUNT_AVATAR_SELECTORS) {
    const locator = page.locator(selector);
    if ((await locator.count()) > 0) {
      return locator.first();
    }
  }
  return null;
}

async function capturePortalScreenshot(page, outputPath, options = {}) {
  const { fullPage = false, requireAvatarMask = true } = options;

  const replacements = await applyPiiReplacements(page);
  await page.waitForTimeout(400);

  const avatar = await resolveAccountAvatarMask(page);
  const masks = avatar ? [avatar] : [];

  if (!avatar && requireAvatarMask) {
    const message =
      'capturePortalScreenshot: no Account-avatar element matched any of ' +
      JSON.stringify(ACCOUNT_AVATAR_SELECTORS) +
      '. Portal UI must be in English and the page must be fully rendered before capture. ' +
      'Pass { requireAvatarMask: false } to override.';
    throw new Error(message);
  }

  await page.screenshot({
    path: outputPath,
    fullPage,
    mask: masks,
    maskColor: PORTAL_BLUE,
  });

  return { replacements, path: outputPath, avatarMasked: Boolean(avatar) };
}

module.exports = {
  PII_RULES,
  PII_REPLACEMENT_SCRIPT,
  PORTAL_BLUE,
  ACCOUNT_AVATAR_SELECTORS,
  applyPiiReplacements,
  resolveAccountAvatarMask,
  capturePortalScreenshot,
};
