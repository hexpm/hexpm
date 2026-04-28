/**
 * TFACodeInput Hook
 *
 * Validates a 6-digit TFA verification code input and enables/disables
 * the associated submit button.
 *
 * Usage:
 * <input phx-hook="TFACodeInput" data-submit-button="button-id" />
 */
export const TFACodeInput = {
  mounted() {
    const buttonId = this.el.dataset.submitButton;
    this.button = document.getElementById(buttonId);

    this.boundValidate = this.validate.bind(this);
    this.el.addEventListener("input", this.boundValidate);

    // Set initial state
    this.validate();
  },

  destroyed() {
    if (this.boundValidate) {
      this.el.removeEventListener("input", this.boundValidate);
    }
  },

  validate() {
    if (this.button) {
      this.button.disabled = !/^[0-9]{6}$/.test(this.el.value);
    }
  },
};
