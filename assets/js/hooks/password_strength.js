/**
 * Password Strength Hook
 *
 * Calculates password strength based on:
 * - Length (min 7 characters required)
 * - Character diversity (lowercase, uppercase, numbers, special chars)
 *
 * Updates the UI with:
 * - Strength bar (visual indicator)
 * - Strength label (Weak, Fair, Good, Strong)
 * - Requirements checklist
 */

const PasswordStrength = {
  mounted() {
    this.input = this.el.querySelector('input[type="password"]');
    this.strengthBar = this.el.querySelector("[data-strength-bar]");
    this.strengthLabel = this.el.querySelector("[data-strength-label]");
    this.progressBar = this.strengthBar?.parentElement; // The progress bar container
    this.requirements = {
      length: this.el.querySelector('[data-requirement="length"]'),
      lowercase: this.el.querySelector('[data-requirement="lowercase"]'),
      uppercase: this.el.querySelector('[data-requirement="uppercase"]'),
      number: this.el.querySelector('[data-requirement="number"]'),
      special: this.el.querySelector('[data-requirement="special"]'),
    };

    // Guard: If input is missing, hook cannot function
    if (!this.input) {
      console.warn("PasswordStrength: password input not found");
      return;
    }

    // Store bound handler for cleanup
    this.inputHandler = () => {
      this.checkStrength(this.input.value);
    };

    this.input.addEventListener("input", this.inputHandler);

    // Initial check if field has value
    if (this.input.value) {
      this.checkStrength(this.input.value);
    }
  },

  destroyed() {
    // Clean up event listener to prevent memory leaks
    if (this.input && this.inputHandler) {
      this.input.removeEventListener("input", this.inputHandler);
    }
  },

  checkStrength(password) {
    const checks = {
      length: password.length >= 7,
      lowercase: /[a-z]/.test(password),
      uppercase: /[A-Z]/.test(password),
      number: /[0-9]/.test(password),
      special: /[^A-Za-z0-9]/.test(password),
    };

    // Update requirement checkmarks
    Object.keys(checks).forEach((key) => {
      const requirementEl = this.requirements[key];
      if (!requirementEl) return;

      const checkIcon = requirementEl.querySelector("[data-check-icon]");
      const xIcon = requirementEl.querySelector("[data-x-icon]");

      // Guard: Skip if icons are missing from DOM
      if (!checkIcon || !xIcon) return;

      if (checks[key]) {
        // Show green checkmark, hide red X
        checkIcon.classList.remove("tw:hidden");
        checkIcon.classList.add("tw:text-green-600");
        xIcon.classList.add("tw:hidden");
      } else {
        // Show red X, hide checkmark
        checkIcon.classList.add("tw:hidden");
        checkIcon.classList.remove("tw:text-green-600");
        xIcon.classList.remove("tw:hidden");
      }
    });

    // Calculate strength score (0-4)
    let score = 0;
    if (checks.length) score++;
    if (checks.lowercase && checks.uppercase) score++;
    if (checks.number) score++;
    if (checks.special) score++;

    // Update strength bar and label
    this.updateStrengthUI(score, password.length);
  },

  updateStrengthUI(score, length) {
    const strengths = [
      { label: "Too weak", color: "tw:bg-red-500", width: "25%" },
      { label: "Weak", color: "tw:bg-orange-500", width: "40%" },
      { label: "Fair", color: "tw:bg-yellow-500", width: "60%" },
      { label: "Good", color: "tw:bg-blue-500", width: "80%" },
      { label: "Strong", color: "tw:bg-green-600", width: "100%" },
    ];

    const strength = length === 0 ? null : strengths[score];

    if (!strength) {
      // Reset UI when password is empty
      if (this.strengthBar) {
        this.strengthBar.style.width = "0%";
        this.strengthBar.className =
          "tw:h-full tw:rounded-full tw:transition-all tw:duration-300";
      }
      if (this.progressBar) {
        this.progressBar.setAttribute("aria-valuenow", "0");
      }
      if (this.strengthLabel) {
        this.strengthLabel.textContent = "";
        this.strengthLabel.className = "tw:text-small tw:font-medium";
      }
      return;
    }

    // Calculate percentage for ARIA
    const percentage = parseInt(strength.width);

    // Update strength bar
    if (this.strengthBar) {
      this.strengthBar.style.width = strength.width;
      this.strengthBar.className = `tw:h-full tw:rounded-full tw:transition-all tw:duration-300 ${strength.color}`;
    }

    // Update ARIA progress value
    if (this.progressBar) {
      this.progressBar.setAttribute("aria-valuenow", percentage.toString());
    }

    // Update strength label
    if (this.strengthLabel) {
      this.strengthLabel.textContent = strength.label;
      const labelColors = {
        "Too weak": "tw:text-red-600",
        Weak: "tw:text-orange-600",
        Fair: "tw:text-yellow-600",
        Good: "tw:text-blue-600",
        Strong: "tw:text-green-600",
      };
      this.strengthLabel.className = `tw:text-small tw:font-medium ${
        labelColors[strength.label]
      }`;
    }
  },
};

export default PasswordStrength;
