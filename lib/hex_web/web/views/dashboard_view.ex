defmodule HexWeb.DashboardView do
  use HexWeb.Web, :view

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
    emails = Email.order_emails(user.emails)

    [{"Don't show a public email address", "none"}] ++
      Enum.filter_map(emails, & &1.verified, &{&1.email, &1.email})
  end

  defp public_email_value(user) do
    User.email(user, :public) || "none"
  end
end
