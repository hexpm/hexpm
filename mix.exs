defmodule HexWeb.Mixfile do
  use Mix.Project

  def project do
    [ app: :hex_web,
      version: "0.0.1",
      elixir: "~> 0.13.2-dev",
      elixirc_options: [
        :debug_info,
        exlager_truncation_size: 8*1024,
        exlager_level: lager_level ],
      deps: deps,
      lager_level: lager_level ]
  end

  defp lager_level do
    if Mix.env in [:dev, :prod] do
      :info
    else
      :notice
    end
  end

  def application do
    [ applications: [:cowboy, :plug, :bcrypt, :mini_s3],
      mod: { HexWeb, [] },
      env: config(Mix.env) ]
  end

  defp config(:prod) do
    [
      config_password_work_factor: 12,
      config_packages_per_page: 30
    ]
  end

  defp config(_) do
    [
      config_password_work_factor: 4,
      config_packages_per_page: 10
    ]
  end

  defp deps do
    [ { :plug, github: "elixir-lang/plug" },
      { :cowboy, github: "extend/cowboy" },
      { :ecto, github: "elixir-lang/ecto" },
      { :poolboy, github: "devinus/poolboy", override: true },
      { :postgrex, github: "ericmj/postgrex", override: true },
      { :decimal, github: "ericmj/decimal", override: true },
      { :bcrypt, github: "opscode/erlang-bcrypt" },
      { :jazz, github: "ericmj/jazz", branch: "elixir-0.13.1" },
      { :mini_s3, github: "ericmj/mini_s3", branch: "hex-fixes" },
      { :exlager, github: "khia/exlager" },
      { :ex_doc, github: "elixir-lang/ex_doc", only: :dev } ]
  end
end
