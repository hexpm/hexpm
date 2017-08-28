[name, username] = System.argv()

package = Hexpm.Repo.get_by!(Hexpm.Repository.Package, name: name)
user = Hexpm.Repo.get_by!(Hexpm.Accounts.User, username: username)

Hexpm.Repository.Package.build_owner(package, user)
|> Hexpm.Repo.insert!()
