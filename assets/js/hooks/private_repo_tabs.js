// Shows repository context and the organization's repository tab for private
// policies. Public policies only publish rules for `hexpm`, so the single-tab
// selector and its repository summary stay hidden.
//
// The container opts in via phx-hook="PrivateRepoTabs" and holds the repo
// tablist; private-only tab buttons use [data-private-only] and context that is
// redundant for public policies uses [data-private-policy-context]. The
// visibility input (#policy_visibility) lives elsewhere in the form.
export const PrivateRepoTabs = {
  mounted() {
    const visibility = document.getElementById("policy_visibility");
    if (!visibility) return;

    const privateOnly = this.el.querySelectorAll("[data-private-only]");
    const privateContext = this.el.querySelectorAll(
      "[data-private-policy-context]"
    );

    const sync = () => {
      const isPrivate =
        visibility.type === "checkbox"
          ? visibility.checked
          : visibility.value === "private";

      privateOnly.forEach((el) => {
        el.hidden = !isPrivate;
      });
      privateContext.forEach((el) => {
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
