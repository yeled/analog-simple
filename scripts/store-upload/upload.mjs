#!/usr/bin/env node
// Upload a .iq to the Garmin Connect IQ store via the developer dashboard.
//
// Garmin has no publishing API (asked-for since 2020, never shipped), so this
// drives the dashboard in Chrome. Cloudflare's bot check refuses browsers that
// Playwright *launches* (the automation fingerprint is visible to Turnstile),
// so the architecture is inverted: a real, un-instrumented Chrome runs on a
// dedicated profile with its debug port open, you sign in there like a human
// — nothing attaches during login, the poll below only reads the tab list
// over HTTP — and Playwright connects over CDP afterwards, to a session
// Cloudflare already blessed. The profile persists, so subsequent runs are
// already signed in.
//
//   node upload.mjs login [--timeout-mins 10]
//   node upload.mjs list
//   node upload.mjs upload --name "Analog Simple" --iq ../../bin/analog-simple-1.6.3.iq \
//        --notes "Wind hairline; badge fixes" [--dry-run]
//
// State lives outside the repo in ~/.config/analog-simple/ (Chrome profile +
// a storageState snapshot) so nothing sensitive can be committed. Every
// failure saves a screenshot + HTML dump into bin/ so selectors can be fixed
// without another sign-in.

import { chromium } from "playwright-core";
import { spawn } from "node:child_process";
import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..", "..");
const STATE_DIR = join(homedir(), ".config", "analog-simple");
const STATE_FILE = join(STATE_DIR, "garmin-session.json");
const PROFILE_DIR = join(STATE_DIR, "chrome-profile");
const CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const CDP_PORT = 9222;
const CDP = `http://127.0.0.1:${CDP_PORT}`;
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

// The tab list over plain HTTP — reads page URLs without instrumenting any
// page, so it is invisible to bot detection.
async function cdpTabs() {
  try {
    const r = await fetch(`${CDP}/json/list`);
    return await r.json();
  } catch {
    return null;
  }
}

