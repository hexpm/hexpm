[
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "bench/*.exs",
    "priv/*/seeds.exs"
  ],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  import_deps: [:ecto, :ecto_sql, :phoenix, :plug]
]
