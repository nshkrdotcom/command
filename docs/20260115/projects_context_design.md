# Command.Projects Context Design

## Overview

The Projects context provides persistent, queryable project/repository management for the Command platform. It replaces the YAML-based portfolio tracking in `portfolio_coder` with PostgreSQL-backed schemas that agents can query, update, and reason about.

## Problem Statement

Current state:
- Project metadata lives in YAML files (`registry.yml`, `relationships.yml`, `repos/*/context.yml`)
- Not queryable by agents - must parse files
- No blocking/priority semantics
- No decision tracking (ADRs)
- Sync state mixed with source-of-truth data

Goals:
- Agents can ask "What should I work on?" and get prioritized results
- Track blocking relationships between projects
- Record architectural decisions per project
- Separate volatile sync state from stable project metadata
- Enable real-time updates via PubSub

## Schema Design

### projects

Core project/repository metadata.

```elixir
schema "projects" do
  field :name, :string                    # Display name: "FlowStone"
  field :slug, :string                    # URL-safe identifier: "flowstone"
  field :description, :string             # Brief description
  field :status, :string, default: "active"
  field :priority, :integer, default: 3   # 1=critical, 5=backlog
  field :category, :string                # library, application, tool, experiment
  field :language, :string                # elixir, python, javascript, rust, go
  field :path, :string                    # Filesystem path
  field :remote_url, :string              # Git remote URL
  field :current_focus, :string           # "What's the immediate next thing"
  field :blocked_reason, :string          # Why blocked (if status=blocked)
  field :tags, {:array, :string}, default: []
  field :metadata, :map, default: %{}     # Flexible key-value storage

  belongs_to :user, Command.Accounts.User
  has_many :relationships_from, Command.Projects.Relationship, foreign_key: :from_project_id
  has_many :relationships_to, Command.Projects.Relationship, foreign_key: :to_project_id
  has_many :decisions, Command.Projects.Decision
  has_one :state, Command.Projects.ProjectState

  timestamps(type: :utc_datetime_usec)
end
```

**Status values:** `planning`, `active`, `paused`, `blocked`, `completed`, `archived`

**Priority scale:**
| Value | Label | Meaning |
|-------|-------|---------|
| 1 | Critical | Drop everything, fix now |
| 2 | High | This week's focus |
| 3 | Medium | Normal priority (default) |
| 4 | Low | When time permits |
| 5 | Backlog | Someday/maybe |

**Category values:** `library`, `application`, `port`, `tool`, `experiment`, `archive`

### project_relationships

Directed edges between projects. Handles dependencies, blocking, and associations.

```elixir
schema "project_relationships" do
  field :relationship_type, :string       # Type of relationship
  field :auto_detected, :boolean, default: false
  field :notes, :string                   # Context, especially for external blockers
  field :metadata, :map, default: %{}

  belongs_to :from_project, Command.Projects.Project
  belongs_to :to_project, Command.Projects.Project  # Nullable for external blockers

  timestamps(type: :utc_datetime_usec)
end
```

**Relationship types:**
| Type | Direction | Example |
|------|-----------|---------|
| `depends_on` | from → to | portfolio_manager depends_on portfolio_core |
| `blocked_by` | from → to | flowstone blocked_by synapse (or external) |
| `port_of` | from → to | duckdb_ex port_of duckdb |
| `forked_from` | from → to | my_lib forked_from original_lib |
| `supersedes` | from → to | v2_lib supersedes v1_lib |
| `related_to` | bidirectional | project_a related_to project_b |
| `alternative_to` | bidirectional | redis_adapter alternative_to ets_adapter |

**External blockers:** When `to_project_id` is NULL, `notes` contains the external blocker description (e.g., "Waiting for pgvector 0.8 release").

### project_decisions

Lightweight ADR (Architecture Decision Record) tracking per project.

```elixir
schema "project_decisions" do
  field :title, :string                   # "Use GenStage for backpressure"
  field :status, :string, default: "accepted"
  field :context, :string                 # Why this decision was needed
  field :decision, :string                # What was decided
  field :consequences, :string            # Tradeoffs, what this enables/prevents
  field :tags, {:array, :string}, default: []
  field :metadata, :map, default: %{}

  belongs_to :project, Command.Projects.Project
  belongs_to :superseded_by, Command.Projects.Decision
  has_many :supersedes, Command.Projects.Decision, foreign_key: :superseded_by_id

  timestamps(type: :utc_datetime_usec)
end
```

**Status values:** `proposed`, `accepted`, `superseded`, `deprecated`

### project_state

Volatile, synced state from git/CI. Separate table for frequent updates without touching core project data.

```elixir
schema "project_state" do
  field :synced_at, :utc_datetime_usec

  # Git state
  field :git_dirty, :boolean, default: false
  field :current_branch, :string
  field :ahead, :integer, default: 0      # Commits ahead of remote
  field :behind, :integer, default: 0     # Commits behind remote
  field :last_commit_sha, :string
  field :last_commit_at, :utc_datetime_usec
  field :last_commit_message, :string
  field :commit_count_30d, :integer, default: 0

  # CI/Build state
  field :ci_status, :string               # passing, failing, pending, none
  field :ci_url, :string
  field :build_status, :string            # success, failed, pending
  field :last_build_at, :utc_datetime_usec

  # Test state
  field :test_count, :integer
  field :test_pass_count, :integer
  field :test_fail_count, :integer
  field :last_test_at, :utc_datetime_usec

  # Dependencies
  field :deps_total_count, :integer, default: 0
  field :deps_outdated_count, :integer, default: 0
  field :deps_vulnerable_count, :integer, default: 0

  # Codebase metrics
  field :loc_count, :integer              # Lines of code
  field :file_count, :integer

  belongs_to :project, Command.Projects.Project

  timestamps(type: :utc_datetime_usec)
end
```

## Context API

### Command.Projects

```elixir
# CRUD
create_project(user, attrs)
get_project(id)
get_project!(id)
get_project_by_slug(slug)
list_projects(opts \\ [])
update_project(project, attrs)
delete_project(project)

# Filtering & queries
list_active_projects(user_id, opts \\ [])
list_blocked_projects(opts \\ [])
list_by_priority(user_id, max_priority \\ 2)
list_by_language(language)
list_by_category(category)
search_projects(query_string)

# Status management
set_status(project, status, reason \\ nil)
block_project(project, reason, blocker_project_or_note)
unblock_project(project)
archive_project(project)

# Priority
set_priority(project, priority)
promote_priority(project)   # Decrease priority number
demote_priority(project)    # Increase priority number

# Relationships
add_relationship(from_project, to_project_or_nil, type, opts \\ [])
remove_relationship(from_project, to_project, type)
list_relationships(project, opts \\ [])
get_dependencies(project)       # Projects this depends on
get_dependents(project)         # Projects that depend on this
get_blockers(project)           # What's blocking this
get_blocking(project)           # What this is blocking
blocked?(project)               # Has any blocked_by relationships?

# Decisions
create_decision(project, attrs)
list_decisions(project, opts \\ [])
supersede_decision(decision, new_decision)
get_active_decisions(project)

# State (sync)
get_state(project)
update_state(project, attrs)
sync_project(project)           # Trigger full resync
sync_all_projects(opts \\ [])
stale_projects(threshold_minutes \\ 60)
```

