defmodule Hexpm.Web.DashboardView do
  use Hexpm.Web, :view

  defp account_settings() do
    [
      profile: "Profile",
      password: "Password",
      email: "Email"
    ]
  end

  defp selected_setting(conn, id) do
    if Enum.take(conn.path_info, -2) == ["dashboard", Atom.to_string(id)] do
      "selected"
    end
  end

  defp selected_repository(conn, name) do
    if Enum.take(conn.path_info, -2) == ["repos", name] do
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

  def gravatar_email_options(user) do
    emails =
      user.emails
      |> Enum.filter(& &1.verified)
      |> Enum.map(&{&1.email, &1.email})

    [{"Don't show an avatar", "none"}] ++ emails
  end

  def gravatar_email_value(user) do
    User.email(user, :gravatar) || "none"
  end

  defp repository_roles_selector() do
    Enum.map(repository_roles(), fn {name, id, _title} ->
      {name, id}
    end)
  end

  defp repository_roles() do
    [
      {"Admin", "admin", "This role has full control of the repository"},
      {"Write", "write", "This role has package owner access to all repository packages"},
      {"Read", "read", "This role can fetch all repository packages"}
    ]
  end

  defp repository_role(id) do
    Enum.find_value(repository_roles(), fn {name, repository_id, _title} ->
      if id == repository_id do
        name
      end
    end)
  end
end
