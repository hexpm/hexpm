# Modal Usage in Controller Views

This document explains how to use modals in Phoenix controller views (non-LiveView pages).

## Key Concept

Even though this is a **controller view** (not a LiveView), modals work with `phx-click` because **LiveSocket is globally connected** on all pages via `assets/js/app.js`.

## How to Implement Modals

### 1. Import the Modal Component

```elixir
import HexpmWeb.Components.Modal, only: [show_modal: 1, show_modal: 2]
```

### 2. Create a Button that Opens the Modal

Use `phx-click={show_modal("modal-id")}`:

```elixir
<.button phx-click={show_modal("my-modal")}>
  Open Modal
</.button>

# Or with icon button:
<.icon_button
  icon="trash"
  variant="danger"
  phx-click={show_modal("delete-modal")}
  aria-label="Delete"
/>
```

### 3. Define the Modal Component

Use `HexpmWeb.Components.Modal.modal`:

```elixir
<HexpmWeb.Components.Modal.modal id="my-modal" max_width="md">
  <:header>
    <div class="tw:flex tw:items-center tw:gap-4">
      <div class="tw:flex-shrink-0 tw:w-12 tw:h-12 tw:rounded-full tw:flex tw:items-center tw:justify-center tw:bg-red-100">
        {icon(:heroicon, "exclamation-triangle", class: "tw:w-6 tw:h-6 tw:text-red-600")}
      </div>
      <div class="tw:flex-1">
        <h2 class="tw:text-xl tw:font-semibold tw:text-grey-900">
          Confirm Action
        </h2>
      </div>
    </div>
  </:header>

  <p class="tw:text-grey-700">
    Are you sure you want to proceed?
  </p>

  <:footer>
    <.button
      type="button"
      variant="outline"
      phx-click={HexpmWeb.Components.Modal.hide_modal("my-modal")}
    >
      Cancel
    </.button>
    <.button type="button" variant="danger" onclick="document.getElementById('my-form').submit()">
      Confirm
    </.button>
  </:footer>
</HexpmWeb.Components.Modal.modal>

<%!-- Hidden form for submission --%>
<%= form_tag(~p"/my/action", [method: :post, id: "my-form"]) do %>
  <input type="hidden" name="field" value={@value} />
<% end %>
```

## Important Notes

### Modal IDs with Dynamic Data

When creating modal IDs from user data (like email addresses), sanitize them to create valid DOM IDs:

```elixir
# BAD - email contains @ and . which are invalid in DOM IDs
modal_id = "delete-email-#{@email.email}"

# GOOD - sanitize special characters
modal_id = "delete-email-#{String.replace(@email.email, ~r/[^a-zA-Z0-9]/, "-")}"
```

### Chaining Modal Actions

You can chain modals (close one, open another):

```elixir
<.button
  type="button"
  phx-click={
    HexpmWeb.Components.Modal.hide_modal("first-modal")
    |> show_modal("second-modal")
  }
>
  Open Next Modal
</.button>
```

### Form Submission from Modal

Use `onclick` with `document.getElementById('form-id').submit()`:

```elixir
# 1. Create hidden form outside modal
<%= form_tag(@action, [method: :post, id: "my-form"]) do %>
  <input type="hidden" name="field" value={@value} />
<% end %>

# 2. Submit from modal button
<.button
  type="button"
  variant="danger"
  onclick="document.getElementById('my-form').submit()"
>
  Confirm
</.button>
```

## Example: Delete with Conditional Logic

See `email_management_card.ex` for a complete example that shows:
- Different modals based on conditions (primary vs non-primary email)
- Modal chaining (cannot delete → add new email)
- Form submission with CSRF protection
- Icon button triggering modal

## Why This Works in Controller Views

The `assets/js/app.js` file initializes LiveSocket globally:

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

liveSocket.connect();
```

This means **all pages** (including controller views) have LiveSocket connected, so `phx-click` and other LiveView bindings work everywhere!
