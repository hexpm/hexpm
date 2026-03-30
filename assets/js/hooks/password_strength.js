/**
 * Password Strength Hook
 *
 * Calculates password strength based on NIST SP 800-63B and ASVS v5 guidelines:
 * - Length (min 8 characters required)
 * - Character diversity (lowercase, uppercase, numbers)
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
      length: password.length >= 8,
      lowercase: /[a-z]/.test(password),
      uppercase: /[A-Z]/.test(password),
      number: /[0-9]/.test(password),
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
        checkIcon.classList.remove("hidden");
        checkIcon.classList.add("text-green-600");
        xIcon.classList.add("hidden");
      } else {
        checkIcon.classList.add("hidden");
        checkIcon.classList.remove("text-green-600");
        xIcon.classList.remove("hidden");
      }
    });

    // Calculate strength score (0-4) per NIST SP 800-63B / ASVS v5
    // Length is the primary driver; character diversity adds incremental value
    let score = 0;
    if (checks.length) score++;
    if (password.length >= 12) score++;
    if (checks.lowercase && checks.uppercase) score++;
    if (checks.number) score++;

    // Update strength bar and label
    this.updateStrengthUI(score, password.length);
  },

  updateStrengthUI(score, length) {
    const strengths = [
      { label: "Too weak", color: "bg-red-500", width: "w-1/4", percentage: 25 },
      { label: "Weak", color: "bg-orange-500", width: "w-2/5", percentage: 40 },
      { label: "Fair", color: "bg-yellow-500", width: "w-3/5", percentage: 60 },
      { label: "Good", color: "bg-blue-500", width: "w-4/5", percentage: 80 },
      { label: "Strong", color: "bg-green-600", width: "w-full", percentage: 100 },
    ];

    const strength = length === 0 ? null : strengths[score];

    if (!strength) {
      // Reset UI when password is empty
      if (this.strengthBar) {
        this.strengthBar.className =
          "h-full w-0 rounded-full transition-all duration-300";
      }
      if (this.progressBar) {
        this.progressBar.setAttribute("aria-valuenow", "0");
      }
      if (this.strengthLabel) {
        this.strengthLabel.textContent = "";
        this.strengthLabel.className = "text-small font-medium";
      }
      return;
    }

    // Update strength bar
    if (this.strengthBar) {
      this.strengthBar.className = `h-full rounded-full transition-all duration-300 ${strength.width} ${strength.color}`;
    }

    // Update ARIA progress value
    if (this.progressBar) {
      this.progressBar.setAttribute("aria-valuenow", strength.percentage.toString());
    }

    // Update strength label
    if (this.strengthLabel) {
      this.strengthLabel.textContent = strength.label;
      const labelColors = {
        "Too weak": "text-red-600",
        Weak: "text-orange-600",
        Fair: "text-yellow-600",
        Good: "text-blue-600",
        Strong: "text-green-600",
      };
      this.strengthLabel.className = `text-small font-medium ${
        labelColors[strength.label]
      }`;
    }
  },
};

export default PasswordStrength;
