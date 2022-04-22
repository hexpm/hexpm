defmodule Hexpm.Accounts.Users do
  use Hexpm.Context

  alias Hexpm.Accounts.{RecoveryCode, TFA}

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

  def get_by_role(role, preload \\ []) do
    User.get_by_role(String.downcase(role))
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def get_email(email, preload \\ []) do
    Repo.get_by(Email, email: String.downcase(email))
    |> Repo.preload(preload)
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
        |> Mailer.deliver_later!()

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
    |> Mailer.deliver_later!()

    email
  end

  def update_profile(%User{organization_id: id} = user, params, audit: audit_data)
      when not is_nil(id) do
    multi =
      Multi.new()
      |> Multi.update(:user, User.update_profile(user, params))
      |> audit(audit_data, "user.update", fn %{user: user} -> user end)
      |> insert_or_update_or_delete_email_multi(user, :public, params["public_email"],
        audit: audit_data
      )
      |> insert_or_update_or_delete_email_multi(user, :gravatar, params["gravatar_email"],
        audit: audit_data
      )

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
        |> Mailer.deliver_later!()

        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def tfa_enable(user, audit: audit_data) do
    secret = Hexpm.Accounts.TFA.generate_secret()
    codes = Hexpm.Accounts.RecoveryCode.generate_set()

    multi =
      Multi.new()
      |> Multi.update(
        :user,
        User.update_tfa(user, %{tfa_enabled: true, secret: secret, recovery_codes: codes})
      )
      |> audit(audit_data, "security.update", fn %{user: user} -> user end)

    {:ok, _} = Repo.transaction(multi)
  end

  def tfa_disable(user, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.update(
        :user,
        User.update_tfa(user, %{tfa_enabled: false, secret: nil, recovery_codes: []})
      )
      |> audit(audit_data, "security.update", fn %{user: user} -> user end)

    {:ok, %{user: user}} = Repo.transaction(multi)
    user
  end

  def tfa_enable_app(user, verification_code, audit: audit_data) do
    if TFA.token_valid?(user.tfa.secret, verification_code) do
      multi =
        Multi.new()
        |> Multi.update(:user, User.update_tfa(user, %{app_enabled: true}))
        |> audit(audit_data, "security.update", fn %{user: user} -> user end)

      {:ok, %{user: user}} = Repo.transaction(multi)
      {:ok, user}
    else
      :error
    end
  end

  def tfa_disable_app(user, audit: audit_data) do
    secret = Hexpm.Accounts.TFA.generate_secret()

    multi =
      Multi.new()
      |> Multi.update(:user, User.update_tfa(user, %{app_enabled: false, secret: secret}))
      |> audit(audit_data, "security.update", fn %{user: user} -> user end)

    {:ok, %{user: user}} = Repo.transaction(multi)
    user
  end

  def tfa_rotate_recovery_codes(user, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.update(:user, User.rotate_recovery_codes(user))
      |> audit(audit_data, "security.rotate_recovery_codes", fn %{user: user} -> user end)

    {:ok, %{user: user}} = Repo.transaction(multi)
    user
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
      |> Mailer.deliver_later!()

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
        |> Mailer.deliver_later!()

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
          |> audit(audit_data, "email.remove", email)
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

  def insert_or_update_or_delete_email_multi(multi, _user, _flag, nil, _params) do
    multi
  end

  def insert_or_update_or_delete_email_multi(multi, user, flag, "", audit: audit_data) do
    user = Repo.preload(user, :organization)

    if old_email = Enum.find(user.emails, &Map.get(&1, flag)) do
      email_op = String.to_atom("#{flag}_email")

      multi
      |> Multi.delete(email_op, old_email)
      |> audit(audit_data, "email.remove", {user.organization, old_email})
    else
      multi
    end
  end

  def insert_or_update_or_delete_email_multi(multi, user, flag, email_address, audit: audit_data) do
    email_op = String.to_atom("#{flag}_email")
    user = Repo.preload(user, :organization)

    if old_email = Enum.find(user.emails, &Map.get(&1, flag)) do
      multi
      |> Multi.update(email_op, Email.update_email(old_email, email_address))
      |> audit(audit_data, "email.#{flag}", fn %{^email_op => new_email} ->
        {user.organization, {old_email, new_email}}
      end)
    else
      multi
      |> Multi.insert(
        email_op,
        Email.changeset(
          build_assoc(user, :emails),
          :create_for_org,
          %{:email => email_address, flag => true},
          false
        )
      )
      |> audit(audit_data, "email.add", fn %{^email_op => email} -> {user.organization, email} end)
      |> audit(audit_data, "email.#{flag}", fn %{^email_op => email} ->
        {user.organization, {nil, email}}
      end)
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
        |> Mailer.deliver_later!()

        :ok
    end
  end

  def tfa_recover(%User{} = user, code_str) do
    case RecoveryCode.verify(user.tfa.recovery_codes, code_str) do
      {:ok, %RecoveryCode{} = code} ->
        user =
          user
          |> User.recovery_code_used(code)
          |> Repo.update!()

        {:ok, user}

      err ->
        err
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
