/**
 * NavigateOnChange Hook
 *
 * Navigates to the URL specified by the selected value when changed.
 *
 * Usage:
 * <select phx-hook="NavigateOnChange" id="my-select">
 *   <option value="/page1">Page 1</option>
 *   <option value="/page2">Page 2</option>
 * </select>
 */
export const NavigateOnChange = {
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
    window.location.href = this.el.value;
  },
};
