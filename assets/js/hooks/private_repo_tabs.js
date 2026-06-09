// Shows or hides the organization's own repository tab based on the policy's
// visibility. A public policy only publishes rules for the public `hexpm`
// repository, so its org tab is hidden; toggling the visibility control to
// private reveals it immediately.
//
// The container opts in via phx-hook="PrivateRepoTabs" and holds the repo
// tablist; the private-only tab buttons are marked [data-private-only]. The
// visibility input (#policy_visibility) lives elsewhere in the form.
export const PrivateRepoTabs = {
  mounted() {
    const visibility = document.getElementById("policy_visibility");
    if (!visibility) return;

    const privateOnly = this.el.querySelectorAll("[data-private-only]");

    const sync = () => {
      const isPrivate =
        visibility.type === "checkbox"
          ? visibility.checked
          : visibility.value === "private";

      privateOnly.forEach((el) => {
        el.hidden = !isPrivate;
      });

      // Going public hides the org tab, so fall back to the always-visible
      // hexpm tab to avoid leaving a hidden tab's panel showing.
      if (!isPrivate) {
        const hexpmTab = this.el.querySelector('[role="tab"][data-value="hexpm"]');
        if (hexpmTab) hexpmTab.click();
      }
    };

    visibility.addEventListener("change", sync);
    visibility.addEventListener("input", sync);
    sync();
  },
};
