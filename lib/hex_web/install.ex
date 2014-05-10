defmodule HexWeb.Install do
  use Ecto.Model

  queryable "installs" do
    field :hex, :string
    field :elixir, :string
  end

  def all do
    HexWeb.Repo.all(HexWeb.Install)
  end

  def latest(current) do
    case Version.parse(current) do
      { :ok, current } ->
        Enum.filter(all(), fn HexWeb.Install.Entity[elixir: elixir] ->
          Version.compare(elixir, current) != :gt
        end)
        |> Enum.map(fn HexWeb.Install.Entity[hex: hex] -> hex end)
        |> Enum.sort(&(Version.compare(&1, &2) == :gt))
        |> List.first

      :error ->
        nil
    end
  end

  def create(hex, elixir) do
    HexWeb.Install.new(hex: hex, elixir: elixir)
    |> HexWeb.Repo.insert
  end
end
