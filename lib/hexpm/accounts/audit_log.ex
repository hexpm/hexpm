defmodule Hexpm.Accounts.AuditLog do
  use Hexpm.Schema

  schema "audit_logs" do
    field :user_agent, :string
    field :remote_ip, :string
    field :action, :string
    field :params, :map

    belongs_to :user, User
    belongs_to :organization, Organization
    belongs_to :key, Key

    timestamps(updated_at: false)
  end

  def build(%{user: nil} = audit_data, action, params)
      when action in ~w(password.reset.init password.reset.finish) do
    params = extract_params(action, params)

    %AuditLog{
      user_id: nil,
      organization_id: nil,
      key: audit_data.key,
      user_agent: truncate_codepoints(audit_data.user_agent, 255),
      remote_ip: audit_data.remote_ip,
      action: action,
      params: params
    }
  end

  def build(%{user: %User{id: user_id}} = audit_data, "organization.create", organization) do
    params = extract_params("organization.create", organization)

    %AuditLog{
      user_id: user_id,
      organization_id: organization.id,
      key: audit_data.key,
      user_agent: truncate_codepoints(audit_data.user_agent, 255),
      remote_ip: audit_data.remote_ip,
      action: "organization.create",
      params: params
    }
  end

  def build(%{user: %User{id: user_id}} = audit_data, action, params) do
    params = extract_params(action, params)

    %AuditLog{
      user_id: user_id,
      organization_id: params[:organization][:id] || params[:package][:organization_id],
      key: audit_data.key,
      user_agent: truncate_codepoints(audit_data.user_agent, 255),
      remote_ip: audit_data.remote_ip,
      action: action,
      params: params
    }
  end

  def build(%{user: %Organization{id: organization_id}} = audit_data, action, params) do
    params = extract_params(action, params)

    %AuditLog{
      user_id: nil,
      organization_id: organization_id,
      key: audit_data.key,
      user_agent: truncate_codepoints(audit_data.user_agent, 255),
      remote_ip: audit_data.remote_ip,
      action: action,
      params: params
    }
  end

  def audit(audit_data, action, params) do
    build(audit_data, action, params)
  end

  def audit(multi, nil, _action, _fun) do
    multi
  end

  def audit(multi, audit_data, action, fun) when is_function(fun, 1) do
    Multi.merge(multi, fn data ->
      Multi.insert(
        Multi.new(),
        multi_key(multi, action),
        build(audit_data, action, fun.(data))
      )
    end)
  end

  def audit(multi, audit_data, action, params) do
    Multi.insert(
      multi,
      multi_key(multi, action),
      build(audit_data, action, params)
    )
  end

  def audit_many(multi, who, action, list, opts \\ [])

  def audit_many(multi, nil, _action, _list, _opts) do
    multi
  end

  def audit_many(multi, audit_data, action, list, opts) do
    fields = AuditLog.__schema__(:fields) -- [:id]
    extra = %{inserted_at: DateTime.utc_now()}

    entries =
      Enum.map(list, fn entry ->
        build(audit_data, action, entry)
        |> Map.take(fields)
        |> Map.merge(extra)
      end)

    Multi.insert_all(multi, multi_key(multi, action), AuditLog, entries, opts)
  end

  def audit_with_user(multi, nil, _action, _fun) do
    multi
  end

  def audit_with_user(multi, %{user: nil} = audit_data, action, fun) do
    Multi.insert(multi, multi_key(multi, action), fn %{user: user} = data ->
      build(%{audit_data | user: user}, action, fun.(data))
    end)
  end

  defp extract_params("docs.publish", {package, release}),
    do: %{package: serialize(package), release: serialize(release)}

  defp extract_params("docs.revert", {package, release}),
    do: %{package: serialize(package), release: serialize(release)}

  defp extract_params("key.generate", key), do: serialize(key)
  defp extract_params("key.remove", key), do: serialize(key)

  defp extract_params("owner.add", {package, level, user}),
    do: %{package: serialize(package), level: level, user: serialize(user)}

  defp extract_params("owner.transfer", {package, level, user}),
    do: %{package: serialize(package), level: level, user: serialize(user)}

  defp extract_params("owner.remove", {package, level, user}),
    do: %{package: serialize(package), level: level, user: serialize(user)}

  defp extract_params("release.publish", {package, release}),
    do: %{package: serialize(package), release: serialize(release)}

  defp extract_params("release.revert", {package, release}),
    do: %{package: serialize(package), release: serialize(release)}

  defp extract_params("release.retire", {package, release}),
    do: %{package: serialize(package), release: serialize(release)}

  defp extract_params("release.unretire", {package, release}),
    do: %{package: serialize(package), release: serialize(release)}

  defp extract_params("email.add", {organization, email}),
    do: Map.merge(%{organization: serialize(organization)}, serialize(email))

  defp extract_params("email.add", email), do: serialize(email)

  defp extract_params("email.remove", {organization, email}),
    do: Map.merge(%{organization: serialize(organization)}, serialize(email))

  defp extract_params("email.remove", email), do: serialize(email)

  defp extract_params("email.primary", {old_email, new_email}),
    do: %{old_email: serialize(old_email), new_email: serialize(new_email)}

  defp extract_params("email.public", {organization, {old_email, new_email}}),
    do: %{
      organization: serialize(organization),
      old_email: serialize(old_email),
      new_email: serialize(new_email)
    }

  defp extract_params("email.public", {old_email, new_email}),
    do: %{old_email: serialize(old_email), new_email: serialize(new_email)}

  defp extract_params("email.gravatar", {organization, {old_email, new_email}}),
    do: %{
      organization: serialize(organization),
      old_email: serialize(old_email),
      new_email: serialize(new_email)
    }

  defp extract_params("email.gravatar", {old_email, new_email}),
    do: %{old_email: serialize(old_email), new_email: serialize(new_email)}

  defp extract_params("user.create", user), do: serialize(user)
  defp extract_params("user.update", user), do: serialize(user)
  defp extract_params("security.update", user), do: serialize(user)
  defp extract_params("security.rotate_recovery_codes", user), do: serialize(user)
  defp extract_params("organization.create", organization), do: serialize(organization)

  defp extract_params("organization.member.add", {organization, user}),
    do: %{organization: serialize(organization), user: serialize(user)}

  defp extract_params("organization.member.remove", {organization, user}),
    do: %{organization: serialize(organization), user: serialize(user)}

  defp extract_params("organization.member.role", {organization, user, role}),
    do: %{organization: serialize(organization), user: serialize(user), role: role}

  defp extract_params("password.reset.init", nil), do: %{}
  defp extract_params("password.reset.finish", nil), do: %{}
  defp extract_params("password.update", nil), do: %{}

  defp extract_params("billing.checkout", {organization, data}),
    do: %{
      organization: serialize(organization),
      payment_source: data[:payment_source]
    }

  defp extract_params("billing.cancel", {organization, _params}),
    do: %{organization: serialize(organization)}

  defp extract_params("billing.create", {organization, params}),
    do: %{
      organization: serialize(organization),
      email: params["email"],
      person: params["person"],
      company: params["company"],
      token: params["token"],
      quantity: params["quantity"]
    }

  defp extract_params("billing.update", {organization, params}),
    do: %{
      organization: serialize(organization),
      email: params["email"],
      person: params["person"],
      company: params["company"],
      token: params["token"],
      quantity: params["quantity"]
    }

  defp extract_params("billing.change_plan", {organization, params}),
    do: %{
      organization: serialize(organization),
      plan_id: params["plan_id"]
    }

  defp extract_params("billing.pay_invoice", {organization, invoice_id}),
    do: %{
      organization: serialize(organization),
      invoice_id: invoice_id
    }

  defp serialize(%Key{} = key) do
    key
    |> do_serialize()
    |> Map.put(:permissions, Enum.map(key.permissions, &serialize/1))
    |> Map.put(:user, serialize(key.user))
    |> Map.put(:organization, serialize(key.organization))
  end

  defp serialize(%Package{} = package) do
    package
    |> do_serialize()
    |> Map.put(:meta, serialize(package.meta))
  end

  defp serialize(%Release{} = release) do
    release
    |> do_serialize()
    |> Map.put(:meta, serialize(release.meta))
    |> Map.put(:retirement, serialize(release.retirement))
  end

  defp serialize(%User{} = user) do
    user
    |> do_serialize()
    |> Map.put(:handles, serialize(user.handles))
  end

  defp serialize(nil), do: nil
  defp serialize(schema), do: do_serialize(schema)

  defp do_serialize(schema), do: Map.take(schema, fields(schema))

  defp fields(%Email{}), do: [:email, :primary, :public, :primary, :gravatar]
  defp fields(%Key{}), do: [:id, :name]
  defp fields(%KeyPermission{}), do: [:resource, :domain]
  defp fields(%Package{}), do: [:id, :name, :organization_id]
  defp fields(%PackageMetadata{}), do: [:description, :licenses, :links, :maintainers, :extra]
  defp fields(%Release{}), do: [:id, :version, :checksum, :has_docs, :package_id]
  defp fields(%ReleaseMetadata{}), do: [:app, :build_tools, :elixir]
  defp fields(%ReleaseRetirement{}), do: [:status, :message]
  defp fields(%Organization{}), do: [:id, :name, :public, :active, :billing_active]
  defp fields(%User{}), do: [:id, :username]
  defp fields(%UserHandles{}), do: [:github, :twitter, :freenode]

  defp multi_key(multi, action) do
    :"log.#{action}.#{length(Multi.to_list(multi))}"
  end

  def count_by(schema) do
    from(l in all_by(schema), select: count())
  end

  def all_by(%Hexpm.Repository.Package{} = package) do
    from(l in AuditLog,
      where: fragment("(? -> 'package' ->> 'id')::integer", l.params) == ^package.id
    )
  end

  def all_by(%Hexpm.Accounts.Organization{} = organization) do
    Ecto.assoc(organization, :audit_logs)
  end

  def all_by(%Hexpm.Accounts.User{} = user) do
    Ecto.assoc(user, :audit_logs)
  end

  def newest_first(query) do
    Ecto.Query.order_by(query, desc: :inserted_at)
  end

  defp truncate_codepoints(string, length) do
    string
    |> String.to_charlist()
    |> Enum.take(length)
    |> List.to_string()
  end
end
