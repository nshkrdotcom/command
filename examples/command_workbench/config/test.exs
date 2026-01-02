import Config

config :command_workbench, CommandWorkbenchWeb.Endpoint,
  server: false,
  secret_key_base: "xwEb2nHq8pQ7s1yJ9lM0b3rT6uV4cZ5n8sD2fG1hK3mP7qR9tY1u5iO4aX6eB7c"

config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_workbench_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :command, Command.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("dGVzdC1rZXktMzItYnl0ZXMtZm9yLXRlc3RpbmchISE="),
      iv_length: 12
    }
  ]

config :command, skip_adapter_validation: true

config :logger, level: :warning
