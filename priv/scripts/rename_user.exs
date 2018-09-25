[old_name, new_name] = System.argv()

user = Hexpm.Accounts.Users.get(old_name)

unless user do
  IO.puts("No user: #{old_name}")
  System.halt(1)
end

IO.inspect(user)

answer = IO.gets("Rename? [Yn] ")

if answer =~ ~r/^(Y(es)?)?$/i do
  user
  |> Ecto.Changeset.change(username: new_name)
  |> Hexpm.Repo.update!()

  IO.puts("Renamed")
else
  IO.puts("Not renamed")
end
