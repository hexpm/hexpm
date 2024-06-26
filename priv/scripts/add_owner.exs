destructure [package, username_or_email, level], System.argv()

alias Hexpm.Repository.{Owners, Packages}
alias Hexpm.Accounts.Users

package = Hexpm.Repo.preload(Packages.get("hexpm", package), repository: :organization)
user = Users.get(username_or_email, [:emails])
params = if level, do: %{"level" => level}, else: %{}

IO.inspect(Owners.add(package, user, params, audit: %{user: Users.get("admin"), user_agent: "CLI", remote_ip: "127.0.0.1", key: nil}))
