defmodule Hexpm.Accounts.Users do
  use Hexpm.Web, :context

  def get(username_or_email, preload \\ []) do
    User.get(username_or_email, preload)
    |> Repo.one()
  end

  def get_by_id(id, preload \\ []) do
    Repo.get(User, id)
    |> Repo.preload(preload)
  end

  def get_by_username(username, preload \\ []) do
    Repo.get_by(User, username: username)
    |> Repo.preload(preload)
  end

  def put_repositories(user) do
    repositories = Map.new(user.repositories, &{&1.id, &1})

    %{
      user
      | owned_packages:
          Enum.map(user.owned_packages, &%{&1 | repository: repositories[&1.repository_id]})
    }
  end

  def all_repositories(%User{repositories: repositories})
      when is_list(repositories) do
    [Repository.hexpm() | repositories]
  end

  def all_repositories(nil) do
    [Repository.hexpm()]
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

  def update_profile(user, params, audit: audit_data) do
    multi =
      Multi.new()
      |> Multi.update(:user, User.update_profile(user, params))
      |> audit(audit_data, "user.update", fn %{user: user} -> user end)
      |> Multi.merge(fn %{user: user} ->
        public_email_multi(user, %{"email" => params["public_email"]}, audit: audit_data)
      end)
      |> Multi.merge(fn %{user: user} ->
        gravatar_email_multi(user, %{"email" => params["gravatar_email"]}, audit: audit_data)
      end)

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
    with %User{emails: emails} <- get(username, :emails),
         %Email{} = email <- Enum.find(emails, &(&1.email == email)),
         true <- Email.verify?(email, key),
         {:ok, _} <- Email.verify(email) |> Repo.update() do
      :ok
    else
      _ -> :error
    end
  end

  def password_reset_init(name, audit: audit_data) do
    if user = get(name, [:emails]) do
      {:ok, %{user: user}} =
        Multi.new()
        |> Multi.update(:user, User.init_password_reset(user))
        |> audit(audit_data, "password.reset.init", nil)
        |> Repo.transaction()

      user
      |> Emails.password_reset_request()
      |> Mailer.deliver_now_throttled()

      :ok
    else
      {:error, :not_found}
    end
  end

  def password_reset_finish(username, key, params, revoke_all_keys?, audit: audit_data) do
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

  def primary_email(user, params, opts) do
    multi =
      email_flag_multi(user, params, :primary, opts)
      |> Multi.update(:reset, User.disable_password_reset(user))

    case Repo.transaction(multi) do
      {:ok, _} ->
        :ok

      {:error, :primary_email, reason, _} ->
        {:error, reason}
    end
  end

  def gravatar_email(user, params, opts) do
    case Repo.transaction(gravatar_email_multi(user, params, opts)) do
      {:ok, _} ->
        :ok

      {:error, :gravatar_email, reason, _} ->
        {:error, reason}
    end
  end

  defp gravatar_email_multi(user, %{"email" => "none"}, opts) do
    unset_email_flag_multi(user, :gravatar, opts)
  end

  defp gravatar_email_multi(user, params, opts) do
    email_flag_multi(user, params, :gravatar, opts)
  end

  def public_email(user, params, opts) do
    case Repo.transaction(public_email_multi(user, params, opts)) do
      {:ok, _} ->
        :ok

      {:error, :public_email, reason, _} ->
        {:error, reason}
    end
  end

  defp public_email_multi(user, %{"email" => "none"}, opts) do
    unset_email_flag_multi(user, :public, opts)
  end

  defp public_email_multi(user, params, opts) do
    email_flag_multi(user, params, :public, opts)
  end

  defp unset_email_flag_multi(user, flag, audit: audit_data) do
    if old_email = Enum.find(user.emails, &Map.get(&1, flag)) do
      old_email_op = String.to_atom("old_#{flag}")

      Multi.new()
      |> Multi.update(old_email_op, Email.toggle_flag(old_email, flag, false))
      |> audit(audit_data, "email.#{flag}", {old_email, nil})
    else
      Multi.new()
    end
  end

  defp email_flag_multi(_user, %{"email" => nil}, _flag, _opts) do
    Multi.new()
  end

  defp email_flag_multi(user, params, flag, audit: audit_data) do
    new_email = find_email(user, params)
    old_email = Enum.find(user.emails, &Map.get(&1, flag))

    error_op_name = String.to_atom("#{flag}_email")

    cond do
      !new_email ->
        Multi.run(Multi.new(), error_op_name, fn _ -> {:error, :unknown_email} end)

      !new_email.verified ->
        Multi.run(Multi.new(), error_op_name, fn _ -> {:error, :not_verified} end)

      old_email && new_email.id == old_email.id ->
        Multi.new()

      true ->
        multi =
          if old_email do
            old_email_op_name = String.to_atom("old_#{flag}")

            Multi.update(
              Multi.new(),
              old_email_op_name,
              Email.toggle_flag(old_email, flag, false)
            )
          else
            Multi.new()
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
        Emails.verification(user, email) |> Mailer.deliver_now_throttled()
        :ok
    end
  end

  defp find_email(user, params) do
    Enum.find(user.emails, &(&1.email == params["email"]))
  end
end
