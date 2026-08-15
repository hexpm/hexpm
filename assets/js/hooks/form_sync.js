/**
 * FormSync Hook
 *
 * Keeps inputs in two parallel forms in sync client-side in real-time.
 * Used for package filtering where we render two distinct forms (desktop sidebar
 * vs mobile bottom sheet) to match viewport mockups.
 *
 * By syncing inputs dynamically in the DOM, we can safely disable auto-recovery
 * on the mobile form (phx-auto-recover="ignore") and only recover the desktop form,
 * without losing the mobile user's unsaved typing progress.
 *
 * This also provides a seamless UX during viewport transitions (e.g. rotating
 * a device or resizing the browser window) because the newly visible form's
 * input elements immediately reflect the exact values the user was just interacting
 * with in the previously visible form.
 */
export const FormSync = {
  mounted() {
    const sync = (e) => {
      const targetFormId = this.el.dataset.syncTo;
      const targetForm = document.getElementById(targetFormId);
      if (targetForm) {
        const input = e.target;
        const name = input.name;
        if (name) {
          const targetInput = targetForm.querySelector(`[name="${name}"]`);
          if (targetInput && document.activeElement !== targetInput) {
            if (input.type === "checkbox" || input.type === "radio") {
              targetInput.checked = input.checked;
            } else {
              targetInput.value = input.value;
            }
          }
        }
      }
    };

    this.el.addEventListener("input", sync);
    this.el.addEventListener("change", sync);
  }
};
