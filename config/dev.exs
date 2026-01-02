import Config

# Configure your database
config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Enable dev mode logging
config :logger, :console, format: "[$level] $message\n"

# Do not include metadata nor timestamps in development logs
config :logger, level: :debug

# Development vault key (DO NOT use in production)
config :command, Command.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("dGhpcy1pcy1hLTMyLWJ5dGUtZGV2LWtleS1vbmx5ISE="),
      iv_length: 12
    }
  ]
