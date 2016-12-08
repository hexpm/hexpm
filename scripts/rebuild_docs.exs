[input, output] = System.argv

tars = File.ls!(input)

max_versions =
  Enum.reduce(tars, %{}, fn file, acc ->
    [package, version] = String.split(file, "-", parts: 2)
    version = String.slice(version, 0..-8)

    Map.update(acc, package, version, fn vsn ->
      if Version.compare(version, vsn) == :gt,
          do: version,
        else: vsn
    end)
  end)

File.mkdir_p!(output)

Enum.each(tars, fn file ->
  [package, version] = String.split(file, "-", parts: 2)
  version = String.slice(version, 0..-8)

  source = Path.join([input, file])               |> String.to_charlist
  root = Path.join([output, package])             |> String.to_charlist
  release = Path.join([output, package, version]) |> String.to_charlist

  if version == max_versions[package] do
    :erl_tar.extract(source, [:compressed, cwd: root])
  end

  :erl_tar.extract(source, [:compressed, cwd: release])
end)
