export const InfiniteScroll = {
  mounted() {
    this.pending = false;
    this.observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !this.pending) {
          this.pending = true;
          this.pushEvent("load-more", {});
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
      const visible = this.el.getBoundingClientRect().top <= window.innerHeight;
      if (visible && !this.pending) {
        this.pending = true;
        this.pushEvent("load-more", {});
      }
    });
  },
};
