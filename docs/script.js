const slides = [
  {
    kicker: "01 / Compose",
    title: "Slides as PowerShell",
    content: `<ul><li>Fluent pipeline API</li><li>Readable slide DSL</li><li>Versionable alongside your code</li></ul>`,
  },
  {
    kicker: "02 / Present",
    title: "Built for live delivery",
    content: `<ul><li>Progressive reveals</li><li>Speaker notes and timer</li><li>Keyboard navigation from start to finish</li></ul>`,
  },
  {
    kicker: "03 / Visualize",
    title: "More than plain text",
    content: `<div class="terminal-code">[A] Idea<br>&nbsp;└─&gt; [B] Deck<br>&nbsp;&nbsp;&nbsp;&nbsp;└─&gt; [C] Terminal</div>`,
  },
  {
    kicker: "04 / Adapt",
    title: "Every terminal is a venue",
    content: `<ul><li>Truecolor ANSI themes</li><li>Viewport-aware layouts</li><li>Automatic capability detection</li></ul>`,
  },
  {
    kicker: "05 / Share",
    title: "Export the same story",
    content: `<ul><li>HTML and Markdown</li><li>JSON and PSD1</li><li>ANSI and plain text</li></ul>`,
  },
];

const root = document.documentElement;
const themeButton = document.querySelector(".theme-toggle");
const storedTheme = localStorage.getItem("terminalslides-theme");
if (storedTheme === "light" || storedTheme === "dark") root.dataset.theme = storedTheme;

themeButton.addEventListener("click", () => {
  root.dataset.theme = root.dataset.theme === "light" ? "dark" : "light";
  localStorage.setItem("terminalslides-theme", root.dataset.theme);
});

async function copyText(button, text) {
  const original = button.textContent;
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = "Copied";
  } catch {
    button.textContent = "Copy failed";
  }
  window.setTimeout(() => { button.textContent = original; }, 1400);
}

document.querySelectorAll(".copy-button").forEach((button) => {
  button.addEventListener("click", async () => {
    const target = button.dataset.copyTarget && document.getElementById(button.dataset.copyTarget);
    const text = button.dataset.copy || target?.innerText || "";
    await copyText(button, text);
  });
});

let activeSlide = 0;
const kicker = document.getElementById("slide-kicker");
const title = document.getElementById("slide-title");
const content = document.getElementById("slide-content");
const count = document.getElementById("slide-count");
const progress = document.getElementById("slide-progress");

function renderSlide() {
  const slide = slides[activeSlide];
  kicker.textContent = slide.kicker;
  title.textContent = slide.title;
  content.innerHTML = slide.content;
  count.textContent = `Slide ${activeSlide + 1} of ${slides.length}`;
  progress.style.width = `${((activeSlide + 1) / slides.length) * 100}%`;
}

function moveSlide(direction) {
  activeSlide = (activeSlide + direction + slides.length) % slides.length;
  renderSlide();
}

function isInteractiveTarget(target) {
  return Boolean(target?.closest?.("button, a, input, textarea, select, summary, [contenteditable], [role='button']"));
}

document.getElementById("previous-slide").addEventListener("click", () => moveSlide(-1));
document.getElementById("next-slide").addEventListener("click", () => moveSlide(1));

document.addEventListener("keydown", (event) => {
  if (isInteractiveTarget(event.target)) return;
  if (["ArrowRight", "PageDown", "n", "N", " "].includes(event.key)) {
    event.preventDefault();
    moveSlide(1);
  }
  if (["ArrowLeft", "PageUp", "p", "P"].includes(event.key)) {
    event.preventDefault();
    moveSlide(-1);
  }
  if (event.key === "Home") { activeSlide = 0; renderSlide(); }
  if (event.key === "End") { activeSlide = slides.length - 1; renderSlide(); }
});

renderSlide();

const commandGrid = document.getElementById("command-grid");
const commandSearch = document.getElementById("command-search");
const commandFilters = document.getElementById("command-filters");
const commandCount = document.getElementById("command-count");
const commandEmpty = document.getElementById("command-empty");
let commandReference = [];
let activeCommandCategory = "All";

function createCommandCard(command) {
  const card = document.createElement("details");
  card.className = "command-card";
  card.id = `command-${command.name.toLowerCase()}`;

  const summary = document.createElement("summary");
  const identity = document.createElement("div");
  const category = document.createElement("span");
  const name = document.createElement("code");
  const description = document.createElement("p");
  const affordance = document.createElement("span");

  category.className = "command-category";
  category.textContent = command.category;
  name.className = "command-name";
  name.textContent = command.name;
  description.textContent = command.description;
  affordance.className = "command-affordance";
  affordance.textContent = "Example";
  identity.append(category, name, description);
  summary.append(identity, affordance);

  const example = document.createElement("div");
  example.className = "command-example";
  const exampleHeader = document.createElement("div");
  exampleHeader.className = "command-example-header";
  const exampleLabel = document.createElement("span");
  exampleLabel.textContent = "PowerShell";
  const copyButton = document.createElement("button");
  copyButton.className = "copy-button";
  copyButton.type = "button";
  copyButton.textContent = "Copy";
  copyButton.setAttribute("aria-label", `Copy ${command.name} example`);
  copyButton.addEventListener("click", () => copyText(copyButton, command.example));
  exampleHeader.append(exampleLabel, copyButton);

  const pre = document.createElement("pre");
  const code = document.createElement("code");
  code.textContent = command.example;
  pre.append(code);
  example.append(exampleHeader, pre);
  card.append(summary, example);
  return card;
}

function renderCommands() {
  const query = commandSearch.value.trim().toLowerCase();
  const visibleCommands = commandReference.filter((command) => {
    const matchesCategory = activeCommandCategory === "All" || command.category === activeCommandCategory;
    const haystack = `${command.name} ${command.category} ${command.description} ${command.example}`.toLowerCase();
    return matchesCategory && haystack.includes(query);
  });

  commandGrid.replaceChildren(...visibleCommands.map(createCommandCard));
  commandGrid.setAttribute("aria-busy", "false");
  commandCount.textContent = `Showing ${visibleCommands.length} of ${commandReference.length}`;
  commandEmpty.hidden = visibleCommands.length !== 0;
}

function renderCommandFilters() {
  const categories = ["All", ...new Set(commandReference.map((command) => command.category))];
  const buttons = categories.map((category) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = category;
    button.setAttribute("aria-pressed", String(category === activeCommandCategory));
    button.addEventListener("click", () => {
      activeCommandCategory = category;
      commandFilters.querySelectorAll("button").forEach((item) => {
        item.setAttribute("aria-pressed", String(item === button));
      });
      renderCommands();
    });
    return button;
  });
  commandFilters.replaceChildren(...buttons);
}

async function loadCommandReference() {
  try {
    const response = await fetch("./commands.json");
    if (!response.ok) throw new Error("Command reference could not be loaded.");
    commandReference = await response.json();
    renderCommandFilters();
    renderCommands();
  } catch {
    commandGrid.setAttribute("aria-busy", "false");
    commandCount.textContent = "Reference unavailable";
    commandEmpty.textContent = "The command reference could not be loaded. View the repository documentation for examples.";
    commandEmpty.hidden = false;
  }
}

commandSearch.addEventListener("input", renderCommands);
document.addEventListener("keydown", (event) => {
  if (event.key === "/" && !isInteractiveTarget(event.target)) {
    event.preventDefault();
    commandSearch.focus();
  }
});

loadCommandReference();
