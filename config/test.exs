import Config

# Configure your database for tests
config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Print only warnings and errors during test
config :logger, level: :warning

# Test vault key
config :command, Command.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("dGVzdC1rZXktMzItYnl0ZXMtZm9yLXRlc3RpbmchISE="),
      iv_length: 12
    }
  ]
