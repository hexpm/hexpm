// Below lg the docs nav is an off-canvas drawer built on <details>. The
// element gives us the open/close plumbing but none of the modal behavior a
// drawer needs: focus can tab straight out to the page sitting behind the
// backdrop, and Escape does nothing. Both are supplied here, and focus is
// handed back to the trigger when the drawer closes.
//
// From lg up the same markup is a plain sidebar, so every branch below is a
// no-op at that width.

const DESKTOP_QUERY = "(min-width: 64rem)";

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function initializeDocsNav() {
  const details = document.querySelector("details.docs-nav");
  if (!details) return;

  const summary = details.querySelector("summary");
  const panel = details.querySelector(".docs-nav-panel");
  if (!summary || !panel) return;

  const desktop = window.matchMedia(DESKTOP_QUERY);
  const isDrawer = () => !desktop.matches;

  // Whether we moved focus into the drawer, so closing only pulls focus back
  // to the trigger when it was ours to move.
  let focusMoved = false;

  function focusableStops() {
    const inPanel = Array.from(panel.querySelectorAll(FOCUSABLE)).filter(
      (el) => el.getClientRects().length > 0,
    );
    return [summary, ...inPanel];
  }

  function openDrawer() {
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-modal", "true");

    const stops = focusableStops();
    const target = stops.length > 1 ? stops[1] : panel;
    target.focus();
    focusMoved = true;
  }

  function releaseDrawer() {
    panel.removeAttribute("role");
    panel.removeAttribute("aria-modal");

    if (focusMoved) {
      focusMoved = false;
      // Only reclaim focus if it is still inside the drawer; a click on a nav
      // link is already navigating and a click elsewhere has moved on.
      if (details.contains(document.activeElement) && isDrawer()) {
        summary.focus();
      }
    }
  }

  details.addEventListener("toggle", () => {
    if (details.open && isDrawer()) {
      openDrawer();
    } else {
      releaseDrawer();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (!details.open || !isDrawer()) return;

    if (event.key === "Escape") {
      event.preventDefault();
      details.open = false;
      return;
    }

    if (event.key !== "Tab") return;

    const stops = focusableStops();
    if (stops.length === 0) return;

    const first = stops[0];
    const last = stops[stops.length - 1];
    const active = document.activeElement;

    if (!details.contains(active)) {
      // Focus already escaped (or started outside): pull it to the edge the
      // user is tabbing toward.
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    } else if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  });

  // Crossing the breakpoint while open would otherwise leave a sidebar
  // carrying dialog semantics and a focus trap.
  desktop.addEventListener("change", () => {
    if (desktop.matches) {
      panel.removeAttribute("role");
      panel.removeAttribute("aria-modal");
      focusMoved = false;
    } else if (details.open) {
      openDrawer();
    }
  });
}
