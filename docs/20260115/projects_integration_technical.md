# Command.Projects - Technical Implementation & Integration Guide

## Executive Summary

**Question:** Is this Command-only or does it need portfolio_* dependencies?

**Answer:** Primarily Command-only, with optional reuse from portfolio_coder.

| Component | Location | Rationale |
|-----------|----------|-----------|
| Ecto schemas & migrations | `command` | Uses existing Ecto/Repo infrastructure |
| Context module (CRUD, queries) | `command` | Follows established Command patterns |
| PubSub integration | `command` | Uses Command.PubSub |
| Background sync jobs | `command` | Uses Command.Scheduling or Oban |
| Git/language detection logic | Extract from `portfolio_coder` | Mature, tested code |
| Scanner/Syncer core | Extract from `portfolio_coder` | ~500 LOC to adapt |
| YAML migration script | One-time in `command` | Imports existing data |

## Architecture Decision

### Why Command (not portfolio_coder)?

1. **Database infrastructure:** Command has Ecto.Repo, migrations, PostgreSQL config
2. **User model:** Command has `Command.Accounts.User` for ownership
3. **PubSub:** Command has real-time event broadcasting
4. **Agent integration:** Command is where agents live and query
5. **Scheduling:** Command has background job infrastructure
6. **Pattern consistency:** Follows established context patterns

### What to extract from portfolio_coder?

The Scanner and Syncer modules contain tested logic for:
- Git command execution and parsing
- Language detection via file markers
- Dependency extraction (Elixir, Python, JavaScript)
- Type detection (library vs application)

**Recommendation:** Copy the pure functions, adapt for Ecto output.

## File Structure

```
lib/command/
├── projects/
│   ├── project.ex              # Project schema
│   ├── relationship.ex         # ProjectRelationship schema
│   ├── decision.ex             # ProjectDecision schema
│   ├── project_state.ex        # ProjectState schema
│   └── scanner.ex              # Git/language detection (from portfolio_coder)
├── projects.ex                 # Context module (CRUD, queries)
└── projects/
    └── sync_worker.ex          # Oban worker OR scheduled job handler

priv/repo/migrations/
├── 20260115000001_create_projects.exs
├── 20260115000002_create_project_relationships.exs
├── 20260115000003_create_project_decisions.exs
└── 20260115000004_create_project_state.exs
```

## Migration Definitions

### 20260115000001_create_projects.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :priority, :integer, null: false, default: 3
      add :category, :string
      add :language, :string
      add :path, :string
      add :remote_url, :string
      add :current_focus, :text
      add :blocked_reason, :text
      add :tags, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:projects, [:user_id])
    create unique_index(:projects, [:user_id, :slug])
    create index(:projects, [:status])
    create index(:projects, [:priority])
    create index(:projects, [:language])
    create index(:projects, [:category])
    create index(:projects, [:tags], using: :gin)
  end
end
```

### 20260115000002_create_project_relationships.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjectRelationships do
  use Ecto.Migration

  def change do
    create table(:project_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :to_project_id, references(:projects, type: :binary_id, on_delete: :delete_all)  # Nullable for external

      add :relationship_type, :string, null: false
      add :auto_detected, :boolean, null: false, default: false
      add :notes, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:project_relationships, [:from_project_id])
    create index(:project_relationships, [:to_project_id])
    create index(:project_relationships, [:relationship_type])
    create unique_index(:project_relationships, [:from_project_id, :to_project_id, :relationship_type],
      name: :project_relationships_unique_edge)
  end
end
```

### 20260115000003_create_project_decisions.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjectDecisions do
  use Ecto.Migration

  def change do
    create table(:project_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :superseded_by_id, references(:project_decisions, type: :binary_id, on_delete: :nilify_all)

      add :title, :string, null: false
      add :status, :string, null: false, default: "accepted"
      add :context, :text
      add :decision, :text
      add :consequences, :text
      add :tags, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:project_decisions, [:project_id])
    create index(:project_decisions, [:status])
    create index(:project_decisions, [:superseded_by_id])
  end
end
```

### 20260115000004_create_project_state.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjectState do
  use Ecto.Migration

  def change do
    create table(:project_state, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false

      add :synced_at, :utc_datetime_usec

      # Git state
      add :git_dirty, :boolean, default: false
      add :current_branch, :string
      add :ahead, :integer, default: 0
      add :behind, :integer, default: 0
      add :last_commit_sha, :string
      add :last_commit_at, :utc_datetime_usec
      add :last_commit_message, :text
      add :commit_count_30d, :integer, default: 0

      # CI/Build state
      add :ci_status, :string
      add :ci_url, :string
      add :build_status, :string
      add :last_build_at, :utc_datetime_usec

      # Test state
      add :test_count, :integer
      add :test_pass_count, :integer
      add :test_fail_count, :integer
      add :last_test_at, :utc_datetime_usec

      # Dependencies
      add :deps_total_count, :integer, default: 0
      add :deps_outdated_count, :integer, default: 0
      add :deps_vulnerable_count, :integer, default: 0

      # Codebase metrics
      add :loc_count, :integer
      add :file_count, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_state, [:project_id])
    create index(:project_state, [:synced_at])
    create index(:project_state, [:ci_status])
  end
end
```

## Code to Extract from portfolio_coder

### Scanner Functions (~200 LOC)

Extract from `/home/home/p/g/n/portfolio_coder/lib/portfolio_coder/portfolio/scanner.ex`:

```elixir
# These functions are pure and can be copied directly:

# Language detection (lines 92-127)
defp detect_language(repo_path) do
  cond do
    File.exists?(Path.join(repo_path, "mix.exs")) -> :elixir
    File.exists?(Path.join(repo_path, "rebar.config")) -> :erlang
    File.exists?(Path.join(repo_path, "requirements.txt")) -> :python
    File.exists?(Path.join(repo_path, "pyproject.toml")) -> :python
    File.exists?(Path.join(repo_path, "setup.py")) -> :python
    File.exists?(Path.join(repo_path, "package.json")) -> :javascript
    File.exists?(Path.join(repo_path, "Cargo.toml")) -> :rust
    File.exists?(Path.join(repo_path, "go.mod")) -> :go
    File.exists?(Path.join(repo_path, "Gemfile")) -> :ruby
    File.exists?(Path.join(repo_path, "pom.xml")) -> :java
    File.exists?(Path.join(repo_path, "build.gradle")) -> :java
    true -> nil
  end
end

# Type detection (lines 129-160)
defp detect_type(repo_path, language) do
  case language do
    :elixir -> detect_elixir_type(repo_path)
    :javascript -> detect_javascript_type(repo_path)
    _ -> :unknown
  end
end

# Git remote extraction (lines 162-185)
def extract_remotes(repo_path) do
  case System.cmd("git", ["-C", repo_path, "remote", "-v"], stderr_to_stdout: true) do
    {output, 0} -> parse_remotes(output)
    _ -> []
  end
end

# Dependency extraction - Elixir (lines 198-230)
def extract_elixir_dependencies(mix_exs_path) do
  # Parse mix.exs for {:dep, "version"} patterns
  # Returns %{runtime: [...], dev: [...]}
end

# Dependency extraction - Python (lines 232-255)
def extract_python_dependencies(repo_path) do
  # Parse requirements.txt
end

# Dependency extraction - JavaScript (lines 257-280)
def extract_javascript_dependencies(package_json_path) do
  # Parse package.json dependencies and devDependencies
end
```

### Syncer Functions (~150 LOC)

Extract from `/home/home/p/g/n/portfolio_coder/lib/portfolio_coder/portfolio/syncer.ex`:

```elixir
# Git info extraction (lines 139-184)
def get_git_info(repo_path) do
  with {:ok, last_commit} <- get_last_commit(repo_path),
       {:ok, commit_count} <- get_commit_count_30d(repo_path),
       {:ok, branch} <- get_current_branch(repo_path) do
    {:ok, %{
      last_commit: last_commit,
      commit_count_30d: commit_count,
      current_branch: branch
    }}
  end
end

defp get_last_commit(repo_path) do
  case System.cmd("git", ["-C", repo_path, "log", "-1", "--format=%H|%s|%ai"], stderr_to_stdout: true) do
    {output, 0} ->
      [sha, message, date] = String.split(String.trim(output), "|", parts: 3)
      {:ok, %{sha: String.slice(sha, 0, 8), message: message, date: date}}
    _ ->
      {:error, :no_commits}
  end
end

defp get_commit_count_30d(repo_path) do
  since = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()
  case System.cmd("git", ["-C", repo_path, "rev-list", "--count", "--since=#{since}", "HEAD"], stderr_to_stdout: true) do
    {output, 0} -> {:ok, String.trim(output) |> String.to_integer()}
    _ -> {:ok, 0}
  end
end

defp get_current_branch(repo_path) do
  case System.cmd("git", ["-C", repo_path, "rev-parse", "--abbrev-ref", "HEAD"], stderr_to_stdout: true) do
    {output, 0} -> {:ok, String.trim(output)}
    _ -> {:error, :not_git}
  end
end
```

