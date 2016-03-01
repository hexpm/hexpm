defmodule HexWeb.Mailer do
  def send(template, title, emails, assigns) do
    assigns = [layout: {HexWeb.EmailView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailView, template, assigns)
    HexWeb.Email.send(emails, title, body)
  end
end
