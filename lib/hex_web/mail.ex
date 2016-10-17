defmodule HexWeb.Mail do
  @type emails :: [String.t]
  @type title  :: String.t
  @type body   :: Phoenix.HTML.Safe

  @callback send(emails, title, body) :: term

  @email_impl Application.get_env(:hex_web, :email_impl)

  defdelegate send(emails, title, body), to: @email_impl
end
