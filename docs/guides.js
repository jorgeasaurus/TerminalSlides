const html = document.documentElement;
const body = document.body;
const rootPath = body.dataset.root ?? '../';
const currentCommand = body.dataset.currentCommand?.toLowerCase();
const sidebar = document.querySelector('[data-sidebar]');
const navigation = document.querySelector('[data-command-navigation]');
const search = document.querySelector('[data-command-search]');

const savedTheme = localStorage.getItem('terminalslides-theme');
if (savedTheme) html.dataset.theme = savedTheme;

document.querySelector('[data-theme-toggle]')?.addEventListener('click', () => {
  html.dataset.theme = html.dataset.theme === 'light' ? 'dark' : 'light';
  localStorage.setItem('terminalslides-theme', html.dataset.theme);
});

function slug(value) {
  return value.toLowerCase();
}

function link(href, label, current = false) {
  const anchor = document.createElement('a');
  anchor.href = href;
  anchor.textContent = label;
  if (current) anchor.setAttribute('aria-current', 'page');
  return anchor;
}

function group(title) {
  const section = document.createElement('section');
  section.className = 'nav-group';
  const heading = document.createElement('h2');
  heading.textContent = title;
  section.append(heading);
  return section;
}

async function buildNavigation() {
  if (!navigation) return;
  const guideGroup = group('Guides');
  const guideLinks = [
    ['guides/', 'Overview'],
    ['guides/install/', 'Install'],
    ['guides/get-started/', 'Get started'],
    ['guides/themes/', 'Themes'],
    ['guides/media/', 'Images and media'],
  ];
  for (const [path, label] of guideLinks) {
    const href = `${rootPath}${path}`;
    const current = new URL(href, location.href).pathname === location.pathname;
    guideGroup.append(link(href, label, current));
  }
  navigation.append(guideGroup);

  const response = await fetch(`${rootPath}commands.json`);
  if (!response.ok) throw new Error(`Command catalog request failed: ${response.status}`);
  const commands = await response.json();
  const categories = [...new Set(commands.map((command) => command.category))];
  for (const category of categories) {
    const commandGroup = group(category);
    for (const command of commands.filter((item) => item.category === category)) {
      const name = command.name;
      const anchor = link(
        `${rootPath}guides/commands/${slug(name)}/`,
        name,
        currentCommand === slug(name)
      );
      anchor.dataset.commandName = name.toLowerCase();
      anchor.dataset.commandDescription = command.description.toLowerCase();
      commandGroup.append(anchor);
    }
    navigation.append(commandGroup);
  }
}

function filterCommands() {
  const query = search?.value.trim().toLowerCase() ?? '';
  for (const anchor of document.querySelectorAll('[data-command-name]')) {
    anchor.hidden = Boolean(query) &&
      !anchor.dataset.commandName.includes(query) &&
      !anchor.dataset.commandDescription.includes(query);
  }
  for (const section of document.querySelectorAll('.nav-group')) {
    const commandLinks = section.querySelectorAll('[data-command-name]');
    if (commandLinks.length) {
      section.hidden = [...commandLinks].every((anchor) => anchor.hidden);
    }
  }
}

function closeSidebar() {
  if (!sidebar) return;
  sidebar.dataset.open = 'false';
  document.querySelector('.sidebar-backdrop')?.setAttribute('data-open', 'false');
}

function toggleSidebar() {
  if (!sidebar) return;
  const isOpen = sidebar.dataset.open === 'true';
  sidebar.dataset.open = String(!isOpen);
  document.querySelector('.sidebar-backdrop')?.setAttribute('data-open', String(!isOpen));
}

const backdrop = document.createElement('button');
backdrop.type = 'button';
backdrop.className = 'sidebar-backdrop';
backdrop.setAttribute('aria-label', 'Close guide navigation');
backdrop.addEventListener('click', closeSidebar);
document.body.append(backdrop);

document.querySelector('[data-sidebar-toggle]')?.addEventListener('click', toggleSidebar);
document.querySelector('[data-search-focus]')?.addEventListener('click', () => search?.focus());
search?.addEventListener('input', filterCommands);
document.addEventListener('keydown', (event) => {
  if (event.key === '/' && !['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) {
    event.preventDefault();
    search?.focus();
  }
  if (event.key === 'Escape') closeSidebar();
});

buildNavigation().then(filterCommands).catch((error) => {
  if (navigation) navigation.textContent = `Command navigation unavailable: ${error.message}`;
});
