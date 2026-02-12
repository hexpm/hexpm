/**
 * CopyButton Hook
 * 
 * Handles copying text to clipboard with visual feedback.
 * Shows an inline "Copied!" tooltip when successful.
 * 
 * Usage:
 * <button phx-hook="CopyButton" data-copy-target="element-id">
 *   <icon />
 * </button>
 * 
 * The target element should have a data-value attribute with the text to copy.
 */
export const CopyButton = {
  mounted() {
    this.boundHandleCopy = this.handleCopy.bind(this);
    this.el.addEventListener("click", this.boundHandleCopy);
  },

  destroyed() {
    if (this.boundHandleCopy) {
      this.el.removeEventListener("click", this.boundHandleCopy);
    }
  },

  handleCopy(event) {
    event.preventDefault();
    
    const targetId = this.el.dataset.copyTarget;
    const targetElement = document.getElementById(targetId);
    
    if (!targetElement) {
      console.error(`Copy target element not found: ${targetId}`);
      return;
    }

    const textToCopy = targetElement.dataset.value;
    
    if (!textToCopy) {
      console.error(`No data-value found on target element: ${targetId}`);
      return;
    }

    // Modern clipboard API
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(textToCopy)
        .then(() => this.showSuccess())
        .catch((err) => this.showError(err));
    } else {
      // Fallback for older browsers
      this.fallbackCopy(textToCopy);
    }
  },

  fallbackCopy(text) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    
    try {
      const successful = document.execCommand("copy");
      document.body.removeChild(textarea);
      
      if (successful) {
        this.showSuccess();
      } else {
        this.showError(new Error("Copy command failed"));
      }
    } catch (err) {
      document.body.removeChild(textarea);
      this.showError(err);
    }
  },

  showSuccess() {
    // Create tooltip element
    const tooltip = document.createElement("div");
    tooltip.textContent = "Copied!";
    tooltip.className = "copy-tooltip tw:absolute tw:bg-grey-900 tw:text-white tw:text-xs tw:px-2 tw:py-1 tw:rounded tw:whitespace-nowrap tw:pointer-events-none tw:z-50";
    tooltip.style.bottom = "calc(100% + 8px)";
    tooltip.style.left = "50%";
    tooltip.style.transform = "translateX(-50%)";
    tooltip.style.opacity = "0";
    tooltip.style.transition = "opacity 0.2s ease-in-out";
    
    // Make button position relative if it isn't already
    const originalPosition = this.el.style.position;
    if (getComputedStyle(this.el).position === "static") {
      this.el.style.position = "relative";
    }
    
    this.el.appendChild(tooltip);
    
    // Trigger animation
    setTimeout(() => {
      tooltip.style.opacity = "1";
    }, 10);
    
    // Remove tooltip after delay
    setTimeout(() => {
      tooltip.style.opacity = "0";
      setTimeout(() => {
        if (tooltip.parentNode) {
          this.el.removeChild(tooltip);
        }
        // Restore original position
        if (originalPosition) {
          this.el.style.position = originalPosition;
        }
      }, 200);
    }, 1500);
  },

  showError(err) {
    console.error("Failed to copy:", err);
    
    // Create error tooltip
    const tooltip = document.createElement("div");
    tooltip.textContent = "Failed to copy";
    tooltip.className = "copy-tooltip tw:absolute tw:bg-red-600 tw:text-white tw:text-xs tw:px-2 tw:py-1 tw:rounded tw:whitespace-nowrap tw:pointer-events-none tw:z-50";
    tooltip.style.bottom = "calc(100% + 8px)";
    tooltip.style.left = "50%";
    tooltip.style.transform = "translateX(-50%)";
    tooltip.style.opacity = "0";
    tooltip.style.transition = "opacity 0.2s ease-in-out";
    
    const originalPosition = this.el.style.position;
    if (getComputedStyle(this.el).position === "static") {
      this.el.style.position = "relative";
    }
    
    this.el.appendChild(tooltip);
    
    setTimeout(() => {
      tooltip.style.opacity = "1";
    }, 10);
    
    setTimeout(() => {
      tooltip.style.opacity = "0";
      setTimeout(() => {
        if (tooltip.parentNode) {
          this.el.removeChild(tooltip);
        }
        if (originalPosition) {
          this.el.style.position = originalPosition;
        }
      }, 200);
    }, 2000);
  }
};
