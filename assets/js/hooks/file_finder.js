/**
 * FileFinder Hook
 *
 * Client-side file navigation for the package file browser. The server renders
 * the top level of the tree and the directories leading to the file on screen;
 * this hook owns everything else:
 *
 * - the file index, read from a <template data-file-paths> JSON payload rather
 *   than from the document, so a directory does not have to be rendered for its
 *   files to be searchable. 700 paths is around 29KB against roughly 2KB of
 *   markup per rendered node.
 * - filling a directory when it is opened, by cloning <template data-tree-file>
 *   and <template data-tree-dir> so the markup matches what the server renders
 * - fuzzy file filtering (sidebar search and modal finder)
 * - the active-file highlight (aria-current) and revealing the file on screen,
 *   driven by the root's data-active-path attribute
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
    this.resultsContainer = this.treeEl.querySelector("[data-results-container]");
    this.sidebarList = this.resultsContainer.querySelector("[data-results]");
    this.sidebarEmpty = this.resultsContainer.querySelector("[data-empty]");
    this.modalList = this.modalResults.querySelector("[data-results]");
    this.modalEmpty = this.modalResults.querySelector("[data-empty]");
    this.query = "";

    this.resolveTree();
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
    // `toggle` does not bubble, so it is captured from the container instead of
    // bound per <details>, which also covers the ones this hook adds later.
    this.onToggle = (event) => {
      const details = event.target;
      if (details.tagName === "DETAILS" && details.open) this.fill(details);
    };

    this.inputs = [this.sidebarInput, this.modalInput].filter(Boolean);
    this.forms = this.inputs.map((input) => input.closest("form")).filter(Boolean);
    this.inputs.forEach((input) => input.addEventListener("input", this.onInput));
    this.forms.forEach((form) => form.addEventListener("submit", this.onSubmit));
    this.sidebarList.addEventListener("click", this.onResultsClick);
    this.modalResults.addEventListener("click", this.onResultsClick);
    this.treeEl.addEventListener("toggle", this.onToggle, true);
  },

  updated() {
    if (this.el.dataset.treeVersion !== this.treeVersion) {
      // A new tree replaces the container, so the cached nodes and the paths
      // they were built from are both stale.
      this.resolveTree();
      this.buildIndex();
    }

    // Re-assert view state on every patch, not only when the tree changed. A
    // patch re-renders the results list from the server, which empties the
    // injected results and restores their hidden class, while the tree
    // container is ignored and keeps whatever class the client put on it. Skip
    // this and a patch during an active search leaves both halves hidden.
    this.filterAndRender();
    this.applyActive();
  },

  destroyed() {
    this.inputs.forEach((input) => input.removeEventListener("input", this.onInput));
    this.forms.forEach((form) => form.removeEventListener("submit", this.onSubmit));
    this.sidebarList.removeEventListener("click", this.onResultsClick);
    this.modalResults.removeEventListener("click", this.onResultsClick);
    this.treeEl.removeEventListener("toggle", this.onToggle, true);
  },

  resolveTree() {
    this.treeContainer = this.treeEl.querySelector("[data-tree-container]");
    this.fileTemplate = this.treeContainer.querySelector("template[data-tree-file]");
    this.dirTemplate = this.treeContainer.querySelector("template[data-tree-dir]");
    this.hrefBase = this.el.dataset.fileHrefBase || "";
  },

  buildIndex() {
    this.treeVersion = this.el.dataset.treeVersion;
    const payload = this.treeContainer.querySelector("template[data-file-paths]");
    const paths = payload ? JSON.parse(payload.content.textContent) : [];

    this.index = paths.map((path) => ({
      path,
      lower: path.toLowerCase(),
      href: this.hrefFor(path),
    }));
  },

  hrefFor(path) {
    const encoded = path.split("/").map(encodeSegment).join("/");
    return `${this.hrefBase}/${encoded}`;
  },

  /**
   * Builds the immediate children of an open directory. Names that have
   * anything below them become directories, the rest become file links.
   */
  fill(details) {
    const holder = details.querySelector("[data-children]");
    if (!holder || holder.dataset.filled === "true") return;

    const parent = details.dataset.dirPath;
    const prefix = parent === "" ? "" : `${parent}/`;
    const directories = new Map();
    const candidates = [];

    for (const entry of this.index) {
      if (!entry.path.startsWith(prefix)) continue;
      const rest = entry.path.slice(prefix.length).split("/");
      if (rest.length === 1) {
        candidates.push({ name: rest[0], entry });
      } else if (!directories.has(rest[0])) {
        directories.set(rest[0], prefix + rest[0]);
      }
    }

    // A name with anything below it is a directory, even if a file of the same
    // name also exists, which is what child_nodes/3 does. Emitting both would
    // put two nodes on the client where the server renders one.
    const files = candidates.filter((file) => !directories.has(file.name));

    const list = document.createElement("ul");
    list.className = "space-y-0.5";

    const names = [...directories.keys()].sort(compare);
    for (const name of names) {
      list.appendChild(this.buildDirectory(name, directories.get(name)));
    }
    for (const file of files.sort((a, b) => compare(a.name, b.name))) {
      list.appendChild(this.buildFile(file.name, file.entry));
    }

    holder.textContent = "";
    holder.appendChild(list);
    holder.dataset.filled = "true";
  },

  buildDirectory(name, path) {
    const item = document.createElement("li");
    const node = this.dirTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.dirPath = path;
    node.querySelector("summary [data-name]").textContent = name;
    item.appendChild(node);
    return item;
  },

  buildFile(name, entry) {
    const item = document.createElement("li");
    const node = this.fileTemplate.content.firstElementChild.cloneNode(true);
    node.setAttribute("href", entry.href);
    node.dataset.path = entry.path;
    node.querySelector("[data-name]").textContent = name;
    item.appendChild(node);
    return item;
  },

  /**
   * Opens every directory above a path, filling each one as it goes so the next
   * one down exists to be opened, and returns the file's link if it is there.
   */
  reveal(path) {
    const parts = path.split("/");
    let prefix = "";

    for (const part of parts.slice(0, -1)) {
      prefix = prefix === "" ? part : `${prefix}/${part}`;
      const details = this.treeContainer.querySelector(
        `details[data-dir-path="${CSS.escape(prefix)}"]`,
      );
      if (!details) break;
      details.open = true;
      this.fill(details);
    }

    return this.treeContainer.querySelector(`a[data-path="${CSS.escape(path)}"]`);
  },

  applyActive() {
    const active = this.el.dataset.activePath || null;

    for (const link of this.treeContainer.querySelectorAll("a[data-path][aria-current]")) {
      link.removeAttribute("aria-current");
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

    if (!active) return;

    const link = this.reveal(active);
    if (!link) return;

    link.setAttribute("aria-current", "page");
    link.scrollIntoView({ block: "nearest" });
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

// Phoenix builds paths with URI.char_unreserved?/1, which percent-encodes these
// five where encodeURIComponent leaves them alone. Matching it keeps one URL per
// file whether the link came from the server or from here.
function encodeSegment(segment) {
  return encodeURIComponent(segment).replace(
    /[!'()*]/g,
    (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

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
