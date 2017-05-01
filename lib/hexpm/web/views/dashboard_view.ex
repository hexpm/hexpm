defmodule Hexpm.Web.DashboardView do
  use Hexpm.Web, :view

  defp pages do
    [profile: "Profile",
     password: "Password",
     email: "Email"]
  end

  defp selected(conn, id) do
    if List.last(conn.path_info) == Atom.to_string(id) do
      "selected"
    end
  end

  defp public_email_options(user) do
    emails =
      user.emails
      |> Email.order_emails()
      |> Enum.filter(& &1.verified)
      |> Enum.map(&{&1.email, &1.email})

    [{"Don't show a public email address", "none"}] ++ emails
  end

  defp public_email_value(user) do
    User.email(user, :public) || "none"
  end
end
