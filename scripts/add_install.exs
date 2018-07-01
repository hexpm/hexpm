case System.argv() do
  [hex | elixirs] ->
    IO.puts("Hex:     " <> hex)
    IO.puts("Elixirs: " <> Enum.join(elixirs, ", "))
    Hexpm.Repository.Install.build(hex, elixirs) |> Hexpm.Repo.insert!()

  _ ->
    :ok
end

all = Hexpm.Repository.Install.all() |> Hexpm.Repo.all()

csv =
  Enum.map_join(all, "\n", fn install ->
    Enum.join([install.hex | install.elixirs], ",")
  end)

opts = [
  acl: :public_read,
  content_type: "text/csv",
  cache_control: "public, max-age=604800",
  meta: [{"surrogate-key", "installs"}]
]

Hexpm.Store.S3.put(nil, :s3_bucket, "installs/list.csv", csv, opts)
Hexpm.CDN.purge_key(:fastly_hexrepo, "installs")

IO.puts("Uploaded installs/list.csv")

Hexpm.Repository.RegistryBuilder.partial_build({:v1, Hexpm.Accounts.Organization.hexpm()})

IO.puts("Rebuilt registry")
