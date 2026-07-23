import { expect, test } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('the landing page stays focused and links into the guides', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('heading', { name: 'Present without leaving the terminal' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Get started' })).toHaveAttribute('href', 'guides/get-started/');
  await expect(page.getByRole('link', { name: 'Read the guides' })).toHaveAttribute('href', 'guides/');
  await expect(page.getByLabel('Install command').locator('code')).toHaveText(
    'Install-Module TerminalSlides'
  );
  await expect(page.locator('#command-grid')).toHaveCount(0);
});

test('the guides expose every command and filter the sidebar locally', async ({ page }, testInfo) => {
  await page.goto('/guides/');

  await expect(page.getByRole('heading', { name: 'TerminalSlides guides' })).toBeVisible();
  if (testInfo.project.name === 'mobile-chromium') {
    await page.getByRole('button', { name: 'Open guide navigation' }).click();
  }
  const commands = page.locator('[data-command-name]');
  await expect(commands).toHaveCount(29);

  const search = page.locator('[data-command-search]');
  await search.fill('Add-SlideImage');
  await expect(page.locator('[data-command-name]:visible')).toHaveCount(1);
  await expect(page.getByRole('link', { name: 'Add-SlideImage' })).toBeVisible();
  await page.getByRole('link', { name: 'Add-SlideImage' }).click();
  await expect(page).toHaveURL(/\/guides\/commands\/add-slideimage\/$/);
});

test('each command guide presents description, examples, parameters, and syntax', async ({ page }) => {
  await page.goto('/guides/commands/show-terminalpresentation/');

  await expect(page.getByRole('heading', { level: 1, name: 'Show-TerminalPresentation' })).toBeVisible();
  for (const heading of ['Description', 'Examples', 'Parameters', 'Syntax']) {
    await expect(page.getByRole('heading', { level: 2, name: heading })).toBeVisible();
  }
  await expect(page.getByText('-ImageRenderer', { exact: true })).toBeVisible();
  await expect(page.getByText('Blocks, Sixel', { exact: false })).toBeVisible();
  await expect(page.locator('#syntax')).toContainText('Show-TerminalPresentation -Presentation');
});

test('the documentation layout is responsive without horizontal page overflow', async ({ page }, testInfo) => {
  await page.goto('/guides/commands/add-slideimage/');

  const article = page.locator('.docs-article');
  await expect(article).toBeVisible();
  const layout = await page.evaluate(() => ({
    overflow: document.documentElement.scrollWidth - window.innerWidth,
    rules: [...document.styleSheets].reduce((count, sheet) => count + sheet.cssRules.length, 0),
  }));
  expect(layout.overflow).toBeLessThanOrEqual(1);
  expect(layout.rules).toBeGreaterThan(60);

  const sidebar = page.locator('[data-sidebar]');
  if (testInfo.project.name === 'mobile-chromium') {
    await expect(sidebar).not.toBeInViewport();
    await page.getByRole('button', { name: 'Open guide navigation' }).click();
    await expect(sidebar).toBeInViewport();
    await expect(page.locator('[data-command-search]')).toBeVisible();
  } else {
    await expect(sidebar).toBeInViewport();
    await expect(page.locator('.page-toc')).toBeVisible();
  }
});

test('the presentation photo is a browser-renderable image', async ({ page, request }) => {
  const response = await request.get('/presentation-team-photo.jpg');
  expect(response.ok()).toBeTruthy();
  expect(response.headers()['content-type']).toBe('image/jpeg');

  await page.goto('/presentation-team-photo.jpg');
  const dimensions = await page.getByRole('img').evaluate((element) => ({
    width: element.naturalWidth,
    height: element.naturalHeight,
  }));
  expect(dimensions).toEqual({ width: 1200, height: 800 });
});

test('the themes guide presents every built-in terminal capture', async ({ page }) => {
  await page.goto('/guides/themes/');

  const expectedThemes = [
    'Midnight', 'PowerShell', 'Solarized Dark', 'Solarized Light',
    'Retro Terminal', 'Minimal', 'Monochrome', 'High Contrast',
  ];
  const gallery = page.getByLabel('Built-in terminal theme previews');
  const cards = gallery.locator('.theme-card');
  await expect(cards).toHaveCount(expectedThemes.length);
  for (const theme of expectedThemes) {
    await expect(cards.filter({ hasText: theme })).toHaveCount(1);
  }
  const captures = await cards.locator('img').evaluateAll((images) =>
    images.map((image) => ({
      alt: image.alt,
      complete: image.complete,
      height: image.naturalHeight,
      width: image.naturalWidth,
    }))
  );
  for (const capture of captures) {
    expect(capture.alt).not.toBe('');
    expect(capture.complete).toBeTruthy();
    expect(capture.width).toBe(1600);
    expect(capture.height).toBe(900);
  }
});

test('the documentation server resolves directory routes and rejects unsafe paths', async ({ request }) => {
  for (const route of ['/guides/', '/guides/install/', '/guides/commands/add-slideimage/']) {
    const response = await request.get(route);
    expect(response.ok(), `${route} should resolve`).toBeTruthy();
    expect(response.headers()['content-type']).toContain('text/html');
  }

  expect((await request.get('/%E0%A4%A')).status()).toBe(400);
  expect((await request.get('/%2e%2e%2fpackage.json')).status()).toBe(403);
  expect((await request.get('/..missing')).status()).toBe(404);
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

test('all published guide routes and internal links resolve', async ({ request }) => {
  const commandResponse = await request.get('/commands.json');
  const commands = await commandResponse.json();
  const routes = [
    '/',
    '/guides/',
    '/guides/install/',
    '/guides/get-started/',
    '/guides/themes/',
    '/guides/media/',
    ...commands.map(({ name }) => `/guides/commands/${name.toLowerCase()}/`),
  ];

  for (const route of routes) {
    const response = await request.get(route);
    expect(response.ok(), `${route} should resolve`).toBeTruthy();
    const html = await response.text();
    const hrefs = [...html.matchAll(/href="([^"]+)"/g)].map((match) => match[1]);
    for (const href of hrefs) {
      const target = new URL(href, `http://127.0.0.1:4173${route}`);
      if (target.origin !== 'http://127.0.0.1:4173' || target.hash) continue;
      const linked = await request.get(target.pathname);
      expect(linked.ok(), `${route} links to missing ${href}`).toBeTruthy();
    }
  }
});
