const LineHighlight = {
  mounted() {
    this.lineSelector = this.el.dataset.lineSelector || ".l-line";
    this.selectedClass = this.el.dataset.selectedClass || "l-highlighted";
    this.idPrefix = this.el.dataset.idPrefix || "L";

    this.onClick = (event) => {
      const line = event.target.closest(this.lineSelector);
      if (!line || !this.el.contains(line) || !line.id) return;

      this.selectLine(line);
    };

    this.onKeyDown = (event) => {
      if (event.key !== "Enter" && event.key !== " ") return;

      const lineNumber = event.target.closest(".ghd-line-number");
      const line = lineNumber && lineNumber.closest(this.lineSelector);
      if (!line || !this.el.contains(line) || !line.id) return;

      event.preventDefault();
      this.selectLine(line);
    };

    this.onHashChange = () => {
      this.requestHashTarget();
      this.highlightLine();
    };
    this.el.addEventListener("click", this.onClick);
    this.el.addEventListener("keydown", this.onKeyDown);
    window.addEventListener("hashchange", this.onHashChange);
    this.handleEvent("scroll-to-file", ({ id }) => {
      requestAnimationFrame(() => {
        const file = document.getElementById(id);
        if (file && this.el.contains(file)) {
          const previous = file.previousElementSibling;
          const gapOffset = previous?.id.startsWith("diff-gap-")
            ? previous.getBoundingClientRect().height
            : 0;

          window.dispatchEvent(new Event("hexpm:scroll-to-diff"));
          window.history.replaceState(null, "", `#${id}`);
          window.scrollTo({
            top:
              file.getBoundingClientRect().top + window.scrollY - gapOffset,
            behavior: "instant",
          });
        }
      });
    });
    this.prepareLines();
    this.requestHashTarget();
  },

  updated() {
    this.prepareLines();
    this.requestHashTarget();
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    this.el.removeEventListener("keydown", this.onKeyDown);
    window.removeEventListener("hashchange", this.onHashChange);
  },

  selectLine(line) {
    window.history.replaceState(null, "", `#${line.id}`);
    this.highlightLine();
  },

  requestHashTarget() {
    if (!window.location.hash) return;

    const id = window.location.hash.slice(1);
    if (document.getElementById(id)) {
      this.loadingHashPiece = null;
      return;
    }

    const match = id.match(/^(diff-\d+)-L/);
    if (!match || this.loadingHashPiece === match[1]) return;

    this.loadingHashPiece = match[1];
    this.pushEvent("load-piece", { id: match[1] });
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
