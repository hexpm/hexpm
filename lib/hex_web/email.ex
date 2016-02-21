defmodule HexWeb.Email do
  import HexWeb.Utils, only: [defdispatch: 2]

  @type email :: String.t
  @type title :: String.t
  @type body  :: Phoenix.HTML.Safe

  @callback send(email, title, body) :: term

  defdispatch send(email, title, body), to: impl

  defp impl, do: Application.get_env(:hex_web, :email_impl)
end
