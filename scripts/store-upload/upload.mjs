#!/usr/bin/env node
// Upload a .iq to the Garmin Connect IQ store via the developer dashboard.
//
// Garmin has no publishing API (asked-for since 2020, never shipped), so this
// drives the dashboard with Playwright against the locally installed Chrome.
// Auth is a saved browser session: run `login` once at the keyboard (SSO +
// MFA), after which `upload` runs unattended until the session expires —
// then it fails loudly and you `login` again.
//
//   node upload.mjs login
//   node upload.mjs list
//   node upload.mjs upload --name "Analog Simple" --iq ../../bin/analog-simple-1.6.3.iq \
//        --notes "Wind hairline; badge fixes" [--dry-run] [--headed]
//
// State lives outside the repo in ~/.config/analog-simple/ so the session
// can never be committed. Every failure saves a screenshot + HTML dump into
// bin/ so selectors can be fixed without another MFA round-trip.

import { chromium } from "playwright-core";
import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..", "..");
const STATE_DIR = join(homedir(), ".config", "analog-simple");
const STATE_FILE = join(STATE_DIR, "garmin-session.json");
const DASHBOARD = "https://apps.garmin.com/developer/dashboard";

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const has = (flag) => process.argv.includes(flag);

async function debugDump(page, label) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const base = join(REPO, "bin", `store-upload-${label}-${stamp}`);
  try {
    await page.screenshot({ path: `${base}.png`, fullPage: true });
    writeFileSync(`${base}.html`, await page.content());
    console.error(`Debug artifacts: ${base}.{png,html}`);
  } catch (e) {
    console.error(`(could not save debug artifacts: ${e.message})`);
  }
}

async function launch({ headed }) {
  return chromium.launch({ channel: "chrome", headless: !headed });
}

async function loggedInContext(browser) {
  if (!existsSync(STATE_FILE)) {
    throw new Error(`No saved session (${STATE_FILE}). Run: node upload.mjs login`);
  }
  return browser.newContext({ storageState: STATE_FILE });
}

// True once the page is a signed-in developer dashboard rather than an SSO
// or marketing page. Kept loose on purpose: the dashboard markup shifts.
async function looksSignedIn(page) {
  if (!/apps\.garmin\.com/.test(page.url()) || /sso\./.test(page.url())) {
    return false;
  }
  const text = await page.textContent("body").catch(() => "");
  if (/sign in|create account/i.test(text ?? "") && !/sign out/i.test(text ?? "")) {
    return false;
  }
  return /dashboard|my apps|app name|store listing|developer/i.test(text ?? "");
}

