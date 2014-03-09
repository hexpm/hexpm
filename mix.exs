defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [ app: :hex_web,
      version: "0.0.1",
      elixir: "~> 0.12.4 or ~> 0.13.0-dev",
      deps: deps ]
  end

  def application do
    [ applications: [:cowboy, :plug, :bcrypt, :mini_s3],
      mod: { HexWeb, [] },
      env: [ config_password_work_factor: 12 ] ]
  end

  defp deps do
    [ { :plug, github: "elixir-lang/plug" },
      { :cowboy, github: "extend/cowboy" },
      { :ecto, github: "elixir-lang/ecto" },
      { :postgrex, github: "ericmj/postgrex" },
      { :bcrypt, github: "opscode/erlang-bcrypt" },
      { :jazz, github: "meh/jazz" },
      { :mini_s3, github: "ericmj/mini_s3", branch: "hex-fixes" } ]
  end
end
