/**
 * SubmitOnce Hook
 *
 * Disables the button on click and submits the parent form.
 * Prevents double-submission of forms.
 *
 * Usage:
 * <button type="button" phx-hook="SubmitOnce" id="my-button">
 *   Submit
 * </button>
 */
export const SubmitOnce = {
  mounted() {
    this.boundHandleClick = this.handleClick.bind(this);
    this.el.addEventListener("click", this.boundHandleClick);
  },

  destroyed() {
    if (this.boundHandleClick) {
      this.el.removeEventListener("click", this.boundHandleClick);
    }
  },

  handleClick() {
    this.el.disabled = true;
    this.el.form.submit();
  },
};