## New Implementation Required

### 1. Project Scanner Module

```elixir
# lib/command/projects/scanner.ex
defmodule Command.Projects.Scanner do
  @moduledoc """
  Scans filesystem for git repositories and extracts metadata.
  Adapted from portfolio_coder's Scanner module.
  """

  # Copy detect_language/1, detect_type/2, extract_remotes/1 from portfolio_coder
  # Add new functions:

  @doc """
  Scan a directory for git repositories and return project attrs.
  """
  def scan_directory(path, opts \\ []) do
    # ... implementation
  end

  @doc """
  Check if repo has uncommitted changes.
  """
  def git_dirty?(repo_path) do
    case System.cmd("git", ["-C", repo_path, "status", "--porcelain"], stderr_to_stdout: true) do
      {"", 0} -> false
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Get ahead/behind counts relative to remote.
  """
  def get_remote_status(repo_path) do
    case System.cmd("git", ["-C", repo_path, "rev-list", "--left-right", "--count", "HEAD...@{u}"],
           stderr_to_stdout: true) do
      {output, 0} ->
        [ahead, behind] = output |> String.trim() |> String.split("\t") |> Enum.map(&String.to_integer/1)
        {:ok, %{ahead: ahead, behind: behind}}
      _ ->
        {:ok, %{ahead: 0, behind: 0}}
    end
  end

  @doc """
  Run tests and capture results (language-specific).
  """
  def run_tests(repo_path, language, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    case language do
      :elixir -> run_elixir_tests(repo_path, timeout)
      :python -> run_python_tests(repo_path, timeout)
      :javascript -> run_javascript_tests(repo_path, timeout)
      _ -> {:ok, %{status: :unknown, count: nil, passed: nil, failed: nil}}
    end
  end

  defp run_elixir_tests(repo_path, timeout) do
    case System.cmd("mix", ["test", "--no-color"],
           cd: repo_path,
           stderr_to_stdout: true,
           env: [{"MIX_ENV", "test"}]) do
      {output, 0} ->
        {count, passed} = parse_elixir_test_output(output)
        {:ok, %{status: :pass, count: count, passed: passed, failed: 0}}
      {output, _} ->
        {count, passed, failed} = parse_elixir_test_output(output)
        {:ok, %{status: :fail, count: count, passed: passed, failed: failed}}
    end
  end

  # ... similar for Python, JavaScript
end
```

### 2. Sync Worker (Oban)

```elixir
# lib/command/projects/sync_worker.ex
defmodule Command.Projects.SyncWorker do
  use Oban.Worker,
    queue: :project_sync,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing]]

  alias Command.Projects
  alias Command.Projects.Scanner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    project = Projects.get_project!(project_id)
    sync_project(project)
  end

  def perform(%Oban.Job{args: %{"action" => "sync_all", "user_id" => user_id}}) do
    projects = Projects.list_projects(user_id: user_id)

    for project <- projects do
      %{"project_id" => project.id}
      |> __MODULE__.new(schedule_in: :rand.uniform(60))
      |> Oban.insert()
    end

    :ok
  end

  defp sync_project(project) do
    with {:ok, git_info} <- Scanner.get_git_info(project.path),
         {:ok, remote_status} <- Scanner.get_remote_status(project.path),
         dirty <- Scanner.git_dirty?(project.path) do

      state_attrs = %{
        synced_at: DateTime.utc_now(),
        current_branch: git_info.current_branch,
        last_commit_sha: git_info.last_commit.sha,
        last_commit_message: git_info.last_commit.message,
        last_commit_at: parse_git_date(git_info.last_commit.date),
        commit_count_30d: git_info.commit_count_30d,
        ahead: remote_status.ahead,
        behind: remote_status.behind,
        git_dirty: dirty
      }

      Projects.update_state(project, state_attrs)
    end
  end
end
```

### 3. Oban Configuration

```elixir
# config/config.exs
config :command, Oban,
  repo: Command.Repo,
  queues: [
    default: 10,
    project_sync: 5
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", Command.Projects.SyncWorker, args: %{"action" => "sync_stale"}}
     ]}
  ]
```

### 4. Alternative: Use Command.Scheduling

If Oban is not desired, use the existing scheduling system:

```elixir
# Create scheduled job
Command.Scheduling.create_scheduled_job(%{
  name: "project_sync_hourly",
  job_type: "custom",
  schedule_type: "interval",
  interval_seconds: 3600,
  job_config: %{
    module: "Command.Projects.Syncer",
    function: "sync_all_stale",
    args: []
  },
  user_id: system_user_id
})

# Handler module
defmodule Command.Projects.Syncer do
  def sync_all_stale do
    stale_threshold = DateTime.add(DateTime.utc_now(), -3600, :second)

    Command.Projects.list_projects()
    |> Enum.filter(fn p ->
      is_nil(p.state) or is_nil(p.state.synced_at) or
        DateTime.compare(p.state.synced_at, stale_threshold) == :lt
    end)
    |> Enum.each(&sync_project/1)
  end

  defp sync_project(project) do
    # ... same as SyncWorker
  end
end
```

## Integration Points

### 1. Agent Tools

```elixir
# lib/command/agents/tools/project_tools.ex
defmodule Command.Agents.Tools.ProjectTools do
  @moduledoc "Agent tools for querying and managing projects"

  def get_work_queue(user_id, opts \\ []) do
    Command.Projects.list_by_priority(user_id, Keyword.get(opts, :max_priority, 3))
    |> Enum.map(&format_for_agent/1)
  end

  def get_blocked_projects(user_id) do
    Command.Projects.list_blocked_projects(user_id: user_id)
    |> Enum.map(&format_blocked_for_agent/1)
  end

  def get_project_context(slug) do
    project = Command.Projects.get_project_by_slug(slug)
    state = Command.Projects.get_state(project)
    decisions = Command.Projects.list_decisions(project, status: "accepted")

    %{
      project: format_for_agent(project),
      state: format_state(state),
      decisions: Enum.map(decisions, &format_decision/1)
    }
  end

  # ... formatting helpers
end
```

### 2. Session Linking

```elixir
# Add to sessions schema
schema "sessions" do
  # ... existing fields
  belongs_to :project, Command.Projects.Project  # Optional: link session to project
end

# Or use metadata
session = %Session{
  metadata: %{
    project_id: project.id,
    project_slug: project.slug
  }
}
```

### 3. PubSub Events

```elixir
# lib/command/projects.ex
defp broadcast_change(project, event) do
  Command.PubSub.broadcast("project:#{project.id}", event, project)
  Command.PubSub.broadcast("user:#{project.user_id}:projects", event, project)

  if event in [:blocked, :unblocked] do
    Command.PubSub.broadcast("projects:blocked", event, project)
  end
end
```

## Testing Strategy

### Unit Tests

```elixir
# test/command/projects_test.exs
defmodule Command.ProjectsTest do
  use Command.DataCase

  alias Command.Projects

  describe "projects" do
    test "create_project/2 with valid attrs" do
      user = insert(:user)
      attrs = %{name: "Test", slug: "test", path: "/tmp/test"}

      assert {:ok, project} = Projects.create_project(user, attrs)
      assert project.status == "active"
      assert project.priority == 3
    end

    test "blocking a project creates relationship" do
      project = insert(:project)
      blocker = insert(:project)

      assert {:ok, _} = Projects.block_project(project, "Waiting for release", blocker)
      assert Projects.blocked?(project)

      [rel] = Projects.get_blockers(project)
      assert rel.to_project_id == blocker.id
    end
  end
end
```

### Scanner Tests

```elixir
# test/command/projects/scanner_test.exs
defmodule Command.Projects.ScannerTest do
  use ExUnit.Case

  alias Command.Projects.Scanner

  describe "detect_language/1" do
    test "detects Elixir from mix.exs" do
      # Create temp dir with mix.exs
      assert Scanner.detect_language(tmp_dir) == :elixir
    end
  end

  describe "get_git_info/1" do
    test "extracts commit info from git repo" do
      # Use a real git repo or create mock
    end
  end
end
```

