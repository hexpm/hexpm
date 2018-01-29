[username, name] = System.argv()

user = Hexpm.Accounts.Users.get(username, [:emails])

Hexpm.Repository.Repositories.create(name, user)
|> IO.inspect()
