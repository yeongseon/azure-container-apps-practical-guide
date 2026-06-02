# Portal capture helpers

Reusable PII-masking utilities for Azure Portal screenshots. Used across every
troubleshooting lab capture to keep redactions consistent and to avoid leaking
real Azure account identifiers into the documentation.

## What it does

- Replaces real identifiers in text nodes and `aria-label` attributes with
  documentation-safe placeholders (see [PII Replacement Rules](../AGENTS.md#pii-replacement-rules)).
- Walks the main frame **and** every nested iframe (Portal blades render
  inside iframes).
- Masks only the Account-menu avatar using Playwright's native `mask` option
  with Portal blue (`#0078d4`), so the masked region blends into the UI
  instead of leaving a jarring black rectangle.

## Node.js usage

```javascript
const { chromium } = require('playwright');
const { capturePortalScreenshot } = require('./portal-capture-helpers');

const browser = await chromium.launch({ headless: false });
const context = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
const page = await context.newPage();

await page.goto(
  'https://ms.portal.azure.com/#@fdpo.onmicrosoft.com/resource/' +
  'subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/containerApps/<app>/containerapp'
);

await capturePortalScreenshot(
  page,
  'docs/assets/troubleshooting/scale-rule-mismatch/01-overview-baseline.png'
);

await browser.close();
```

## MCP `browser_run_code_unsafe` usage

The MCP browser tool executes a single async function in an isolated page
context, so it cannot `require()` this module. Inline the snippet below
(replace `<OUTPUT_PATH>` per capture):

```javascript
async (page) => {
  const piiScript = `(() => {
    const subs = [
      { re: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, val: '00000000-0000-0000-0000-000000000000' },
      { re: /MCAPS[-A-Za-z0-9_]*/g, val: 'Visual Studio Enterprise Subscription' },
      { re: /[A-Za-z0-9._%+-]+@microsoft\\.com/gi, val: 'user@example.com' },
      { re: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.onmicrosoft\\.com/gi, val: 'user@example.com' },
      { re: /[A-Za-z0-9-]+\\.onmicrosoft\\.com/g, val: 'contoso.onmicrosoft.com' },
      { re: /ychoe/gi, val: 'demouser' },
      { re: /Yeongseon\\s+Choe/g, val: 'Demo User' },
    ];
    let count = 0;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    const nodes = []; let n; while ((n = walker.nextNode())) nodes.push(n);
    for (const node of nodes) {
      let txt = node.textContent || ''; let changed = false;
      for (const { re, val } of subs) { re.lastIndex = 0; if (re.test(txt)) { re.lastIndex = 0; txt = txt.replace(re, val); changed = true; } }
      if (changed) { node.textContent = txt; count++; }
    }
    document.querySelectorAll('[aria-label]').forEach(el => {
      const orig = el.getAttribute('aria-label') || ''; let updated = orig;
      for (const { re, val } of subs) { re.lastIndex = 0; updated = updated.replace(re, val); }
      if (updated !== orig) el.setAttribute('aria-label', updated);
    });
    return count;
  })()`;

  let total = await page.evaluate(piiScript);
  for (const frame of page.frames()) {
    try { total += await frame.evaluate(piiScript); } catch (_) {}
  }
  await page.waitForTimeout(400);

  const accountBtn = page.locator('button[aria-label*="Account menu"]');
  const masks = (await accountBtn.count()) > 0 ? [accountBtn.first()] : [];

  await page.screenshot({
    path: '<OUTPUT_PATH>',
    fullPage: false,
    mask: masks,
    maskColor: '#0078d4',
  });

  return 'replaced ' + total + ' text occurrences';
};
```

## Important notes

- Re-navigate (`browser_navigate`) between captures. Portal CSS is cumulative,
  and leftover styles from a previous capture can leak into the next page.
- The Portal must be reached via `ms.portal.azure.com` with the tenant hint
  fragment (`#@fdpo.onmicrosoft.com/...`). Plain `portal.azure.com` triggers a
  login redirect.
- Viewport: 1600 x 1000 captures the standard Portal blade layout without
  horizontal scrollbars.
- If `PII_RULES` is updated, mirror the change in the
  [PII Replacement Rules](../AGENTS.md#pii-replacement-rules) table.