## Dependency Summary

| Dependency | Required? | Source |
|------------|-----------|--------|
| Ecto 3.11+ | Yes | Already in command |
| PostgreSQL | Yes | Already configured |
| Command.Accounts | Yes | For user ownership |
| Command.PubSub | Yes | For real-time events |
| Oban (optional) | Recommended | For background sync |
| Command.Scheduling | Alternative | If not using Oban |
| portfolio_coder | Optional | Extract Scanner/Syncer logic |

## Implementation Order

1. **Phase 1: Core schemas** (2-3 hours)
   - Create migrations
   - Define schema modules
   - Basic CRUD in context

2. **Phase 2: Scanner adaptation** (2-3 hours)
   - Copy pure functions from portfolio_coder
   - Adapt for Ecto output
   - Add git dirty/ahead/behind detection

3. **Phase 3: Relationships & decisions** (2 hours)
   - Relationship CRUD
   - Decision CRUD
   - Blocking logic

4. **Phase 4: Sync infrastructure** (2-3 hours)
   - Choose Oban vs Scheduling
   - Implement SyncWorker
   - Configure periodic sync

5. **Phase 5: YAML migration** (1-2 hours)
   - Migration script
   - Test with real data
   - Verify relationships

6. **Phase 6: Agent integration** (2 hours)
   - Project tools for agents
   - Session linking
   - Query helpers

7. **Phase 7: CLI commands** (2 hours)
   - mix command.projects tasks
   - List, show, block, decide commands

**Total estimated: 15-18 hours**

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Scanner runs slow on large repos | Add timeout, limit test runs |
| Test execution dangerous | Sandbox, skip by default, opt-in flag |
| YAML migration data loss | Backup YAMLs, dry-run mode, validation |
| Sync storms on startup | Stagger initial sync, rate limit |
| Git commands fail | Graceful degradation, mark sync failed |

---

## Additional Migrations (Expanded Scope)

Based on design review, add these migrations:

### 20260115000005_create_session_projects.exs

```elixir
defmodule Command.Repo.Migrations.CreateSessionProjects do
  use Ecto.Migration

  def change do
    create table(:session_projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, references(:sessions, type: :binary_id, on_delete: :delete_all), null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false

      add :role, :string, null: false, default: "primary"  # primary, secondary, reference
      add :files_touched, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:session_projects, [:session_id])
    create index(:session_projects, [:project_id])
    create unique_index(:session_projects, [:session_id, :project_id])
  end
end
```

