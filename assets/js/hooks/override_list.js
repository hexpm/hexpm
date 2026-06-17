// Dynamic allow/deny override rows for a repository policy tab.
//
// The container opts in via phx-hook="OverrideList" and holds:
//   - [data-override-rows]      the element new rows are appended to
//   - <template data-override-template>  one blank row whose names use the
//                               literal __INDEX__ placeholder
//   - [data-override-add]       button that appends a cloned row
//   - [data-override-empty]     empty-state shown when there are no rows
//   - data-package-suggestions-url / data-version-suggestions-url endpoints
//   - per row: [data-override-row] wrapper, [data-override-remove] button, and
//     an allow/deny [data-decision] group
//
// Cloned rows carry no embed id, so the server inserts them; removing a row
// drops it from the submitted params and the embed is deleted. The allow/deny
// toggle is handled here by delegation rather than a per-row hook so it works
// on cloned rows too (LiveView only mounts hooks on server-rendered elements).
export const OverrideList = {
  mounted() {
    const rows = this.el.querySelector("[data-override-rows]");
    const template = this.el.querySelector("[data-override-template]");
    const addButton = this.el.querySelector("[data-override-add]");
    const empty = this.el.querySelector("[data-override-empty]");
    const packageSuggestionsUrl = this.el.dataset.packageSuggestionsUrl;
    const versionSuggestionsUrl = this.el.dataset.versionSuggestionsUrl;
    const suggestionLimit = 8;
    let counter = 0;

    const notifyFormChanged = () => {
      this.el
        .closest("form")
        ?.dispatchEvent(new Event("policy-form-change", { bubbles: true }));
    };

    const refreshEmpty = () => {
      if (empty) empty.classList.toggle("hidden", rows.children.length > 0);
    };

    const closeSuggestions = (row) => {
      if (!row) return;

      row.querySelectorAll("[data-override-suggestions]").forEach((menu) => {
        menu.hidden = true;
        menu.replaceChildren();
      });
      row
        .querySelectorAll("[data-override-package], [data-override-requirement]")
        .forEach((input) => {
          clearTimeout(input.suggestionTimer);
          input.setAttribute("aria-expanded", "false");
          input.dataset.activeSuggestion = "-1";
          input.dataset.suggestionToken = "";
        });
    };

    const closeAllSuggestions = () => {
      rows.querySelectorAll("[data-override-row]").forEach(closeSuggestions);
    };

    const keepSuggestionsOpenTarget = (target) =>
      target.closest(
        "[data-override-suggestions], [data-override-package], [data-override-requirement]"
      );

    const suggestionKind = (input) => {
      if (input.matches("[data-override-package]")) return "package";
      if (input.matches("[data-override-requirement]")) return "version";
      return null;
    };

    const suggestionMenu = (input) => {
      const kind = suggestionKind(input);
      return input
        .closest("[data-override-row]")
        ?.querySelector(`[data-override-suggestions="${kind}"]`);
    };

    const packageName = (row) =>
      row.querySelector("[data-override-package]")?.value.trim() || "";

    const closeInactiveSuggestions = (activeInput) => {
      const activeRow = activeInput.closest("[data-override-row]");
      const activeMenu = suggestionMenu(activeInput);

      rows.querySelectorAll("[data-override-row]").forEach((row) => {
        if (row !== activeRow) {
          closeSuggestions(row);
          return;
        }

        row.querySelectorAll("[data-override-suggestions]").forEach((menu) => {
          if (menu === activeMenu) return;

          menu.hidden = true;
          menu.replaceChildren();
        });
        row
          .querySelectorAll(
            "[data-override-package], [data-override-requirement]"
          )
          .forEach((input) => {
            if (input === activeInput) return;

            clearTimeout(input.suggestionTimer);
            input.setAttribute("aria-expanded", "false");
            input.dataset.activeSuggestion = "-1";
            input.dataset.suggestionToken = "";
          });
      });
    };

    const buildUrl = (baseUrl, params) => {
      const url = new URL(baseUrl, window.location.origin);
      Object.entries(params).forEach(([key, value]) => {
        url.searchParams.set(key, value);
      });
      return url;
    };

    const renderSuggestions = (input, items) => {
      const menu = suggestionMenu(input);
      const kind = suggestionKind(input);
      if (!menu || !kind) return;

      menu.replaceChildren();
      input.dataset.activeSuggestion = "-1";
      input.setAttribute("aria-expanded", items.length > 0 ? "true" : "false");
      menu.hidden = items.length === 0;

      items.slice(0, suggestionLimit).forEach((item, index) => {
        const value = kind === "package" ? item.name : item.version;
        const button = document.createElement("button");
        button.type = "button";
        button.dataset.suggestionKind = kind;
        button.dataset.suggestionValue = value;
        button.dataset.suggestionIndex = String(index);
        button.dataset.active = "false";
        button.className =
          "block w-full px-3 py-2 text-left text-sm text-grey-700 dark:text-grey-100 hover:bg-primary-50 dark:hover:bg-grey-700 data-[active=true]:bg-primary-50 dark:data-[active=true]:bg-grey-700";

        const label = document.createElement("span");
        label.className = "font-mono font-medium";
        label.textContent = value;
        button.appendChild(label);

        if (kind === "package" && item.latest_version) {
          const version = document.createElement("span");
          version.className = "ml-2 text-xs text-grey-400 dark:text-grey-300";
          version.textContent = `v${item.latest_version}`;
          button.appendChild(version);
        }

        menu.appendChild(button);
      });
    };

    const fetchSuggestions = async (input) => {
      const kind = suggestionKind(input);
      const row = input.closest("[data-override-row]");
      if (!kind || !row) return;

      const term = input.value.trim();
      if (kind === "package" && term.length < 3) {
        closeSuggestions(row);
        return;
      }

      const selectedPackage = packageName(row);
      if (kind === "version" && selectedPackage === "") {
        closeSuggestions(row);
        return;
      }

      const baseUrl =
        kind === "package" ? packageSuggestionsUrl : versionSuggestionsUrl;
      if (!baseUrl) return;

      const token = `${Date.now()}-${Math.random()}`;
      input.dataset.suggestionToken = token;

      const url =
        kind === "package"
          ? buildUrl(baseUrl, { term })
          : buildUrl(baseUrl, { package: selectedPackage, term });

      try {
        const response = await fetch(url);
        if (!response.ok || input.dataset.suggestionToken !== token) return;

        const payload = await response.json();
        if (input.dataset.suggestionToken !== token) return;

        renderSuggestions(input, payload.items || []);
      } catch (_error) {
        closeSuggestions(row);
      }
    };

    const scheduleSuggestions = (input) => {
      clearTimeout(input.suggestionTimer);
      input.suggestionTimer = setTimeout(() => fetchSuggestions(input), 100);
    };

    const setActiveSuggestion = (input, nextIndex) => {
      const menu = suggestionMenu(input);
      if (!menu || menu.hidden) return;

      const buttons = Array.from(
        menu.querySelectorAll("[data-suggestion-value]")
      );
      if (buttons.length === 0) return;

      const index = (nextIndex + buttons.length) % buttons.length;
      input.dataset.activeSuggestion = String(index);
      buttons.forEach((button, buttonIndex) => {
        button.dataset.active = buttonIndex === index ? "true" : "false";
      });
      buttons[index].scrollIntoView({ block: "nearest" });
    };

    const selectSuggestion = (button) => {
      const row = button.closest("[data-override-row]");
      const kind = button.dataset.suggestionKind;
      const input =
        kind === "package"
          ? row.querySelector("[data-override-package]")
          : row.querySelector("[data-override-requirement]");
      if (!input) return;

      input.value = button.dataset.suggestionValue;
      input.dispatchEvent(new Event("change", { bubbles: true }));
      closeSuggestions(row);

      if (kind === "package") {
        const requirement = row.querySelector("[data-override-requirement]");
        requirement?.focus();
      } else {
        input.focus();
      }
    };

    const add = () => {
      // A large, unique index keeps cloned rows from colliding with the
      // server-rendered ones (0, 1, …) when the form is cast.
      const index = 100000 + counter++;
      const html = template.innerHTML.replace(/__INDEX__/g, String(index));
      const wrapper = document.createElement("div");
      wrapper.innerHTML = html.trim();
      const row = wrapper.firstElementChild;
      rows.appendChild(row);
      refreshEmpty();
      notifyFormChanged();

      const pkg = row.querySelector("[data-override-package]");
      if (pkg) pkg.focus();
    };

    const onClick = (event) => {
      const suggestion = event.target.closest("[data-suggestion-value]");
      if (suggestion) {
        selectSuggestion(suggestion);
        return;
      }

      const decision = event.target.closest("[data-decision-value]");
      if (decision) {
        const group = decision.closest("[data-decision]");
        const input = group.querySelector("[data-decision-input]");
        input.value = decision.dataset.decisionValue;
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
        group.querySelectorAll("[data-decision-value]").forEach((button) => {
          button.dataset.active = button === decision ? "true" : "false";
        });
        const row = decision.closest("[data-override-row]");
        row.classList.toggle(
          "border-l-green-500",
          decision.dataset.decisionValue === "allow"
        );
        row.classList.toggle(
          "border-l-red-500",
          decision.dataset.decisionValue === "deny"
        );
        notifyFormChanged();
        return;
      }

      const remove = event.target.closest("[data-override-remove]");
      if (!remove) return;
      const row = remove.closest("[data-override-row]");
      if (row) row.remove();
      refreshEmpty();
      notifyFormChanged();
    };

    const onInput = (event) => {
      if (
        !event.target.matches(
          "[data-override-package], [data-override-requirement]"
        )
      ) {
        return;
      }

      closeInactiveSuggestions(event.target);
      scheduleSuggestions(event.target);
    };

    const onFocusIn = (event) => {
      if (
        !event.target.matches(
          "[data-override-package], [data-override-requirement]"
        )
      ) {
        return;
      }

      closeInactiveSuggestions(event.target);
    };

    const onKeyDown = (event) => {
      if (
        !event.target.matches(
          "[data-override-package], [data-override-requirement]"
        )
      ) {
        return;
      }

      const input = event.target;
      const row = input.closest("[data-override-row]");
      const menu = suggestionMenu(input);
      if (!menu || menu.hidden) return;

      const active = Number(input.dataset.activeSuggestion || "-1");

      if (event.key === "ArrowDown") {
        event.preventDefault();
        setActiveSuggestion(input, active + 1);
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        setActiveSuggestion(input, active - 1);
      } else if (event.key === "Enter" && active >= 0) {
        const button = menu.querySelector(`[data-suggestion-index="${active}"]`);
        if (button) {
          event.preventDefault();
          selectSuggestion(button);
        }
      } else if (event.key === "Escape") {
        event.preventDefault();
        closeSuggestions(row);
      }
    };

    this.closeSuggestionsOnOutsideClick = (event) => {
      const target = keepSuggestionsOpenTarget(event.target);

      if (target && this.el.contains(target)) return;

      closeAllSuggestions();
    };
    document.addEventListener("click", this.closeSuggestionsOnOutsideClick);

    if (addButton) addButton.addEventListener("click", add);
    rows.addEventListener("click", onClick);
    rows.addEventListener("input", onInput);
    rows.addEventListener("focusin", onFocusIn);
    rows.addEventListener("keydown", onKeyDown);
    refreshEmpty();
  },

  destroyed() {
    if (this.closeSuggestionsOnOutsideClick) {
      document.removeEventListener("click", this.closeSuggestionsOnOutsideClick);
    }
  },
};