## Key Queries

```elixir
# "What should I work on next?"
Project
|> where([p], p.user_id == ^user_id)
|> where([p], p.status == "active")
|> where([p], p.priority <= 2)
|> order_by([p], [asc: p.priority, desc: p.updated_at])
|> preload(:state)
|> limit(5)

# "What's blocked and why?"
from p in Project,
  where: p.status == "blocked",
  left_join: r in Relationship,
    on: r.from_project_id == p.id and r.relationship_type == "blocked_by",
  left_join: blocker in Project,
    on: blocker.id == r.to_project_id,
  preload: [relationships_from: {r, to_project: blocker}]

# "What depends on portfolio_core?"
from r in Relationship,
  where: r.to_project_id == ^core_id,
  where: r.relationship_type == "depends_on",
  preload: :from_project

# "Show me the dependency graph"
from r in Relationship,
  where: r.relationship_type == "depends_on",
  select: %{from: r.from_project_id, to: r.to_project_id}

# "Find decisions about streaming"
from d in Decision,
  where: ilike(d.title, ^"%streaming%") or ilike(d.decision, ^"%streaming%"),
  preload: :project

# "Projects with failing tests"
from p in Project,
  join: s in ProjectState, on: s.project_id == p.id,
  where: s.test_fail_count > 0,
  order_by: [desc: s.test_fail_count]

# "Stale projects (not synced in 24h)"
from p in Project,
  join: s in ProjectState, on: s.project_id == p.id,
  where: s.synced_at < ago(24, "hour")
```

## PubSub Topics

```elixir
# Project changes
"project:#{project_id}"              # All changes to a project
"project:#{project_id}:state"        # State sync updates
"project:#{project_id}:decisions"    # Decision changes
"user:#{user_id}:projects"           # All project changes for a user

# Aggregate topics
"projects:blocked"                   # Any project becomes blocked/unblocked
"projects:sync"                      # Sync job completions
```

## Changesets

### Project

```elixir
@statuses ~w(planning active paused blocked completed archived)
@categories ~w(library application port tool experiment archive)
@languages ~w(elixir python javascript typescript rust go ruby java erlang)

def create_changeset(project, attrs) do
  project
  |> cast(attrs, [:name, :slug, :description, :status, :priority, :category,
                  :language, :path, :remote_url, :current_focus, :tags, :metadata, :user_id])
  |> validate_required([:name, :slug, :user_id])
  |> validate_length(:name, min: 1, max: 200)
  |> validate_length(:slug, min: 1, max: 100)
  |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9_-]*$/)
  |> validate_inclusion(:status, @statuses)
  |> validate_inclusion(:priority, 1..5)
  |> validate_inclusion(:category, @categories)
  |> validate_inclusion(:language, @languages)
  |> unique_constraint(:slug, name: :projects_user_id_slug_index)
end

def status_changeset(project, status, reason \\ nil) do
  project
  |> cast(%{status: status, blocked_reason: reason}, [:status, :blocked_reason])
  |> validate_inclusion(:status, @statuses)
  |> validate_blocked_reason()
end

def priority_changeset(project, priority) do
  project
  |> cast(%{priority: priority}, [:priority])
  |> validate_inclusion(:priority, 1..5)
end

defp validate_blocked_reason(changeset) do
  status = get_field(changeset, :status)
  reason = get_field(changeset, :blocked_reason)

  if status == "blocked" and (is_nil(reason) or reason == "") do
    add_error(changeset, :blocked_reason, "is required when status is blocked")
  else
    changeset
  end
end
```

### Relationship

```elixir
@relationship_types ~w(depends_on blocked_by port_of forked_from supersedes related_to alternative_to)

def create_changeset(rel, attrs) do
  rel
  |> cast(attrs, [:relationship_type, :from_project_id, :to_project_id,
                  :auto_detected, :notes, :metadata])
  |> validate_required([:relationship_type, :from_project_id])
  |> validate_inclusion(:relationship_type, @relationship_types)
  |> validate_external_blocker()
  |> foreign_key_constraint(:from_project_id)
  |> foreign_key_constraint(:to_project_id)
  |> unique_constraint([:from_project_id, :to_project_id, :relationship_type])
end

defp validate_external_blocker(changeset) do
  to_project_id = get_field(changeset, :to_project_id)
  notes = get_field(changeset, :notes)
  type = get_field(changeset, :relationship_type)

  # External blockers (to_project_id is nil) require notes
  if is_nil(to_project_id) and type == "blocked_by" and (is_nil(notes) or notes == "") do
    add_error(changeset, :notes, "is required for external blockers")
  else
    changeset
  end
end
```

## Background Sync

Projects should be synced periodically to update `project_state`. Options:

### Option A: Scheduled Job (Command.Scheduling)

```elixir
# Create a scheduled job for project sync
Scheduling.create_scheduled_job(%{
  name: "project_sync",
  job_type: "custom",
  schedule_type: "interval",
  interval_seconds: 3600,  # Hourly
  job_config: %{
    handler: "Command.Projects.Syncer",
    function: "sync_all"
  }
})
```

### Option B: Oban Worker

```elixir
defmodule Command.Projects.SyncWorker do
  use Oban.Worker, queue: :sync, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    project = Projects.get_project!(project_id)
    Projects.sync_project(project)
  end
end

# Enqueue all projects hourly
Oban.insert_all(
  for project <- Projects.list_projects() do
    SyncWorker.new(%{project_id: project.id})
  end
)
```

### Option C: On-Demand with Staleness Check

```elixir
def get_project_with_fresh_state(id) do
  project = get_project!(id) |> Repo.preload(:state)

  if stale?(project.state) do
    {:ok, _} = sync_project(project)
    get_project!(id) |> Repo.preload(:state)
  else
    project
  end
end

defp stale?(nil), do: true
defp stale?(%{synced_at: synced_at}) do
  DateTime.diff(DateTime.utc_now(), synced_at, :minute) > 60
end
```

## Migration from YAML

One-time migration script:

