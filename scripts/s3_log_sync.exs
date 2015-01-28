File.mkdir("hex")
HexWeb.Util.shell(~s(aws s3 sync s3://logs.hex.pm . --delete --exclude "*" --include "hex/*"))
