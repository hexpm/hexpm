# Modal Implementation in Controller Views

This document explains how to properly implement modals in traditional Phoenix controller views (non-LiveView pages) using Phoenix.LiveView.JS commands.

## Key Concept

Even though pages like Email, Keys, and Sessions are **controller views** (not LiveView), we can still use LiveView's modal components and JS commands because `LiveSocket.connect()` is initialized globally in `assets/js/app.js`.

## The Right Way: Phoenix.LiveView.JS

**Always use `Phoenix.LiveView.JS` commands** - never write custom JavaScript or jQuery for modals.

### Implementation Steps

1. **Import the modal functions** in your component:
   ```elixir
   import HexpmWeb.Components.Modal, only: [show_modal: 1, hide_modal: 1]
   ```

2. **Use `phx-click` with JS commands** (NOT `onclick`):
   ```heex
   <%!-- Correct: Use phx-click with show_modal --%>
   <button phx-click={show_modal("my-modal-id")}>
     Open Modal
   </button>

   <%!-- Wrong: Don't use onclick with JavaScript --%>
   <button onclick="showModal('my-modal-id')">
     Open Modal
   </button>
   ```

3. **Define your modal** using the `.modal` component:
   ```heex
   <.modal id="my-modal-id">
     <:header>Modal Title</:header>
     <p>Modal content</p>
     <:footer>
       <.button phx-click={hide_modal("my-modal-id")}>Close</.button>
     </:footer>
   </.modal>
   ```

## Why This Works in Controller Views

The `assets/js/app.js` file establishes a LiveSocket connection:

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  // ... configuration
});
liveSocket.connect();
```

This global connection enables:
- `phx-click` events to work
- `Phoenix.LiveView.JS` commands to execute
- Modal show/hide transitions to animate smoothly

## Common Mistakes to Avoid

### ❌ Don't: Write Custom JavaScript
```heex
<%!-- Wrong --%>
<button onclick="document.getElementById('modal').classList.add('show')">
  Open
</button>
```

### ✅ Do: Use Phoenix.LiveView.JS
```heex
<%!-- Correct --%>
<button phx-click={show_modal("modal-id")}>
  Open
</button>
```

### ❌ Don't: Use `onclick` with custom functions
```heex
<%!-- Wrong --%>
<button onclick="showModal('modal-id')">
  Open
</button>
```

### ✅ Do: Use `phx-click` with imported functions
```heex
<%!-- Correct --%>
<button phx-click={show_modal("modal-id")}>
  Open
</button>
```

## Form Submissions in Modals

For forms inside modals in controller views, use regular form submissions with CSRF tokens:

```heex
<.modal id="form-modal">
  <:header>Submit Form</:header>
  <form action={~p"/dashboard/email"} method="post">
    <input type="hidden" name="_csrf_token" value={@csrf_token} />
    <%!-- form fields --%>
    <.button type="submit">Submit</.button>
  </form>
</.modal>
```

## Icon Buttons with Modals

When using icon buttons to trigger modals:

```heex
<.tooltip text="Delete">
  <.icon_button 
    phx-click={show_modal("delete-modal-#{@item.id}")} 
    icon="trash" 
    variant="danger"
  />
</.tooltip>

<.modal id={"delete-modal-#{@item.id}"}>
  <:header>Confirm Deletion</:header>
  <p>Are you sure?</p>
  <:footer>
    <.button phx-click={hide_modal("delete-modal-#{@item.id}")}>Cancel</.button>
    <form action={@delete_path} method="post" class="tw:inline">
      <input type="hidden" name="_method" value="delete" />
      <input type="hidden" name="_csrf_token" value={@csrf_token} />
      <.button type="submit" variant="danger">Delete</.button>
    </form>
  </:footer>
</.modal>
```

## Modal ID Best Practices

### Critical: Use Database IDs for Dynamic Modals

When rendering multiple modals for list items (e.g., delete confirmations), **always use the database ID** to generate unique modal IDs, not derived values like names or emails.

#### ✅ Correct: Use Database ID
```elixir
# In the component that triggers the modal
defp item_row(assigns) do
  modal_id = "delete-item-#{assigns.item.id}"  # ✅ Uses unique ID
  assigns = assign(assigns, :modal_id, modal_id)
  
  ~H"""
  <.icon_button phx-click={show_modal(@modal_id)} icon="trash" />
  <.delete_modal item={@item} modal_id={@modal_id} />
  """
end

# In the modal component
def delete_modal(assigns) do
  modal_id = "delete-item-#{assigns.item.id}"  # ✅ Must match exactly
  assigns = assign(assigns, :modal_id, modal_id)
  
  ~H"""
  <.modal id={@modal_id}>
    <:header>Delete {@item.name}?</:header>
    ...
  </.modal>
  """
end
```

#### ❌ Wrong: Sanitizing Names/Emails
```elixir
# DON'T DO THIS - Can cause ID collisions!
defp item_row(assigns) do
  # ❌ "api-key" and "api_key" both become "delete-item-api-key"
  modal_id = "delete-item-#{String.replace(assigns.item.name, ~r/[^a-zA-Z0-9]/, "-")}"
  
  # ❌ "user+test@example.com" and "user-test@example.com" collide
  modal_id = "delete-email-#{String.replace(assigns.email.email, ~r/[^a-zA-Z0-9]/, "-")}"
end
```

### Why This Matters

**ID collisions cause invisible modals:**
- The `show_modal()` command targets the wrong ID
- Modal backdrop appears (freezing the page)
- Modal content doesn't show
- User must press ESC to unfreeze

**Example bug scenario:**
```elixir
# Component renders these keys:
- Key 1: name = "api-key", id = 42
- Key 2: name = "api_key", id = 85

# Both get modal_id = "revoke-key-api-key" (collision!)
# Clicking revoke on Key 2 shows Key 1's modal instead
```

### Pattern Summary

| Modal Type | ID Strategy | Example |
|------------|-------------|---------|
| **Dynamic** (per-item modals) | Use database ID | `"delete-email-#{email.id}"` |
| **Singleton** (single instance) | Static string | `"add-email-modal"` |

**Rule:** If you're rendering the modal in a loop or multiple times, use the database ID. If it's a unique modal (like "Add New"), a static string is fine.

## Summary

- ✅ **Always** use `phx-click={show_modal(id)}`
- ✅ **Always** import modal functions from `HexpmWeb.Components.Modal`
- ✅ **Always** use the `.modal` component
- ❌ **Never** write custom JavaScript for modals
- ❌ **Never** use `onclick` with custom functions
- ❌ **Never** manipulate DOM classes manually

The Phoenix.LiveView.JS approach is cleaner, more maintainable, and works consistently across the entire application.