```elixir
defmodule Command.Projects.YAMLMigrator do
  def migrate(portfolio_path, user_id) do
    # 1. Import registry.yml
    registry = YamlElixir.read_from_file!(Path.join(portfolio_path, "registry.yml"))

    projects = for repo <- registry["repos"] do
      {:ok, project} = Projects.create_project(user_id, %{
        name: repo["name"],
        slug: repo["id"],
        path: repo["path"],
        language: repo["language"],
        category: repo["type"],
        status: repo["status"],
        remote_url: repo["remote_url"],
        tags: repo["tags"] || []
      })
      {repo["id"], project}
    end |> Map.new()

    # 2. Import relationships.yml
    rels = YamlElixir.read_from_file!(Path.join(portfolio_path, "relationships.yml"))

    for rel <- rels["relationships"] do
      from_project = projects[rel["from"]]
      to_project = projects[rel["to"]]

      if from_project && to_project do
        Projects.add_relationship(from_project, to_project, rel["type"],
          auto_detected: rel["auto_detected"],
          notes: get_in(rel, ["details", "reason"])
        )
      end
    end

    # 3. Import context.yml files
    for {slug, project} <- projects do
      context_path = Path.join([portfolio_path, "repos", slug, "context.yml"])
      if File.exists?(context_path) do
        context = YamlElixir.read_from_file!(context_path)
        computed = context["computed"] || %{}

        Projects.update_state(project, %{
          current_branch: computed["current_branch"],
          last_commit_sha: get_in(computed, ["last_commit", "sha"]),
          last_commit_message: get_in(computed, ["last_commit", "message"]),
          commit_count_30d: computed["commit_count_30d"],
          synced_at: DateTime.utc_now()
        })
      end
    end

    :ok
  end
end
```

## Usage Examples

### Agent Integration

```elixir
# Agent tool: get_work_queue
def get_work_queue(user_id, opts \\ []) do
  max_priority = Keyword.get(opts, :max_priority, 3)
  limit = Keyword.get(opts, :limit, 10)

  Projects.list_by_priority(user_id, max_priority)
  |> Enum.take(limit)
  |> Enum.map(fn project ->
    %{
      name: project.name,
      priority: project.priority,
      status: project.status,
      current_focus: project.current_focus,
      blocked_by: get_blocker_summary(project)
    }
  end)
end

defp get_blocker_summary(project) do
  case Projects.get_blockers(project) do
    [] -> nil
    blockers ->
      Enum.map(blockers, fn
        %{to_project: nil, notes: notes} -> notes
        %{to_project: p} -> p.name
      end)
  end
end
```

### CLI Commands

```bash
# List active projects by priority
mix command.projects list --status active --sort priority

# Show what's blocked
mix command.projects blocked

# Set priority
mix command.projects priority flowstone 1

# Block a project
mix command.projects block flowstone --by portfolio_core --reason "Waiting for v0.5"

# Record a decision
mix command.projects decide flowstone "Use GenStage" --context "Need backpressure" --decision "..."

# Sync all projects
mix command.projects sync
```

---

## Workflow Automation Triggers

Project state changes can trigger workflows automatically. This enables scenarios like:
- "When all crucible-* projects pass CI → create release workflow"
- "When a P1 project is blocked for >24h → notify and create investigation session"
- "When test_fail_count > 0 → run debug agent workflow"

### Trigger Definition Schema

Add to `project_relationships` or create dedicated `project_workflow_triggers` table:

```elixir
schema "project_workflow_triggers" do
  field :name, :string
  field :enabled, :boolean, default: true
  field :trigger_on, :string  # state_change, schedule, manual

  # Condition: JSON expression evaluated against ProjectState
  field :condition, :map
  # Example: %{"ci_status" => "passing", "test_fail_count" => 0}
  # Example: %{"$and" => [%{"ci_status" => "passing"}, %{"priority" => %{"$lte" => 2}}]}

  # What to trigger
  field :workflow_id, :binary_id
  field :workflow_input, :map, default: %{}  # Template with {{project.slug}} etc.

  # Scope
  field :project_match, :map  # %{"tags" => ["crucible"], "language" => "elixir"}

  belongs_to :user, Command.Accounts.User

  timestamps(type: :utc_datetime_usec)
end
```

### Trigger Evaluation Flow

```elixir
# In Projects context, after state update:
defp maybe_trigger_workflows(project, old_state, new_state) do
  triggers = list_enabled_triggers(project.user_id)

  for trigger <- triggers,
      matches_project?(trigger, project),
      condition_met?(trigger.condition, new_state),
      not condition_met?(trigger.condition, old_state) do  # Only on transition

    input = interpolate_input(trigger.workflow_input, project, new_state)

    Command.Workflows.create_workflow_run(trigger.workflow_id, %{
      trigger_type: "project_state",
      trigger_metadata: %{
        project_id: project.id,
        project_slug: project.slug,
        trigger_id: trigger.id
      },
      input: input
    })
  end
end
```

### FlowStone Integration

For complex multi-project triggers, use FlowStone pipelines:

```elixir
# Define a pipeline that checks multiple project states
defmodule Command.Projects.ReleasePipeline do
  use FlowStone.Pipeline

  step :check_all_green do
    projects = Projects.list_projects(tags: ["crucible"])
    all_passing = Enum.all?(projects, fn p ->
      state = Projects.get_state(p)
      state.ci_status == "passing" && state.test_fail_count == 0
    end)

    if all_passing, do: {:ok, projects}, else: {:halt, :not_ready}
  end

  step :create_release, depends_on: [:check_all_green] do
    # Create release workflow for each project
  end
end
```

### Example Triggers

```elixir
# Trigger: Auto-investigate test failures
%ProjectWorkflowTrigger{
  name: "Test Failure Investigation",
  trigger_on: "state_change",
  condition: %{"test_fail_count" => %{"$gt" => 0}},
  project_match: %{"priority" => %{"$lte" => 2}},
  workflow_id: debug_workflow_id,
  workflow_input: %{
    "project_path" => "{{project.path}}",
    "task" => "Investigate test failures in {{project.name}}"
  }
}

# Trigger: All crucible-* green → release
%ProjectWorkflowTrigger{
  name: "Crucible Release Gate",
  trigger_on: "state_change",
  condition: %{"$all_matching" => %{
    "tags" => ["crucible"],
    "state.ci_status" => "passing"
  }},
  workflow_id: release_workflow_id
}
```

---

## Agent Tool Definitions (ALTAR ADM Format)

Project tools follow the ALTAR ADM (Abstract Data Model) format used throughout Command.

### Tool Manifest

