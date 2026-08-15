const loadedGapChains = new Set();
let gapLoadLocked = false;
let gapLoadUnlockTimer;

function lockGapLoading() {
  gapLoadLocked = true;
  clearTimeout(gapLoadUnlockTimer);
  gapLoadUnlockTimer = setTimeout(() => {
    gapLoadLocked = false;
  }, 150);
}

function extendGapLoadLock() {
  if (gapLoadLocked) lockGapLoading();
}

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
      extendGapLoadLock();

      if (
        this.blocked &&
        this.intersecting &&
        !this.pending &&
        !gapLoadLocked &&
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

    this.onGapLoad = ({ detail }) => {
      this.lastScrollY = window.scrollY;

      if (detail?.id === this.el.id && !this.pending) {
        this.blocked = false;
        this.pending = true;
        this.loadGap();
      }
    };

    this.onFileScroll = () => {
      this.blocked = true;
      loadedGapChains.add(this.chain);
      this.lastScrollY = window.scrollY;
    };

    window.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("hexpm:load-diff-gap", this.onGapLoad);
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
    window.removeEventListener("hexpm:load-diff-gap", this.onGapLoad);
    window.removeEventListener("hexpm:scroll-to-diff", this.onFileScroll);
  },

  updated() {
    this.pending = false;
    this.chain = gapChain(this.el);
    this.blocked = loadedGapChains.has(this.chain);
    this.lastScrollY = window.scrollY;
  },

  loadGap() {
    lockGapLoading();
    loadedGapChains.add(this.chain);
    this.pushEvent("load-gap", {
      start: this.el.dataset.start,
      last: this.el.dataset.last,
    });
  },
};
