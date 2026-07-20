defmodule Hexpm.OAuth.ReadOnly do
  def enabled?() do
    Application.get_env(:hexpm, :read_only_mode, false)
  end

  def configure!(read_only?) when is_boolean(read_only?) do
    Application.put_env(:hexpm, :read_only_mode, read_only?)
  end
end
