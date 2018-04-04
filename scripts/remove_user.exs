[name] = System.argv()

user = Hexpm.Accounts.Users.get(name, [:emails])

unless user do
  IO.puts("No user: #{name}")
  System.halt(1)
end

IO.inspect(user)

answer = IO.gets("Remove? [Yn] ")

if answer =~ ~r/^(Y(es)?)?$/i do
  Hexpm.Repo.delete!(user)
  IO.puts("Removed")
else
  IO.puts("Not removed")
end
