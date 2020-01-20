switches = [dry_run: :boolean]
{opts, [old_name, new_name]} = OptionParser.parse!(System.argv(), strict: switches)
dry_run? = opts[:dry_run]

organization = Hexpm.Accounts.Organizations.get(old_name, [:user])

unless organization do
  IO.puts("No organization: #{old_name}")
  System.halt(1)
end

IO.inspect(organization)

answer = IO.gets("Rename? [Yn] ")

if answer =~ ~r/^(Y(es)?)?$/i do
  user_changeset = Ecto.Changeset.change(organization.user, username: new_name)

  changeset =
    organization
    |> Ecto.Changeset.change(name: new_name)
    |> Ecto.Changeset.put_assoc(:user, user_changeset)

  Hexpm.Repo.transaction(fn ->
    if dry_run? do
      IO.inspect(changeset)
    else
      Hexpm.Repo.update!(changeset)
    end

    keys = Hexpm.Repo.all(Hexpm.Accounts.Key)

    Enum.each(keys, fn key ->
      yes? =
        Enum.any?(key.permissions, fn permission ->
          permission.domain == "repository" and permission.resource == old_name
        end)

      if yes? do
        permissions =
          Enum.map(key.permissions, fn permission ->
            if permission.domain == "repository" do
              Ecto.Changeset.change(permission, resource: new_name)
            else
              permission
            end
          end)

        changeset =
          key
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_embed(:permissions, permissions)

        if dry_run? do
          IO.inspect(changeset)
        else
          Hexpm.Repo.update!(changeset)
        end

        IO.puts("#{key.name} - #{key.id}")
      end
    end)
  end)

  IO.puts("Renamed")
else
  IO.puts("Not renamed")
end
