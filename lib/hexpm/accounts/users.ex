defmodule Hexpm.Accounts.Users do
  use HexpmWeb, :context

  def get(username_or_email, preload \\ []) do
    User.get(String.downcase(username_or_email), preload)
    |> Repo.one()
  end

  def public_get(username_or_email, preload \\ []) do
    User.public_get(String.downcase(username_or_email), preload)
    |> Repo.one()
  end

  def get_by_id(id, preload \\ []) do
    Repo.get(User, id)
    |> Repo.preload(preload)
  end

  def get_by_username(username, preload \\ []) do
    Repo.get_by(User, username: String.downcase(username))
    |> Repo.preload(preload)
  end

  def get_email(email, preload \\ []) do
    Repo.get_by(Email, email: String.downcase(email))
    |> Repo.preload(preload)
  end

  def put_organizations(user) do
    repositories = Map.new(user.organizations, &{&1.repository.id, &1.repository})

    owned_packages =
      Enum.map(user.owned_packages, fn package ->
        %{package | repository: repositories[package.repository_id]}
      end)

    %{user | owned_packages: owned_packages}
  end

  def all_organizations(%User{organizations: organizations}) when is_list(organizations) do
    [Organization.hexpm() | organizations]
  end

  def all_organizations(nil) do
    [Organization.hexpm()]
  end

  def add(params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.insert(:user, User.build(params))
      |> audit_with_user(audit_data, "user.create", fn %{user: user} -> user end)
      |> audit_with_user(audit_data, "email.add", fn %{user: %{emails: [email]}} -> email end)
      |> audit_with_user(audit_data, "email.primary", fn %{user: %{emails: [email]}} ->
        {nil, email}
      end)
      |> audit_with_user(audit_data, "email.public", fn %{user: %{emails: [email]}} ->
        {nil, email}
      end)

    case Repo.transaction(multi) do
      {:ok, %{user: %{emails: [email]} = user}} ->
        Emails.verification(user, email)
        |> Mailer.deliver_now_throttled()

        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def email_verification(%User{organization_id: id}, email) when not is_nil(id) do
    email
  end

  def email_verification(user, email) do
    email =
      Email.verification(email)
      |> Repo.update!()

    Emails.verification(user, email)
    |> Mailer.deliver_now_throttled()

    email
  end

  def update_profile(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot update profile of organizations")
  end

  def update_profile(user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.update(:user, User.update_profile(user, params))
      |> audit(audit_data, "user.update", fn %{user: user} -> user end)
      |> public_email_multi(user, %{"email" => params["public_email"]}, audit: audit_data)
      |> gravatar_email_multi(user, %{"email" => params["gravatar_email"]}, audit: audit_data)

    case Repo.transaction(multi) do
      {:ok, %{user: user}} ->
        {:ok, user}

      {:error, :public_email, _, _} ->
        {:error,
         %Ecto.Changeset{data: user, errors: [public_email: {"unknown error", []}], valid?: false}}

      {:error, :gravatar_email, _, _} ->
        {:error,
         %Ecto.Changeset{
           data: user,
           errors: [gravatar_email: {"unknown error", []}],
           valid?: false
         }}
    end
  end

  def update_password(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot change password of organizations")
  end

  def update_password(user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.update(:user, User.update_password(user, params))
      |> audit(audit_data, "password.update", nil)

    case Repo.transaction(multi) do
      {:ok, %{user: user}} ->
        user
        |> Emails.password_changed()
        |> Mailer.deliver_now_throttled()

        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def verify_email(username, email, key) do
    with %User{organization_id: nil, emails: emails} <- get(username, :emails),
         %Email{} = email <- Enum.find(emails, &(&1.email == email)),
         true <- Email.verify?(email, key),
         {:ok, _} <- Email.verify(email) |> Repo.update() do
      :ok
    else
      _ -> :error
    end
  end

  def password_reset_init(name, audit: audit_data) do
    user = get(name, [:emails])

    if user && !User.organization?(user) do
      changeset = PasswordReset.changeset(build_assoc(user, :password_resets), user)

      {:ok, %{reset: reset}} =
        Multi.new()
        |> Multi.insert(:reset, changeset)
        |> audit(audit_data, "password.reset.init", nil)
        |> Repo.transaction()

      Emails.password_reset_request(user, reset)
      |> Mailer.deliver_now_throttled()

      :ok
    else
      {:error, :not_found}
    end
  end

  def password_reset_finish(username, key, params, revoke_all_keys?, audit: audit_data) do
    user = get(username, [:emails, :password_resets])

    if user && !User.organization?(user) && User.can_reset_password?(user, key) do
      multi =
        password_reset(user, params, revoke_all_keys?)
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

  defp password_reset(user, params, revoke_all_keys) do
    multi =
      Multi.new()
      |> Multi.update(:password, User.update_password_no_check(user, params))
      |> Multi.delete_all(:reset, assoc(user, :password_resets))
      |> Multi.delete_all(:reset_sessions, Session.by_user(user))

    if revoke_all_keys,
      do: Multi.update_all(multi, :keys, Key.revoke_all(user), []),
      else: multi
  end

  def add_email(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot add email to organizations")
  end

  def add_email(user, params, audit: audit_data) do
    email = build_assoc(user, :emails)

    multi =
      Multi.new()
      |> Multi.insert(:email, Email.changeset(email, :create, params))
      |> audit(audit_data, "email.add", fn %{email: email} -> email end)

    case Repo.transaction(multi) do
      {:ok, %{email: email}} ->
        user = Repo.preload(user, :emails, force: true)

        Emails.verification(user, email)
        |> Mailer.deliver_now_throttled()

        {:ok, user}

      {:error, :email, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_email(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot remove email of organizations")
  end

  def remove_email(user, params, audit: audit_data) do
    email = find_email(user, params)

    cond do
      !email ->
        {:error, :unknown_email}

      email.primary ->
        {:error, :primary}

      true ->
        {:ok, _} =
          Multi.new()
          |> Ecto.Multi.delete(:email, email)
          |> audit(audit_data, "email.add", email)
          |> Repo.transaction()

        :ok
    end
  end

  def primary_email(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot set email of organizations")
  end

  def primary_email(user, params, opts) do
    multi =
      Multi.new()
      |> email_flag_multi(user, params, :primary, opts)
      |> Multi.delete_all(:reset, assoc(user, :password_resets))

    case Repo.transaction(multi) do
      {:ok, _} -> :ok
      {:error, :primary_email, reason, _} -> {:error, reason}
    end
  end

  def gravatar_email(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot set email of organizations")
  end

  def gravatar_email(user, params, opts) do
    multi = gravatar_email_multi(Multi.new(), user, params, opts)

    case Repo.transaction(multi) do
      {:ok, _} -> :ok
      {:error, :gravatar_email, reason, _} -> {:error, reason}
    end
  end

  defp gravatar_email_multi(multi, user, %{"email" => "none"}, opts) do
    unset_email_flag_multi(multi, user, :gravatar, opts)
  end

  defp gravatar_email_multi(multi, user, params, opts) do
    email_flag_multi(multi, user, params, :gravatar, opts)
  end

  def public_email(%User{organization_id: id} = user, _params, _opts) when not is_nil(id) do
    organization_error(user, "cannot set email of organizations")
  end

  def public_email(user, params, opts) do
    multi = public_email_multi(Multi.new(), user, params, opts)

    case Repo.transaction(multi) do
      {:ok, _} -> :ok
      {:error, :public_email, reason, _} -> {:error, reason}
    end
  end

  defp public_email_multi(multi, user, %{"email" => "none"}, opts) do
    unset_email_flag_multi(multi, user, :public, opts)
  end

  defp public_email_multi(multi, user, params, opts) do
    email_flag_multi(multi, user, params, :public, opts)
  end

  defp unset_email_flag_multi(multi, user, flag, audit: audit_data) do
    if old_email = Enum.find(user.emails, &Map.get(&1, flag)) do
      old_email_op = String.to_atom("old_#{flag}")

      multi
      |> Multi.update(old_email_op, Email.toggle_flag(old_email, flag, false))
      |> audit(audit_data, "email.#{flag}", {old_email, nil})
    else
      multi
    end
  end

  defp email_flag_multi(multi, _user, %{"email" => nil}, _flag, _opts) do
    multi
  end

  defp email_flag_multi(multi, user, params, flag, audit: audit_data) do
    new_email = find_email(user, params)
    old_email = Enum.find(user.emails, &Map.get(&1, flag))
    error_op_name = String.to_atom("#{flag}_email")

    cond do
      !new_email ->
        Multi.error(multi, error_op_name, :unknown_email)

      !new_email.verified ->
        Multi.error(multi, error_op_name, :not_verified)

      old_email && new_email.id == old_email.id ->
        multi

      true ->
        multi =
          if old_email do
            old_email_op_name = String.to_atom("old_#{flag}")
            toggle_changeset = Email.toggle_flag(old_email, flag, false)
            Multi.update(multi, old_email_op_name, toggle_changeset)
          else
            multi
          end

        new_email_op_name = String.to_atom("new_#{flag}")

        multi
        |> Multi.update(new_email_op_name, Email.toggle_flag(new_email, flag, true))
        |> audit(audit_data, "email.#{flag}", {old_email, new_email})
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
        Emails.verification(user, email)
        |> Mailer.deliver_now_throttled()

        :ok
    end
  end

  defp find_email(user, params) do
    Enum.find(user.emails, &(&1.email == params["email"]))
  end

  defp organization_error(user, message) do
    {:error,
     %Ecto.Changeset{
       data: user,
       errors: [organization: {message, []}],
       valid?: false
     }}
  end
end
