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

export const DiffList = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const lineNumber = event.target.closest(".ghd-line-number");
      const line = lineNumber?.closest(".ghd-line");
      if (!line?.id) return;

      this.select(line);
      history.replaceState(null, "", `#${line.id}`);
    });
    this.selectHash();
  },

  updated() {
    this.selectHash();
  },

  select(line) {
    this.el.querySelectorAll(".ghd-line.selected").forEach((element) => {
      element.classList.remove("selected");
    });
    line.classList.add("selected");
  },

  selectHash() {
    if (!location.hash) return;
    const line = document.getElementById(location.hash.slice(1));
    if (line) {
      this.select(line);
      line.scrollIntoView({ block: "center" });
    }
  },
};
