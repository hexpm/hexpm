defmodule HexpmWeb.Dashboard.Key.Components.RevokeKeyModal do
  use Phoenix.Component
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons

  attr :key, :map, required: true
  attr :csrf_token, :string, required: true
  attr :delete_key_path, :string, required: true

  def revoke_key_modal(assigns) do
    modal_id = "revoke-key-#{assigns.key.id}"
    assigns = assign(assigns, :modal_id, modal_id)

    ~H"""
    <.modal id={@modal_id}>
      <:header>
        <h2 class="tw:text-lg tw:font-semibold tw:text-grey-900">
          Revoke Key
        </h2>
      </:header>

      <p class="tw:text-sm tw:text-grey-600 tw:mb-4">
        Are you sure you want to revoke the key <strong class="tw:font-semibold">{@key.name}</strong>?
      </p>

      <p class="tw:text-sm tw:text-grey-600">
        This action cannot be undone. Any applications using this key will no longer be able to authenticate.
      </p>

      <:footer>
        <div class="tw:flex tw:gap-3 tw:justify-end">
          <.button phx-click={hide_modal(@modal_id)} variant="secondary">
            Cancel
          </.button>
          <form action={@delete_key_path} method="post" class="tw:m-0">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <input type="hidden" name="name" value={@key.name} />
            <.button type="submit" variant="danger">
              Revoke Key
            </.button>
          </form>
        </div>
      </:footer>
    </.modal>
    """
  end
end
