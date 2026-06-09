export const FocusFirstField = {
  mounted() {
    this.el.addEventListener("click", () => {
      const targetId = this.el.dataset.target;
      const target = targetId && document.getElementById(targetId);
      if (target) {
        target.focus();
        target.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    });
  },
};

export const ScrollToTarget = {
  mounted() {
    this.el.addEventListener("click", () => {
      const targetId = this.el.dataset.target;
      const target = targetId && document.getElementById(targetId);
      if (target) {
        target.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    });
  },
};
