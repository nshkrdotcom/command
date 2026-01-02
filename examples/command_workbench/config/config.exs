import Config

config :command_workbench,
  generators: [timestamp_type: :utc_datetime_usec]

config :command_workbench, CommandWorkbenchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CommandWorkbenchWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: CommandWorkbench.PubSub,
  live_view: [signing_salt: "your_signing_salt"]

# Configure Command to use our PubSub
config :command,
  ecto_repos: [Command.Repo],
  pubsub: CommandWorkbench.PubSub,
  pubsub_prefix: "command",
  skip_adapter_validation: true

# Use Command's Repo
config :command, Command.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "command_workbench_dev"

# Disable portfolio auto-loading in the example app
config :portfolio_core, :manifest,
  manifest_path: nil,
  auto_load: false

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :esbuild,
  version: "0.17.11",
  command_workbench: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  command_workbench: [
    args:
      ~w(--config=tailwind.config.js --input=css/app.css --output=../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
