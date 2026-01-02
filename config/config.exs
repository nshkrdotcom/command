import Config

# General configuration
config :command,
  ecto_repos: [Command.Repo],
  generators: [binary_id: true]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :session_id, :user_id]

# Repo configuration
config :command, Command.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

# Import environment specific config
import_config "#{config_env()}.exs"
