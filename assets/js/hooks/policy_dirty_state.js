export const PolicyDirtyState = {
  mounted() {
    this.form = this.el.matches("form") ? this.el : this.el.querySelector("form");
    this.status = document.getElementById(this.el.dataset.statusTarget);
    if (!this.form || !this.status) return;

    this.cleanText = this.status.dataset.cleanText || "All changes saved";
    this.dirtyText = this.status.dataset.dirtyText || "Unsaved changes";
    this.cleanValue = this.serialize();

    this.sync = () => {
      const dirty = this.serialize() !== this.cleanValue;
      this.status.textContent = dirty ? this.dirtyText : this.cleanText;
      this.status.classList.toggle("text-grey-500", !dirty);
      this.status.classList.toggle("dark:text-grey-400", !dirty);
      this.status.classList.toggle("text-yellow-700", dirty);
      this.status.classList.toggle("dark:text-yellow-300", dirty);
    };

    this.form.addEventListener("input", this.sync);
    this.form.addEventListener("change", this.sync);
    this.form.addEventListener("policy-form-change", this.sync);
    this.form.addEventListener("reset", () => window.setTimeout(this.sync, 0));
    this.sync();
  },

  serialize() {
    return Array.from(new FormData(this.form).entries())
      .filter(([name]) => !["_csrf_token", "_sudo_token", "_method"].includes(name))
      .map(([name, value]) => [name, String(value)])
      .sort(([leftName, leftValue], [rightName, rightValue]) => {
        if (leftName === rightName) return leftValue.localeCompare(rightValue);
        return leftName.localeCompare(rightName);
      })
      .map(([name, value]) => `${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
      .join("&");
  },
};
