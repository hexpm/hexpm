[old_name, new_name] = System.argv()

organization = Hexpm.Accounts.Organizations.get(old_name)

unless organization do
  IO.puts("No organization: #{old_name}")
  System.halt(1)
end

IO.inspect(organization)

answer = IO.gets("Rename? [Yn] ")

if answer =~ ~r/^(Y(es)?)?$/i do
  Hexpm.Repo.transaction(fn ->
    organization
    |> Ecto.Changeset.change(name: new_name)
    |> Hexpm.Repo.update!()

    keys = Repo.all(Key)

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

        key
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_embed(:permissions, permissions)
        |> Repo.update!()

        IO.puts("#{key.name} - #{key.id}")
      end
    end)
  end)

  IO.puts("Renamed")
else
  IO.puts("Not renamed")
end
