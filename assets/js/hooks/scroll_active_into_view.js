export const ScrollActiveIntoView = {
  mounted() {
    const active = this.el.querySelector("[data-active='true']");
    if (!active) return;
    const target = active.offsetLeft - this.el.clientWidth / 2 + active.offsetWidth / 2;
    this.el.scrollLeft = Math.max(0, target);
  },
};
