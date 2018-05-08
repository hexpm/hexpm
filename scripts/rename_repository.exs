[old_name, new_name] = System.argv()

repository = Hexpm.Repositories.get(old_name)

unless repository do
  IO.puts("No repository: #{name}")
  System.halt(1)
end

IO.inspect(repository)

answer = IO.gets("Rename? [Yn] ")

if answer =~ ~r/^(Y(es)?)?$/i do
  repository
  |> Ecto.Changeset.change(name: new_name)
  |> Hexpm.Repo.update!()

  IO.puts("Renamed")
else
  IO.puts("Not renamed")
end
