File.mkdir("logs")
HexWeb.Util.shell(~s(aws s3 sync s3://s3.hex.pm . --delete --exclude "*" --include "logs/*"))
