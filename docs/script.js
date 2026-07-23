const root = document.documentElement;
const savedTheme = localStorage.getItem('terminalslides-theme');
if (savedTheme) root.dataset.theme = savedTheme;

document.querySelector('[data-theme-toggle]')?.addEventListener('click', () => {
  root.dataset.theme = root.dataset.theme === 'light' ? 'dark' : 'light';
  localStorage.setItem('terminalslides-theme', root.dataset.theme);
});

document.querySelector('[data-copy]')?.addEventListener('click', async (event) => {
  const button = event.currentTarget;
  await navigator.clipboard.writeText(button.dataset.copy);
  const original = button.textContent;
  button.textContent = 'Copied';
  window.setTimeout(() => { button.textContent = original; }, 1200);
});
