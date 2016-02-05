defmodule HexWeb.Mailer do
  def send(template, title, email, assigns) do
    mailer  = Application.get_env(:hex_web, :email)
    assigns = [layout: {HexWeb.EmailView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailView, template, assigns)
    mailer.send(email, title, body)
  end
end
