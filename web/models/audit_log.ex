defmodule HexWeb.AuditLog do
  use HexWeb.Web, :model

  schema "audit_logs" do
    belongs_to :actor, User
    field :user_agent, :string
    field :action, :string
    field :params, :map
    timestamps(updated_at: false)
  end

  def build(nil, user_agent, action, nil)
  when action in ~w(password.reset.init password.reset.finish) do
    %AuditLog{
      actor_id: nil,
      user_agent: user_agent,
      action: action,
      params: %{}
    }
  end
  def build(%User{id: user_id}, user_agent, action, params) do
    %AuditLog{
      actor_id: user_id,
      user_agent: user_agent,
      action: action,
      params: extract_params(action, params)
    }
  end

  def audit(%Multi{} = multi, {user, user_agent}, action, fun) when is_function(fun, 1) do
    Multi.merge(multi, fn data ->
      Multi.insert(Multi.new, multi_key(action), build(user, user_agent, action, fun.(data)))
    end)
  end
  def audit(%Multi{} = multi, {user, user_agent}, action, params) do
    Multi.insert(multi, multi_key(action), build(user, user_agent, action, params))
  end

  def audit_many(multi, {user, user_agent}, action, list, opts \\ []) do
    fields = AuditLog.__schema__(:fields) -- [:id]
    extra = %{inserted_at: HexWeb.Utils.utc_now}
    entry = fn (element) ->
      build(user, user_agent, action, element)
      |> Map.take(fields)
      |> Map.merge(extra)
    end
    Multi.insert_all(multi, multi_key(action), AuditLog, Enum.map(list, entry), opts)
  end

  def audit_with_user(multi, {nil, user_agent}, action, fun) do
    Multi.merge(multi, fn %{user: user} = data ->
      Multi.insert(Multi.new, multi_key(action), build(user, user_agent, action, fun.(data)))
    end)
  end

  defp extract_params("docs.publish", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("docs.revert", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("key.generate", key), do: serialize(key)
  defp extract_params("key.remove", key), do: serialize(key)
  defp extract_params("owner.add", {package, user}), do: %{package: serialize(package), user: serialize(user)}
  defp extract_params("owner.remove", {package, user}), do: %{package: serialize(package), user: serialize(user)}
  defp extract_params("release.publish", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("release.revert", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("email.add", email), do: serialize(email)
  defp extract_params("email.remove", email), do: serialize(email)
  defp extract_params("email.primary", {old_email, new_email}), do: %{old_email: serialize(old_email), new_email: serialize(new_email)}
  defp extract_params("email.public", {old_email, new_email}), do: %{old_email: serialize(old_email), new_email: serialize(new_email)}
  defp extract_params("user.create", user), do: serialize(user)
  defp extract_params("user.update", user), do: serialize(user)
  defp extract_params("password.reset.init", nil), do: %{}
  defp extract_params("password.reset.finish", nil), do: %{}
  defp extract_params("password.update", nil), do: %{}

  defp serialize(%Package{} = package),
    do: package |> do_serialize |> Map.put(:meta, serialize(package.meta))
  defp serialize(%Release{} = release),
    do: release |> do_serialize |> Map.put(:meta, serialize(release.meta))
  defp serialize(%User{} = user),
    do: user |> do_serialize |> Map.put(:handles, serialize(user.handles))
  defp serialize(nil),
    do: nil
  defp serialize(schema),
    do: do_serialize(schema)

  defp do_serialize(schema), do: Map.take(schema, fields(schema))

  defp fields(%Key{}), do: [:id, :name]
  defp fields(%Package{}), do: [:id, :name]
  defp fields(%Release{}), do: [:id, :version, :checksum, :has_docs, :package_id]
  defp fields(%User{}), do: [:id, :username]
  defp fields(%PackageMetadata{}), do: [:description, :licenses, :links, :maintainers, :extra]
  defp fields(%ReleaseMetadata{}), do: [:app, :build_tools, :elixir]
  defp fields(%Email{}), do: [:email, :primary, :public, :primary]
  defp fields(%UserHandles{}), do: [:github, :twitter, :freenode]

  defp multi_key(action), do: :"log.#{action}"
end
