import Config

config :command_workbench, dev_routes: true

config :command_workbench, CommandWorkbenchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "6fG9oX7u6sbG7P3xwX8m3p0A9Yk5sR5r1yQ9B2a3u6v8t1w2e3r4t5y6u7i8o9p0",
  watchers: [
    tailwind: {Tailwind, :install_and_run, [:command_workbench, ~w(--watch)]},
    esbuild: {Esbuild, :install_and_run, [:command_workbench, ~w(--watch)]}
  ]

config :command_workbench, CommandWorkbenchWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!assets/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/static/assets/.*(js|css)$",
      ~r"lib/command_workbench_web/(controllers|live|components|layouts)/.*(ex|heex)$"
    ]
  ]

config :command, Command.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("dGhpcy1pcy1hLTMyLWJ5dGUtZGV2LWtleS1vbmx5ISE="),
      iv_length: 12
    }
  ]

config :logger, :console, format: "[$level] $message\n"
config :logger, level: :debug

config :phoenix, :stacktrace_depth, 20
