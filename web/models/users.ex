defmodule HexWeb.Users do
  use HexWeb.Web, :crud

  def get(username_or_email, preload \\ []) do
    # Somewhat crazy hack to get this done in one query
    # Makes assumptions about how Ecto choses variable names
    Repo.one(
      from u in HexWeb.User,
      where: u.username == ^username_or_email or
             ^username_or_email in fragment("SELECT emails.email FROM emails WHERE emails.user_id = u0.id"),
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

  def add_email(user, params) do
    email = build_assoc(user, :emails)
    case Email.changeset(email, :create, params) |> Repo.insert do
      {:ok, email} ->
        user = with_emails(%{user | emails: %Ecto.Association.NotLoaded{}})
        Mailer.send_verification_email(user, email)
        {:ok, user}
      {:error, _} = error ->
        error
    end
  end

  def remove_email(user, params) do
    if email = find_email(user, params) do
      Repo.delete!(email)
      :ok
    else
      {:error, :unknown_email}
    end
  end

  def primary_email(user, params) do
    new_primary = find_email(user, params)
    old_primary = Enum.find(user.emails, &(&1.primary))

    cond do
      !new_primary ->
        {:error, :unknown_email}
      !new_primary.verified ->
        {:error, :not_verified}
      true ->
        now = Ecto.DateTime.utc(:usec)
        Repo.transaction(fn ->
          Repo.update!(change(old_primary, primary: false, updated_at: now))
          Repo.update!(change(new_primary, primary: true, updated_at: now))
        end)
        :ok
    end
  end

  def public_email(user, params) do
    new_public = find_email(user, params)
    old_public = Enum.find(user.emails, &(&1.public))

    cond do
      !new_public ->
        {:error, :unknown_email}
      !new_public.verified ->
        {:error, :not_verified}
      true ->
        now = Ecto.DateTime.utc(:usec)
        Repo.transaction(fn ->
          Repo.update!(change(old_public, public: false, updated_at: now))
          Repo.update!(change(new_public, public: true, updated_at: now))
        end)
        :ok
    end
  end

  def resend_verify_email(user, params) do
    if email = find_email(user, params) do
      Mailer.send_verification_email(user, email)
      :ok
    else
      {:error, :unknown_email}
    end
  end

  defp find_email(user, params) do
    Enum.find(user.emails, &(&1.email == params["email"]))
  end
end
