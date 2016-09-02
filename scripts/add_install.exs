case System.argv do
  [hex | elixirs] ->
    IO.puts "Hex:     " <> hex
    IO.puts "Elixirs: " <> Enum.join(elixirs, ", ")

    HexWeb.Install.build(hex, elixirs) |> HexWeb.Repo.insert

  _ ->
    :ok
end

all = HexWeb.Install.all |> HexWeb.Repo.all

csv =
  Enum.map_join(all, "\n", fn install ->
    Enum.join([install.hex|install.elixirs], ",")
  end)

opts = [acl: :public_read, content_type: "text/csv", cache_control: "public, max-age=604800", meta: [{"surrogate-key", "installs"}]]
HexWeb.Store.S3.put(nil, :s3_bucket, "installs/list.csv", csv, opts)
HexWeb.CDN.purge_key(:fastly_hexrepo, "installs")

IO.puts "Uploaded installs/list.csv"

HexWeb.RegistryBuilder.partial_build(:v1)

IO.puts "Rebuilt registry"
