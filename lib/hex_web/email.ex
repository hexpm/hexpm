defmodule HexWeb.Email do
  import HexWeb.Utils, only: [defdispatch: 2]

  @type emails :: [String.t]
  @type title  :: String.t
  @type body   :: Phoenix.HTML.Safe

  @callback send(emails, title, body) :: term

  defdispatch send(emails, title, body), to: impl

  defp impl, do: Application.get_env(:hex_web, :email_impl)
end
