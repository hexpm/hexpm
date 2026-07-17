export const InfiniteScroll = {
  mounted() {
    this.pending = false;
    this.observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !this.pending) {
          this.pending = true;
          this.loadGap();
        }
      },
      { rootMargin: "100px", threshold: 0.1 },
    );
    this.observer.observe(this.el);
  },

  destroyed() {
    this.observer?.disconnect();
  },

  updated() {
    this.pending = false;
    requestAnimationFrame(() => {
      const rect = this.el.getBoundingClientRect();
      const visible = rect.top <= window.innerHeight + 100 && rect.bottom >= -100;
      if (visible && !this.pending) {
        this.pending = true;
        this.loadGap();
      }
    });
  },

  loadGap() {
    this.pushEvent("load-gap", {
      start: this.el.dataset.start,
      last: this.el.dataset.last,
    });
  },
};