```elixir
defmodule Command.Projects.Tools do
  @moduledoc "ALTAR tool definitions for Project operations"

  alias Altar.ADM.{Tool, FunctionDeclaration}

  def tool_manifest do
    {:ok, manifest} = Altar.ADM.ToolManifest.new(%{
      version: "1.0.0",
      tools: [work_queue_tool(), project_info_tool(), blocking_tool(), decision_tool()],
      metadata: %{"domain" => "projects", "version" => "1.0.0"}
    })
    manifest
  end

  def work_queue_tool do
    {:ok, tool} = Tool.new(%{
      function_declarations: [
        %{
          name: "get_work_queue",
          description: "Get prioritized list of projects to work on. Returns active, unblocked projects sorted by priority.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "max_priority" => %{
                "type" => "integer",
                "description" => "Maximum priority level (1=critical, 5=backlog). Default: 3",
                "minimum" => 1,
                "maximum" => 5
              },
              "limit" => %{
                "type" => "integer",
                "description" => "Maximum number of projects to return. Default: 10",
                "minimum" => 1,
                "maximum" => 50
              },
              "language" => %{
                "type" => "string",
                "description" => "Filter by language (elixir, python, javascript, etc.)"
              }
            }
          }
        },
        %{
          name: "get_actionable_work",
          description: "Get projects that are active, unblocked, and ready for work. Excludes blocked and paused projects.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "limit" => %{"type" => "integer", "description" => "Max results", "default" => 5}
            }
          }
        }
      ]
    })
    tool
  end

  def project_info_tool do
    {:ok, tool} = Tool.new(%{
      function_declarations: [
        %{
          name: "get_project",
          description: "Get detailed information about a specific project including status, priority, current focus, and recent state.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "slug" => %{
                "type" => "string",
                "description" => "Project slug (e.g., 'flowstone', 'portfolio_core')"
              }
            },
            "required" => ["slug"]
          }
        },
        %{
          name: "get_project_state",
          description: "Get the current sync state of a project: git status, CI status, test results, dependencies.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "slug" => %{"type" => "string", "description" => "Project slug"},
              "refresh" => %{"type" => "boolean", "description" => "Force refresh if stale. Default: false"}
            },
            "required" => ["slug"]
          }
        },
        %{
          name: "search_projects",
          description: "Search projects by name, tags, or description.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "query" => %{"type" => "string", "description" => "Search query"},
              "filters" => %{
                "type" => "object",
                "properties" => %{
                  "language" => %{"type" => "string"},
                  "category" => %{"type" => "string"},
                  "status" => %{"type" => "string"},
                  "tags" => %{"type" => "array", "items" => %{"type" => "string"}}
                }
              }
            },
            "required" => ["query"]
          }
        }
      ]
    })
    tool
  end

  def blocking_tool do
    {:ok, tool} = Tool.new(%{
      function_declarations: [
        %{
          name: "get_blocked_projects",
          description: "List all blocked projects with their blockers (other projects or external factors).",
          parameters: %{"type" => "object", "properties" => %{}}
        },
        %{
          name: "get_blockers",
          description: "Get what's blocking a specific project.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "slug" => %{"type" => "string", "description" => "Project slug"}
            },
            "required" => ["slug"]
          }
        },
        %{
          name: "get_blocking",
          description: "Get what a project is blocking (projects waiting on this one).",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "slug" => %{"type" => "string", "description" => "Project slug"}
            },
            "required" => ["slug"]
          }
        },
        %{
          name: "get_dependency_graph",
          description: "Get the dependency graph for projects. Shows what depends on what.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "root_slug" => %{"type" => "string", "description" => "Optional: start from specific project"},
              "depth" => %{"type" => "integer", "description" => "Max depth to traverse. Default: 3"}
            }
          }
        }
      ]
    })
    tool
  end

  def decision_tool do
    {:ok, tool} = Tool.new(%{
      function_declarations: [
        %{
          name: "get_project_decisions",
          description: "Get architectural decisions (ADRs) for a project.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "slug" => %{"type" => "string", "description" => "Project slug"},
              "status" => %{"type" => "string", "description" => "Filter by status: proposed, accepted, superseded, deprecated"}
            },
            "required" => ["slug"]
          }
        },
        %{
          name: "search_decisions",
          description: "Search decisions across all projects.",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "query" => %{"type" => "string", "description" => "Search in title, context, decision text"}
            },
            "required" => ["query"]
          }
        }
      ]
    })
    tool
  end
end
```

### Tool Execution Handler

```elixir
defmodule Command.Projects.ToolHandler do
  @moduledoc "Executes project tools and returns results"

  alias Command.Projects

  def execute("get_work_queue", args, context) do
    user_id = context.user_id
    opts = [
      max_priority: Map.get(args, "max_priority", 3),
      limit: Map.get(args, "limit", 10)
    ]

    projects = Projects.list_actionable_work(user_id, opts)
    {:ok, format_work_queue(projects)}
  end

  def execute("get_project", %{"slug" => slug}, context) do
    case Projects.get_project_by_slug(slug, user_id: context.user_id) do
      nil -> {:error, "Project not found: #{slug}"}
      project -> {:ok, format_project(project)}
    end
  end

  def execute("get_blocked_projects", _args, context) do
    projects = Projects.list_blocked_projects(user_id: context.user_id)
    {:ok, format_blocked_list(projects)}
  end

  # ... other handlers
end
```

### Integration with Command.Agents.ToolUse

When an agent invokes a project tool, it flows through the standard ToolUse lifecycle:

```elixir
# Agent requests tool use
{:ok, tool_use} = Command.Agents.create_tool_use(agent_call, %{
  tool_name: "get_work_queue",
  input: %{"max_priority" => 2, "limit" => 5},
  requires_approval: false  # Project reads don't need approval
})

# Execute and complete
case Command.Projects.ToolHandler.execute(tool_use.tool_name, tool_use.input, context) do
  {:ok, result} ->
    Command.Agents.complete_tool_use(tool_use, %{output: Jason.encode!(result)})
  {:error, reason} ->
    Command.Agents.fail_tool_use(tool_use, %{error_message: reason})
end
```

---

## Synapse Signal Integration

Project state changes emit Synapse signals that orchestrators can subscribe to.

### Signal Types

```elixir
defmodule Command.Projects.Signals do
  @moduledoc "Synapse signal definitions for project events"

  @signal_types %{
    # State transitions
    project_status_changed: "project.status.changed",
    project_blocked: "project.blocked",
    project_unblocked: "project.unblocked",

    # Sync events
    project_synced: "project.synced",
    project_ci_changed: "project.ci.changed",
    project_tests_failed: "project.tests.failed",
    project_tests_passed: "project.tests.passed",

    # Priority changes
    project_priority_changed: "project.priority.changed",
    project_escalated: "project.escalated",  # Priority increased to 1 or 2

    # Relationship changes
    project_dependency_added: "project.dependency.added",
    project_blocker_added: "project.blocker.added",
    project_blocker_removed: "project.blocker.removed"
  }

  def signal_type(event), do: Map.get(@signal_types, event)
  def all_types, do: Map.values(@signal_types)
end
```

### Emitting Signals

```elixir
# In Command.Projects context
defp emit_signal(event, project, payload \\ %{}) do
  if Command.Orchestration.enabled?() do
    Command.Orchestration.publish(
      Command.Projects.Signals.signal_type(event),
      Map.merge(payload, %{
        project_id: project.id,
        project_slug: project.slug,
        project_name: project.name,
        timestamp: DateTime.utc_now()
      }),
      command_user_id: project.user_id
    )
  end
end

# Example: in set_status/3
def set_status(project, new_status, reason \\ nil) do
  old_status = project.status

  with {:ok, updated} <- do_update_status(project, new_status, reason) do
    # Emit appropriate signal
    cond do
      new_status == "blocked" ->
        emit_signal(:project_blocked, updated, %{reason: reason, previous_status: old_status})

      old_status == "blocked" && new_status != "blocked" ->
        emit_signal(:project_unblocked, updated, %{previous_status: old_status})

      true ->
        emit_signal(:project_status_changed, updated, %{
          from: old_status,
          to: new_status
        })
    end

    {:ok, updated}
  end
end
```

