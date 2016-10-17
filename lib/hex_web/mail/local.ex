defmodule HexWeb.Mail.Local do
  @behaviour HexWeb.Mail

  def send(to, subject, {:safe, body}) do
    Path.join("tmp", "email")
    |> File.mkdir_p!

    Enum.map(to, fn email ->
      Path.join(["tmp", "email", "#{email}.html"])
      |> File.write!([subject, "\n\n", body])
    end)
  end

  def read(to) do
    Path.join(["tmp", "email", "#{to}.html"])
    |> File.read!
    |> String.split("\n\n", parts: 2)
    |> List.to_tuple
  end
end
