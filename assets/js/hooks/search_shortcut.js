/**
 * SearchShortcut Hook
 *
 * Press "/" to focus the search input.
 * Ignores input when typing in form fields.
 *
 * Usage: <input phx-hook="SearchShortcut" />
 */
export const SearchShortcut = {
  mounted() {
    this.handleKeydown = (e) => {
      // Only respond to "/" key without modifiers
      if (e.key !== "/" || e.ctrlKey || e.metaKey || e.altKey) return;

      // Ignore if user is already typing in an input field
      if (e.target.matches("input, textarea, [contenteditable]")) return;

      e.preventDefault();
      this.el.focus();
      this.el.select();
    };

    document.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener("keydown", this.handleKeydown);
  },
};