### Orchestrator Subscription

```elixir
# Register an orchestrator that responds to project signals
Command.Orchestration.register_agent(%{
  id: :project_monitor,
  type: :orchestrator,
  signals: %{
    subscribes: [
      "project.blocked",
      "project.tests.failed",
      "project.escalated"
    ],
    emits: ["project.action.taken"]
  },
  actions: [
    Command.Projects.Actions.InvestigateFailure,
    Command.Projects.Actions.NotifyOwner,
    Command.Projects.Actions.CreateSession
  ]
})
```

### SignalBridge Extension

The existing `Command.Orchestration.SignalBridge` already bridges Synapse signals to PubSub. Add project-specific routing:

```elixir
# In SignalBridge.handle_info/2, add:
defp maybe_broadcast_project(signal) do
  case extract_signal_field(signal, "project_id") do
    nil -> :ok
    project_id ->
      PubSub.broadcast("project:#{project_id}:signals", :synapse_signal, signal)
  end
end
```

---

## Session ↔ Project Relationship

### Schema Change: Many-to-Many

Sessions can touch multiple projects (refactoring across repos), and projects have many sessions. Use a join table:

```elixir
# New migration: create_session_projects.exs
schema "session_projects" do
  belongs_to :session, Command.Sessions.Session
  belongs_to :project, Command.Projects.Project

  field :role, :string, default: "primary"  # primary, secondary, reference
  field :files_touched, {:array, :string}, default: []
  field :metadata, :map, default: %{}

  timestamps(type: :utc_datetime_usec)
end

# In Session schema, add:
many_to_many :projects, Command.Projects.Project, join_through: "session_projects"

# In Project schema, add:
many_to_many :sessions, Command.Sessions.Session, join_through: "session_projects"
```

### Query Patterns

```elixir
# "All sessions that touched portfolio_core"
def list_sessions_for_project(project_id, opts \\ []) do
  from sp in SessionProject,
    where: sp.project_id == ^project_id,
    join: s in Session, on: s.id == sp.session_id,
    order_by: [desc: s.updated_at],
    preload: [session: s]
end

# "What projects did this session work on?"
def list_projects_for_session(session_id) do
  from sp in SessionProject,
    where: sp.session_id == ^session_id,
    preload: :project
end

# Filter sessions by project in UI
def list_sessions(opts) do
  query = from s in Session

  query = if project_id = opts[:project_id] do
    from s in query,
      join: sp in SessionProject, on: sp.session_id == s.id,
      where: sp.project_id == ^project_id
  else
    query
  end

  # ... other filters
end
```

### Auto-Linking Sessions to Projects

When a session operates on files, detect project membership:

```elixir
def link_session_to_project_from_path(session, file_path) do
  case find_project_for_path(file_path) do
    nil -> :ok
    project ->
      upsert_session_project(session.id, project.id, %{
        files_touched: [file_path]
      })
  end
end

defp find_project_for_path(file_path) do
  Projects.list_projects()
  |> Enum.find(fn p -> String.starts_with?(file_path, p.path) end)
end
```

---

## External Blocker Structure (Decision)

**Decision: Use structured `blocker_type` with optional fields.**

Freeform notes lose queryability. Structured types enable:
- "Show all projects blocked on dependency updates"
- "What's waiting for external releases?"

### Updated Relationship Schema

```elixir
schema "project_relationships" do
  field :relationship_type, :string
  field :auto_detected, :boolean, default: false

  # Structured blocker info (when relationship_type == "blocked_by")
  field :blocker_type, :string  # project, dependency, external_event, decision_pending
  field :blocker_details, :map, default: %{}
  # Examples:
  # %{"package" => "pgvector", "version_constraint" => ">= 0.8.0", "current" => "0.7.4"}
  # %{"event" => "upstream_release", "url" => "https://github.com/..."}
  # %{"decision_id" => "uuid", "title" => "Auth strategy"}

  field :notes, :string  # Still available for context
  field :metadata, :map, default: %{}

  belongs_to :from_project, Command.Projects.Project
  belongs_to :to_project, Command.Projects.Project  # Nullable

  timestamps(type: :utc_datetime_usec)
end

@blocker_types ~w(project dependency external_event decision_pending other)
```

### Queries Enabled

```elixir
# "What's blocked on dependency updates?"
from r in Relationship,
  where: r.relationship_type == "blocked_by",
  where: r.blocker_type == "dependency",
  preload: :from_project

# "Show projects blocked on external events"
from r in Relationship,
  where: r.blocker_type == "external_event",
  select: %{
    project: r.from_project,
    event: fragment("?->>'event'", r.blocker_details),
    url: fragment("?->>'url'", r.blocker_details)
  }
```

---

## current_focus Lifecycle (Decision)

**Decision: Agent-updateable with timestamp tracking.**

### Schema Addition

```elixir
# Add to projects table:
field :current_focus, :string
field :focus_updated_at, :utc_datetime_usec
field :focus_updated_by, :string  # "user", "agent:debug", "agent:refactor", "workflow:xyz"
```

### Update Rules

1. **Manual update:** User sets via CLI/UI → `focus_updated_by: "user"`
2. **Agent update:** After completing work → `focus_updated_by: "agent:#{agent_type}"`
3. **Auto-clear:** When status changes to `completed` or `archived` → `current_focus: nil`
4. **Workflow update:** Workflow can set focus as output → `focus_updated_by: "workflow:#{workflow_id}"`

```elixir
def set_focus(project, focus, updated_by \\ "user") do
  project
  |> Project.focus_changeset(%{
    current_focus: focus,
    focus_updated_at: DateTime.utc_now(),
    focus_updated_by: updated_by
  })
  |> Repo.update()
end

# Auto-clear on status change
def set_status(project, status, reason \\ nil) do
  attrs = %{status: status, blocked_reason: reason}

  attrs = if status in ["completed", "archived"] do
    Map.merge(attrs, %{current_focus: nil, focus_updated_at: DateTime.utc_now()})
  else
    attrs
  end

  # ...
end
```

---

## Priority + Blocked Interaction (Clarification)

### Work Queue Logic

**Actionable work** = Active AND not blocked:

```elixir
def list_actionable_work(user_id, opts \\ []) do
  max_priority = Keyword.get(opts, :max_priority, 3)

  from p in Project,
    where: p.user_id == ^user_id,
    where: p.status == "active",  # Not blocked, paused, etc.
    where: p.priority <= ^max_priority,
    order_by: [asc: p.priority, desc: p.updated_at]
end

def list_blocked_by_priority(user_id) do
  from p in Project,
    where: p.user_id == ^user_id,
    where: p.status == "blocked",
    order_by: [asc: p.priority]  # P1 blocked items first!
end
```

### Query Summary

| Function | Returns | Use Case |
|----------|---------|----------|
| `list_actionable_work/2` | Active + unblocked | "What can I work on?" |
| `list_blocked_by_priority/1` | Blocked, sorted by priority | "What P1 items need unblocking?" |
| `list_by_priority/2` | All statuses by priority | "Show me everything" |

