defmodule HexWeb.Mailer do
  def send(template, title, emails, assigns) do
    assigns = [layout: {HexWeb.EmailView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailView, template, assigns)

    Enum.map(emails, fn email ->
      HexWeb.Email.send([email], title, body)
    end)
  end
end
