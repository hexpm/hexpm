destructure [package, username_or_email], System.argv()

alias Hexpm.Repository.{Owners, Packages}
alias Hexpm.Accounts.Users

package = Packages.get("hexpm", package)
user = Users.get(username_or_email, [:emails])

IO.inspect(Owners.remove(package, user, audit: {Users.get("admin"), "CLI"}))
