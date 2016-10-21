defmodule HexWeb.AuditLog do
  use HexWeb.Web, :model

  schema "audit_logs" do
    belongs_to :actor, User
    field :user_agent, :string
    field :action, :string
    field :params, :map
    timestamps(updated_at: false)
  end

  # NOTE: user_agent should be just "WEB" when action is from the web interface

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
      Multi.insert(Multi.new, :log, build(user, user_agent, action, fun.(data)))
    end)
  end
  def audit(%Multi{} = multi, {user, user_agent}, action, params) do
    Multi.insert(multi, :log, build(user, user_agent, action, params))
  end

  def audit_many(multi, {user, user_agent}, action, list, opts \\ []) do
    fields = AuditLog.__schema__(:fields) -- [:id]
    extra = %{inserted_at: HexWeb.Utils.utc_now}
    entry = fn (element) ->
      build(user, user_agent, action, element)
      |> Map.take(fields)
      |> Map.merge(extra)
    end
    Multi.insert_all(multi, :log, AuditLog, Enum.map(list, entry), opts)
  end

  # TODO: Add emails

  defp extract_params("docs.publish", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("docs.revert", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("key.generate", key), do: serialize(key)
  defp extract_params("key.remove", key), do: serialize(key)
  defp extract_params("owner.add", {package, user}), do: %{package: serialize(package), user: serialize(user)}
  defp extract_params("owner.remove", {package, user}), do: %{package: serialize(package), user: serialize(user)}
  defp extract_params("release.publish", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("release.revert", {package, release}), do: %{package: serialize(package), release: serialize(release)}

  defp serialize(%Package{} = package) do
    do_serialize(package) |> Map.put(:meta, serialize(package.meta))
  end
  defp serialize(%Release{} = release) do
    do_serialize(release) |> Map.put(:meta, serialize(release.meta))
  end
  defp serialize(schema), do: do_serialize(schema)
  defp do_serialize(schema), do: Map.take(schema, fields(schema))

  defp fields(%Key{}), do: [:id, :name]
  defp fields(%Package{}), do: [:id, :name]
  defp fields(%Release{}), do: [:id, :version, :checksum, :has_docs, :package_id]
  defp fields(%User{}), do: [:id, :username]
  defp fields(%PackageMetadata{}), do: [:description, :licenses, :links, :maintainers, :extra]
  defp fields(%ReleaseMetadata{}), do: [:app, :build_tools, :elixir]
  defp fields(%Email{}), do: [:email, :primary, :public, :primary]
end