async function cmdLogin() {
  mkdirSync(STATE_DIR, { recursive: true });
  const browser = await launch({ headed: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(DASHBOARD, { waitUntil: "domcontentloaded" });
  console.log("A Chrome window is open. Sign in to the developer dashboard");
  console.log("(SSO + MFA). Waiting up to 5 minutes for the dashboard...");
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline) {
    if (await looksSignedIn(page)) {
      await context.storageState({ path: STATE_FILE });
      console.log(`Session saved: ${STATE_FILE}`);
      await browser.close();
      return;
    }
    await page.waitForTimeout(2000);
  }
  await debugDump(page, "login-timeout");
  await browser.close();
  throw new Error("Timed out waiting for a signed-in dashboard.");
}

async function openDashboard(browser) {
  const context = await loggedInContext(browser);
  const page = await context.newPage();
  await page.goto(DASHBOARD, { waitUntil: "networkidle" });
  if (!(await looksSignedIn(page))) {
    await debugDump(page, "session-expired");
    throw new Error("Session looks expired or invalid. Run: node upload.mjs login");
  }
  return { context, page };
}

async function appLinks(page) {
  // App cards/rows link into the per-app dashboard pages. Collect any
  // anchors under the developer area whose text isn't navigation chrome.
  const links = await page.$$eval("a[href*='/developer/']", (as) =>
    as
      .map((a) => ({ text: (a.textContent || "").trim(), href: a.href }))
      .filter(
        (l) =>
          l.text.length > 0 &&
          !/dashboard|sign out|help|forum|documentation|new app|submit/i.test(l.text)
      )
  );
  const seen = new Set();
  return links.filter((l) => !seen.has(l.href) && seen.add(l.href));
}

async function cmdList() {
  const browser = await launch({ headed: has("--headed") });
  try {
    const { page } = await openDashboard(browser);
    const links = await appLinks(page);
    if (links.length === 0) {
      await debugDump(page, "list-empty");
      console.log("No app links recognised — see debug artifacts for the real markup.");
    }
    for (const l of links) {
      console.log(`${l.text}\n    ${l.href}`);
    }
  } finally {
    await browser.close();
  }
}

// Click the first locator that exists and is visible, from a list of
// candidate selectors. Returns the matched selector or null.
async function clickFirst(page, candidates) {
  for (const c of candidates) {
    const loc = page.locator(c).first();
    if (await loc.isVisible().catch(() => false)) {
      await loc.click();
      return c;
    }
  }
  return null;
}

async function cmdUpload() {
  const name = arg("--name", "Analog Simple");
  const iq = arg("--iq", null);
  const notes = arg("--notes", arg("--notes-file", null) ? readFileSync(arg("--notes-file"), "utf8") : null);
  const dryRun = has("--dry-run");
  if (!iq) throw new Error("--iq <path to .iq> is required");
  const iqPath = resolve(process.cwd(), iq);
  if (!existsSync(iqPath)) throw new Error(`No such file: ${iqPath}`);

  const browser = await launch({ headed: has("--headed") });
  const finishAndFail = async (page, label, message) => {
    await debugDump(page, label);
    await browser.close();
    throw new Error(message);
  };

  try {
    const { page } = await openDashboard(browser);

    // 1. Into the app's own page.
    const links = await appLinks(page);
    const app = links.find((l) => l.text.toLowerCase().includes(name.toLowerCase()));
    if (!app) {
      return await finishAndFail(page, "no-app-match",
        `No app link matching "${name}". Run 'list' to see what the dashboard shows.`);
    }
    console.log(`Opening: ${app.text} — ${app.href}`);
    await page.goto(app.href, { waitUntil: "networkidle" });

    // 2. Find the new-version / update entry point.
    const versionClick = await clickFirst(page, [
      "text=/new version/i",
      "text=/update version/i",
      "text=/upload new version/i",
      "text=/update app/i",
      "a[href*='version']",
    ]);
    if (!versionClick) {
      return await finishAndFail(page, "no-version-entry",
        "Couldn't find a new-version control on the app page.");
    }
    await page.waitForLoadState("networkidle");

    // 3. Attach the .iq.
    const fileInput = page.locator("input[type='file']").first();
    if (!(await fileInput.count())) {
      return await finishAndFail(page, "no-file-input", "No file input on the version page.");
    }
    await fileInput.setInputFiles(iqPath);
    console.log(`Attached: ${iqPath}`);

    // Binary validation runs server-side; give it a generous window.
    await page.waitForTimeout(5000);
    await page.waitForLoadState("networkidle", { timeout: 120000 }).catch(() => {});

    // 4. What's-new notes, if a field exists and notes were given.
    if (notes) {
      for (const sel of ["textarea[name*='what' i]", "textarea[id*='what' i]", "textarea"]) {
        const ta = page.locator(sel).first();
        if (await ta.isVisible().catch(() => false)) {
          await ta.fill(notes);
          console.log("Filled what's-new notes.");
          break;
        }
      }
    }

    if (dryRun) {
      await debugDump(page, "dry-run");
      console.log("Dry run: stopping before submit. Review the screenshot.");
      return;
    }

    // 5. Submit.
    const submitClick = await clickFirst(page, [
      "button:has-text('Submit')",
      "button:has-text('Save')",
      "button:has-text('Publish')",
      "input[type='submit']",
    ]);
    if (!submitClick) {
      return await finishAndFail(page, "no-submit", "Couldn't find a submit control.");
    }
    await page.waitForLoadState("networkidle", { timeout: 120000 }).catch(() => {});
    await debugDump(page, "after-submit");
    console.log("Submitted. Check the after-submit screenshot to confirm the store accepted it.");
  } finally {
    await browser.close().catch(() => {});
  }
}

const cmd = process.argv[2];
const run = { login: cmdLogin, list: cmdList, upload: cmdUpload }[cmd];
if (!run) {
  console.error("Usage: node upload.mjs <login|list|upload> [options]");
  process.exit(2);
}
run().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
