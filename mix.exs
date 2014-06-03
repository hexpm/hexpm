defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [ app: :hex_web,
      version: "0.0.1",
      elixir: "0.14.0-dev",
      config_path: "config/#{Mix.env}.exs",
      deps: deps ]
  end

  def application do
    [ applications: [:cowboy, :plug, :bcrypt, :mini_s3, :lager],
      mod: { HexWeb, [] },
      env: [ config_password_work_factor: 12 ] ]
  end

  defp deps do
    [ { :plug, github: "elixir-lang/plug" },
      { :cowboy, github: "extend/cowboy" },
      { :ecto, github: "elixir-lang/ecto" },
      { :poolboy, github: "devinus/poolboy", override: true },
      { :postgrex, github: "ericmj/postgrex", override: true },
      { :decimal, github: "ericmj/decimal", override: true },
      { :bcrypt, github: "opscode/erlang-bcrypt" },
      { :jazz, github: "meh/jazz" },
      { :mini_s3, github: "ericmj/mini_s3", branch: "hex-fixes" },
      { :stout, github: "ericmj/stout" },
      { :ex_doc, github: "elixir-lang/ex_doc", only: :dev } ]
  end
end
