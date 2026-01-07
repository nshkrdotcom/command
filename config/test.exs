import Config

# Configure your database for tests
config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Synapse Repo configuration for tests (shared DB)
config :synapse, Synapse.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

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

# Portfolio Core - use test manifest with mock adapters
# Tests register mocks programmatically for isolation
config :portfolio_core, :manifest,
  manifest_path: nil,
  auto_load: false

# Skip adapter validation in tests - mocks are registered per-test
config :command, skip_adapter_validation: true

# Disable orchestration runtime in tests to avoid sandbox ownership issues
config :command, Command.Orchestration, enabled: false

# Hammer rate limiter configuration for tests
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# PortfolioIndex Repo configuration for tests
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 2

# Neo4j (Boltx) configuration for tests
config :boltx, Boltx,
  name: Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 5