// Make sure the dedicated-profile Chrome is running with its debug port
// open, starting it on `url` if it isn't.
async function ensureChrome(url) {
  if (await cdpTabs()) {
    if (url) {
      await fetch(`${CDP}/json/new?${encodeURIComponent(url)}`, { method: "PUT" }).catch(() => {});
    }
    return;
  }
  if (!existsSync(CHROME_BIN)) {
    throw new Error(`Chrome not found at ${CHROME_BIN}`);
  }
  mkdirSync(PROFILE_DIR, { recursive: true });
  const child = spawn(
    CHROME_BIN,
    [
      `--user-data-dir=${PROFILE_DIR}`,
      `--remote-debugging-port=${CDP_PORT}`,
      "--no-first-run",
      "--no-default-browser-check",
      url ?? DASHBOARD,
    ],
    { detached: true, stdio: "ignore" }
  );
  child.unref();
  for (let i = 0; i < 40; i++) {
    if (await cdpTabs()) return;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("Chrome started but the debug port never answered.");
}

// True once the page is a signed-in developer dashboard rather than an SSO,
// Cloudflare or marketing page. Kept loose on purpose: the markup shifts.
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
  await ensureChrome(DASHBOARD);
  const minutes = Number(arg("--timeout-mins", "10"));
  console.log("A separate Chrome (its own profile, no automation attached) is open.");
  console.log("Sign in to the developer dashboard there — paste the password from");
  console.log(`1Password; this profile has no extensions. Waiting up to ${minutes} minutes...`);

  // Watch the tab list; attach nothing while any auth-ish page is up. The
  // sign-in form is served from apps.garmin.com itself (spelled "sign-in"),
  // so the URL alone can't prove login — when a candidate appears, attach
  // briefly to verify, and if it isn't signed in yet, detach and keep
  // waiting rather than giving up on the user mid-password.
  const deadline = Date.now() + minutes * 60 * 1000;
  const authish = /sso\.|sign-?in|login|auth|cloudflare|challenge/i;
  while (Date.now() < deadline) {
    const tabs = (await cdpTabs()) ?? [];
    const candidate = tabs.some(
      (t) => t.type === "page" && /apps\.garmin\.com/.test(t.url) && !authish.test(t.url)
    );
    if (candidate) {
      const browser = await chromium.connectOverCDP(CDP);
      try {
        const context = browser.contexts()[0];
        const page = context
          .pages()
          .find((p) => /apps\.garmin\.com/.test(p.url()) && !authish.test(p.url()));
        if (page != null && (await looksSignedIn(page))) {
          await context.storageState({ path: STATE_FILE });
          console.log(`Signed in. Session snapshot: ${STATE_FILE}`);
          console.log("You can close that Chrome window — the profile keeps the session.");
          return;
        }
      } finally {
        await browser.close(); // detaches; the real Chrome keeps running
      }
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error("Timed out: no signed-in dashboard tab appeared.");
}

// Shared entry for list/upload: real Chrome on the dedicated profile,
// attached over CDP, dashboard open and signed in.
async function openDashboard() {
  await ensureChrome(DASHBOARD);
  const browser = await chromium.connectOverCDP(CDP);
  const context = browser.contexts()[0];
  const page =
    context.pages().find((p) => /apps\.garmin\.com/.test(p.url())) ?? (await context.newPage());
  await page.goto(DASHBOARD, { waitUntil: "networkidle" }).catch(() => {});
  if (!(await looksSignedIn(page))) {
    await debugDump(page, "session-expired");
    throw new Error("Not signed in (session expired?). Run: node upload.mjs login");
  }
  return { browser, page };
}

async function appLinks(page) {
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

// The dashboard lists the developer account; the apps themselves live one
// level deeper at /developer/<uuid>/apps. Descend there if we aren't
// already, then return the app entries.
async function gotoApps(page) {
  if (!/\/developer\/[^/]+\/apps/.test(page.url())) {
    const devApps = (await appLinks(page)).find((l) => /\/developer\/[^/]+\/apps\/?$/.test(l.href));
    if (devApps) {
      await page.goto(devApps.href, { waitUntil: "networkidle" });
    }
  }
  // The apps page renders each app as a data-tid="app-card" card: the name
  // lives in the icon's title attribute and the link is the card's anchor.
  const entries = await page.$$eval("[data-tid='app-card']", (cards) =>
    cards.map((card) => {
      const img = card.querySelector("img[title]");
      const a = card.querySelector("a[href]");
      const status = (card.textContent.match(/Status:\s*\w+/) || [""])[0];
      const beta = /BETA/.test(card.textContent) ? " [BETA]" : "";
      return {
        text: `${img ? img.title : "?"}${beta}${status ? " — " + status : ""}`,
        name: img ? img.title : "",
        href: a ? a.href : null,
      };
    }).filter((l) => l.href)
  );
  const seen = new Set();
  return entries.filter((l) => !seen.has(l.href) && seen.add(l.href));
}

async function cmdList() {
  const { browser, page } = await openDashboard();
  try {
    const apps = await gotoApps(page);
    if (apps.length === 0) {
      await debugDump(page, "list-empty");
      console.log("No app entries recognised — see debug artifacts for the real markup.");
    }
    for (const l of apps) {
      console.log(`${l.text}\n    ${l.href}`);
    }
  } finally {
    await browser.close();
  }
}

async function clickFirst(page, candidates) {
  for (const c of candidates) {
    const loc = page.locator(c).first();
    if (
      (await loc.isVisible().catch(() => false)) &&
      (await loc.isEnabled().catch(() => false))
    ) {
      await loc.scrollIntoViewIfNeeded().catch(() => {});
      try {
        await loc.click({ timeout: 10000 });
        return c;
      } catch {
        // fall through to the next candidate
      }
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

  const { browser, page } = await openDashboard();
  const fail = async (label, message) => {
    await debugDump(page, label);
    await browser.close();
    throw new Error(message);
  };

  try {
    const apps = await gotoApps(page);
    const app = apps.find((l) => l.name.toLowerCase().includes(name.toLowerCase()));
    if (!app) {
      return await fail("no-app-match",
        `No app entry matching "${name}". Run 'list' to see what the dashboard shows.`);
    }
    console.log(`Opening: ${app.text} — ${app.href}`);
    await page.goto(app.href, { waitUntil: "networkidle" });

    // "Upload New Version" opens a native file chooser rather than exposing
    // an input, so arm the filechooser listener before clicking.
    const chooserPromise = page.waitForEvent("filechooser", { timeout: 15000 }).catch(() => null);
    const versionClick = await clickFirst(page, [
      "button:has-text('Upload New Version')",
      "text=/upload new version/i",
      "text=/new version/i",
      "text=/update version/i",
    ]);
    if (!versionClick) {
      return await fail("no-version-entry", "Couldn't find an upload-new-version control.");
    }
    const chooser = await chooserPromise;
    if (chooser) {
      await chooser.setFiles(iqPath);
    } else {
      // Fallback: some flows render a modal with a real input instead.
      const fileInput = page.locator("input[type='file']").first();
      if (!(await fileInput.count())) {
        return await fail("no-file-input", "Neither a file chooser nor a file input appeared.");
      }
      await fileInput.setInputFiles(iqPath);
    }
    console.log(`Attached: ${iqPath}`);

    // Step 1 also wants the human-readable version string. Derive it from
    // the .iq filename (analog-simple-<version>.iq) unless --version given.
    const version =
      arg("--version", null) ?? (iqPath.match(/analog-simple-([0-9][^/]*?)\.iq$/) || [])[1];
    if (!version) {
      return await fail("no-version-string",
        "Couldn't derive a version from the filename; pass --version.");
    }
    let versionFilled = false;
    for (const make of [
      () => page.getByLabel(/app version/i),
      () => page.locator("input:below(:text('App Version'))").first(),
      () => page.locator("input[type='text']").last(),
    ]) {
      const field = make();
      if (await field.isVisible().catch(() => false)) {
        await field.fill(version);
        versionFilled = true;
        break;
      }
    }
    if (!versionFilled) {
      return await fail("no-version-field", "Couldn't find the App Version field.");
    }
    console.log(`Version: ${version}`);

    if (dryRun) {
      await debugDump(page, "dry-run");
      console.log("Dry run: stopping before 'Upload and publish'. Review the screenshot.");
      return;
    }

    // Step 1 → Step 2: uploads the binary and verifies it server-side.
    const uploadClick = await clickFirst(page, [
      "button:has-text('Upload and publish')",
      "button:has-text('Upload')",
    ]);
    if (!uploadClick) {
      return await fail("no-upload-button", "Couldn't find the Upload and publish button.");
    }
    console.log("Uploading; waiting for verification...");
    // The public .iq carries 60+ device builds and verification is slow —
    // wait for Step 2's verified panel, not for the network to go quiet.
    try {
      await page
        .locator("text=/Status:\\s*Verified/i")
        .first()
        .waitFor({ timeout: 300000 });
    } catch {
      return await fail("verify-timeout",
        "Binary verification didn't complete within 5 minutes.");
    }
    await page.waitForTimeout(2000);
    await debugDump(page, "step2");

    // Step 2: what's-new (never the description field), then the final
    // submit — exact button text, so 'Submit' can't match the Step 1
    // 'Upload and publish' button lingering disabled in the DOM.
    if (notes) {
      let filled = false;
      for (const sel of ["textarea[name*='what' i]", "textarea[id*='what' i]"]) {
        const ta = page.locator(sel).first();
        if (await ta.isVisible().catch(() => false)) {
          await ta.fill(notes);
          filled = true;
          break;
        }
      }
      if (!filled) {
        const tas = page.locator("textarea");
        if ((await tas.count()) >= 2) {
          await tas.nth(1).fill(notes);
          filled = true;
        }
      }
      console.log(filled ? "Filled what's-new notes." : "No what's-new field found; continuing.");
    }
    // The dashboard disables Submit for a beat while it validates the field
    // just edited, and sometimes floats a "Not Now / Get Started" popup over
    // the form — so retry with a native DOM click (Playwright's actionability
    // checks lose this race) until the button takes or a minute passes.
    let submitted = false;
    for (let i = 0; i < 30 && !submitted; i++) {
      submitted = await page.evaluate(() => {
        const dismiss = [...document.querySelectorAll("button")]
          .find((b) => b.textContent.trim() === "Not Now");
        if (dismiss) dismiss.click();
        const btn = [...document.querySelectorAll("button, input[type='submit']")]
          .find((b) => /^(Submit|Publish|Save)$/.test((b.textContent || b.value || "").trim()) && !b.disabled);
        if (!btn) return false;
        btn.scrollIntoView();
        btn.click();
        return true;
      });
      if (!submitted) await page.waitForTimeout(2000);
    }
    if (!submitted) {
      return await fail("no-submit",
        "Submit never became clickable on Step 2 — see the step2 artifacts.");
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
