[
  import_deps: [:ecto, :ecto_sql],
  inputs:
    Enum.reject(
      [
        "{mix,.formatter}.exs",
        "{config,lib}/**/*.{ex,exs}",
        "priv/repo/**/*.exs"
      ] ++
        (Path.wildcard("test/**/*.{ex,exs}") --
           ["test/fixtures/cli/invalid_syntax.exs"]),
      &is_nil/1
    ),
  subdirectories: ["priv/repo/migrations"]
]
