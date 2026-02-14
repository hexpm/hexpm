/**
 * PermissionGroup Hook
 * 
 * Handles parent-child checkbox relationships for permission groups.
 * When a parent checkbox is checked:
 * - All child checkboxes are automatically checked and disabled
 * - This prevents conflicting permissions (parent gives full access)
 * When a parent checkbox is unchecked:
 * - All child checkboxes are unchecked and enabled
 * 
 * Usage:
 * <div phx-hook="PermissionGroup" data-parent="parent-checkbox-id">
 *   <input type="checkbox" id="parent-checkbox-id" />
 *   <input type="checkbox" class="child-checkbox" />
 *   <input type="checkbox" class="child-checkbox" />
 * </div>
 */
export const PermissionGroup = {
  mounted() {
    this.abortController = new AbortController();
    this.setupPermissionGroups();
  },

  updated() {
    // Remove old listeners before setting up new ones
    this.abortController.abort();
    this.abortController = new AbortController();
    this.setupPermissionGroups();
  },

  destroyed() {
    this.abortController.abort();
  },

  setupPermissionGroups() {
    const parentId = this.el.dataset.parent;
    if (!parentId) return;

    // Use scoped query to find parent checkbox within this hook element
    const parentCheckbox = this.el.querySelector(`#${parentId}`);
    if (!parentCheckbox) return;

    const childCheckboxes = this.el.querySelectorAll('.child-checkbox');
    const signal = this.abortController.signal;

    // Initialize state based on current parent checkbox state
    this.updateChildrenState(parentCheckbox, childCheckboxes);

    // Handle parent checkbox change
    parentCheckbox.addEventListener('change', (e) => {
      this.updateChildrenState(e.target, childCheckboxes);
    }, { signal });

    // Handle child checkbox changes (update parent if all children are unchecked)
    childCheckboxes.forEach(child => {
      child.addEventListener('change', () => {
        const anyChildChecked = Array.from(childCheckboxes).some(c => c.checked);
        if (!anyChildChecked) {
          parentCheckbox.checked = false;
        }
      }, { signal });
    });
  },

  updateChildrenState(parentCheckbox, childCheckboxes) {
    const isParentChecked = parentCheckbox.checked;
    childCheckboxes.forEach(child => {
      if (isParentChecked) {
        // Parent is checked: check and disable children
        child.checked = true;
        child.disabled = true;
      } else {
        // Parent is unchecked: uncheck and enable children
        child.checked = false;
        child.disabled = false;
      }
    });
  }
};
