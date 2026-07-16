const LineHighlight = {
  mounted() {
    this.lineSelector = this.el.dataset.lineSelector || ".l-line";
    this.selectedClass = this.el.dataset.selectedClass || "l-highlighted";
    this.idPrefix = this.el.dataset.idPrefix || "L";

    this.onClick = (event) => {
      const line = event.target.closest(this.lineSelector);
      if (!line || !this.el.contains(line) || !line.id) return;

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
    this.el.querySelectorAll(this.lineSelector).forEach((line) => {
      if (!line.id && line.dataset.line) {
        line.id = `${this.idPrefix}${line.dataset.line}`;
      }
    });
    this.highlightLine();
  },

  highlightLine() {
    this.el.querySelectorAll(`.${this.selectedClass}`).forEach((line) => {
      line.classList.remove(this.selectedClass);
    });

    if (!window.location.hash) return;

    const id = window.location.hash.slice(1);
    const line = document.getElementById(id);

    if (line && this.el.contains(line) && line.matches(this.lineSelector)) {
      line.classList.add(this.selectedClass);
      line.scrollIntoView({ block: "center" });
    }
  },
};

export default LineHighlight;
