const loadedGapChains = new Set();
let lastGapLoadAt = 0;

function gapChain(el) {
  const boundary =
    el.dataset.direction === "backward" ? el.dataset.start : el.dataset.last;

  return `${el.dataset.direction}:${boundary}`;
}

export const InfiniteScroll = {
  mounted() {
    this.pending = false;
    this.chain = gapChain(this.el);
    this.blocked = loadedGapChains.has(this.chain);
    this.intersecting = false;
    this.lastScrollY = window.scrollY;

    this.onScroll = () => {
      const scrollY = window.scrollY;
      const delta = scrollY - this.lastScrollY;

      if (
        this.blocked &&
        this.intersecting &&
        !this.pending &&
        Date.now() - lastGapLoadAt > 300 &&
        ((this.el.dataset.direction === "backward" && delta < -50) ||
          (this.el.dataset.direction === "forward" && delta > 50))
      ) {
        this.blocked = false;
        this.pending = true;
        this.loadGap();
      }

      if (Math.abs(delta) > 50) {
        this.lastScrollY = scrollY;
      }
    };

    this.onFileScroll = () => {
      this.blocked = true;
      loadedGapChains.add(this.chain);
      this.lastScrollY = window.scrollY;
    };

    window.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("hexpm:scroll-to-diff", this.onFileScroll);
    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.intersecting = entry.isIntersecting;

        if (!entry.isIntersecting) {
          this.blocked = false;
          loadedGapChains.delete(this.chain);
        } else if (!this.blocked && !this.pending) {
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
    window.removeEventListener("scroll", this.onScroll);
    window.removeEventListener("hexpm:scroll-to-diff", this.onFileScroll);
  },

  updated() {
    this.pending = false;
    this.chain = gapChain(this.el);
    this.blocked = loadedGapChains.has(this.chain);
    this.lastScrollY = window.scrollY;
  },

  loadGap() {
    lastGapLoadAt = Date.now();
    loadedGapChains.add(this.chain);
    this.pushEvent("load-gap", {
      start: this.el.dataset.start,
      last: this.el.dataset.last,
    });
  },
};
