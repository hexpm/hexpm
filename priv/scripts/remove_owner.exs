destructure [package, username_or_email], System.argv()

alias Hexpm.Repository.{Owners, Packages}
alias Hexpm.Accounts.{AuditLogs, Users}

package = Packages.get("hexpm", package)
user = Users.get(username_or_email, [:emails])

Owners.remove(package, user, audit: AuditLogs.admin())
|> IO.inspect()
