/**
 * SearchInputSync Hook
 *
 * Keeps the nav search input value in sync with the current page's `?search=`
 * URL parameter. This is needed on /packages where the sidebar filters can
 * update the search query (via push_patch from PackageLive.Index) without the
 * user typing in the input directly.
 *
 * The parent LiveView (PackageLive.Index) broadcasts a "sync-search" event via
 * push_event/3. This hook receives that window event, updates the input's DOM
 * value, and pushes a "sync_term" event back to SearchSuggestionsLive so its
 * internal @term assign stays consistent.
 *
 * If the user is actively focused on the input we leave it alone to avoid
 * interrupting typing.
 */
export const SearchInputSync = {
  mounted() {
    // The hook lives on a wrapper element; the actual <input> is inside it.
    this._input = this.el.querySelector("input[type='search']") || this.el;

    this._syncHandler = (e) => {
      // Don't clobber the input while the user is actively typing in it
      if (document.activeElement === this._input) return;

      const value = e.detail.value ?? "";
      this._input.value = value;
      // Tell SearchSuggestionsLive to update its @term assign to match
      this.pushEvent("sync_term", { value });
    };

    window.addEventListener("phx:sync-search", this._syncHandler);
  },

  destroyed() {
    window.removeEventListener("phx:sync-search", this._syncHandler);
  },
};