### 20260115000006_create_project_workflow_triggers.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjectWorkflowTriggers do
  use Ecto.Migration

  def change do
    create table(:project_workflow_triggers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :workflow_id, references(:workflows, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :trigger_on, :string, null: false, default: "state_change"  # state_change, schedule

      # Condition DSL: JSON expression evaluated against ProjectState
      add :condition, :map, null: false, default: %{}
      # Examples:
      # %{"ci_status" => "passing"}
      # %{"test_fail_count" => %{"$gt" => 0}}
      # %{"$and" => [%{"ci_status" => "passing"}, %{"priority" => %{"$lte" => 2}}]}

      # Which projects this trigger applies to
      add :project_match, :map, null: false, default: %{}
      # Examples:
      # %{"tags" => ["crucible"]}
      # %{"language" => "elixir", "priority" => %{"$lte" => 2}}

      # Input template for workflow (supports {{project.slug}} interpolation)
      add :workflow_input, :map, null: false, default: %{}

      add :last_triggered_at, :utc_datetime_usec
      add :trigger_count, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:project_workflow_triggers, [:user_id])
    create index(:project_workflow_triggers, [:workflow_id])
    create index(:project_workflow_triggers, [:enabled])
  end
end
```

### 20260115000007_add_focus_tracking_to_projects.exs

```elixir
defmodule Command.Repo.Migrations.AddFocusTrackingToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :focus_updated_at, :utc_datetime_usec
      add :focus_updated_by, :string  # "user", "agent:debug", "workflow:xyz"
    end
  end
end
```

### 20260115000008_add_blocker_type_to_relationships.exs

```elixir
defmodule Command.Repo.Migrations.AddBlockerTypeToRelationships do
  use Ecto.Migration

  def change do
    alter table(:project_relationships) do
      add :blocker_type, :string  # project, dependency, external_event, decision_pending, other
      add :blocker_details, :map, null: false, default: %{}
    end

    create index(:project_relationships, [:blocker_type])
  end
end
```

### 20260115000009_add_ecosystem_to_decisions.exs

```elixir
defmodule Command.Repo.Migrations.AddEcosystemToDecisions do
  use Ecto.Migration

  def change do
    alter table(:project_decisions) do
      add :scope, :string, null: false, default: "project"  # project, ecosystem
      add :ecosystem_tag, :string  # "crucible", "portfolio", "all"
      add :related_decision_ids, {:array, :binary_id}, null: false, default: []
    end

    # Allow project_id to be null for ecosystem decisions
    execute "ALTER TABLE project_decisions ALTER COLUMN project_id DROP NOT NULL"

    create index(:project_decisions, [:scope])
    create index(:project_decisions, [:ecosystem_tag])
  end
end
```

---

## Updated File Structure

```
lib/command/
├── projects/
│   ├── project.ex                    # Project schema
│   ├── relationship.ex               # ProjectRelationship schema
│   ├── decision.ex                   # ProjectDecision schema
│   ├── project_state.ex              # ProjectState schema
│   ├── session_project.ex            # SessionProject join schema (NEW)
│   ├── workflow_trigger.ex           # ProjectWorkflowTrigger schema (NEW)
│   ├── scanner.ex                    # Git/language detection
│   ├── signals.ex                    # Synapse signal definitions (NEW)
│   ├── tools.ex                      # ALTAR tool definitions (NEW)
│   └── tool_handler.ex               # Tool execution handler (NEW)
├── projects.ex                       # Context module (CRUD, queries)
└── projects/
    ├── sync_worker.ex                # Oban worker for sync
    └── trigger_evaluator.ex          # Workflow trigger evaluation (NEW)

priv/repo/migrations/
├── 20260115000001_create_projects.exs
├── 20260115000002_create_project_relationships.exs
├── 20260115000003_create_project_decisions.exs
├── 20260115000004_create_project_state.exs
├── 20260115000005_create_session_projects.exs             # NEW
├── 20260115000006_create_project_workflow_triggers.exs    # NEW
├── 20260115000007_add_focus_tracking_to_projects.exs      # NEW
├── 20260115000008_add_blocker_type_to_relationships.exs   # NEW
└── 20260115000009_add_ecosystem_to_decisions.exs          # NEW
```

---

## Synapse Signal Integration

### Signal Module

```elixir
# lib/command/projects/signals.ex
defmodule Command.Projects.Signals do
  @moduledoc "Synapse signal type definitions for project events"

  @signal_types %{
    # Status transitions
    project_created: "project.created",
    project_status_changed: "project.status.changed",
    project_blocked: "project.blocked",
    project_unblocked: "project.unblocked",
    project_archived: "project.archived",

    # Sync events
    project_synced: "project.synced",
    project_ci_changed: "project.ci.changed",
    project_tests_failed: "project.tests.failed",
    project_tests_passed: "project.tests.passed",

    # Priority changes
    project_priority_changed: "project.priority.changed",
    project_escalated: "project.escalated",

    # Relationship changes
    project_dependency_added: "project.dependency.added",
    project_blocker_added: "project.blocker.added",
    project_blocker_removed: "project.blocker.removed",

    # Focus changes
    project_focus_changed: "project.focus.changed"
  }

  @doc "Get signal type string for an event atom"
  def signal_type(event), do: Map.get(@signal_types, event)

  @doc "List all signal type strings"
  def all_types, do: Map.values(@signal_types)

  @doc "List all event atoms"
  def all_events, do: Map.keys(@signal_types)
end
```

### Signal Emission in Context

```elixir
# lib/command/projects.ex (additions)
defmodule Command.Projects do
  alias Command.Projects.Signals

  # After successful operations, emit signals
  def set_status(project, new_status, reason \\ nil) do
    old_status = project.status

    with {:ok, updated} <- do_update_status(project, new_status, reason) do
      # Emit signal based on transition
      event = cond do
        new_status == "blocked" -> :project_blocked
        old_status == "blocked" -> :project_unblocked
        new_status == "archived" -> :project_archived
        true -> :project_status_changed
      end

      emit_signal(event, updated, %{
        from_status: old_status,
        to_status: new_status,
        reason: reason
      })

      # Check workflow triggers on state change
      maybe_evaluate_triggers(updated)

      {:ok, updated}
    end
  end

  def update_state(project, attrs) do
    old_state = get_state(project)

    with {:ok, state} <- do_update_state(project, attrs) do
      # Detect what changed
      if state_transition?(old_state, state, :ci_status) do
        emit_signal(:project_ci_changed, project, %{
          from: old_state && old_state.ci_status,
          to: state.ci_status
        })
      end

      if test_status_changed?(old_state, state) do
        event = if state.test_fail_count > 0, do: :project_tests_failed, else: :project_tests_passed
        emit_signal(event, project, %{
          test_count: state.test_count,
          pass_count: state.test_pass_count,
          fail_count: state.test_fail_count
        })
      end

      emit_signal(:project_synced, project, %{synced_at: state.synced_at})

      # Check workflow triggers
      maybe_evaluate_triggers(project, old_state, state)

      {:ok, state}
    end
  end

  defp emit_signal(event, project, payload) do
    if Command.Orchestration.enabled?() do
      signal_type = Signals.signal_type(event)

      Command.Orchestration.publish(
        signal_type,
        Map.merge(payload, %{
          project_id: project.id,
          project_slug: project.slug,
          project_name: project.name,
          project_priority: project.priority,
          timestamp: DateTime.utc_now()
        }),
        command_user_id: project.user_id
      )
    end

    # Also broadcast to PubSub for UI updates
    broadcast_change(project, event)
  end
end
```

### SignalBridge Extension

```elixir
# In lib/command/orchestration/signal_bridge.ex, add to handle_info:
@impl true
def handle_info({:signal, %Jido.Signal{} = signal}, state) do
  _ =
    case Signal.topic_from_type(signal.type) do
      {:ok, topic} ->
        _ = PubSub.broadcast("synapse:signals:#{topic}", :synapse_signal, signal)
        _ = maybe_broadcast_session(signal)
        _ = maybe_broadcast_workflow(signal)
        _ = maybe_broadcast_project(signal)  # NEW

      :error ->
        :ok
    end

  {:noreply, state}
end

# NEW: Add project routing
defp maybe_broadcast_project(signal) do
  case extract_signal_field(signal, "project_id") do
    nil -> :ok
    project_id ->
      PubSub.broadcast("project:#{project_id}:signals", :synapse_signal, signal)
  end
end
```

---

## Workflow Trigger Evaluator

```elixir
# lib/command/projects/trigger_evaluator.ex
defmodule Command.Projects.TriggerEvaluator do
  @moduledoc "Evaluates workflow triggers based on project state changes"

  alias Command.Projects
  alias Command.Projects.WorkflowTrigger
  alias Command.Workflows
  import Ecto.Query

  @doc "Evaluate all enabled triggers for a project state change"
  def evaluate(project, old_state, new_state) do
    triggers = list_matching_triggers(project)

    for trigger <- triggers,
        condition_newly_met?(trigger.condition, old_state, new_state) do
      trigger_workflow(trigger, project, new_state)
    end
  end

  defp list_matching_triggers(project) do
    from(t in WorkflowTrigger,
      where: t.user_id == ^project.user_id,
      where: t.enabled == true,
      where: t.trigger_on == "state_change"
    )
    |> Command.Repo.all()
    |> Enum.filter(&project_matches?(&1.project_match, project))
  end

  defp project_matches?(%{} = match, project) when map_size(match) == 0, do: true
  defp project_matches?(match, project) do
    Enum.all?(match, fn {key, expected} ->
      actual = Map.get(project, String.to_existing_atom(key))
      matches_value?(actual, expected)
    end)
  end

  defp matches_value?(actual, %{"$lte" => val}), do: actual <= val
  defp matches_value?(actual, %{"$gte" => val}), do: actual >= val
  defp matches_value?(actual, %{"$in" => list}), do: actual in list
  defp matches_value?(actual, expected) when is_list(expected), do: Enum.any?(expected, &(&1 in actual))
  defp matches_value?(actual, expected), do: actual == expected

  defp condition_newly_met?(condition, old_state, new_state) do
    # Only trigger on transition: NOT met before, NOW met
    not condition_met?(condition, old_state) and condition_met?(condition, new_state)
  end

  defp condition_met?(condition, nil), do: false
  defp condition_met?(condition, state) do
    Enum.all?(condition, fn {key, expected} ->
      actual = Map.get(state, String.to_existing_atom(key))
      matches_value?(actual, expected)
    end)
  end

  defp trigger_workflow(trigger, project, state) do
    input = interpolate_input(trigger.workflow_input, project, state)

    {:ok, run} = Workflows.create_workflow_run(trigger.workflow_id, %{
      user_id: project.user_id,
      trigger_type: "project_state",
      trigger_metadata: %{
        project_id: project.id,
        project_slug: project.slug,
        trigger_id: trigger.id,
        trigger_name: trigger.name
      },
      input: input
    })

    # Update trigger stats
    Projects.update_trigger_stats(trigger)

    run
  end

  defp interpolate_input(template, project, state) do
    template
    |> Jason.encode!()
    |> String.replace("{{project.id}}", project.id)
    |> String.replace("{{project.slug}}", project.slug)
    |> String.replace("{{project.name}}", project.name)
    |> String.replace("{{project.path}}", project.path || "")
    |> String.replace("{{state.ci_status}}", state.ci_status || "")
    |> String.replace("{{state.current_branch}}", state.current_branch || "")
    |> Jason.decode!()
  end
end
```

---

## Revised Implementation Order

1. **Phase 1: Core schemas** (2-3 hours)
   - Create all 9 migrations
   - Define all schema modules
   - Basic CRUD in context

2. **Phase 2: Scanner adaptation** (2-3 hours)
   - Copy pure functions from portfolio_coder
   - Adapt for Ecto output
   - Add git dirty/ahead/behind detection

3. **Phase 3: Relationships & decisions** (2-3 hours)
   - Relationship CRUD with blocker_type
   - Decision CRUD with ecosystem scope
   - Blocking/unblocking logic

4. **Phase 4: Session linking** (1-2 hours)
   - SessionProject schema and context functions
   - Auto-linking from file paths
   - Query helpers

5. **Phase 5: Sync infrastructure** (2-3 hours)
   - SyncWorker with Oban
   - CI status fetching (GitHub Actions API)
   - Configure periodic sync

6. **Phase 6: Synapse signals** (2 hours)
   - Signals module
   - Emit signals on all state changes
   - SignalBridge extension

7. **Phase 7: Workflow triggers** (3-4 hours)
   - TriggerEvaluator module
   - Condition DSL evaluation
   - Integration with state updates

8. **Phase 8: Agent tools** (2-3 hours)
   - ALTAR tool definitions
   - ToolHandler execution
   - Integration with ToolUse lifecycle

9. **Phase 9: YAML migration** (1-2 hours)
   - Migration script
   - Test with real data
   - Verify relationships

10. **Phase 10: CLI commands** (2 hours)
    - mix command.projects tasks
    - List, show, block, decide, trigger commands

**Revised total: 20-25 hours**

---

## Updated Dependency Summary

| Dependency | Required? | Purpose |
|------------|-----------|---------|
| Ecto 3.11+ | Yes | Database layer |
| PostgreSQL + extensions | Yes | Storage (citext, pg_trgm, btree_gin) |
| Command.Accounts | Yes | User ownership |
| Command.Sessions | Yes | Session linking |
| Command.Workflows | Yes | Workflow triggers |
| Command.PubSub | Yes | Real-time events |
| Command.Orchestration | Yes | Synapse signals |
| Oban | Recommended | Background sync jobs |
| Altar.ADM | Yes | Tool definitions |
| portfolio_coder | Optional | Extract Scanner/Syncer logic |

---

## Testing Additions

### Trigger Evaluator Tests

```elixir
defmodule Command.Projects.TriggerEvaluatorTest do
  use Command.DataCase

  alias Command.Projects.TriggerEvaluator

  describe "condition_met?/2" do
    test "simple equality" do
      condition = %{"ci_status" => "passing"}
      state = %ProjectState{ci_status: "passing"}
      assert TriggerEvaluator.condition_met?(condition, state)
    end

    test "comparison operators" do
      condition = %{"test_fail_count" => %{"$gt" => 0}}
      failing_state = %ProjectState{test_fail_count: 5}
      passing_state = %ProjectState{test_fail_count: 0}

      assert TriggerEvaluator.condition_met?(condition, failing_state)
      refute TriggerEvaluator.condition_met?(condition, passing_state)
    end
  end

  describe "evaluate/3" do
    test "triggers workflow on state transition" do
      project = insert(:project)
      trigger = insert(:workflow_trigger, user_id: project.user_id,
        condition: %{"ci_status" => "passing"})

      old_state = %ProjectState{ci_status: "failing"}
      new_state = %ProjectState{ci_status: "passing"}

      [run] = TriggerEvaluator.evaluate(project, old_state, new_state)
      assert run.trigger_type == "project_state"
    end

    test "does not trigger if condition was already met" do
      # Condition already met = no trigger
    end
  end
end
```

### Signal Tests

```elixir
defmodule Command.Projects.SignalsTest do
  use Command.DataCase

  test "emits project_blocked signal on status change" do
    project = insert(:project, status: "active")

    # Subscribe to signals
    Command.PubSub.subscribe("project:#{project.id}")

    # Block the project
    {:ok, _} = Projects.set_status(project, "blocked", "Waiting for release")

    # Assert signal received
    assert_receive {:project_blocked, _payload}
  end
end
```

---

## Bulk Execution System Implementation

### Additional Migrations

#### 20260115000010_create_project_changesets.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjectChangesets do
  use Ecto.Migration

  def change do
    create table(:project_changesets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :workflow_run_id, references(:workflow_runs, type: :binary_id, on_delete: :nilify_all)

      add :name, :string, null: false
      add :status, :string, null: false, default: "preview"
      add :operation_type, :string, null: false

      # The command/template to execute
      add :operation, :map, null: false, default: %{}

      # Project selection filter
      add :project_filter, :map, null: false, default: %{}

      # Execution options
      add :parallelism, :integer, null: false, default: 4
      add :on_failure, :string, null: false, default: "continue"
      add :timeout_ms, :integer, null: false, default: 60_000

      # Results tracking
      add :preview_count, :integer, null: false, default: 0
      add :success_count, :integer, null: false, default: 0
      add :failure_count, :integer, null: false, default: 0
      add :skipped_count, :integer, null: false, default: 0

      # Timing
      add :previewed_at, :utc_datetime_usec
      add :confirmed_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:project_changesets, [:user_id])
    create index(:project_changesets, [:status])
    create index(:project_changesets, [:workflow_run_id])
    create index(:project_changesets, [:created_at])
  end
end
```

#### 20260115000011_create_project_changeset_items.exs

```elixir
defmodule Command.Repo.Migrations.CreateProjectChangesetItems do
  use Ecto.Migration

  def change do
    create table(:project_changeset_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :changeset_id, references(:project_changesets, type: :binary_id, on_delete: :delete_all), null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :cascade), null: false

      add :status, :string, null: false, default: "pending"
      add :excluded, :boolean, null: false, default: false

      # Resolved operation for this specific project
      add :resolved_operation, :map, null: false, default: %{}

      # Execution results
      add :output, :text
      add :error, :text
      add :exit_code, :integer
      add :duration_ms, :integer

      # Timing
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:project_changeset_items, [:changeset_id])
    create index(:project_changeset_items, [:project_id])
    create index(:project_changeset_items, [:status])
    create unique_index(:project_changeset_items, [:changeset_id, :project_id])
  end
end
```

### Schema Modules

#### lib/command/projects/changeset.ex

```elixir
defmodule Command.Projects.ChangeSet do
  @moduledoc "Represents a bulk operation across multiple projects"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(preview confirmed executing completed failed cancelled)
  @operation_types ~w(shell file_write git_commit dependency_update custom)
  @failure_modes ~w(continue halt)

  schema "project_changesets" do
    field :name, :string
    field :status, :string, default: "preview"
    field :operation_type, :string

    field :operation, :map, default: %{}
    field :project_filter, :map, default: %{}

    field :parallelism, :integer, default: 4
    field :on_failure, :string, default: "continue"
    field :timeout_ms, :integer, default: 60_000

    field :preview_count, :integer, default: 0
    field :success_count, :integer, default: 0
    field :failure_count, :integer, default: 0
    field :skipped_count, :integer, default: 0

    field :previewed_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    field :metadata, :map, default: %{}

    belongs_to :user, Command.Accounts.User
    belongs_to :workflow_run, Command.Workflows.WorkflowRun
    has_many :items, Command.Projects.ChangeSetItem

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:name, :operation_type, :operation, :project_filter,
                    :parallelism, :on_failure, :timeout_ms, :user_id,
                    :workflow_run_id, :metadata])
    |> validate_required([:name, :operation_type, :operation, :user_id])
    |> validate_inclusion(:operation_type, @operation_types)
    |> validate_inclusion(:on_failure, @failure_modes)
    |> validate_number(:parallelism, greater_than: 0, less_than_or_equal_to: 20)
    |> validate_number(:timeout_ms, greater_than: 0, less_than_or_equal_to: 600_000)
    |> validate_operation()
  end

  def status_changeset(changeset, status, attrs \\ %{}) do
    now = DateTime.utc_now()

    timing_field = case status do
      "preview" -> :previewed_at
      "confirmed" -> :confirmed_at
      "executing" -> :started_at
      "completed" -> :completed_at
      "failed" -> :completed_at
      "cancelled" -> :completed_at
      _ -> nil
    end

    attrs = if timing_field, do: Map.put(attrs, timing_field, now), else: attrs

    changeset
    |> cast(Map.put(attrs, :status, status), [:status, timing_field] |> Enum.filter(&(&1)))
    |> validate_inclusion(:status, @statuses)
  end

  def counts_changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:preview_count, :success_count, :failure_count, :skipped_count])
  end

  defp validate_operation(changeset) do
    operation_type = get_field(changeset, :operation_type)
    operation = get_field(changeset, :operation) || %{}

    case operation_type do
      "shell" ->
        if is_nil(operation["command"]) or operation["command"] == "" do
          add_error(changeset, :operation, "must include 'command' for shell operations")
        else
          changeset
        end

      "file_write" ->
        cond do
          is_nil(operation["file"]) -> add_error(changeset, :operation, "must include 'file' for file_write")
          is_nil(operation["content"]) -> add_error(changeset, :operation, "must include 'content' for file_write")
          true -> changeset
        end

      "git_commit" ->
        if is_nil(operation["command"]) do
          add_error(changeset, :operation, "must include 'command' for git operations")
        else
          changeset
        end

      _ ->
        changeset
    end
  end
end
```

#### lib/command/projects/changeset_item.ex

```elixir
defmodule Command.Projects.ChangeSetItem do
  @moduledoc "Tracks a single project's status within a bulk changeset"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending running success failed skipped excluded)

  schema "project_changeset_items" do
    field :status, :string, default: "pending"
    field :excluded, :boolean, default: false

    field :resolved_operation, :map, default: %{}

    field :output, :string
    field :error, :string
    field :exit_code, :integer
    field :duration_ms, :integer

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :changeset, Command.Projects.ChangeSet
    belongs_to :project, Command.Projects.Project

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(item, attrs) do
    item
    |> cast(attrs, [:changeset_id, :project_id, :resolved_operation, :excluded])
    |> validate_required([:changeset_id, :project_id])
    |> unique_constraint([:changeset_id, :project_id])
  end

  def execution_changeset(item, status, attrs \\ %{}) do
    now = DateTime.utc_now()

    attrs = case status do
      "running" -> Map.put(attrs, :started_at, now)
      status when status in ["success", "failed", "skipped"] ->
        attrs
        |> Map.put(:completed_at, now)
        |> maybe_add_duration(item)
      _ -> attrs
    end

    item
    |> cast(Map.put(attrs, :status, status), [:status, :output, :error, :exit_code,
                                               :duration_ms, :started_at, :completed_at])
    |> validate_inclusion(:status, @statuses)
  end

  def exclude_changeset(item, excluded) do
    status = if excluded, do: "excluded", else: "pending"

    item
    |> cast(%{excluded: excluded, status: status}, [:excluded, :status])
  end

  defp maybe_add_duration(attrs, %{started_at: started_at}) when not is_nil(started_at) do
    duration = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    Map.put(attrs, :duration_ms, duration)
  end
  defp maybe_add_duration(attrs, _), do: attrs
end
```

### Executor Module

```elixir
# lib/command/projects/changeset_executor.ex
defmodule Command.Projects.ChangeSetExecutor do
  @moduledoc """
  Executes changeset operations across projects with controlled parallelism.
  """

  require Logger
  alias Command.Projects
  alias Command.Projects.{ChangeSet, ChangeSetItem}
  alias Command.Repo

  @blocked_patterns [
    ~r/sudo\s/,
    ~r/rm\s+-rf?\s+\//,
    ~r/DROP\s+TABLE/i,
    ~r/DELETE\s+FROM\s+\w+\s*;/i,
    ~r/TRUNCATE/i
  ]

  @requires_destructive_flag [
    ~r/--force/,
    ~r/--hard/,
    ~r/\s-f\s/
  ]

  @doc "Preview a changeset - resolve templates and create items"
  def preview(%ChangeSet{status: "preview"} = changeset) do
    projects = Projects.list_projects_matching(changeset.project_filter, user_id: changeset.user_id)

    items = Enum.map(projects, fn project ->
      resolved = resolve_operation(changeset.operation, project)
      %{
        changeset_id: changeset.id,
        project_id: project.id,
        resolved_operation: resolved
      }
    end)

    Repo.transaction(fn ->
      # Delete existing items (in case of re-preview)
      Repo.delete_all(from i in ChangeSetItem, where: i.changeset_id == ^changeset.id)

      # Insert new items
      {count, _} = Repo.insert_all(ChangeSetItem, items,
        returning: false,
        on_conflict: :nothing)

      # Update changeset counts
      {:ok, updated} = changeset
        |> ChangeSet.status_changeset("preview", %{preview_count: count})
        |> Repo.update()

      updated
    end)
  end

  @doc "Execute a confirmed changeset"
  def execute(%ChangeSet{status: "confirmed"} = changeset) do
    # Validate all operations before starting
    with :ok <- validate_all_operations(changeset) do
      # Mark as executing
      {:ok, changeset} = changeset
        |> ChangeSet.status_changeset("executing")
        |> Repo.update()

      # Get pending items
      items = Projects.list_changeset_items(changeset,
        status: ["pending"],
        excluded: false,
        preload: [:project])

      # Execute with controlled parallelism
      results = execute_items(items, changeset)

      # Update changeset with final counts
      finalize_changeset(changeset, results)
    end
  end

  @doc "Retry failed items in a changeset"
  def retry_failed(%ChangeSet{status: status} = changeset) when status in ["completed", "failed"] do
    # Reset failed items to pending
    items = Projects.list_changeset_items(changeset, status: ["failed"])

    Enum.each(items, fn item ->
      item
      |> ChangeSetItem.execution_changeset("pending", %{
        output: nil,
        error: nil,
        exit_code: nil,
        started_at: nil,
        completed_at: nil,
        duration_ms: nil
      })
      |> Repo.update()
    end)

    # Reset changeset to confirmed
    {:ok, changeset} = changeset
      |> ChangeSet.status_changeset("confirmed")
      |> Repo.update()

    # Execute again
    execute(changeset)
  end

  defp execute_items(items, changeset) do
    items
    |> Task.async_stream(
      fn item -> execute_item(item, changeset) end,
      max_concurrency: changeset.parallelism,
      timeout: changeset.timeout_ms + 5_000,  # Buffer for cleanup
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
    end)
  end

  defp execute_item(item, changeset) do
    # Mark as running
    {:ok, item} = item
      |> ChangeSetItem.execution_changeset("running")
      |> Repo.update()

    # Emit signal
    emit_item_signal(:changeset_item_started, changeset, item)

    # Execute based on operation type
    result = case changeset.operation_type do
      "shell" -> execute_shell(item, changeset)
      "file_write" -> execute_file_write(item)
      "git_commit" -> execute_shell(item, changeset)  # Same as shell
      _ -> {:error, "Unknown operation type: #{changeset.operation_type}"}
    end

    # Update item with result
    {status, attrs} = case result do
      {:ok, output} ->
        {"success", %{output: truncate_output(output), exit_code: 0}}

      {:error, %{output: output, exit_code: code}} ->
        {"failed", %{output: truncate_output(output), error: "Exit code: #{code}", exit_code: code}}

      {:error, reason} when is_binary(reason) ->
        {"failed", %{error: reason}}

      {:error, :timeout} ->
        {"failed", %{error: "Operation timed out after #{changeset.timeout_ms}ms"}}
    end

    {:ok, updated_item} = item
      |> ChangeSetItem.execution_changeset(status, attrs)
      |> Repo.update()

    # Emit completion signal
    emit_item_signal(:changeset_item_completed, changeset, updated_item)

    {status, updated_item}
  end

  defp execute_shell(item, changeset) do
    command = item.resolved_operation["command"]
    cwd = item.resolved_operation["cwd"] || item.project.path

    case System.cmd("sh", ["-c", command],
           cd: cwd,
           stderr_to_stdout: true,
           env: build_env(item.project)) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, %{output: output, exit_code: code}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp execute_file_write(item) do
    file = item.resolved_operation["file"]
    content = item.resolved_operation["content"]
    path = Path.join(item.project.path, file)

    # Ensure directory exists
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, content) do
      :ok -> {:ok, "Wrote #{byte_size(content)} bytes to #{file}"}
      {:error, reason} -> {:error, "Failed to write file: #{reason}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp resolve_operation(operation, project) do
    operation
    |> Map.new(fn {key, value} ->
      resolved = if is_binary(value) do
        value
        |> String.replace("{{project.id}}", project.id)
        |> String.replace("{{project.slug}}", project.slug)
        |> String.replace("{{project.name}}", project.name)
        |> String.replace("{{project.path}}", project.path || "")
        |> String.replace("{{project.language}}", project.language || "")
      else
        value
      end
      {key, resolved}
    end)
    |> Map.put("cwd", project.path)
  end

  defp build_env(project) do
    [
      {"PROJECT_ID", project.id},
      {"PROJECT_SLUG", project.slug},
      {"PROJECT_NAME", project.name},
      {"PROJECT_PATH", project.path || ""},
      {"PROJECT_LANGUAGE", project.language || ""}
    ]
  end

  defp validate_all_operations(changeset) do
    items = Projects.list_changeset_items(changeset, excluded: false)

    errors = items
      |> Enum.map(fn item ->
        command = item.resolved_operation["command"]
        validate_operation(command, changeset.metadata)
      end)
      |> Enum.filter(&match?({:error, _, _}, &1))

    case errors do
      [] -> :ok
      [{:error, type, message} | _] -> {:error, {type, message}}
    end
  end

  @doc "Validate a single operation command for safety"
  def validate_operation(nil, _opts), do: :ok
  def validate_operation(command, opts) when is_binary(command) do
    allow_destructive = opts["allow_destructive"] || false

    cond do
      Enum.any?(@blocked_patterns, &Regex.match?(&1, command)) ->
        {:error, :operation_blocked, "This operation type is not allowed in bulk execution"}

      not allow_destructive and Enum.any?(@requires_destructive_flag, &Regex.match?(&1, command)) ->
        {:error, :requires_flag, "This operation requires allow_destructive flag"}

      true ->
        :ok
    end
  end

  defp finalize_changeset(changeset, results) do
    counts = Enum.reduce(results, %{success: 0, failed: 0}, fn
      {"success", _}, acc -> %{acc | success: acc.success + 1}
      {"failed", _}, acc -> %{acc | failed: acc.failed + 1}
      _, acc -> acc
    end)

    # Also count excluded items
    excluded_count = Projects.count_changeset_items(changeset, excluded: true)

    final_status = if counts.failed > 0, do: "failed", else: "completed"

    {:ok, updated} = changeset
      |> ChangeSet.status_changeset(final_status)
      |> ChangeSet.counts_changeset(%{
        success_count: counts.success,
        failure_count: counts.failed,
        skipped_count: excluded_count
      })
      |> Repo.update()

    # Emit completion signal
    emit_changeset_signal(String.to_atom("changeset_#{final_status}"), updated)

    {:ok, updated}
  end

  defp truncate_output(output) when byte_size(output) > 100_000 do
    String.slice(output, 0, 100_000) <> "\n... (truncated)"
  end
  defp truncate_output(output), do: output

  defp emit_item_signal(event, changeset, item) do
    if Command.Orchestration.enabled?() do
      Command.Orchestration.publish(
        "changeset.item.#{event |> Atom.to_string() |> String.replace("changeset_item_", "")}",
        %{
          changeset_id: changeset.id,
          item_id: item.id,
          project_id: item.project_id,
          status: item.status
        },
        command_user_id: changeset.user_id
      )
    end
  end

  defp emit_changeset_signal(event, changeset) do
    if Command.Orchestration.enabled?() do
      Command.Orchestration.publish(
        "changeset.#{event |> Atom.to_string() |> String.replace("changeset_", "")}",
        %{
          changeset_id: changeset.id,
          name: changeset.name,
          status: changeset.status,
          success_count: changeset.success_count,
          failure_count: changeset.failure_count
        },
        command_user_id: changeset.user_id
      )
    end
  end
end
```

### Workflow Step Handler

```elixir
# lib/command/workflows/steps/project_operation.ex
defmodule Command.Workflows.Steps.ProjectOperation do
  @moduledoc "Workflow step for bulk project operations"

  alias Command.Projects
  alias Command.Projects.{ChangeSet, ChangeSetExecutor}

  @doc "Execute a project_operation workflow step"
  def execute(step_config, context) do
    mode = step_config["mode"] || "preview"

    case mode do
      "preview" ->
        create_and_preview(step_config, context)

      "execute" ->
        execute_existing(step_config, context)

      "retry_failed" ->
        retry_failed(step_config, context)
    end
  end

  defp create_and_preview(config, context) do
    attrs = %{
      name: config["name"] || "Workflow operation",
      operation_type: config["operation_type"] || "shell",
      operation: build_operation(config),
      project_filter: config["select"] || %{},
      parallelism: config["parallelism"] || 4,
      on_failure: config["on_failure"] || "continue",
      timeout_ms: config["timeout_ms"] || 60_000,
      user_id: context.user_id,
      workflow_run_id: context[:workflow_run_id],
      metadata: %{
        "allow_destructive" => config["allow_destructive"] || false
      }
    }

    with {:ok, changeset} <- Projects.create_changeset(context.user, attrs),
         {:ok, changeset} <- ChangeSetExecutor.preview(changeset) do

      items = Projects.list_changeset_items(changeset, preload: [:project])

      # Check auto-confirm conditions
      changeset = maybe_auto_confirm(changeset, config, items)

      {:ok, %{
        changeset_id: changeset.id,
        status: changeset.status,
        summary: %{
          preview_count: changeset.preview_count,
          success_count: changeset.success_count,
          failure_count: changeset.failure_count
        },
        items: format_items(items)
      }}
    end
  end

  defp execute_existing(%{"changeset_id" => changeset_id}, context) do
    changeset = Projects.get_changeset!(changeset_id)

    # Verify ownership
    if changeset.user_id != context.user_id do
      {:error, :unauthorized}
    else
      case changeset.status do
        "confirmed" ->
          {:ok, result} = ChangeSetExecutor.execute(changeset)
          format_result(result)

        "preview" ->
          {:error, "Changeset must be confirmed before execution"}

        other ->
          {:error, "Cannot execute changeset in status: #{other}"}
      end
    end
  end

  defp retry_failed(%{"changeset_id" => changeset_id}, context) do
    changeset = Projects.get_changeset!(changeset_id)

    if changeset.user_id != context.user_id do
      {:error, :unauthorized}
    else
      {:ok, result} = ChangeSetExecutor.retry_failed(changeset)
      format_result(result)
    end
  end

  defp build_operation(config) do
    base = %{}

    base = if config["command"], do: Map.put(base, "command", config["command"]), else: base
    base = if config["file"], do: Map.put(base, "file", config["file"]), else: base
    base = if config["content"], do: Map.put(base, "content", resolve_content(config["content"])), else: base

    # Add any explicit variables
    variables = config["variables"] || %{}
    Map.merge(base, variables)
  end

  defp resolve_content({"input", key}), do: {:input, key}
  defp resolve_content(content), do: content

  defp maybe_auto_confirm(changeset, config, items) do
    if config["auto_confirm"] do
      condition = config["confirm_condition"] || %{}

      should_confirm = cond do
        max = condition["max_affected"] ->
          length(items) <= max

        condition["require_green_ci"] ->
          Enum.all?(items, fn item ->
            item.project.state && item.project.state.ci_status == "passing"
          end)

        true ->
          true
      end

      if should_confirm do
        {:ok, confirmed} = Projects.confirm_changeset(changeset)
        confirmed
      else
        changeset
      end
    else
      changeset
    end
  end

  defp format_items(items) do
    Enum.map(items, fn item ->
      %{
        project_slug: item.project.slug,
        project_name: item.project.name,
        status: item.status,
        excluded: item.excluded,
        resolved_command: item.resolved_operation["command"]
      }
    end)
  end

  defp format_result(changeset) do
    {:ok, %{
      changeset_id: changeset.id,
      status: changeset.status,
      summary: %{
        preview_count: changeset.preview_count,
        success_count: changeset.success_count,
        failure_count: changeset.failure_count,
        skipped_count: changeset.skipped_count
      }
    }}
  end
end
```

### Context Functions for ChangeSets

```elixir
# Add to lib/command/projects.ex

# ChangeSet CRUD
def create_changeset(user, attrs) do
  %ChangeSet{}
  |> ChangeSet.create_changeset(Map.put(attrs, :user_id, user.id))
  |> Repo.insert()
end

def get_changeset!(id), do: Repo.get!(ChangeSet, id)

def list_changesets(user_id, opts \\ []) do
  ChangeSet
  |> where([c], c.user_id == ^user_id)
  |> maybe_filter_changeset_status(opts[:status])
  |> order_by([c], desc: c.inserted_at)
  |> limit(^(opts[:limit] || 50))
  |> Repo.all()
end

def confirm_changeset(%ChangeSet{status: "preview"} = changeset) do
  changeset
  |> ChangeSet.status_changeset("confirmed")
  |> Repo.update()
end

def cancel_changeset(%ChangeSet{} = changeset) do
  changeset
  |> ChangeSet.status_changeset("cancelled")
  |> Repo.update()
end

# ChangeSetItem functions
def list_changeset_items(changeset, opts \\ []) do
  ChangeSetItem
  |> where([i], i.changeset_id == ^changeset.id)
  |> maybe_filter_item_status(opts[:status])
  |> maybe_filter_excluded(opts[:excluded])
  |> maybe_preload(opts[:preload])
  |> Repo.all()
end

def count_changeset_items(changeset, opts \\ []) do
  ChangeSetItem
  |> where([i], i.changeset_id == ^changeset.id)
  |> maybe_filter_excluded(opts[:excluded])
  |> Repo.aggregate(:count)
end

def exclude_from_changeset(changeset, project_or_item) do
  item = get_or_find_item(changeset, project_or_item)

  item
  |> ChangeSetItem.exclude_changeset(true)
  |> Repo.update()
end

def include_in_changeset(changeset, project_or_item) do
  item = get_or_find_item(changeset, project_or_item)

  item
  |> ChangeSetItem.exclude_changeset(false)
  |> Repo.update()
end

defp get_or_find_item(changeset, %ChangeSetItem{} = item), do: item
defp get_or_find_item(changeset, %Project{} = project) do
  Repo.get_by!(ChangeSetItem, changeset_id: changeset.id, project_id: project.id)
end
defp get_or_find_item(changeset, project_id) when is_binary(project_id) do
  Repo.get_by!(ChangeSetItem, changeset_id: changeset.id, project_id: project_id)
end

defp maybe_filter_changeset_status(query, nil), do: query
defp maybe_filter_changeset_status(query, status), do: where(query, [c], c.status == ^status)

defp maybe_filter_item_status(query, nil), do: query
defp maybe_filter_item_status(query, statuses) when is_list(statuses) do
  where(query, [i], i.status in ^statuses)
end
defp maybe_filter_item_status(query, status), do: where(query, [i], i.status == ^status)

defp maybe_filter_excluded(query, nil), do: query
defp maybe_filter_excluded(query, true), do: where(query, [i], i.excluded == true)
defp maybe_filter_excluded(query, false), do: where(query, [i], i.excluded == false)

defp maybe_preload(query, nil), do: query
defp maybe_preload(query, preloads), do: preload(query, ^preloads)

# Project filtering for changesets
def list_projects_matching(filter, opts \\ []) do
  Project
  |> maybe_filter_user(opts[:user_id])
  |> apply_project_filter(filter)
  |> preload(:state)
  |> Repo.all()
end

defp apply_project_filter(query, filter) when map_size(filter) == 0, do: query
defp apply_project_filter(query, filter) do
  Enum.reduce(filter, query, fn {key, value}, q ->
    apply_filter_clause(q, key, value)
  end)
end

defp apply_filter_clause(query, "tags", tags) when is_list(tags) do
  where(query, [p], fragment("? && ?", p.tags, ^tags))
end
defp apply_filter_clause(query, "language", language) do
  where(query, [p], p.language == ^language)
end
defp apply_filter_clause(query, "category", category) do
  where(query, [p], p.category == ^category)
end
defp apply_filter_clause(query, "status", status) do
  where(query, [p], p.status == ^status)
end
defp apply_filter_clause(query, "state.ci_status", status) do
  query
  |> join(:inner, [p], s in assoc(p, :state), as: :state)
  |> where([p, state: s], s.ci_status == ^status)
end
defp apply_filter_clause(query, "state.git_dirty", dirty) do
  query
  |> join(:inner, [p], s in assoc(p, :state), as: :state)
  |> where([p, state: s], s.git_dirty == ^dirty)
end
defp apply_filter_clause(query, key, %{"$lte" => val}) do
  field = String.to_existing_atom(key)
  where(query, [p], field(p, ^field) <= ^val)
end
defp apply_filter_clause(query, key, %{"$gte" => val}) do
  field = String.to_existing_atom(key)
  where(query, [p], field(p, ^field) >= ^val)
end
defp apply_filter_clause(query, _key, _value), do: query
```

### Updated File Structure

```
lib/command/
├── projects/
│   ├── project.ex
│   ├── relationship.ex
│   ├── decision.ex
│   ├── project_state.ex
│   ├── session_project.ex
│   ├── workflow_trigger.ex
│   ├── changeset.ex                    # NEW: ChangeSet schema
│   ├── changeset_item.ex               # NEW: ChangeSetItem schema
│   ├── changeset_executor.ex           # NEW: Execution engine
│   ├── scanner.ex
│   ├── signals.ex
│   ├── tools.ex
│   └── tool_handler.ex
├── projects.ex
└── workflows/
    └── steps/
        └── project_operation.ex        # NEW: Workflow step handler

priv/repo/migrations/
├── 20260115000001_create_projects.exs
├── 20260115000002_create_project_relationships.exs
├── 20260115000003_create_project_decisions.exs
├── 20260115000004_create_project_state.exs
├── 20260115000005_create_session_projects.exs
├── 20260115000006_create_project_workflow_triggers.exs
├── 20260115000007_add_focus_tracking_to_projects.exs
├── 20260115000008_add_blocker_type_to_relationships.exs
├── 20260115000009_add_ecosystem_to_decisions.exs
├── 20260115000010_create_project_changesets.exs       # NEW
└── 20260115000011_create_project_changeset_items.exs  # NEW
```

### Testing the Bulk Execution System

```elixir
defmodule Command.Projects.ChangeSetExecutorTest do
  use Command.DataCase

  alias Command.Projects
  alias Command.Projects.ChangeSetExecutor

  describe "preview/1" do
    test "creates items for matching projects" do
      user = insert(:user)
      p1 = insert(:project, user: user, tags: ["crucible"])
      p2 = insert(:project, user: user, tags: ["crucible"])
      _p3 = insert(:project, user: user, tags: ["other"])

      {:ok, changeset} = Projects.create_changeset(user, %{
        name: "Test",
        operation_type: "shell",
        operation: %{"command" => "echo hello"},
        project_filter: %{"tags" => ["crucible"]}
      })

      {:ok, previewed} = ChangeSetExecutor.preview(changeset)

      assert previewed.preview_count == 2
      items = Projects.list_changeset_items(previewed)
      assert length(items) == 2
    end

    test "resolves template variables" do
      user = insert(:user)
      project = insert(:project, user: user, slug: "my-project", tags: ["test"])

      {:ok, changeset} = Projects.create_changeset(user, %{
        name: "Test",
        operation_type: "shell",
        operation: %{"command" => "echo {{project.slug}}"},
        project_filter: %{"tags" => ["test"]}
      })

      {:ok, _} = ChangeSetExecutor.preview(changeset)
      [item] = Projects.list_changeset_items(changeset)

      assert item.resolved_operation["command"] == "echo my-project"
    end
  end

  describe "validate_operation/2" do
    test "blocks dangerous operations" do
      assert {:error, :operation_blocked, _} =
        ChangeSetExecutor.validate_operation("sudo rm -rf /", %{})

      assert {:error, :operation_blocked, _} =
        ChangeSetExecutor.validate_operation("DROP TABLE users;", %{})
    end

    test "requires flag for destructive operations" do
      assert {:error, :requires_flag, _} =
        ChangeSetExecutor.validate_operation("git push --force", %{})

      assert :ok =
        ChangeSetExecutor.validate_operation("git push --force", %{"allow_destructive" => true})
    end

    test "allows safe operations" do
      assert :ok = ChangeSetExecutor.validate_operation("mix deps.update --all", %{})
      assert :ok = ChangeSetExecutor.validate_operation("git status", %{})
    end
  end

  describe "execute/1" do
    test "executes shell commands across projects" do
      user = insert(:user)
      project = insert(:project, user: user, path: "/tmp/test_project", tags: ["test"])
      File.mkdir_p!(project.path)

      {:ok, changeset} = Projects.create_changeset(user, %{
        name: "Test",
        operation_type: "shell",
        operation: %{"command" => "echo success"},
        project_filter: %{"tags" => ["test"]}
      })

      {:ok, changeset} = ChangeSetExecutor.preview(changeset)
      {:ok, changeset} = Projects.confirm_changeset(changeset)
      {:ok, result} = ChangeSetExecutor.execute(changeset)

      assert result.status == "completed"
      assert result.success_count == 1
      assert result.failure_count == 0

      [item] = Projects.list_changeset_items(result)
      assert item.status == "success"
      assert item.output =~ "success"
    end
  end
end
```

### Revised Implementation Order (Final)

1. **Phase 1: Core schemas** (2-3 hours)
   - Create all 11 migrations
   - Define all schema modules
   - Basic CRUD in context

2. **Phase 2: Scanner adaptation** (2-3 hours)
   - Copy pure functions from portfolio_coder
   - Adapt for Ecto output
   - Add git dirty/ahead/behind detection

3. **Phase 3: Relationships & decisions** (2-3 hours)
   - Relationship CRUD with blocker_type
   - Decision CRUD with ecosystem scope
   - Blocking/unblocking logic

4. **Phase 4: Session linking** (1-2 hours)
   - SessionProject schema and context functions
   - Auto-linking from file paths
   - Query helpers

5. **Phase 5: Sync infrastructure** (2-3 hours)
   - SyncWorker with Oban
   - CI status fetching (GitHub Actions API)
   - Configure periodic sync

6. **Phase 6: Synapse signals** (2 hours)
   - Signals module
   - Emit signals on all state changes
   - SignalBridge extension

7. **Phase 7: Workflow triggers** (3-4 hours)
   - TriggerEvaluator module
   - Condition DSL evaluation
   - Integration with state updates

8. **Phase 8: Bulk execution system** (4-5 hours) **NEW**
   - ChangeSet and ChangeSetItem schemas
   - ChangeSetExecutor module
   - Workflow step handler
   - Safety validation

9. **Phase 9: Agent tools** (2-3 hours)
   - ALTAR tool definitions
   - ToolHandler execution
   - Bulk operation tools
   - Integration with ToolUse lifecycle

10. **Phase 10: YAML migration** (1-2 hours)
    - Migration script
    - Test with real data
    - Verify relationships

11. **Phase 11: CLI commands** (3-4 hours)
    - mix command.projects tasks
    - Bulk operation CLI (bulk, bulk:confirm, bulk:execute, etc.)
    - List, show, block, decide, trigger commands

**Revised total: 25-32 hours**

### Updated Dependency Summary

| Dependency | Required? | Purpose |
|------------|-----------|---------|
| Ecto 3.11+ | Yes | Database layer |
| PostgreSQL + extensions | Yes | Storage (citext, pg_trgm, btree_gin) |
| Command.Accounts | Yes | User ownership |
| Command.Sessions | Yes | Session linking |
| Command.Workflows | Yes | Workflow triggers + project_operation step |
| Command.PubSub | Yes | Real-time events |
| Command.Orchestration | Yes | Synapse signals |
| Oban | Recommended | Background sync + changeset execution |
| Altar.ADM | Yes | Tool definitions |
| portfolio_coder | Optional | Extract Scanner/Syncer logic |
