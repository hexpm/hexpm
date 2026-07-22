defmodule Hexpm.Emails.Delivery do
  @callback deliver!(Swoosh.Email.t()) :: term()

  def impl do
    Application.get_env(:hexpm, :sso_mailer_impl, Hexpm.Emails.Mailer)
  end
end
