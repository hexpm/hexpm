destructure [package, username_or_email], System.argv()

alias Hexpm.Repository.{Owners, Packages}
alias Hexpm.Accounts.Users

package = Packages.get("hexpm", package)
user = Users.get(username_or_email, [:emails])

Owners.remove(package, user,
  audit: %{user: Users.get("admin"), user_agent: "CLI", remote_ip: "127.0.0.1", key: nil}
)
|> IO.inspect()