### Agent Guidance

```elixir
def get_work_guidance(user_id) do
  actionable = list_actionable_work(user_id, max_priority: 2, limit: 3)
  blocked_p1 = list_blocked_by_priority(user_id) |> Enum.filter(&(&1.priority == 1))

  %{
    work_on: format_projects(actionable),
    urgent_blocked: format_projects(blocked_p1),
    recommendation: cond do
      blocked_p1 != [] -> "P1 project #{hd(blocked_p1).name} is blocked - consider unblocking first"
      actionable != [] -> "Work on #{hd(actionable).name}: #{hd(actionable).current_focus}"
      true -> "No actionable work - review blocked projects or backlog"
    end
  }
end
```

---

## portfolio_coder CLI Deprecation Path

### Phase 1: Parallel Operation (Current)

Both systems work independently:
- `portfolio_coder` → YAML files
- `command` → PostgreSQL

### Phase 2: Command.Projects Available

Add new CLI commands to Command:

```bash
# New commands in command
mix command.projects list
mix command.projects sync
mix command.projects blocked
# etc.
```

### Phase 3: Thin Wrapper (Deprecation)

Update portfolio_coder commands to delegate to Command:

```elixir
# lib/mix/tasks/portfolio/list.ex
defmodule Mix.Tasks.Portfolio.List do
  use Mix.Task

  @shortdoc "DEPRECATED: Use `mix command.projects list`"

  def run(args) do
    IO.warn("portfolio.list is deprecated. Use `mix command.projects list` instead.")

    # Option A: Shell out to command
    System.cmd("mix", ["command.projects", "list" | args])

    # Option B: Direct call if command is a dependency
    Mix.Tasks.Command.Projects.List.run(args)
  end
end
```

### Phase 4: Full Migration

