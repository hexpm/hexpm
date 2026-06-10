// Generic radio/tab/preset toggle group.
//
// Container element opts in via phx-hook="ToggleGroup" and (optionally)
// data-target="<input_id>". Each child button declares data-value="...".
// Use data-panel-container="<selector>" when panels are outside the hook element.
//
//   - With data-target: clicking a button writes data-value into the
//     target input. Re-clicking the active button clears the input
//     (unset) when data-allow-clear="true" is set on the container.
//   - Without data-target: the group renders panels selected by
//     data-panel="<value>" matching data-value, toggling their hidden state.
//
// Buttons reflect their active state via data-active="true|false" so the
// template can style them with Tailwind data-[active=...] variants.
export const ToggleGroup = {
  mounted() {
    const targetId = this.el.dataset.target;
    const target = targetId && document.getElementById(targetId);
    const buttons = this.el.querySelectorAll("button[data-value]");
    const panelRoot = this.el.dataset.panelContainer
      ? document.querySelector(this.el.dataset.panelContainer)
      : this.el;
    const panels = panelRoot ? panelRoot.querySelectorAll("[data-panel]") : [];
    const allowClear = this.el.dataset.allowClear === "true";
    // When the group is an ARIA tablist, also drive aria-selected, a roving
    // tabindex, and arrow-key navigation across the tabs.
    const isTablist = this.el.getAttribute("role") === "tablist";

    const sync = () => {
      const current = target ? target.value : this.currentPanel;

      buttons.forEach((b) => {
        const active = String(b.dataset.value) === String(current);
        b.dataset.active = active ? "true" : "false";

        if (isTablist) {
          b.setAttribute("aria-selected", active ? "true" : "false");
          b.tabIndex = active ? 0 : -1;
        }
      });

      panels.forEach((panel) => {
        panel.hidden = String(panel.dataset.panel) !== String(current);
      });
    };

    if (isTablist) {
      this.el.addEventListener("keydown", (event) => {
        const tabs = Array.from(buttons).filter((b) => !b.hidden);
        const currentIndex = tabs.indexOf(document.activeElement);
        if (currentIndex === -1) return;

        let nextIndex;
        switch (event.key) {
          case "ArrowRight":
          case "ArrowDown":
            nextIndex = (currentIndex + 1) % tabs.length;
            break;
          case "ArrowLeft":
          case "ArrowUp":
            nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
            break;
          case "Home":
            nextIndex = 0;
            break;
          case "End":
            nextIndex = tabs.length - 1;
            break;
          default:
            return;
        }

        event.preventDefault();
        const next = tabs[nextIndex];
        next.focus();
        next.click();
      });
    }

    if (!target && panels.length > 0) {
      const initial =
        Array.from(buttons).find((b) => b.dataset.active === "true") ||
        buttons[0];
      this.currentPanel = initial && initial.dataset.value;
    }

    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        const value = button.dataset.value;

        if (target) {
          if (allowClear && String(target.value) === String(value)) {
            target.value = "";
          } else {
            target.value = value;
          }
          target.dispatchEvent(new Event("input", { bubbles: true }));
          target.dispatchEvent(new Event("change", { bubbles: true }));
        } else {
          this.currentPanel = value;
        }

        sync();
      });
    });

    if (target) target.addEventListener("input", sync);

    sync();
  },
};
