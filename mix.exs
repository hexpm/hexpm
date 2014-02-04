defmodule ExplexWeb.Mixfile do
  use Mix.Project

  def project do
    [ app: :explex_web,
      version: "0.0.1",
      elixir: "~> 0.12.3-dev",
      build_per_environment: false,
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [ applications: [:cowboy, :plug, :bcrypt],
      mod: { ExplexWeb, [] },
      env: [password_work_factor: 12] ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, git: "https://github.com/elixir-lang/foobar.git", tag: "0.1" }
  #
  # To specify particular versions, regardless of the tag, do:
  # { :barbat, "~> 0.1", github: "elixir-lang/barbat" }
  defp deps do
    [ { :plug, github: "elixir-lang/plug" },
      { :cowboy, github: "extend/cowboy" },
      { :ecto, github: "elixir-lang/ecto" },
      { :postgrex, github: "ericmj/postgrex" },
      { :bcrypt, github: "opscode/erlang-bcrypt" },
      { :jazz, github: "meh/jazz" } ]
  end
end
