const THEME_STORAGE_KEY = "hexpm-theme";
const THEME_MEDIA_QUERY = "(prefers-color-scheme: dark)";

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

function closeAllMenus() {
  document.querySelectorAll("[data-theme-menu]").forEach((menu) => {
    menu.classList.add("hidden");
  });
}

export function initializeTheme() {
  applyTheme(resolveTheme());

  // Toggle menu open/closed
  document.addEventListener("click", (event) => {
    const toggle = event.target.closest("[data-theme-toggle]");
    if (toggle) {
      event.preventDefault();
      const menu = toggle.parentElement.querySelector("[data-theme-menu]");
      if (menu) menu.classList.toggle("hidden");
      return;
    }

    // Handle choice selection
    const choice = event.target.closest("[data-theme-choice]");
    if (choice) {
      event.preventDefault();
      setPreference(choice.getAttribute("data-theme-choice"));
      closeAllMenus();
      return;
    }

    // Click outside closes menu
    closeAllMenus();
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
