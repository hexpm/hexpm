case System.argv do
  [hex | elixirs] ->
    IO.puts "Hex:     " <> hex
    IO.puts "Elixirs: " <> Enum.join(elixirs, ", ")

    HexWeb.Install.create(hex, elixirs) |> HexWeb.Repo.insert

  _ ->
    :ok
end

all = HexWeb.Install.all |> HexWeb.Repo.all

csv =
  Enum.map_join(all, "\n", fn install ->
    Enum.join([install.hex|install.elixirs], ",")
  end)

HexWeb.RegistryBuilder.rebuild

IO.puts "Rebuilt registry"
