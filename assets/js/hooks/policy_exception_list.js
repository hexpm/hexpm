export const PolicyExceptionList = {
  mounted() {
    const rows = this.el.querySelector("[data-exception-rows]");
    const overrideCard = this.el.closest('[phx-hook="OverrideList"]');
    const empty = overrideCard?.querySelector("[data-override-empty]");
    const suggestionsUrl = this.el.dataset.advisorySuggestionsUrl;
    let counter = 0;

    const notifyFormChanged = () => {
      this.el
        .closest("form")
        ?.dispatchEvent(new Event("policy-form-change", { bubbles: true }));
    };

    const refreshEmpty = () => {
      const rowCount = overrideCard?.querySelectorAll(
        "[data-override-row], [data-exception-row]"
      ).length;
      empty?.classList.toggle("hidden", rowCount > 0);
    };

    const menuFor = (input) =>
      input.closest("[data-exception-row]")?.querySelector(
        "[data-exception-suggestions]"
      );

    const statusFor = (input) =>
      input.closest("[data-exception-row]")?.querySelector(
        "[data-exception-status]"
      );

    const setStatus = (input, message) => {
      const status = statusFor(input);
      if (status) {
        status.textContent = message;
        status.hidden = message === "";
      }
    };

    const closeSuggestions = (input) => {
      if (!input) return;

      clearTimeout(input.suggestionTimer);
      input.suggestionController?.abort();
      input.suggestionController = null;
      input.dataset.suggestionToken = "";
      input.dataset.activeSuggestion = "-1";
      input.setAttribute("aria-expanded", "false");
      input.removeAttribute("aria-activedescendant");

      const menu = menuFor(input);
      if (menu) {
        menu.hidden = true;
        menu.replaceChildren();
      }

      setStatus(input, "");
    };

    const restoreSelection = (input) => {
      if (!input || input.dataset.reselecting !== "true") return;

      const row = input.closest("[data-exception-row]");
      const advisory = row.querySelector("[data-exception-advisory-id]");
      const selected = row.querySelector("[data-exception-selected]");
      if (!advisory.value) return;

      input.value = advisory.value;
      input.readOnly = true;
      input.hidden = true;
      input.dataset.reselecting = "false";
      selected.hidden = false;
    };

    const closeAllSuggestions = (except = null) => {
      rows.querySelectorAll("[data-exception-search]").forEach((input) => {
        if (input !== except) {
          closeSuggestions(input);
          restoreSelection(input);
        }
      });
    };

    const buildUrl = (term) => {
      const url = new URL(suggestionsUrl, window.location.origin);
      url.searchParams.set("term", term);
      return url;
    };

    const renderSuggestions = (input, items) => {
      const menu = menuFor(input);
      if (!menu) return;

      menu.replaceChildren();
      input.dataset.activeSuggestion = "-1";
      input.removeAttribute("aria-activedescendant");

      items.forEach((item, index) => {
        const button = document.createElement("button");
        button.type = "button";
        button.tabIndex = -1;
        button.id = `${menu.id}-option-${index}`;
        button.setAttribute("role", "option");
        button.setAttribute("aria-selected", "false");
        button.dataset.exceptionSuggestion = "true";
        button.dataset.suggestionIndex = String(index);
        button.dataset.active = "false";
        button.dataset.identifier = item.identifier;
        button.dataset.package = item.package;
        button.dataset.requirement = (item.requirements || []).join(" or ");
        button.className =
          "block w-full px-3 py-2 text-left hover:bg-primary-50 dark:hover:bg-grey-700 data-[active=true]:bg-primary-50 dark:data-[active=true]:bg-grey-700";

        const heading = document.createElement("span");
        heading.className = "block text-sm text-grey-900 dark:text-grey-100";

        const identifier = document.createElement("strong");
        identifier.className = "font-mono";
        identifier.textContent = item.identifier;
        heading.appendChild(identifier);
        heading.appendChild(document.createTextNode(` ${item.summary}`));

        const packageName = document.createElement("span");
        packageName.className =
          "block mt-1 text-xs font-mono text-grey-600 dark:text-grey-300";
        packageName.textContent = item.package;

        const requirements = document.createElement("span");
        requirements.className =
          "block mt-0.5 text-xs text-grey-500 dark:text-grey-400";
        requirements.textContent = (item.requirements || []).join(" or ");

        button.append(heading, packageName, requirements);
        menu.appendChild(button);
      });

      menu.hidden = items.length === 0;
      input.setAttribute("aria-expanded", items.length > 0 ? "true" : "false");
      setStatus(input, items.length === 0 ? "No matching advisories." : "");
    };

    const fetchSuggestions = async (input) => {
      const term = input.value.trim();
      if (input.readOnly || term.length < 2 || !suggestionsUrl) {
        closeSuggestions(input);
        setStatus(input, term.length > 0 && term.length < 2 ? "Enter at least two characters." : "");
        return;
      }

      closeAllSuggestions(input);
      closeSuggestions(input);
      input.suggestionController?.abort();
      const controller = new AbortController();
      input.suggestionController = controller;
      const token = `${Date.now()}-${Math.random()}`;
      input.dataset.suggestionToken = token;
      setStatus(input, "Loading advisories...");

      try {
        const response = await fetch(buildUrl(term), { signal: controller.signal });
        if (input.dataset.suggestionToken !== token) return;

        if (!response.ok) {
          closeSuggestions(input);
          setStatus(input, "Advisory search failed. Try again.");
          return;
        }

        const payload = await response.json();
        if (input.dataset.suggestionToken !== token) return;
        renderSuggestions(input, payload.items || []);
      } catch (error) {
        if (error.name === "AbortError") return;
        closeSuggestions(input);
        setStatus(input, "Advisory search failed. Try again.");
      }
    };

    const scheduleSuggestions = (input) => {
      clearTimeout(input.suggestionTimer);
      input.suggestionTimer = setTimeout(() => fetchSuggestions(input), 150);
    };

    const setActiveSuggestion = (input, nextIndex) => {
      const menu = menuFor(input);
      if (!menu || menu.hidden) return;

      const options = Array.from(menu.querySelectorAll("[data-exception-suggestion]"));
      if (options.length === 0) return;

      const index = (nextIndex + options.length) % options.length;
      input.dataset.activeSuggestion = String(index);
      options.forEach((option, optionIndex) => {
        const active = optionIndex === index;
        option.dataset.active = active ? "true" : "false";
        option.setAttribute("aria-selected", active ? "true" : "false");
      });
      input.setAttribute("aria-activedescendant", options[index].id);
      options[index].scrollIntoView({ block: "nearest" });
    };

    const dispatchChange = (input) => {
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    };

    const selectSuggestion = (button) => {
      const row = button.closest("[data-exception-row]");
      const input = row.querySelector("[data-exception-search]");
      const advisory = row.querySelector("[data-exception-advisory-id]");
      const packageInput = row.querySelector("[data-exception-package]");
      const requirement = row.querySelector("[data-exception-requirement]");
      const comment = row.querySelector('input[name$="[comment]"]');
      const selected = row.querySelector("[data-exception-selected]");

      input.value = button.dataset.identifier;
      input.readOnly = true;
      input.hidden = true;
      input.dataset.reselecting = "false";
      advisory.value = button.dataset.identifier;
      packageInput.value = button.dataset.package;
      requirement.value = button.dataset.requirement;
      selected.hidden = false;
      selected.querySelector("[data-exception-selected-id]").textContent =
        button.dataset.identifier;
      selected.querySelector("[data-exception-selected-package]").textContent =
        button.dataset.package;

      dispatchChange(advisory);
      dispatchChange(packageInput);
      dispatchChange(requirement);
      closeSuggestions(input);
      setStatus(input, "");
      comment.focus();
    };

    const reselect = (button) => {
      const row = button.closest("[data-exception-row]");
      const input = row.querySelector("[data-exception-search]");
      const advisory = row.querySelector("[data-exception-advisory-id]");
      const selected = row.querySelector("[data-exception-selected]");

      closeAllSuggestions(input);
      input.value = advisory.value;
      input.readOnly = false;
      input.hidden = false;
      input.dataset.reselecting = "true";
      selected.hidden = true;
      input.focus();
      input.setSelectionRange(0, input.value.length);
      fetchSuggestions(input);
    };

    const addRow = (kind) => {
      const template = this.el.querySelector(
        `[data-exception-template="${kind}"]`
      );
      if (!template) return;

      const index = 200000 + counter++;
      const wrapper = document.createElement("div");
      wrapper.innerHTML = template.innerHTML
        .replace(/__INDEX__/g, String(index))
        .trim();
      const row = wrapper.firstElementChild;
      rows.appendChild(row);
      refreshEmpty();
      notifyFormChanged();
      row.querySelector("input:not([type=hidden]), select")?.focus();
    };

    this.onClick = (event) => {
      const add = event.target.closest("[data-exception-add]");
      if (add) {
        closeAllSuggestions();
        addRow(add.dataset.exceptionAdd);
        return;
      }

      const suggestion = event.target.closest("[data-exception-suggestion]");
      if (suggestion) {
        selectSuggestion(suggestion);
        return;
      }

      const reselectButton = event.target.closest("[data-exception-reselect]");
      if (reselectButton) {
        reselect(reselectButton);
        return;
      }

      const remove = event.target.closest("[data-exception-remove]");
      if (!remove) {
        const input = event.target.closest("[data-exception-search]");
        closeAllSuggestions(input);
        if (input && !input.readOnly && input.value.trim().length >= 2) {
          scheduleSuggestions(input);
        }
        return;
      }

      const row = remove.closest("[data-exception-row]");
      closeAllSuggestions(row.querySelector("[data-exception-search]"));
      closeSuggestions(row.querySelector("[data-exception-search]"));
      row.remove();
      refreshEmpty();
      notifyFormChanged();
    };

    this.onInput = (event) => {
      if (!event.target.matches("[data-exception-search]")) return;
      scheduleSuggestions(event.target);
    };

    this.onKeyDown = (event) => {
      if (!event.target.matches("[data-exception-search]")) return;

      const input = event.target;
      const menu = menuFor(input);
      const active = Number(input.dataset.activeSuggestion || "-1");

      if (event.key === "ArrowDown") {
        event.preventDefault();
        if (menu?.hidden) fetchSuggestions(input);
        else setActiveSuggestion(input, active + 1);
      } else if (event.key === "ArrowUp" && !menu?.hidden) {
        event.preventDefault();
        setActiveSuggestion(input, active - 1);
      } else if (event.key === "Enter" && active >= 0 && !menu?.hidden) {
        const option = menu.querySelector(`[data-suggestion-index="${active}"]`);
        if (option) {
          event.preventDefault();
          selectSuggestion(option);
        }
      } else if (event.key === "Escape") {
        event.preventDefault();
        closeSuggestions(input);
        restoreSelection(input);
        setStatus(input, "");
      }
    };

    this.onDocumentClick = (event) => {
      if (!this.el.contains(event.target)) closeAllSuggestions();
    };

    this.el.addEventListener("click", this.onClick);
    rows.addEventListener("input", this.onInput);
    rows.addEventListener("keydown", this.onKeyDown);
    document.addEventListener("click", this.onDocumentClick);
    this.exceptionRows = rows;
    refreshEmpty();
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    this.exceptionRows?.removeEventListener("input", this.onInput);
    this.exceptionRows?.removeEventListener("keydown", this.onKeyDown);
    document.removeEventListener("click", this.onDocumentClick);
  },
};
