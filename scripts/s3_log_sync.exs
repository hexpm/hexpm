File.mkdir("logs")
HexWeb.Util.shell(~s(aws s3 cp s3://logs.hex.pm logs --recursive --exclude "*" --include "hex/2016-01-27*"))
