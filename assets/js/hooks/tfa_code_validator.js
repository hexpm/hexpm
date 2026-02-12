/**
 * TFA Code Validator Hook
 * 
 * Validates a 6-digit numeric code input and enables/disables a submit button
 * based on the validation result.
 * 
 * Usage:
 * <input phx-hook="TFACodeValidator" data-target-button="button-id" />
 */
export default {
  mounted() {
    this.handleInput = this.handleInput.bind(this);
    this.el.addEventListener("input", this.handleInput);
    
    // Get target button ID from data attribute
    this.targetButtonId = this.el.dataset.targetButton;
    this.button = document.getElementById(this.targetButtonId);
    
    if (!this.button) {
      console.warn(`TFACodeValidator: Button with id "${this.targetButtonId}" not found`);
      return;
    }
    
    // Set initial disabled state
    this.button.disabled = true;
    
    // Initial validation on mount
    this.validateAndUpdate();
  },

  destroyed() {
    if (this.handleInput) {
      this.el.removeEventListener("input", this.handleInput);
    }
  },

  handleInput() {
    this.validateAndUpdate();
  },

  validateAndUpdate() {
    const value = this.el.value;
    const isValid = /^[0-9]{6}$/.test(value);
    
    if (!this.button) return;
    
    // Update button disabled state
    this.button.disabled = !isValid;
    
    // Update button visual state
    if (isValid) {
      this.button.classList.remove('tw:opacity-50', 'tw:cursor-not-allowed');
      this.button.classList.add('tw:cursor-pointer');
    } else {
      this.button.classList.add('tw:opacity-50', 'tw:cursor-not-allowed');
      this.button.classList.remove('tw:cursor-pointer');
    }
  }
};
