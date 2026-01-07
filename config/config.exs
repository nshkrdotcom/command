import Config

# jido and jido_signal both define Jido.Signal.TraceContext; ignore redefinition warnings.
Code.compiler_options(ignore_module_conflict: true)

# General configuration
config :command,
  ecto_repos: [Command.Repo],
  generators: [binary_id: true]

# Portfolio Core configuration
# The manifest defines which adapters to use for RAG/LLM operations
config :portfolio_core, :manifest, manifest_path: "config/portfolio_manifest.yaml"

# Hammer rate limiter configuration (required by portfolio_index)
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :session_id, :user_id]

# Repo configuration
config :command, Command.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

# FlowStone configuration (in-memory defaults for Command)
config :flowstone,
  io_managers: %{
    memory: FlowStone.IO.Memory,
    postgres: FlowStone.IO.Postgres,
    s3: FlowStone.IO.S3,
    parquet: FlowStone.IO.Parquet
  },
  default_io_manager: :memory

# PortfolioManager is a dependency of portfolio_coder; disable runtime services by default
config :portfolio_manager,
  start_repo: false,
  start_router: false,
  manifest: %{}

# Synapse orchestration integration
config :command, Command.Orchestration,
  enabled: true,
  synapse_runtime: Synapse.Runtime,
  orchestrator_name: Command.Orchestration.Runtime,
  reconcile_interval: 5_000

# Disable Synapse's built-in orchestrator so Command can manage it
config :synapse, Synapse.Orchestrator.Runtime, enabled: false

# Import environment specific config
import_config "#{config_env()}.exs"
