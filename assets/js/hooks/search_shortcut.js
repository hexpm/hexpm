/**
 * SearchShortcut Hook
 *
 * Press "/" or Cmd+K / Ctrl+K to focus the search input.
 * Ignores input when typing in form fields.
 * Skips hidden inputs (offsetParent === null).
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

    document.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown);
  },
};
