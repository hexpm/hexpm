defmodule HexWeb.Users do
  use HexWeb.Web, :crud

  def get(username_or_email, preload \\ []) do
    Repo.one(
      from u in HexWeb.User,
      join: e in assoc(u, :emails),
      where: u.username == ^username_or_email or e.email == ^username_or_email,
      preload: ^preload
    )
  end

  def get_by_username(username) do
    Repo.get_by(User, username: username)
  end

  def with_owned_packages(user) do
    Repo.preload(user, :owned_packages)
  end

  def with_emails(user) do
    Repo.preload(user, :emails)
  end

  def add(params) do
    case User.build(params) |> Repo.insert do
      {:ok, user} ->
        Mailer.send_verification_email(user, hd(user.emails))
        {:ok, user}
      other ->
        other
    end
  end

  def update_profile(user, params) do
    User.update_profile(user, params)
    |> Repo.update
  end

  def update_password(user, params) do
    User.update_password(user, params)
    |> Repo.update
  end

  def verify_email(username, email, key) do
    user = Repo.preload(get(username), :emails)

    if email = Enum.find(user.emails, &(&1.email == email)) do
      if Email.verify?(email, key) do
        Email.verify(email)
        |> Repo.update!
        :ok
      else
        :error
      end
    else
      :error
    end
  end

  def request_reset(name) do
    user = Repo.get_by(User, username: name) || Repo.get_by(User, email: name)

    if user do
      user = user |> User.password_reset |> Repo.update! |> with_emails
      Mailer.send_password_reset_request_email(user)
      :ok
    else
      {:error, :not_found}
    end
  end

  def reset(username, key, password, revoke_all_keys?) do
    user = get(username)
    if User.reset?(user, key) do
      multi = User.reset(user, password, revoke_all_keys?)
      {:ok, _} = Repo.transaction(multi)
      user |> with_emails |> Mailer.send_password_reset_email
      :ok
    else
      :error
    end
  end
end
