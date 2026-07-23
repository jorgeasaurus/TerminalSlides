import { expect, test } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('users can navigate the preview and search the complete command reference', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('heading', { name: /Present without leaving the terminal/i })).toBeVisible();
  await expect(page.getByText('Showing 29 of 29')).toBeVisible();
  await expect(page.getByText('Slide 1 of 5')).toBeVisible();

  await page.getByRole('button', { name: 'Next demo slide' }).click();
  await expect(page.getByText('Slide 2 of 5')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Built for live delivery' })).toBeVisible();

  const search = page.getByRole('searchbox', { name: 'Search public commands' });
  await search.fill('Add-SlideImage');
  await expect(page.getByText('Showing 1 of 29')).toBeVisible();
  await expect(page.getByText('Add-SlideImage', { exact: true })).toBeVisible();

  await search.press('n');
  await expect(search).toHaveValue('Add-SlideImagen');
  await expect(page.getByText('Slide 2 of 5')).toBeVisible();
});

test('the styled layout adapts between desktop and mobile viewports', async ({ page }, testInfo) => {
  await page.goto('/');

  const heading = page.getByRole('heading', { level: 1, name: /Present without leaving the terminal/i });
  const preview = page.getByLabel('Interactive TerminalSlides preview');
  const importCommand = page.getByLabel('Import command', { exact: true });
  await expect(heading).toBeVisible();
  await expect(preview).toBeVisible();

  const styleContract = await preview.evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      backgroundColor: style.backgroundColor,
      borderRadius: style.borderRadius,
      loadedRuleCount: [...document.styleSheets].reduce((count, sheet) => count + sheet.cssRules.length, 0),
      horizontalOverflow: document.documentElement.scrollWidth - window.innerWidth,
    };
  });
  expect(styleContract.loadedRuleCount).toBeGreaterThan(100);
  expect(styleContract.backgroundColor).toBe('rgb(5, 10, 17)');
  expect(styleContract.borderRadius).toBe('14px');
  expect(styleContract.horizontalOverflow).toBeLessThanOrEqual(1);

  const headingBox = await heading.boundingBox();
  const previewBox = await preview.boundingBox();
  const importBox = await importCommand.boundingBox();
  expect(headingBox).not.toBeNull();
  expect(previewBox).not.toBeNull();
  expect(importBox).not.toBeNull();

  const featuresLink = page.getByRole('link', { name: 'Features', exact: true });
  if (testInfo.project.name === 'mobile-chromium') {
    await expect(featuresLink).toBeHidden();
    expect(previewBox.y).toBeGreaterThan(importBox.y + importBox.height);
  } else {
    await expect(featuresLink).toBeVisible();
    expect(previewBox.x).toBeGreaterThan(headingBox.x + headingBox.width);
    expect(previewBox.y).toBeLessThan(headingBox.y + headingBox.height);
  }
});

test('the presentation photo is a browser-renderable image', async ({ page, request }) => {
  const response = await request.get('/presentation-team-photo.jpg');
  expect(response.ok()).toBeTruthy();
  expect(response.headers()['content-type']).toBe('image/jpeg');

  await page.goto('/presentation-team-photo.jpg');
  const image = page.getByRole('img');
  await expect(image).toBeVisible();
  const dimensions = await image.evaluate((element) => ({
    width: element.naturalWidth,
    height: element.naturalHeight,
  }));
  expect(dimensions.width).toBe(1200);
  expect(dimensions.height).toBe(800);
});

test('the documentation server rejects malformed and traversing paths safely', async ({ request }) => {
  const malformed = await request.get('/%E0%A4%A');
  expect(malformed.status()).toBe(400);

  const traversal = await request.get('/%2e%2e%2fpackage.json');
  expect(traversal.status()).toBe(403);

  const dottedFilename = await request.get('/..missing');
  expect(dottedFilename.status()).toBe(404);
});

test('exported quote attribution preserves logical rows in Chromium', async ({ page }) => {
  const outputDirectory = mkdtempSync(join(tmpdir(), 'terminalslides-browser-'));
  const outputPath = join(outputDirectory, 'quote.html');
  const exportScript = `
    Import-Module (Join-Path (Get-Location) 'TerminalSlides.psd1') -Force
    $deck = New-TerminalPresentation -Title 'Quote rows'
    $attribution = 'Ada<&' + [char]13 + 'Grace' + [char]10 + 'Linus' + [char]13 + [char]10 + 'End'
    $deck | Add-TerminalSlide -Title 'Quote' -Content {
      Add-SlideQuote -Text 'A logical row should stay visible.' -Attribution $attribution
    } | Out-Null
    Export-TerminalPresentation -Presentation $deck -Path $env:TERMINALSLIDES_BROWSER_EXPORT -Format Html | Out-Null
  `;

  try {
    const result = spawnSync('pwsh', ['-NoLogo', '-NoProfile', '-Command', exportScript], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: { ...process.env, TERMINALSLIDES_BROWSER_EXPORT: outputPath },
    });
    expect(result.status, result.stderr || result.stdout).toBe(0);

    await page.setContent(readFileSync(outputPath, 'utf8'));
    const rendered = await page.locator('.slide footer').evaluate((element) => ({
      innerText: element.innerText,
      whiteSpace: getComputedStyle(element).whiteSpace,
    }));
    expect(rendered.innerText).toBe('— Ada<&\nGrace\nLinus\nEnd');
    expect(rendered.whiteSpace).toBe('pre-wrap');
  } finally {
    rmSync(outputDirectory, { recursive: true, force: true });
  }
});

test('all internal links and fragments resolve', async ({ page, request }) => {
  await page.goto('/');
  const hrefs = await page.getByRole('link').evaluateAll((links) =>
    [...new Set(links.map((link) => link.getAttribute('href')).filter(Boolean))]
  );

  for (const href of hrefs) {
    const url = new URL(href, page.url());
    if (url.origin !== new URL(page.url()).origin) continue;

    const response = await request.get(url.pathname);
    expect(response.ok(), `Internal link ${href} should resolve`).toBeTruthy();
    if (url.hash) {
      await page.goto(url.href);
      const targetExists = await page.evaluate(
        (id) => Boolean(document.getElementById(id)),
        decodeURIComponent(url.hash.slice(1))
      );
      expect(targetExists, `Fragment ${href} should resolve`).toBeTruthy();
    }
  }
});
