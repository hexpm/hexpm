const PreviewLineHighlight = {
  mounted() {
    this.onClick = (event) => {
      const line = event.target.closest(".l-line");
      if (!line || !this.el.contains(line)) return;

      window.history.replaceState(null, "", `#${line.id}`);
      this.highlightLine();
    };

    this.onHashChange = () => this.highlightLine();
    this.el.addEventListener("click", this.onClick);
    window.addEventListener("hashchange", this.onHashChange);
    this.prepareLines();
  },

  updated() {
    this.prepareLines();
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    window.removeEventListener("hashchange", this.onHashChange);
  },

  prepareLines() {
    this.el.querySelectorAll(".l-line").forEach((line) => {
      line.id = `L${line.dataset.line}`;
    });
    this.highlightLine();
  },

  highlightLine() {
    this.el.querySelectorAll(".l-highlighted").forEach((line) => {
      line.classList.remove("l-highlighted");
    });

    if (/^#L\d+$/.test(window.location.hash)) {
      const line = this.el.querySelector(window.location.hash);
      if (line) line.classList.add("l-highlighted");
    }
  },
};

export default PreviewLineHighlight;