1. Run `mix command.projects import --from-yaml ~/p/g/n/portfolio`
2. Verify data integrity
3. Archive YAML files (don't delete - keep as backup)
4. Remove portfolio_coder portfolio commands from active use
5. Update documentation

### Compatibility Matrix

| Old Command | New Command | Notes |
|-------------|-------------|-------|
| `mix portfolio.scan` | `mix command.projects scan` | Discovers repos |
| `mix portfolio.list` | `mix command.projects list` | List with filters |
| `mix portfolio.show <id>` | `mix command.projects show <slug>` | Project details |
| `mix portfolio.sync` | `mix command.projects sync` | Update state |
| `mix portfolio.add` | `mix command.projects create` | Add project |
| `mix portfolio.remove` | `mix command.projects delete` | Remove project |
| `mix portfolio.status` | `mix command.projects status` | Summary view |

---

## Cross-Project Decisions (Decision)

**Decision: Use tags + duplicate with linking for ecosystem decisions.**

### Approach

1. **Single-project decisions:** Normal `project_id` foreign key
2. **Ecosystem decisions:** Create in one project, link via `related_decision_ids`

### Schema Addition

```elixir
schema "project_decisions" do
  # ... existing fields

  # For ecosystem-wide decisions
  field :scope, :string, default: "project"  # project, ecosystem
  field :ecosystem_tag, :string  # e.g., "crucible", "portfolio"
  field :related_decision_ids, {:array, :binary_id}, default: []

  belongs_to :project, Command.Projects.Project  # Can be nil for ecosystem
end
```

### Usage Patterns

```elixir
# Single project decision
create_decision(project, %{
  title: "Use GenStage for backpressure",
  scope: "project"
})

# Ecosystem decision (stored once, tagged)
create_ecosystem_decision(%{
  title: "All crucible-* use consistent telemetry",
  scope: "ecosystem",
  ecosystem_tag: "crucible",
  context: "Need consistent observability across crucible projects",
  decision: "Use OpenTelemetry with shared config module"
})

# Query: "What ecosystem decisions affect portfolio_core?"
def ecosystem_decisions_for(project) do
  from d in Decision,
    where: d.scope == "ecosystem",
    where: d.ecosystem_tag in ^project.tags or d.ecosystem_tag == "all"
end
```

### Why Not Many-to-Many?

- Simpler schema
- Ecosystem decisions are rare (< 5% of decisions)
- Tag-based query is sufficient
- Avoids join table complexity

---

## Test Execution (Decision)

**Decision: Option A - Never run tests automatically. Read cached CI results only.**

### Rationale

1. **Risk:** Running tests can:
   - Take 10+ minutes per project
   - Consume significant CPU/memory
   - Have side effects (database writes, network calls)
   - Fail unpredictably in sandbox environments

2. **CI is authoritative:** Most projects have CI that:
   - Runs on every push
   - Stores results (GitHub Actions, CircleCI, etc.)
   - Is already configured correctly

3. **Sync should be fast:** Hourly sync touching 20+ projects must complete in seconds, not hours

### Implementation

```elixir
defmodule Command.Projects.Scanner do
  # DO: Read CI status from APIs
  def get_ci_status(project) do
    case detect_ci_provider(project) do
      :github_actions -> fetch_github_actions_status(project)
      :circle_ci -> fetch_circle_ci_status(project)
      _ -> %{ci_status: "none", ci_url: nil}
    end
  end

  # DO: Read test results from CI artifacts
  def get_test_results(project) do
    # Parse test count from CI logs/artifacts
    # NOT: Run tests locally
  end

  # DO NOT: Run tests
  # def run_tests(project), do: raise "Not implemented - use CI"
end
```

### Manual Test Execution

For explicit user request only:

```bash
# Explicit command - user knows this is slow
mix command.projects test flowstone --timeout 300
```

```elixir
def run_tests_manually(project, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 120_000)

  IO.puts("Running tests for #{project.name} (timeout: #{div(timeout, 1000)}s)...")

  # Actually run tests, update state
  case Scanner.run_tests(project.path, project.language, timeout: timeout) do
    {:ok, results} ->
      update_state(project, %{
        test_count: results.count,
        test_pass_count: results.passed,
        test_fail_count: results.failed,
        last_test_at: DateTime.utc_now()
      })
    {:error, :timeout} ->
      {:error, "Tests timed out after #{div(timeout, 1000)}s"}
  end
end
```

---

## Resolved Questions Summary

| Question | Decision |
|----------|----------|
| External blocker structure | Structured `blocker_type` enum with `blocker_details` JSONB |
| current_focus lifecycle | Agent-updateable, auto-clears on completion, timestamp tracked |
| Priority + blocked | Separate queries: `list_actionable_work` vs `list_blocked_by_priority` |
| CLI deprecation | Thin wrapper → full migration with compatibility matrix |
| Cross-project decisions | Tags + ecosystem scope, not many-to-many |
| Test execution | Never auto-run; read CI status only; manual command for explicit runs |
| Session ↔ Project | Many-to-many via `session_projects` join table |
| Workflow triggers | Dedicated `project_workflow_triggers` table with condition DSL |
| Synapse signals | Emit on state changes, bridge to PubSub via SignalBridge |
| Tool definitions | ALTAR ADM format with ToolManifest and FunctionDeclarations |

---

## Bulk Execution System

The bulk execution system enables operations like "bump deps across all crucible-*" or "commit all dirty repos with shared message" with proper preview, confirmation, and tracking semantics.

### Design Philosophy

1. **Preview before execute:** All bulk operations start in preview mode
2. **Per-project tracking:** Success/failure tracked individually
3. **Resumable:** Failed items can be retried without re-running successful ones
4. **Auditable:** Full history of what ran, when, by whom

### ChangeSet Schema

A ChangeSet represents a bulk operation across multiple projects.

```elixir
schema "project_changesets" do
  field :name, :string                    # "Bump deps for crucible-*"
  field :status, :string, default: "preview"
  field :operation_type, :string          # shell, file_write, git_commit, custom

  # The command/template to execute
  field :operation, :map
  # Examples:
  # %{"command" => "mix deps.update --all"}
  # %{"command" => "git add -A && git commit -m '{{message}}'", "message" => "Sync configs"}
  # %{"file" => "README.md", "content" => "..."}

  # Which projects are affected
  field :project_filter, :map, default: %{}
  # %{"tags" => ["crucible"], "state.ci_status" => "passing"}

  # Execution options
  field :parallelism, :integer, default: 4
  field :on_failure, :string, default: "continue"  # continue | halt
  field :timeout_ms, :integer, default: 60_000

  # Results tracking
  field :preview_count, :integer, default: 0
  field :success_count, :integer, default: 0
  field :failure_count, :integer, default: 0
  field :skipped_count, :integer, default: 0

  # Timing
  field :previewed_at, :utc_datetime_usec
  field :started_at, :utc_datetime_usec
  field :completed_at, :utc_datetime_usec

  field :metadata, :map, default: %{}

  belongs_to :user, Command.Accounts.User
  belongs_to :workflow_run, Command.Workflows.WorkflowRun  # Optional: if triggered from workflow
  has_many :items, Command.Projects.ChangeSetItem

  timestamps(type: :utc_datetime_usec)
end

@statuses ~w(preview confirmed executing completed failed cancelled)
@operation_types ~w(shell file_write git_commit dependency_update custom)
@failure_modes ~w(continue halt)
```

**Status Flow:**
```
preview → confirmed → executing → completed
                  ↓              ↓
               cancelled       failed
```

### ChangeSetItem Schema

Tracks each project's result within a changeset.

```elixir
schema "project_changeset_items" do
  field :status, :string, default: "pending"
  field :excluded, :boolean, default: false   # User excluded from execution

  # What would/will/did run
  field :resolved_operation, :map             # Template resolved for this project
  # %{"command" => "mix deps.update --all", "cwd" => "/home/user/projects/crucible_core"}

  # Execution results
  field :output, :text
  field :error, :text
  field :exit_code, :integer
  field :duration_ms, :integer

  field :started_at, :utc_datetime_usec
  field :completed_at, :utc_datetime_usec

  belongs_to :changeset, Command.Projects.ChangeSet
  belongs_to :project, Command.Projects.Project

  timestamps(type: :utc_datetime_usec)
end

@item_statuses ~w(pending running success failed skipped excluded)
```

### Context API for ChangeSets

```elixir
# Command.Projects.ChangeSets context

# Create and preview
create_changeset(user, attrs)
preview_changeset(changeset)           # Resolves templates, creates items
add_project_to_changeset(changeset, project)
exclude_from_changeset(changeset, project_or_item)
include_in_changeset(changeset, project_or_item)

# Confirmation and execution
confirm_changeset(changeset)           # status: preview → confirmed
execute_changeset(changeset)           # status: confirmed → executing → completed
cancel_changeset(changeset)            # status: any → cancelled

# Retry and resume
retry_failed(changeset)                # Re-run failed items only
retry_item(item)                       # Re-run single item

# Queries
get_changeset!(id)
list_changesets(user_id, opts \\ [])
list_changeset_items(changeset, opts \\ [])
get_changeset_summary(changeset)       # {preview: N, success: N, failed: N, ...}
```

### Workflow Step: project_operation

For use in Command.Workflows pipelines:

```elixir
# Workflow step definition
%{
  "id" => "bump_deps",
  "type" => "project_operation",
  "config" => %{
    # Project selection
    "select" => %{
      "tags" => ["crucible"],
      "state.ci_status" => "passing",
      "language" => "elixir"
    },

    # Operation
    "operation_type" => "shell",
    "command" => "mix deps.update --all",

    # Execution settings
    "mode" => "preview",           # preview | execute | retry_failed
    "parallelism" => 4,
    "on_failure" => "continue",    # continue | halt
    "timeout_ms" => 120_000,

    # Optional: auto-confirm if conditions met
    "auto_confirm" => false,
    "confirm_condition" => %{      # Only auto-confirm if:
      "max_affected" => 10,        # - No more than 10 projects
      "require_green_ci" => true   # - All have passing CI
    }
  }
}

# Step output
%{
  "changeset_id" => "uuid",
  "status" => "preview",           # or "completed" if auto_confirm + execute
  "summary" => %{
    "preview_count" => 7,
    "success_count" => 0,          # 0 in preview mode
    "failure_count" => 0
  },
  "items" => [
    %{
      "project_slug" => "crucible_core",
      "status" => "pending",
      "resolved_command" => "mix deps.update --all"
    },
    # ...
  ]
}
```

### Example Workflows

#### Workflow 1: Bump Dependencies with Review

```elixir
%{
  "name" => "Bump Crucible Dependencies",
  "steps" => [
    # Step 1: Create preview
    %{
      "id" => "preview_bump",
      "type" => "project_operation",
      "config" => %{
        "select" => %{"tags" => ["crucible"], "state.ci_status" => "passing"},
        "operation_type" => "shell",
        "command" => "mix deps.update --all",
        "mode" => "preview"
      }
    },

    # Step 2: Wait for approval
    %{
      "id" => "approve",
      "type" => "approval",
      "depends_on" => ["preview_bump"],
      "config" => %{
        "prompt" => "Review dependency updates for {{preview_bump.summary.preview_count}} projects",
        "show_details" => true
      }
    },

    # Step 3: Execute
    %{
      "id" => "execute_bump",
      "type" => "project_operation",
      "depends_on" => ["approve"],
      "config" => %{
        "changeset_id" => "{{preview_bump.changeset_id}}",
        "mode" => "execute"
      }
    },

    # Step 4: Run tests on affected projects
    %{
      "id" => "run_tests",
      "type" => "project_operation",
      "depends_on" => ["execute_bump"],
      "config" => %{
        "changeset_id" => "{{execute_bump.changeset_id}}",
        "filter_items" => %{"status" => "success"},  # Only test successful updates
        "operation_type" => "shell",
        "command" => "mix test",
        "mode" => "execute",
        "timeout_ms" => 300_000
      }
    }
  ]
}
```

#### Workflow 2: Commit All Dirty Repos

```elixir
%{
  "name" => "Commit Dirty Repos",
  "steps" => [
    %{
      "id" => "commit_all",
      "type" => "project_operation",
      "config" => %{
        "select" => %{"state.git_dirty" => true},
        "operation_type" => "git_commit",
        "command" => "git add -A && git commit -m '{{message}}'",
        "variables" => %{
          "message" => {"input", "commit_message"}  # From workflow input
        },
        "mode" => "preview"
      }
    },
    %{
      "id" => "approve_commits",
      "type" => "approval",
      "depends_on" => ["commit_all"]
    },
    %{
      "id" => "execute_commits",
      "type" => "project_operation",
      "depends_on" => ["approve_commits"],
      "config" => %{
        "changeset_id" => "{{commit_all.changeset_id}}",
        "mode" => "execute"
      }
    }
  ]
}
```

#### Workflow 3: Push Config File to Multiple Repos

```elixir
%{
  "name" => "Distribute Config File",
  "steps" => [
    %{
      "id" => "write_config",
      "type" => "project_operation",
      "config" => %{
        "select" => %{"language" => "elixir", "category" => "library"},
        "operation_type" => "file_write",
        "file" => ".github/workflows/ci.yml",
        "content" => {"input", "ci_yaml_content"},  # From workflow input
        "mode" => "preview"
      }
    },
    # ... approval and execute steps
  ]
}
```

### CLI Commands for ChangeSets

```bash
# Create and preview
mix command.projects bulk --operation "mix deps.update --all" \
  --filter "tags:crucible,state.ci_status:passing" \
  --name "Q1 deps bump"

# Output:
# Created changeset abc123 (preview)
# Affected projects (7):
#   crucible_core     mix deps.update --all
#   crucible_bench    mix deps.update --all
#   crucible_telemetry mix deps.update --all
#   ...
# Run `mix command.projects bulk:confirm abc123` to confirm

# Exclude a project
mix command.projects bulk:exclude abc123 crucible_bench

# Confirm and execute
mix command.projects bulk:confirm abc123
mix command.projects bulk:execute abc123

# Or confirm + execute in one
mix command.projects bulk:run abc123

# Check status
mix command.projects bulk:status abc123

# Output:
# Changeset abc123: executing (3/7)
#   crucible_core       ✓ success (2.3s)
#   crucible_bench      ⊘ excluded
#   crucible_telemetry  ✓ success (1.8s)
#   crucible_store      ◌ running...
#   crucible_web        ◌ pending
#   crucible_api        ◌ pending
#   crucible_worker     ◌ pending

# Retry failures
mix command.projects bulk:retry abc123

# Cancel
mix command.projects bulk:cancel abc123

# List recent changesets
mix command.projects bulk:list --status completed --limit 10
```

### Agent Tool for Bulk Operations

```elixir
def bulk_operation_tool do
  {:ok, tool} = Tool.new(%{
    function_declarations: [
      %{
        name: "create_bulk_operation",
        description: "Create a preview of a bulk operation across multiple projects. Returns a changeset ID that can be reviewed, modified, and executed.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "name" => %{
              "type" => "string",
              "description" => "Human-readable name for this operation"
            },
            "operation_type" => %{
              "type" => "string",
              "enum" => ["shell", "git_commit", "file_write"],
              "description" => "Type of operation to perform"
            },
            "command" => %{
              "type" => "string",
              "description" => "Shell command or git command to run. Use {{variable}} for templating."
            },
            "project_filter" => %{
              "type" => "object",
              "description" => "Filter for which projects to include. Keys: tags, language, category, status, state.ci_status, state.git_dirty"
            }
          },
          "required" => ["name", "operation_type", "command", "project_filter"]
        }
      },
      %{
        name: "get_changeset_preview",
        description: "Get the preview of a bulk operation changeset, showing which projects would be affected and what would run.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "changeset_id" => %{"type" => "string"}
          },
          "required" => ["changeset_id"]
        }
      },
      %{
        name: "execute_changeset",
        description: "Execute a confirmed changeset. Requires prior user approval.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "changeset_id" => %{"type" => "string"},
            "require_approval" => %{
              "type" => "boolean",
              "description" => "If true, marks for approval. If false, executes immediately (requires pre-approval)."
            }
          },
          "required" => ["changeset_id"]
        }
      },
      %{
        name: "get_changeset_status",
        description: "Get current status and results of a changeset execution.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "changeset_id" => %{"type" => "string"}
          },
          "required" => ["changeset_id"]
        }
      }
    ]
  })
  tool
end
```

### Safety Constraints

1. **Approval required by default:** ChangeSets require explicit confirmation before execution
2. **No auto-execute in preview:** `mode: "preview"` never executes
3. **Timeout enforcement:** All operations have configurable timeouts
4. **Output capture:** All stdout/stderr captured for audit
5. **Atomic per-project:** Each project's operation is independent
6. **No cascading failures:** `on_failure: "continue"` is default

### Dangerous Operations Checklist

Operations that require additional confirmation:

| Operation | Risk | Mitigation |
|-----------|------|------------|
| `git push --force` | History loss | Block unless explicit flag |
| `rm -rf` | Data loss | Block entirely |
| `DROP TABLE` | Data loss | Block entirely |
| `git reset --hard` | Work loss | Require `--allow-destructive` |
| Anything with `sudo` | Privilege escalation | Block entirely |

```elixir
@blocked_patterns [
  ~r/sudo\s/,
  ~r/rm\s+-rf?\s+\//,
  ~r/DROP\s+TABLE/i,
  ~r/DELETE\s+FROM/i,
  ~r/TRUNCATE/i
]

@requires_destructive_flag [
  ~r/--force/,
  ~r/--hard/,
  ~r/-f\s/
]

def validate_operation(command, opts \\ []) do
  allow_destructive = Keyword.get(opts, :allow_destructive, false)

  cond do
    Enum.any?(@blocked_patterns, &Regex.match?(&1, command)) ->
      {:error, :operation_blocked, "This operation type is not allowed in bulk execution"}

    not allow_destructive and Enum.any?(@requires_destructive_flag, &Regex.match?(&1, command)) ->
      {:error, :requires_flag, "This operation requires --allow-destructive flag"}

    true ->
      :ok
  end
end
```

### Integration with Existing Systems

| System | Integration |
|--------|-------------|
| **Workflows** | `project_operation` step type uses ChangeSets |
| **Sessions** | Changeset execution creates session history |
| **Synapse Signals** | Emit `changeset.started`, `changeset.completed`, `changeset.item.completed` |
| **PubSub** | Real-time progress updates to UI |
| **Telemetry** | Duration, success rate, failure reasons |

### ChangeSet Signals

```elixir
@changeset_signals %{
  changeset_created: "changeset.created",
  changeset_confirmed: "changeset.confirmed",
  changeset_started: "changeset.started",
  changeset_completed: "changeset.completed",
  changeset_failed: "changeset.failed",
  changeset_cancelled: "changeset.cancelled",
  changeset_item_started: "changeset.item.started",
  changeset_item_completed: "changeset.item.completed",
  changeset_item_failed: "changeset.item.failed"
}
```
