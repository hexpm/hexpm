/**
 * FileFinder Hook
 *
 * Client-side file navigation for the package file browser. The server
 * renders the full file tree once per version; this hook owns everything
 * that used to be a LiveView round trip:
 *
 * - fuzzy file filtering (sidebar search and modal finder) over the tree's
 *   `a[data-path]` links, rendered from a <template data-finder-item>
 * - the active-file highlight (aria-current) and ancestor <details>
 *   expansion, driven by the root's data-active-path attribute, which the
 *   server updates on patch navigation
 *
 * The filter mirrors HexpmWeb.Components.FileSelector.filter/2: match by
 * substring or character subsequence, rank exact > prefix > path-segment >
 * substring > subsequence, capped at 100 results.
 */

const RESULT_LIMIT = 100;

export const FileFinder = {
  mounted() {
    this.treeEl = document.getElementById(this.el.dataset.treeId);
    this.sidebarInput = document.getElementById(this.el.dataset.sidebarInput);
    this.modalInput = document.getElementById(this.el.dataset.modalInput);
    this.modalId = this.el.dataset.modalId;
    this.modalResults = document.getElementById(this.el.dataset.modalResults);
    this.template = this.el.querySelector("template[data-finder-item]");
    this.treeContainer = this.treeEl.querySelector("[data-tree-container]");
    this.resultsContainer = this.treeEl.querySelector("[data-results-container]");
    this.sidebarList = this.resultsContainer.querySelector("[data-results]");
    this.sidebarEmpty = this.resultsContainer.querySelector("[data-empty]");
    this.modalList = this.modalResults.querySelector("[data-results]");
    this.modalEmpty = this.modalResults.querySelector("[data-empty]");
    this.query = "";

    this.buildIndex();
    this.applyActive();
    this.renderResults(this.modalList, this.modalEmpty, this.filter(""));

    this.onInput = (event) => this.setQuery(event.target.value);
    this.onSubmit = (event) => event.preventDefault();
    this.onResultsClick = (event) => {
      const link = event.target.closest("a[data-path]");
      if (!link) return;
      if (this.modalResults.contains(link)) this.closeModal();
      this.setQuery("");
    };

    this.inputs = [this.sidebarInput, this.modalInput].filter(Boolean);
    this.forms = this.inputs.map((input) => input.closest("form")).filter(Boolean);
    this.inputs.forEach((input) => input.addEventListener("input", this.onInput));
    this.forms.forEach((form) => form.addEventListener("submit", this.onSubmit));
    this.sidebarList.addEventListener("click", this.onResultsClick);
    this.modalResults.addEventListener("click", this.onResultsClick);
  },

  updated() {
    if (this.el.dataset.treeVersion !== this.treeVersion) {
      this.buildIndex();
      this.filterAndRender();
    }
    this.applyActive();
  },

  destroyed() {
    this.inputs.forEach((input) => input.removeEventListener("input", this.onInput));
    this.forms.forEach((form) => form.removeEventListener("submit", this.onSubmit));
    this.sidebarList.removeEventListener("click", this.onResultsClick);
    this.modalResults.removeEventListener("click", this.onResultsClick);
  },

  buildIndex() {
    this.treeVersion = this.el.dataset.treeVersion;
    this.index = Array.from(this.treeContainer.querySelectorAll("a[data-path]")).map((el) => ({
      el,
      path: el.dataset.path,
      lower: el.dataset.path.toLowerCase(),
      href: el.getAttribute("href"),
    }));
  },

  applyActive() {
    const active = this.el.dataset.activePath || null;

    for (const entry of this.index) {
      if (entry.path === active) {
        entry.el.setAttribute("aria-current", "page");
      } else {
        entry.el.removeAttribute("aria-current");
      }
    }

    for (const list of [this.sidebarList, this.modalList]) {
      for (const link of list.querySelectorAll("a[data-path]")) {
        if (link.dataset.path === active) {
          link.setAttribute("aria-current", "page");
        } else {
          link.removeAttribute("aria-current");
        }
      }
    }

    const entry = this.index.find((item) => item.path === active);
    if (!entry) return;

    let parent = entry.el.parentElement;
    while (parent && parent !== this.treeEl) {
      if (parent.tagName === "DETAILS") parent.open = true;
      parent = parent.parentElement;
    }

    entry.el.scrollIntoView({ block: "nearest" });
  },

  setQuery(value) {
    this.query = value;
    this.inputs.forEach((input) => {
      if (input.value !== value) input.value = value;
    });
    this.filterAndRender();
  },

  filterAndRender() {
    const query = this.query.trim().toLowerCase();
    const matches = this.filter(query);

    this.renderResults(this.modalList, this.modalEmpty, matches);

    if (query === "") {
      this.treeContainer.classList.remove("hidden");
      this.resultsContainer.classList.add("hidden");
    } else {
      this.treeContainer.classList.add("hidden");
      this.resultsContainer.classList.remove("hidden");
      this.renderResults(this.sidebarList, this.sidebarEmpty, matches);
    }
  },

  filter(query) {
    return this.index
      .filter((entry) => fuzzyMatch(entry.lower, query))
      .map((entry) => [score(entry.lower, query), entry])
      .sort(([scoreA, a], [scoreB, b]) => scoreA - scoreB || compare(a.lower, b.lower))
      .slice(0, RESULT_LIMIT)
      .map(([, entry]) => entry);
  },

  renderResults(list, empty, matches) {
    const active = this.el.dataset.activePath || null;
    const fragment = document.createDocumentFragment();

    for (const entry of matches) {
      const item = this.template.content.firstElementChild.cloneNode(true);
      const link = item.querySelector("a");
      link.setAttribute("href", entry.href);
      link.dataset.path = entry.path;
      if (entry.path === active) link.setAttribute("aria-current", "page");
      link.querySelector("[data-name]").textContent = entry.path;
      fragment.appendChild(item);
    }

    list.textContent = "";
    list.appendChild(fragment);
    empty.classList.toggle("hidden", matches.length !== 0);
  },

  closeModal() {
    const content = document.getElementById(`${this.modalId}-content`);
    content?.querySelector('[aria-label="Close modal"]')?.click();
  },
};

function fuzzyMatch(file, query) {
  return query === "" || file.includes(query) || subsequence(file, query);
}

function subsequence(file, query) {
  const characters = Array.from(query);
  let position = 0;
  for (const character of file) {
    if (character === characters[position]) position += 1;
    if (position === characters.length) return true;
  }
  return characters.length === 0;
}

function score(file, query) {
  if (query === "" || file === query) return 0;
  if (file.startsWith(query)) return 1;
  if (file.includes(`/${query}`)) return 2;
  if (file.includes(query)) return 3;
  return 4;
}

function compare(a, b) {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}
