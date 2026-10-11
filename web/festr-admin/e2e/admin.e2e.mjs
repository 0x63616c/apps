// End-to-end check against a running admin with a seeded database and FESTR_VISION_MOCK=1.
// Usage: E2E_PASSWORD=... [E2E_BASE_URL=http://localhost:3000] [E2E_SCREENSHOTS=dir] pnpm e2e
// Note: the final step locks out the client IP for 15 minutes (clear the login_attempts table to reset).
import { mkdirSync } from "node:fs";
import { chromium } from "playwright";

const BASE = process.env.E2E_BASE_URL ?? "http://localhost:3000";
const OUT = process.env.E2E_SCREENSHOTS ?? "build/e2e";
mkdirSync(OUT, { recursive: true });
const password = process.env.E2E_PASSWORD ?? "";
if (!password) throw new Error("Set E2E_PASSWORD");
const email = process.env.ADMIN_EMAIL ?? "calumpeterwebb@icloud.com";

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 },
  deviceScaleFactor: 2,
  colorScheme: "dark",
});
const page = await context.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
const step = (name) => console.log("✓", name);
const shot = async (name) => {
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${OUT}/${name}.png` });
};

// Login: redirect, wrong password, then success.
await page.goto(`${BASE}/festivals/head-trip-2026`);
await page.waitForURL(/\/login\?next=/);
step("signed-out visit redirects to /login with next");
await shot("1-login");
await page.fill("#email", email);
await page.fill("#password", "wrong-password");
await page.click("button[type=submit]");
await page.getByText("Invalid email or password").waitFor();
step("wrong password rejected");
await page.fill("#password", password);
await page.click("button[type=submit]");
await page.waitForURL(`${BASE}/festivals/head-trip-2026`);
step("login redirects back to next");
const cookie = (await context.cookies()).find((c) => c.name === "festr_session");
if (!cookie?.httpOnly || cookie.sameSite !== "Lax") throw new Error("session cookie flags");
step("session cookie is httpOnly + SameSite=Lax");

await page.goto(BASE);
await page.getByRole("link", { name: "Head Trip" }).waitFor();
await shot("2-festivals");
step("festivals list");

await page.getByRole("link", { name: "Head Trip" }).click();
await page.getByRole("tab", { name: /Sets/ }).waitFor();
await page.getByText("Calvin Harris").first().waitFor();
await shot("3-festival-sets");
step("festival sets tab");

// Add a set through the dialog (Sunday, after midnight start), then delete it.
await page.getByRole("button", { name: "Add set" }).click();
await page.fill("#artist", "E2E Test Act");
await page.getByRole("combobox", { name: "Day" }).click();
await page.getByRole("option", { name: "Sun, Oct 11" }).click();
await page.fill("#start", "00:15");
await page.fill("#end", "01:00");
await shot("4-set-dialog");
await page.getByRole("button", { name: "Save" }).click();
await page.getByText("Set added").waitFor();
const row = page.getByRole("row", { name: /E2E Test Act/ });
await row.waitFor();
const rowText = await row.innerText();
if (!rowText.includes("00:15")) throw new Error(`unexpected row: ${rowText}`);
step("set added via dialog");
await page.getByText("Unpublished changes").count();
await row.getByRole("button", { name: /Delete/ }).click();
await page.getByRole("alertdialog").getByRole("button", { name: "Delete" }).click();
await page.getByText("Set deleted").waitFor();
step("set deleted via confirm dialog");

await page.getByRole("tab", { name: /Stages/ }).click();
await page
  .getByRole("cell", { name: /Sunflower/ })
  .first()
  .waitFor();
await shot("5-festival-stages");
await page.getByRole("tab", { name: "Details" }).click();
await page.locator("#venue").waitFor();
await shot("6-festival-details");
step("stages and details tabs");

// Import: paste preview, then image extraction (mock model on this server).
await page.goto(`${BASE}/festivals/head-trip-2026/import`);
await page
  .getByLabel("Sets as CSV")
  .fill("DJ Harvey, Main Stage, Sun, 3:30 PM, 5:00 PM\nSwedish House Mafia, Main Stage, Sunday, 22:30, late");
await page.getByRole("button", { name: "Preview" }).click();
await page.getByRole("button", { name: "Save 2 sets" }).waitFor();
await shot("7-import-paste");
step("CSV paste preview");
await page.getByRole("tab", { name: "Image" }).click();
await page.setInputFiles("#image", new URL("./poster.png", import.meta.url).pathname);
await page.getByRole("button", { name: "Extract" }).click();
await page.getByText("Found 2 sets").waitFor();
await page.getByRole("button", { name: "Save 2 sets" }).waitFor();
await page.mouse.move(0, 0);
await shot("8-import-image");
step("image extraction into editable preview");

// Publish and check the feed.
await page.goto(BASE);
const publish = page.getByRole("button", { name: "Publish" });
if (await publish.isEnabled()) {
  await publish.click();
  await page.getByText(/Published v\d+/).waitFor();
  step("published");
}
const feed = await (await fetch(`${BASE}/feed/index.json`)).json();
if (feed.schemaVersion !== 1 || feed.festivals.length < 5) throw new Error("feed");
step(`feed has ${feed.festivals.length} festivals`);

// Light mode sample.
await page.getByRole("button", { name: "Toggle theme" }).click();
await page.waitForTimeout(300);
await shot("9-festivals-light");
await page.getByRole("button", { name: "Toggle theme" }).click();

// Logout.
await page.getByRole("button", { name: "Account" }).click();
await page.getByRole("menuitem", { name: "Log out" }).click();
await page.waitForURL(/\/login/);
step("logout");

// Rate limit: the sixth wrong attempt within 15 minutes is refused.
const attempt = async (pw) => {
  await page.fill("#email", "someone@example.com");
  await page.fill("#password", pw);
  await Promise.all([
    page.waitForResponse((r) => r.request().method() === "POST" && r.url().includes("/login")),
    page.click("button[type=submit]"),
  ]);
  await page.waitForTimeout(200);
};
for (let i = 0; i < 5; i++) await attempt(`nope-${i}`);
await attempt("nope-final");
await page.getByText(/Too many attempts/).waitFor();
step("rate limit after 5 failures");

await browser.close();
const relevant = errors.filter((e) => !e.includes("401") && !e.includes("Failed to load resource"));
if (relevant.length) console.log("Console errors:\n" + relevant.join("\n"));
console.log("E2E passed");
