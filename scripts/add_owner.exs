destructure [package, username_or_email, level], System.argv()

package = Packages.get("hexpm", package)
user = Users.get(username_or_email, [:emails])
params = if level, do: %{"level" => level}, else: %{}

IO.inspect Owners.add(package, user, params, audit: {Users.get("admin"), "CLI"})
