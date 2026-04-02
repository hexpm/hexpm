/**
 * FormSubmit Hook
 *
 * Submits a form by ID when the element is clicked.
 * CSP-compliant replacement for inline onclick="document.getElementById('form-id').submit()".
 *
 * Usage:
 * <button phx-hook="FormSubmit" data-form="form-id">Submit</button>
 */
export const FormSubmit = {
  mounted() {
    this.boundSubmit = this.handleSubmit.bind(this);
    this.el.addEventListener("click", this.boundSubmit);
  },

  destroyed() {
    if (this.boundSubmit) {
      this.el.removeEventListener("click", this.boundSubmit);
    }
  },

  handleSubmit(event) {
    event.preventDefault();

    const formId = this.el.dataset.form;
    const form = document.getElementById(formId);

    if (form) {
      form.submit();
    }
  },
};
