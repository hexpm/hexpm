defmodule HexWeb.Users do
  use HexWeb.Web, :crud

  def with_owned_packages(user) do
    Repo.preload(user, :owned_packages)
  end

  def add(params) do
    recreate_unconfirmed_user(params["username"])

    case User.build(params) |> Repo.insert do
      {:ok, user} ->
        send_confirmation_request_email(user)
        {:ok, user}

      other ->
        other
    end
  end

  defp recreate_unconfirmed_user(username) do
    if (user = Repo.get_by(User, username: username)) && !user.confirmed do
      # Unconfirmed users only have the key creation in the audits log
      # That key will be deleted when the user is deleted
      Repo.delete_all(assoc(user, :audit_logs))
      Repo.delete!(user)
    end
  end

  def reset(name) do
    user = Repo.get_by(User, username: name) ||
             Repo.get_by(User, email: name)

    if user do
      user = User.password_reset(user) |> Repo.update!
      send_password_reset_request_email(user)
      :ok
    else
      {:error, :not_found}
    end
  end

  defp send_confirmation_request_email(user) do
    HexWeb.Mailer.send(
      "confirmation_request.html",
      "Hex.pm - Account confirmation",
      [user.email],
      username: user.username,
      key: user.confirmation_key)
  end

  def send_password_reset_request_email(user) do
    HexWeb.Mailer.send(
      "password_reset_request.html",
      "Hex.pm - Password reset request",
      [user.email],
      username: user.username,
      key: user.reset_key)
  end
end
