/**
 * ConfirmModal Hook
 *
 * Opens a confirmation modal instead of submitting the form, unless the
 * submit comes from a button with `data-confirmed`, the modal's confirm button.
 * Covers the submit button and pressing Enter in a field.
 *
 * Usage:
 * <form id="my-form" phx-hook="ConfirmModal" data-show-modal={show_modal("my-modal")}>
 *   ...
 *   <button type="submit">Save</button>
 * </form>
 * <button type="submit" form="my-form" data-confirmed>Confirm</button>
 */
export const ConfirmModal = {
  mounted() {
    this.boundHandleSubmit = this.handleSubmit.bind(this);
    this.el.addEventListener("submit", this.boundHandleSubmit);
  },

  destroyed() {
    if (this.boundHandleSubmit) {
      this.el.removeEventListener("submit", this.boundHandleSubmit);
    }
  },

  handleSubmit(event) {
    if (event.submitter && event.submitter.hasAttribute("data-confirmed")) {
      return;
    }

    event.preventDefault();
    this.js().exec(this.el.dataset.showModal);
  },
};
