[dir, date] = System.argv
File.mkdir_p!("logs/#{dir}")
File.cd!("logs")

HexWeb.Util.shell(~s(aws s3 cp s3://logs.hex.pm . --recursive --exclude "*" --include "#{dir}/#{date}*"))

File.cd!(dir)
HexWeb.Util.shell(~s(zip -9 -r #{date}.zip .))

HexWeb.Util.shell(~s(aws s3 cp #{date}.zip s3://s3.hex.pm/log-archives/#{dir}-#{date}.zip))

HexWeb.Util.shell(~s(aws s3 rm s3://logs.hex.pm --recursive --exclude "*" --include "#{dir}/#{date}*"))

