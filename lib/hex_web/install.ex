defmodule HexWeb.Install do
  use Ecto.Model

  schema "installs" do
    field :hex, :string
    field :elixirs, {:array, :string}
  end

  def all do
    from(i in HexWeb.Install, order_by: [asc: i.id])
    |> HexWeb.Repo.all
  end

  def latest(current) do
    case Version.parse(current) do
      {:ok, current} ->
        installs =
          Enum.filter(all(), fn %HexWeb.Install{elixirs: elixirs} ->
            Enum.any?(elixirs, &Version.compare(&1, current) != :gt)
          end)

        elixir =
          if install = List.last(installs) do
            install.elixirs
            |> Enum.filter(&(Version.compare(&1, current) != :gt))
            |> List.last
          end

        if elixir do
          {:ok, install.hex, elixir}
        else
          :error
        end

      :error ->
        :error
    end
  end

  def create(hex, elixirs) do
    {:ok, %HexWeb.Install{hex: hex, elixirs: elixirs}
          |> HexWeb.Repo.insert!}
  end
end
