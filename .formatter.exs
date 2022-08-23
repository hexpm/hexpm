[
  inputs: [
    "*.exs",
    "config/*.exs",
    "lib/**/*.ex",
    "priv/**/*.exs",
    "scripts/*.exs",
    "test/**/*.{ex,exs}"
  ],
  import_deps: [:ecto, :phoenix, :plug]
]
