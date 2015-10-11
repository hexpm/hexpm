[dir, date] = System.argv
File.mkdir_p!("logs/#{dir}")
File.cd!("logs")

HexWeb.Util.shell(~s(aws s3 cp s3://logs.hex.pm . --recursive --exclude "*" --include "#{dir}/#{date}*"))

contents =
  Path.wildcard("#{dir}/**")
  |> Enum.reduce([], fn file, acc -> [acc|File.read!(file)] end)
  |> :zlib.gzip

filename = "#{dir}-#{date}.txt.gz"
File.write!(filename, contents)

HexWeb.Util.shell(~s(aws s3 cp #{filename} s3://s3.hex.pm/log-archives/#{filename}))

HexWeb.Util.shell(~s(aws s3 rm s3://logs.hex.pm --recursive --exclude "*" --include "#{dir}/#{date}*"))

