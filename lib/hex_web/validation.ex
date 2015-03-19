defmodule HexWeb.Validation do
  @doc """
  Ecto validation helpers.
  """

  import Ecto.Query, only: [from: 2]

  @doc """
  Checks if a version is valid semver.
  """
  def valid_version(_attr, version, opts \\ []) do
    allow_pre = Keyword.get(opts, :pre, true)

    case Version.parse(version) do
      {:ok, %Version{pre: pre}} when allow_pre or pre == [] ->
        nil
      {:ok, %Version{}} when not allow_pre ->
        opts[:message] || "pre release version is not allowed"
      _ ->
        opts[:message] || "invalid version"
    end
  end

  @doc """
  Checks if the fields on the given entity are unique
  by querying the database.
  """
  def unique(model, field, opts \\ []) when is_list(opts) do
    module  = model.__struct__
    repo    = Keyword.fetch!(opts, :on)
    scope   = opts[:scope] || []
    message = opts[:message] || "already taken"
    case    = Keyword.get(opts, :case_sensitive, true)

    if value = Map.fetch!(model, field) do
      query = from var in module, select: true, limit: 1

      query =
        if case do
          from var in query,
               where: fragment("lower(?) = lower(?)", field(var, ^field), ^value)
        else
          from var in query,
               where: field(var, ^field) == ^value
        end

      query =
        Enum.reduce(scope, query, fn field, query ->
          value = Map.fetch!(model, field)
          from var in query,
               where: field(var, ^field) == ^value
        end)

      if repo.all(query) == [true] do
        Map.put(%{}, field, message)
      end
    end
  end
end
