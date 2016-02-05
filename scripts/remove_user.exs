[name] = System.argv

user = HexWeb.Repo.get_by!(HexWeb.User, username: name) ||
         HexWeb.Repo.get_by!(HexWeb.User, email: name)

unless user do
  IO.puts "No user: #{name}"
  System.halt(1)
end

IO.inspect user

answer = IO.gets "Remove? [Yn] "

if answer =~ ~r/^(Y(es)?)?$/i do
  HexWeb.Repo.delete!(user)
  IO.puts "Removed"
else
  IO.puts "Not removed"
end
