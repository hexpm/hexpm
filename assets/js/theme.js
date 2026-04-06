const THEME_STORAGE_KEY = "hexpm-theme";
const THEME_MEDIA_QUERY = "(prefers-color-scheme: dark)";

function getStoredTheme() {
  return window.localStorage.getItem(THEME_STORAGE_KEY);
}

function getSystemTheme() {
  return window.matchMedia(THEME_MEDIA_QUERY).matches ? "dark" : "light";
}

function resolveTheme() {
  return getStoredTheme() || getSystemTheme();
}

function syncThemeToggleState(theme) {
  document.querySelectorAll("[data-theme-toggle]").forEach((toggle) => {
    toggle.setAttribute("aria-pressed", String(theme === "dark"));
    toggle.setAttribute(
      "aria-label",
      theme === "dark" ? "Switch to light theme" : "Switch to dark theme"
    );
  });

  document.querySelectorAll("[data-theme-label]").forEach((label) => {
    label.textContent = theme === "dark" ? "Dark" : "Light";
  });
}

function syncReadmeFrameTheme(theme) {
  const frame = document.getElementById("readme-frame");
  if (!frame || !frame.contentWindow) return;

  frame.contentWindow.postMessage({ type: "theme-change", theme }, "*");
}

function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
  document.documentElement.style.colorScheme = theme;
  syncThemeToggleState(theme);
  syncReadmeFrameTheme(theme);
}

function persistTheme(theme) {
  window.localStorage.setItem(THEME_STORAGE_KEY, theme);
}

export function initializeTheme() {
  applyTheme(resolveTheme());

  document.addEventListener("click", (event) => {
    const toggle = event.target.closest("[data-theme-toggle]");
    if (!toggle) return;
    event.preventDefault();

    const nextTheme =
      document.documentElement.getAttribute("data-theme") === "dark"
        ? "light"
        : "dark";

    persistTheme(nextTheme);
    applyTheme(nextTheme);
  });

  const systemThemeMedia = window.matchMedia(THEME_MEDIA_QUERY);
  const handleSystemThemeChange = (event) => {
    const storedTheme = getStoredTheme();
    if (storedTheme === "light" || storedTheme === "dark") return;
    applyTheme(event.matches ? "dark" : "light");
  };

  if (typeof systemThemeMedia.addEventListener === "function") {
    systemThemeMedia.addEventListener("change", handleSystemThemeChange);
  } else if (typeof systemThemeMedia.addListener === "function") {
    systemThemeMedia.addListener(handleSystemThemeChange);
  }

  window.addEventListener("storage", (event) => {
    if (event.key !== THEME_STORAGE_KEY) return;
    applyTheme(resolveTheme());
  });
}

export { applyTheme, resolveTheme };
