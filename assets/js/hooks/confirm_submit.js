/**
 * ConfirmSubmit Hook
 *
 * Shows a confirmation dialog before clicking a target element.
 *
 * Usage:
 * <button phx-hook="ConfirmSubmit" id="my-btn"
 *   data-confirm="Are you sure?"
 *   data-target="target-element-id">
 *   Remove
 * </button>
 */
export const ConfirmSubmit = {
  mounted() {
    this.boundHandleClick = this.handleClick.bind(this);
    this.el.addEventListener("click", this.boundHandleClick);
  },

  destroyed() {
    if (this.boundHandleClick) {
      this.el.removeEventListener("click", this.boundHandleClick);
    }
  },

  handleClick(event) {
    event.preventDefault();

    const message = this.el.dataset.confirm;
    const targetId = this.el.dataset.target;

    if (!message || !targetId) {
      console.error("ConfirmSubmit: missing data-confirm or data-target");
      return;
    }

    if (confirm(message)) {
      const target = document.getElementById(targetId);
      if (target) {
        target.click();
      } else {
        console.error(`ConfirmSubmit: target element not found: ${targetId}`);
      }
    }
  },
};
