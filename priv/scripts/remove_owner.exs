destructure [package, username_or_email], System.argv()

package = Packages.get(package)
user = Users.get(username_or_email, [:emails])

IO.inspect(Owners.remove(package, user, audit: {Users.get("admin"), "CLI"}))
