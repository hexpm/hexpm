[date] = System.argv
File.mkdir("logs")

IO.puts :os.cmd('aws s3 cp s3://s3.hex.pm . --recursive --exclude "*" --include "logs/#{date}*"')
File.cd!("logs")

IO.puts :os.cmd('zip -9 -r #{date}.zip .')

IO.puts :os.cmd('aws s3 cp #{date}.zip s3://s3.hex.pm/log-archives/#{date}.zip')

IO.puts :os.cmd('aws s3 rm s3://s3.hex.pm --recursive --exclude "*" --include "logs/#{date}*"')

File.cd!("..")
File.rm_rf!("logs")
