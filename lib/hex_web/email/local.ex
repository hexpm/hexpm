defmodule HexWeb.Email.Local do
  @behaviour HexWeb.Email

  def send(to, subject, {:safe, body}) do
    Path.join("tmp", "email")
    |> File.mkdir_p!

    Path.join(["tmp", "email", "#{to}.html"])
    |> File.write!([subject, "\n\n", body])
  end

  def read(to) do
    Path.join(["tmp", "email", "#{to}.html"])
    |> File.read!
    |> String.split("\n\n", parts: 2)
    |> List.to_tuple
  end
end
