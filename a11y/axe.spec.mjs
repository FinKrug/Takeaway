// Runs axe-core (WCAG 2.0/2.1/2.2 A and AA) against the main pages of a running
// app. Any violation fails the test, so an accessibility regression fails CI.
//
//   cd a11y && npm ci && npx playwright install --with-deps chromium
//   BASE_URL=http://localhost:4000 npm test
import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

async function audit(page, name) {
  const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
  const summary = results.violations.map(
    (v) => `${v.id} (${v.impact}): ${v.help}\n  ${v.nodes.map((n) => n.target.join(" ")).join("\n  ")}`,
  );
  expect(summary, `axe violations on ${name}`).toEqual([]);
}

const publicPages = ["/", "/join", "/organizers/log_in", "/organizers/register"];

for (const path of publicPages) {
  test(`axe: ${path}`, async ({ page }) => {
    await page.goto(path);
    await page.waitForLoadState("networkidle");
    await audit(page, path);
  });
}

test("axe: organizer pages (after registering)", async ({ page }) => {
  const stamp = Date.now();
  await page.goto("/organizers/register");
  await page.getByLabel(/name/i).first().fill("A11y Bot");
  await page.getByLabel(/email/i).fill(`a11y-${stamp}@example.com`);
  await page.getByLabel(/password/i).fill("a-long-enough-password-1");
  await page.getByRole("button", { name: /register|sign up|create/i }).click();
  await page.waitForURL((url) => !url.pathname.includes("/register"));

  for (const path of ["/organizers", "/speeches/new"]) {
    await page.goto(path);
    await page.waitForLoadState("networkidle");
    await audit(page, path);
  }
});
