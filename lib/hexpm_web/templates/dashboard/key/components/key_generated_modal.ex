defmodule HexpmWeb.Dashboard.Key.Components.KeyGeneratedModal do
  use Phoenix.Component
  import HexpmWeb.Components.Modal
  import HexpmWeb.Components.Buttons
  import HexpmWeb.ViewIcons, only: [icon: 3]

  attr :key, :map, required: true

  def key_generated_modal(assigns) do
    # Handle both atom and string keys from session
    key_name = assigns.key[:name] || assigns.key["name"]
    key_secret = assigns.key[:user_secret] || assigns.key["user_secret"]

    # Validate required fields
    if is_nil(key_name) or is_nil(key_secret) do
      raise ArgumentError, """
      key_generated_modal requires a key with both name and user_secret.
      Received: #{inspect(assigns.key)}
      """
    end

    assigns = assign(assigns, key_name: key_name, key_secret: key_secret)

    ~H"""
    <.modal id="key-generated-modal" show={true}>
      <:header>
        <h2 class="tw:text-lg tw:font-semibold tw:text-grey-900">
          Key Generated Successfully
        </h2>
      </:header>

      <div class="tw:space-y-4">
        <p class="tw:text-sm tw:text-grey-600">
          Your key <strong class="tw:font-semibold">{@key_name}</strong> has been generated.
          Copy the secret below and store it securely.
        </p>

        <div class="tw:bg-amber-50 tw:border tw:border-amber-200 tw:rounded-lg tw:p-4">
          <div class="tw:flex tw:gap-2">
            <svg
              class="tw:w-5 tw:h-5 tw:text-amber-600 tw:flex-shrink-0"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fill-rule="evenodd"
                d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                clip-rule="evenodd"
              />
            </svg>
            <p class="tw:text-sm tw:text-amber-800">
              <strong class="tw:font-semibold">Warning:</strong>
              You won't be able to see this secret again. Make sure to copy it now.
            </p>
          </div>
        </div>

        <div class="tw:space-y-2">
          <label class="tw:block tw:text-sm tw:font-medium tw:text-grey-700">
            Key Secret
          </label>
          <div class="tw:flex tw:items-center tw:gap-2">
            <div
              id="key-secret-value"
              data-value={@key_secret}
              class="tw:flex-1 tw:px-3 tw:py-2 tw:border tw:border-grey-300 tw:rounded-lg tw:bg-grey-50 tw:text-sm tw:font-mono tw:text-grey-900 tw:break-all"
            >
              {@key_secret}
            </div>
            <button
              type="button"
              phx-hook="CopyButton"
              id="copy-key-secret"
              data-copy-target="key-secret-value"
              class="tw:flex-shrink-0 tw:p-2 tw:text-grey-600 tw:hover:text-grey-900 tw:hover:bg-grey-100 tw:rounded tw:transition-colors"
              title="Copy to clipboard"
            >
              {icon(:heroicon, "clipboard-document", class: "tw:w-5 tw:h-5")}
            </button>
          </div>
        </div>
      </div>

      <:footer>
        <div class="tw:flex tw:justify-end">
          <.button phx-click={hide_modal("key-generated-modal")} variant="primary">
            I've Saved My Key
          </.button>
        </div>
      </:footer>
    </.modal>
    """
  end
end
