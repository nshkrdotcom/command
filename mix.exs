defmodule Command.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/command"

  def project do
    [
      app: :command,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],

      # Hex
      name: "Command",
      description: "Command center core library for AI agent orchestration",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Command.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        credo: :test,
        dialyzer: :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      # Note: pgvector now provided by portfolio_index

      # JSON
      {:jason, "~> 1.4"},

      # Utilities
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.2"},

      # Phoenix integration
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},

      # Security
      {:cloak_ecto, "~> 1.3"},

      # Pipeline orchestration
      {:flowstone, path: "../flowstone"},
      # Note: flowstone_ai merged into altar_ai as Altar.AI.Integrations.FlowStone
      # See docs/20260105/07_ai_layer_consolidation.md

      # Multi-agent orchestration
      {:synapse, path: "../synapse"},
      # Note: Synapse.ReqLLM replaced by Altar.AI.Integrations.Synapse

      # Unified AI abstraction layer (consolidates flowstone_ai, Synapse.ReqLLM)
      # Tool contracts (ADM/LATER)
      {:altar, path: "../ALTAR"},
      # Unified LLM/embedding layer
      {:altar_ai, path: "../altar_ai"},

      # Portfolio ecosystem - hexagonal architecture for RAG/LLM
      {:portfolio_core, path: "../portfolio_core", override: true},
      {:portfolio_index, path: "../portfolio_index", override: true},
      {:portfolio_coder, path: "../portfolio_coder"},

      # Background jobs (optional, for scheduled jobs)
      {:oban, "~> 2.18", optional: true},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:faker, "~> 0.18", only: :test},
      {:supertester, path: "../supertester", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      lint: ["format --check-formatted", "credo --strict"],
      "lint.fix": ["format", "credo --strict"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:ex_unit],
      flags: [
        :error_handling,
        :missing_return,
        :underspecs,
        :unknown,
        :unmatched_returns
      ]
    ]
  end

  defp package do
    [
      name: "command",
      licenses: ["MIT"],
      maintainers: ["nshkrdotcom"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files:
        ~w(lib priv/repo/migrations .formatter.exs mix.exs README.md LICENSE CHANGELOG.md SCHEMA.md assets)
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Command",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/command.svg",
      extras: ["README.md", "SCHEMA.md", "CHANGELOG.md", "LICENSE"],
      groups_for_extras: [
        Introduction: ~w(README.md),
        Reference: ~w(SCHEMA.md),
        "Release Notes": ~w(CHANGELOG.md),
        Legal: ~w(LICENSE)
      ],
      groups_for_modules: [
        "Core Schemas": [
          Command.Accounts.User,
          Command.Sessions.Session,
          Command.Sessions.Message
        ],
        Agents: [
          Command.Agents.AgentCall,
          Command.Agents.ToolUse
        ],
        Workflows: [
          Command.Workflows.Workflow,
          Command.Workflows.WorkflowRun,
          Command.Workflows.WorkflowStep
        ],
        "RAG & Indexes": [
          Command.Indexes.Index,
          Command.Indexes.ContextDocument,
          Command.Indexes.ContextChunk
        ],
        Approvals: [
          Command.Approvals.ApprovalItem,
          Command.Approvals.ApprovalRule
        ],
        "Plan Runs": [
          Command.PlanRuns,
          Command.PlanRuns.PlanRun
        ],
        RunIndex: [
          Command.RunIndex,
          Command.RunIndex.Run,
          Command.RunIndex.Step
        ],
        Lineage: [
          LineageIR.Event,
          LineageIR.Trace,
          LineageIR.Span,
          LineageIR.Artifact,
          LineageIR.ProvenanceEdge,
          LineageIR.EventRecord,
          LineageIR.Sink,
          LineageIR.Sink.Adapter,
          LineageIR.Sink.Adapters.Ecto
        ],
        Policy: [
          Command.Policy,
          Command.Flowstone.ApprovalBridge
        ],
        Costs: [
          Command.Costs.CostRecord,
          Command.Costs.CostDailySummary
        ]
      ]
    ]
  end
end
