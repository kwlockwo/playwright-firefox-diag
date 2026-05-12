/**
 * camoufox-render-test.js
 *
 * Deploy as a Render Background Worker. Check logs for PASS or FAIL.
 * Configure which fix to test via the CAMOUFOX_FIX env var:
 *
 *   CAMOUFOX_FIX=none          baseline (should reproduce the hang)
 *   CAMOUFOX_FIX=prefs         --no-remote + sandbox.content.level=0  (fix 1)
 *   CAMOUFOX_FIX=env           MOZ_DISABLE_CONTENT_SANDBOX=1          (fix 2)
 *   CAMOUFOX_FIX=prefs+env     both combined                          (fix 2+1)
 *
 * For fix 3 (shm_size) there is nothing to set in code — open a Render
 * support ticket and re-run with CAMOUFOX_FIX=none after they apply it.
 */

const { Camoufox } = require('camoufox');

const FIX = process.env.CAMOUFOX_FIX ?? 'none';
const TIMEOUT_MS = 30_000;

function step(name) {
  console.log(`[${new Date().toISOString()}] step=${name}`);
}

async function withTimeout(promise, ms, label) {
  let t;
  const race = Promise.race([
    promise,
    new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`TIMEOUT: ${label} exceeded ${ms}ms`)), ms); }),
  ]);
  try   { const r = await race; clearTimeout(t); return r; }
  catch (e) { clearTimeout(t); throw e; }
}

async function main() {
  console.log(`\n=== Camoufox newPage() test  fix=${FIX} ===`);

  // ── build launch options based on which fix is under test ──────────────────
  const opts = {
    headless: true, os: 'linux', humanize: false, geoip: false, locale: 'en-US',
  };

  if (FIX === 'prefs' || FIX === 'prefs+env') {
    opts.args = ['--no-remote'];
    opts.firefoxUserPrefs = { 'security.sandbox.content.level': 0 };
  }

  if (FIX === 'env' || FIX === 'prefs+env') {
    process.env.MOZ_DISABLE_CONTENT_SANDBOX = '1';
  }

  console.log('opts:', JSON.stringify(opts));
  console.log('MOZ_DISABLE_CONTENT_SANDBOX:', process.env.MOZ_DISABLE_CONTENT_SANDBOX ?? '(not set)');

  // ── test ───────────────────────────────────────────────────────────────────
  let browser, ctx, page;
  try {
    step('launch_start');
    browser = await withTimeout(Camoufox(opts), TIMEOUT_MS, 'launch');
    step('launch_done');

    step('ctx_start');
    ctx = await withTimeout(browser.newContext(), TIMEOUT_MS, 'newContext');
    step('ctx_done');

    step('newpage_start');
    page = await withTimeout(ctx.newPage(), TIMEOUT_MS, 'newPage');
    step('newpage_done');

    console.log(`\n✓ PASS  fix=${FIX}`);

  } catch (err) {
    console.error(`\n✗ FAIL  fix=${FIX}  error=${err.message}`);
    process.exitCode = 1;

  } finally {
    try { if (page)    await page.close();    } catch {}
    try { if (ctx)     await ctx.close();     } catch {}
    try { if (browser) await browser.close(); } catch {}
  }
}

main();
