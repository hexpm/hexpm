defmodule HexpmWeb.Dashboard.Key.Components.RevokeAllKeysModal do
  use Phoenix.Component
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons
  import HexpmWeb.Components.Form, only: [sudo_form: 1]

  attr :keys, :list, required: true
  attr :current_user, :map, required: true
  attr :delete_all_keys_path, :string, required: true

  def revoke_all_keys_modal(assigns) do
    ~H"""
    <.modal id="revoke-all-keys-modal" title="Revoke All Keys">
      <p class="text-sm text-grey-600 dark:text-grey-300 mb-4">
        Are you sure you want to revoke all keys?
        <strong class="font-semibold">{key_count(length(@keys))}</strong>
        will be revoked.
      </p>

      <p class="text-sm text-grey-600 dark:text-grey-300">
        This action cannot be undone. Any applications using these keys will no longer be able to authenticate.
      </p>

      <:footer>
        <div class="flex gap-3 justify-end">
          <.button phx-click={hide_modal("revoke-all-keys-modal")} variant="secondary">
            Cancel
          </.button>
          <.sudo_form
            current_user={@current_user}
            action={@delete_all_keys_path}
            method="delete"
            class="m-0"
          >
            <.button type="submit" variant="danger">
              Revoke All Keys
            </.button>
          </.sudo_form>
        </div>
      </:footer>
    </.modal>
    """
  end

  defp key_count(1), do: "1 key"
  defp key_count(count), do: "#{count} keys"
end
