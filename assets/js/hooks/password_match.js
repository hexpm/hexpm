/**
 * Password Match Hook
 *
 * Validates that the password confirmation field matches the password field in real-time.
 * Shows/hides the error message dynamically as the user types.
 */

const PasswordMatch = {
  mounted() {
    const passwordSelector = this.el.dataset.passwordId;

    // Guard: Validate required data attribute exists
    if (!passwordSelector) {
      console.warn("PasswordMatch: data-password-id attribute is missing");
      return;
    }

    this.passwordInput = document.querySelector(passwordSelector);
    this.confirmInput = this.el.querySelector('input[type="password"]');
    this.errorContainer = this.el.querySelector("[data-match-error]");

    // Guard: Validate all required elements exist
    if (!this.passwordInput || !this.confirmInput || !this.errorContainer) {
      console.warn("PasswordMatch: required DOM elements not found");
      return;
    }

    // Store bound handlers for cleanup
    this.confirmInputHandler = () => {
      this.checkMatch();
    };

    this.passwordInputHandler = () => {
      // Only validate if confirmation field has been touched
      if (this.confirmInput.value.length > 0) {
        this.checkMatch();
      }
    };

    // Attach event listeners
    this.confirmInput.addEventListener("input", this.confirmInputHandler);
    this.passwordInput.addEventListener("input", this.passwordInputHandler);

    // Initial check if both fields have values
    if (this.passwordInput.value && this.confirmInput.value) {
      this.checkMatch();
    }
  },

  destroyed() {
    // Clean up event listeners to prevent memory leaks
    if (this.confirmInput && this.confirmInputHandler) {
      this.confirmInput.removeEventListener("input", this.confirmInputHandler);
    }
    if (this.passwordInput && this.passwordInputHandler) {
      this.passwordInput.removeEventListener(
        "input",
        this.passwordInputHandler
      );
    }
  },

  checkMatch() {
    const password = this.passwordInput.value;
    const confirmation = this.confirmInput.value;

    // Only show error if confirmation field has content
    if (confirmation.length === 0) {
      this.hideError();
      return;
    }

    if (password !== confirmation) {
      this.showError();
    } else {
      this.hideError();
    }
  },

  showError() {
    this.errorContainer.classList.remove("tw:hidden");
  },

  hideError() {
    this.errorContainer.classList.add("tw:hidden");
  },
};

export default PasswordMatch;
