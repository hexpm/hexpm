defmodule HexWeb.Install do
  use Ecto.Model
  import Kernel, except: [max: 2]

  schema "installs" do
    field :hex, :string
    field :elixirs, {:array, :string}
  end

  def all do
    HexWeb.Repo.all(HexWeb.Install)
  end

  def latest(current) do
    case Version.parse(current) do
      {:ok, current} ->
        installs =
          Enum.filter(all(), fn %HexWeb.Install{elixirs: elixirs} ->
            Enum.any?(elixirs, &Version.compare(&1, current) != :gt)
          end)

        if installs != [] do
          install = max(installs, &(&1.hex))

          if install do
            elixir =
              install.elixirs
              |> Enum.filter(&(Version.compare(&1, current) != :gt))
              |> Enum.max

            {install.hex, elixir}
          end
        end

      :error ->
        nil
    end
  end

  def create(hex, elixirs) do
    {:ok, %HexWeb.Install{hex: hex, elixirs: elixirs}
           |> HexWeb.Repo.insert}
  end

  defp max([first|rest], fun) do
    {_, elem} = Enum.reduce(rest, {fun.(first), first}, &Kernel.max({fun.(&1), &1}, &2))
    elem
  end
end
