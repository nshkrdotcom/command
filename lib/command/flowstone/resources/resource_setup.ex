defmodule Command.FlowStone.Resources.ResourceSetup do
  @moduledoc """
  Registers Command resources with FlowStone.

  Called during pipeline initialization to bind resources
  for asset execution.

  ## Usage

      # During pipeline setup
      prompt_set = Command.PromptSets.get_prompt_set!(id)
      run_id = Ecto.UUID.generate()

      :ok = ResourceSetup.register(prompt_set, run_id)

      # Resources are now available via FlowStone.Resources.get/1
      {:ok, agent_runner} = FlowStone.Resources.get(:agent_runner)
      {:ok, artifact_store} = FlowStone.Resources.get(:artifact_store)
      {:ok, progress} = FlowStone.Resources.get(:progress)

  ## Registered Resources

  This module registers the following resources:

  - `:agent_runner` - LLM provider abstraction (Claude, Codex)
  - `:artifact_store` - Filesystem-based artifact storage
  - `:progress` - DB-backed progress tracking

  Additional resources from ADR-0011 (to be implemented separately):
  - `:vcs` / `:vcs_*` - VCS port adapter (per-repo)
  - `:changeset` - Multi-repo changeset tracking
  - `:branch_manager` - Feature branch coordination
  - `:partial_recovery` - Partial success recovery

  ## Configuration

  Resources are configured from the prompt_set config:

  - `default_provider` → agent_runner provider
  - `default_model` → agent_runner model
  - `allowed_tools` → agent_runner tools
  - `log_dir` → artifact_store log_dir
  - `project_dir` → vcs project_dir (future)

  The `run_id` is passed to both artifact_store and progress for run isolation.
  """

  alias Command.FlowStone.Resources.{AgentRunner, ArtifactStore, ProgressTracker}

  require Logger

  @doc """
  Register all Command resources with FlowStone.

  Builds resource configurations from the prompt_set and run_id,
  then registers them with FlowStone.Resources.

  Returns `:ok` on success, `{:error, reason}` if registration fails.

  ## Parameters

  - `prompt_set` - Struct or map with `:config` key containing:
    - `default_provider` - LLM provider (`:claude` | `:codex`)
    - `default_model` - Model identifier
    - `allowed_tools` - List of tool names
    - `log_dir` - Base directory for artifacts
    - `project_dir` - Project directory for VCS operations
  - `run_id` - UUID string for run isolation

  ## Example

      prompt_set = %{
        config: %{
          default_provider: :claude,
          default_model: "claude-sonnet-4-20250514",
          allowed_tools: ["Read", "Write", "Edit", "Bash"],
          log_dir: "/var/log/flowstone",
          project_dir: "/home/project"
        }
      }

      :ok = ResourceSetup.register(prompt_set, run_id)
  """
  @spec register(map(), String.t(), keyword()) :: :ok | {:error, term()}
  def register(prompt_set, run_id, opts \\ []) do
    server = Keyword.get(opts, :server, FlowStone.Resources)
    config = prompt_set.config

    resources = [
      {:agent_runner, AgentRunner,
       %{
         provider: config[:default_provider] || :claude,
         model: config[:default_model],
         tools: config[:allowed_tools] || [],
         permission_mode: config[:permission_mode],
         execution_mode: config[:execution_mode] || :per_repo,
         workspace_root: config[:workspace_root]
       }},
      {:artifact_store, ArtifactStore,
       %{
         log_dir: config[:log_dir] || default_log_dir(),
         run_id: run_id
       }},
      {:progress, ProgressTracker,
       %{
         run_id: run_id
       }}
    ]

    # Register each resource
    Enum.each(resources, fn {name, module, resource_config} ->
      case module.setup(resource_config) do
        {:ok, resource} ->
          # Register with FlowStone.Resources
          # Note: FlowStone.Resources.register/3 expects {module, config} tuple
          # We need to use FlowStone.Resources.override/2 to inject already-setup resources
          current_resources = FlowStone.Resources.load(server)
          updated_resources = Map.put(current_resources, name, resource)
          FlowStone.Resources.override(updated_resources, server)

          Logger.debug("Registered FlowStone resource: #{name}")

        {:error, reason} ->
          Logger.error("Failed to setup resource #{name}: #{inspect(reason)}")
          raise "Resource setup failed for #{name}: #{inspect(reason)}"
      end
    end)

    :ok
  end

  # Private helpers

  defp default_log_dir do
    # Default to a logs directory relative to the project
    Path.join([System.tmp_dir(), "flowstone_logs"])
  end
end
