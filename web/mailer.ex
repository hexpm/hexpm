defmodule HexWeb.Mailer do
  def send(template, title, emails, assigns) do
    assigns = [layout: {HexWeb.EmailView, "layout.html"}] ++ assigns
    body    = Phoenix.View.render(HexWeb.EmailView, template, assigns)

    HexWeb.Utils.task(fn ->
      fun = fn email -> HexWeb.Email.send([email], title, body) end
      HexWeb.Parallel.run(fun, emails)
    end)
  end
end
