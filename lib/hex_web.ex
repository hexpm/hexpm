defmodule HexWeb do
  use Application

  def start(_type, _args) do
    :erlang.system_flag(:backtrace_depth, 16)

    opts = [compress: true, linger: {true, 10}]
    port = Application.get_env(:hex_web, :port)
    opts = Keyword.put(opts, :port, String.to_integer(port))

    use_ssl = match?("https://" <> _, Application.get_env(:hex_web, :url))
    Application.put_env(:hex_web, :use_ssl, use_ssl)
    Application.put_env(:hex_web, :tmp, Path.expand("tmp"))

    File.mkdir_p!("tmp")

    shutdown_on_eof()
    HexWeb.Supervisor.start_link(opts)
  end

  def request_read_opts do
    # Max filesize: ~10mb
    # Min upload: ~10kb/s
    [ length: 10_000_000,
      read_length: 100_000,
      read_timeout: 10_000 ]
  end

  def request_read_fast_opts do
    # Max filesize: ~10mb
    # Min upload: ~10kb/s
    [ length: 10_000_000,
      read_length: 10_000,
      read_timeout: 1_000 ]
  end

  # Make sure we exit after hex client tests are finished running
  if Mix.env == :hex do
    def shutdown_on_eof do
      spawn_link(fn ->
        IO.gets(:stdio, '') == :eof && System.halt(0)
      end)
    end
  else
    def shutdown_on_eof, do: nil
  end

  defprotocol Render do
    @moduledoc """
    Render entities to something that can be showed publicly.
    Used, for example, when converting entities to JSON responses.
    """

    @spec render(term) :: map
    def render(entity)
  end
end
