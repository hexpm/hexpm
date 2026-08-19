const THEME_STORAGE_KEY = "hexpm-theme";
const THEME_MEDIA_QUERY = "(prefers-color-scheme: dark)";
const PREFERENCE_CYCLE = ["light", "dark", "system"];

function nextPreference(preference) {
  const index = PREFERENCE_CYCLE.indexOf(preference);
  return PREFERENCE_CYCLE[(index + 1) % PREFERENCE_CYCLE.length];
}

function getStoredPreference() {
  return window.localStorage.getItem(THEME_STORAGE_KEY);
}

function getSystemTheme() {
  return window.matchMedia(THEME_MEDIA_QUERY).matches ? "dark" : "light";
}

function resolveTheme() {
  const pref = getStoredPreference();
  if (pref === "light" || pref === "dark") return pref;
  return getSystemTheme();
}

function currentPreference() {
  return getStoredPreference() || "system";
}

function syncToggleState(preference) {
  document.documentElement.setAttribute("data-theme-preference", preference);

  const label = `Switch to ${nextPreference(preference)} mode`;
  document.querySelectorAll("[data-theme-toggle]").forEach((toggle) => {
    toggle.setAttribute("title", label);
    toggle.setAttribute("aria-label", label);
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
  syncToggleState(currentPreference());
  syncReadmeFrameTheme(theme);
}

function setPreference(preference) {
  if (preference === "system") {
    window.localStorage.removeItem(THEME_STORAGE_KEY);
  } else {
    window.localStorage.setItem(THEME_STORAGE_KEY, preference);
  }
  applyTheme(resolveTheme());
}

export function initializeTheme() {
  applyTheme(resolveTheme());

  // Clicking the icon cycles to the next theme
  document.addEventListener("click", (event) => {
    const toggle = event.target.closest("[data-theme-toggle]");
    if (!toggle) return;

    event.preventDefault();
    setPreference(nextPreference(currentPreference()));
  });

  // System theme changes
  const systemThemeMedia = window.matchMedia(THEME_MEDIA_QUERY);
  const handleSystemThemeChange = (event) => {
    if (getStoredPreference()) return;
    applyTheme(event.matches ? "dark" : "light");
  };

  if (typeof systemThemeMedia.addEventListener === "function") {
    systemThemeMedia.addEventListener("change", handleSystemThemeChange);
  } else if (typeof systemThemeMedia.addListener === "function") {
    systemThemeMedia.addListener(handleSystemThemeChange);
  }

  // Cross-tab sync
  window.addEventListener("storage", (event) => {
    if (event.key !== THEME_STORAGE_KEY) return;
    applyTheme(resolveTheme());
  });
}

export { applyTheme, resolveTheme, syncReadmeFrameTheme };
