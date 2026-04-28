/**
 * AutoSubmit Hook
 *
 * Automatically submits the form when any input changes.
 * Attach to a form element or an input within a form.
 *
 * Usage:
 * <form phx-hook="AutoSubmit" id="my-form">
 *   <select name="role">...</select>
 * </form>
 */
export const AutoSubmit = {
  mounted() {
    this.boundHandleChange = this.handleChange.bind(this);
    this.el.addEventListener("change", this.boundHandleChange);
  },

  destroyed() {
    if (this.boundHandleChange) {
      this.el.removeEventListener("change", this.boundHandleChange);
    }
  },

  handleChange() {
    const form = this.el.closest("form") || this.el;
    form.submit();
  },
};
