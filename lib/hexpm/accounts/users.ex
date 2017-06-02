defmodule Hexpm.Accounts.Users do
  use Hexpm.Web, :context

  def get(username_or_email, preload \\ []) do
    User.get(username_or_email, preload)
    |> Repo.one
  end

  def get_by_id(id) do
    Repo.get(User, id)
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

  def add(params, [audit: audit_data]) do
    multi =
      Multi.new
      |> Multi.insert(:user, User.build(params))
      |> audit_with_user(audit_data, "user.create", fn %{user: user} -> user end)
      |> audit_with_user(audit_data, "email.add", fn %{user: %{emails: [email]}} -> email end)
      |> audit_with_user(audit_data, "email.primary", fn %{user: %{emails: [email]}} -> {nil, email} end)
      |> audit_with_user(audit_data, "email.public", fn %{user: %{emails: [email]}} -> {nil, email} end)

    case Repo.transaction(multi) do
      {:ok, %{user: %{emails: [email]} = user}} ->
        Emails.verification(user, email) |> Mailer.deliver_now_throttled
        {:ok, user}
      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def update_profile(user, params, [audit: audit_data]) do
    multi =
      Multi.new
      |> Multi.update(:user, User.update_profile(user, params))
      |> audit(audit_data, "user.update", fn %{user: user} -> user end)
      |> Multi.merge(fn %{user: user} -> public_email_multi(user, %{"email" => params["public_email"]}, [audit: audit_data]) end)

    case Repo.transaction(multi) do
      {:ok, %{user: user}} ->
        {:ok, user}
      {:error, :public_email, _, _} ->
        {:error, %Ecto.Changeset{data: user, errors: [public_email: {"unknown error", []}], valid?: false}}
    end
  end

  def update_password(user, params, [audit: audit_data]) do
    multi =
      Multi.new
      |> Multi.update(:user, User.update_password(user, params))
      |> audit(audit_data, "password.update", nil)

    case Repo.transaction(multi) do
      {:ok, %{user: user}} ->
        {:ok, user}
      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def verify_email(username, email, key) do
    with %User{emails: emails} <- get(username, :emails),
         %Email{} = email <- Enum.find(emails, &(&1.email == email)),
         true <- Email.verify?(email, key),
         {:ok, _} <- Email.verify(email) |> Repo.update do
      :ok
    else
      _ -> :error
    end
  end

  def password_reset_init(name, [audit: audit_data]) do
    if user = get(name) do
      {:ok, %{user: user}} =
        Multi.new
        |> Multi.update(:user, User.init_password_reset(user))
        |> audit(audit_data, "password.reset.init", nil)
        |> Repo.transaction

      user
      |> with_emails
      |> Emails.password_reset_request
      |> Mailer.deliver_now_throttled

      :ok
    else
      {:error, :not_found}
    end
  end

  def password_reset_finish(username, key, params, revoke_all_keys?, [audit: audit_data]) do
    user = get(username)

    if user && User.password_reset?(user, key) do
      multi =
        User.password_reset(user, params, revoke_all_keys?)
        |> audit(audit_data, "password.reset.finish", nil)

      case Repo.transaction(multi) do
        {:ok, _} ->
          :ok
        {:error, _, changeset, _} ->
          {:error, changeset}
      end
    else
      :error
    end
  end

  def add_email(user, params, [audit: audit_data]) do
    email = build_assoc(user, :emails)

    multi =
      Multi.new
      |> Multi.insert(:email, Email.changeset(email, :create, params))
      |> audit(audit_data, "email.add", fn %{email: email} -> email end)

    case Repo.transaction(multi) do
      {:ok, %{email: email}} ->
        user = with_emails(%{user | emails: %Ecto.Association.NotLoaded{}})
        Emails.verification(user, email) |> Mailer.deliver_now_throttled
        {:ok, user}
      {:error, :email, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_email(user, params, [audit: audit_data]) do
    email = find_email(user, params)

    cond do
      !email ->
        {:error, :unknown_email}
      email.primary ->
        {:error, :primary}
      true ->
        {:ok, _} =
          Multi.new
          |> Ecto.Multi.delete(:email, email)
          |> audit(audit_data, "email.add", email)
          |> Repo.transaction
        :ok
    end
  end

  def primary_email(user, params, [audit: audit_data]) do
    new_primary = find_email(user, params)
    old_primary = Enum.find(user.emails, &(&1.primary))

    cond do
      !new_primary ->
        {:error, :unknown_email}
      !new_primary.verified ->
        {:error, :not_verified}
      true ->
        {:ok, _} =
          Multi.new
          |> Multi.update(:reset, User.disable_password_reset(user))
          |> Multi.update(:old_primary, Email.toggle_primary(old_primary, false))
          |> Multi.update(:new_primary, Email.toggle_primary(new_primary, true))
          |> audit(audit_data, "email.primary", {old_primary, new_primary})
          |> Repo.transaction
        :ok
    end
  end

  def public_email(user, params, opts) do
    case Repo.transaction(public_email_multi(user, params, opts)) do
      {:ok, _} ->
        :ok
      {:error, :public_email, reason, _} ->
        {:error, reason}
    end
  end

  defp public_email_multi(_user, %{"email" => nil}, _opts) do
    Multi.new
  end

  defp public_email_multi(user, %{"email" => "none"}, [audit: audit_data]) do
    if old_public = Enum.find(user.emails, &(&1.public)) do
      Multi.new
      |> Multi.update(:old_public, Email.toggle_public(old_public, false))
      |> audit(audit_data, "email.public", {old_public, nil})
    else
      Multi.new
    end
  end

  defp public_email_multi(user, params, [audit: audit_data]) do
    new_public = find_email(user, params)
    old_public = Enum.find(user.emails, &(&1.public))

    cond do
      !new_public ->
        Multi.run(Multi.new, :public_email, fn _ -> {:error, :unknown_email} end)
      !new_public.verified ->
        Multi.run(Multi.new, :public_email, fn _ -> {:error, :not_verified} end)
      old_public && new_public.id == old_public.id ->
        Multi.new
      true ->
        multi =
          if old_public,
            do: Multi.update(Multi.new, :old_public, Email.toggle_public(old_public, false)),
          else: Multi.new

        multi
        |> Multi.update(:new_public, Email.toggle_public(new_public, true))
        |> audit(audit_data, "email.public", {old_public, new_public})
    end
  end

  def resend_verify_email(user, params) do
    email = find_email(user, params)

    cond do
      !email ->
        {:error, :unknown_email}
      email.verified ->
        {:error, :already_verified}
      true ->
        Emails.verification(user, email) |> Mailer.deliver_now_throttled
        :ok
    end
  end

  defp find_email(user, params) do
    Enum.find(user.emails, &(&1.email == params["email"]))
  end
end
