defmodule HexWeb.Mailer do
  def send(template, title, email, assigns) do
    assigns = [layout: {HexWeb.EmailView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailView, template, assigns)
    HexWeb.Email.send(email, title, body)
  end
end
