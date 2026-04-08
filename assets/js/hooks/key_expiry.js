/**
 * KeyExpiry Hook
 *
 * Shows/hides the custom date input when "Custom..." is selected,
 * and a warning when "No expiration" is selected.
 */
export const KeyExpiry = {
  mounted() {
    this.abortController = new AbortController();
    this.setup();
  },

  updated() {
    this.abortController.abort();
    this.abortController = new AbortController();
    this.setup();
  },

  destroyed() {
    this.abortController.abort();
  },

  setup() {
    const select = this.el.querySelector("#key-expires-in");
    const warning = this.el.querySelector("#no-expiry-warning");
    const customInput = this.el.querySelector("#custom-expiry-input");
    if (!select || !warning || !customInput) return;

    const signal = this.abortController.signal;

    const toggle = () => {
      if (select.value === "none") {
        warning.classList.remove("hidden");
      } else {
        warning.classList.add("hidden");
      }

      if (select.value === "custom") {
        customInput.classList.remove("hidden");
      } else {
        customInput.classList.add("hidden");
      }
    };

    toggle();
    select.addEventListener("change", toggle, { signal });
  },
};
