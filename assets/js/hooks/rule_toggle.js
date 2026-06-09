// Enables/disables a categorical policy rule client-side.
//
// The container opts in via phx-hook="RuleToggle" and holds:
//   - a [data-rule-enabled] checkbox (the visible switch)
//   - a [data-rule-body] element with the rule's controls
//
// Toggling the switch shows or hides the body. Turning the rule off clears
// every control inside the body so the disabled rule submits as unset.
export const RuleToggle = {
  mounted() {
    const checkbox = this.el.querySelector("[data-rule-enabled]");
    const body = this.el.querySelector("[data-rule-body]");
    const disabled = this.el.querySelector("[data-rule-disabled]");
    if (!checkbox || !body) return;

    const severityClasses = [
      "bg-blue-500",
      "bg-yellow-500",
      "bg-red-500",
      "bg-red-600",
      "bg-grey-300",
      "dark:bg-grey-500",
    ];

    const severityClass = (value) => {
      switch (value) {
        case "1":
          return ["bg-blue-500"];
        case "2":
          return ["bg-yellow-500"];
        case "3":
          return ["bg-red-500"];
        case "4":
          return ["bg-red-600"];
        default:
          return ["bg-grey-300", "dark:bg-grey-500"];
      }
    };

    const syncSeverityDot = (select) => {
      const dot = select
        .closest("[data-severity-select]")
        ?.querySelector("[data-severity-dot]");
      if (!dot) return;

      dot.classList.remove(...severityClasses);
      dot.classList.add(...severityClass(select.value));
    };

    const sync = () => {
      body.classList.toggle("hidden", !checkbox.checked);
      if (disabled) {
        disabled.classList.toggle("hidden", checkbox.checked);
        disabled.classList.toggle("flex", !checkbox.checked);
      }
    };

    checkbox.addEventListener("change", () => {
      if (!checkbox.checked) {
        body.querySelectorAll('input[type="checkbox"]').forEach((input) => {
          input.checked = false;
        });
        body.querySelectorAll('input:not([type="checkbox"])').forEach((input) => {
          input.value = "";
          input.dispatchEvent(new Event("input", { bubbles: true }));
        });
        body.querySelectorAll("select").forEach((select) => {
          select.value = "";
          select.dispatchEvent(new Event("change", { bubbles: true }));
          select.dispatchEvent(new Event("input", { bubbles: true }));
        });
      }
      sync();
    });

    body.querySelectorAll("[data-severity-control]").forEach((select) => {
      select.addEventListener("change", () => syncSeverityDot(select));
      syncSeverityDot(select);
    });

    sync();
  },
};
