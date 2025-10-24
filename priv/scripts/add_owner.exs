{opts, args} = OptionParser.parse!(System.argv(), strict: [transfer: :boolean])
destructure [package, username_or_email, level], args

alias Hexpm.Repository.{Owners, Packages}
alias Hexpm.Accounts.{AuditLogs, Users}

package = Hexpm.Repo.preload(Packages.get("hexpm", package), repository: :organization)
user = Users.get(username_or_email, [:emails])

params =
  if level do
    %{"level" => level}
  else
    %{}
  end

params =
  if opts[:transfer] do
    put_in(params["transfer"], true)
  else
    params
  end

Owners.add(package, user, params, audit: AuditLogs.admin())
|> IO.inspect()
