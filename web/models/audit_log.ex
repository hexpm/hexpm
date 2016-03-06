defmodule HexWeb.AuditLog do
  use HexWeb.Web, :model

  schema "audit_logs" do
    belongs_to :actor, User
    field :action, :string
    field :params, :map
    timestamps(updated_at: false)
  end

  def create(%HexWeb.User{id: user_id}, action, params) do
    params = extract_params(action, params)
    %HexWeb.AuditLog{actor_id: user_id, action: action, params: params}
  end

  defp extract_params("docs.publish", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("docs.revert", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("key.generate", key), do: serialize(key)
  defp extract_params("key.remove", key), do: serialize(key)
  defp extract_params("owner.add", {package, user}), do: %{package: serialize(package), user: serialize(user)}
  defp extract_params("owner.remove", {package, user}), do: %{package: serialize(package), user: serialize(user)}
  defp extract_params("release.publish", {package, release}), do: %{package: serialize(package), release: serialize(release)}
  defp extract_params("release.revert", {package, release}), do: %{package: serialize(package), release: serialize(release)}

  defp serialize(%HexWeb.Package{} = package) do
    do_serialize(package) |> Map.put(:meta, serialize(package.meta))
  end
  defp serialize(%HexWeb.Release{} = release) do
    do_serialize(release) |> Map.put(:meta, serialize(release.meta))
  end
  defp serialize(schema), do: do_serialize(schema)
  defp do_serialize(schema), do: Map.take(schema, fields(schema))

  defp fields(%HexWeb.Key{}), do: [:id, :name]
  defp fields(%HexWeb.Package{}), do: [:id, :name]
  defp fields(%HexWeb.Release{}), do: [:id, :version, :checksum, :has_docs, :package_id]
  defp fields(%HexWeb.User{}), do: [:id, :username, :email, :confirmed]
  defp fields(%HexWeb.PackageMetadata{}), do: [:contributors, :description, :licenses, :links, :maintainers]
  defp fields(%HexWeb.ReleaseMetadata{}), do: [:app, :build_tools, :elixir]
end
