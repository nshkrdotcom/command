[
  import_deps: [:ecto, :ecto_sql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/repo/**/*.exs"],
  subdirectories: ["priv/repo/migrations"]
]
