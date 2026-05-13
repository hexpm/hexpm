/**
 * SearchShortcut Hook
 *
 * Press "/" or Cmd+K / Ctrl+K to focus the search input.
 * Ignores input when typing in form fields.
 * Skips hidden inputs (offsetParent === null).
 *
 * Also handles Enter key on the search input: when no autocomplete suggestion
 * is active, submits the form natively (bypassing the LiveView roundtrip) so
 * navigation is immediate.
 *
 * Usage: <input phx-hook="SearchShortcut" />
 */
export const SearchShortcut = {
  mounted() {
    this.handleKeydown = (e) => {
      const inField = e.target.matches("input, textarea, [contenteditable]");

      const isSlash = e.key === "/" && !e.ctrlKey && !e.metaKey && !e.altKey && !inField;
      const isCmdK = (e.key === "k" || e.key === "K") && (e.metaKey || e.ctrlKey) && !e.altKey && !inField;

      if (!isSlash && !isCmdK) return;

      // Skip inputs that are not visible (e.g. mobile input when on desktop)
      if (this.el.offsetParent === null) return;

      e.preventDefault();
      e.stopImmediatePropagation();
      this.el.focus();
      this.el.select();
    };

    // Submit natively on Enter when no autocomplete suggestion is active,
    // bypassing the LiveView roundtrip for instant navigation.
    this.handleEnter = (e) => {
      if (e.key !== "Enter") return;
      if (this.el.getAttribute("aria-activedescendant")) return;
      const form = this.el.closest("form");
      if (!form) return;
      e.stopImmediatePropagation();
      form.submit();
    };

    this.el.addEventListener("keydown", this.handleEnter, { capture: true });
    document.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.handleEnter, { capture: true });
    document.removeEventListener("keydown", this.handleKeydown);
  },
};
