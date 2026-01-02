defmodule Command.Factory do
  @moduledoc """
  Factory module for creating test data.
  """

  use ExMachina.Ecto, repo: Command.Repo

  alias Command.Accounts.{ApiCredential, User}
  alias Command.Agents.{AgentCall, ToolUse}
  alias Command.Approvals.{ApprovalItem, ApprovalRule}
  alias Command.Artifacts.Artifact
  alias Command.Costs.{CostDailySummary, CostRecord}
  alias Command.Indexes.{ContextChunk, ContextDocument, Index}
  alias Command.Presence.{ActivityLog, PresenceRecord}
  alias Command.Scheduling.ScheduledJob
  alias Command.Sessions.{Message, Session}
  alias Command.Workflows.{Workflow, WorkflowRun, WorkflowStep}

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: sequence(:name, &"User #{&1}"),
      status: "active",
      preferences: %{},
      api_keys: %{}
    }
  end

  def api_credential_factory do
    %ApiCredential{
      user: build(:user),
      name: sequence(:credential_name, &"API Key #{&1}"),
      provider: "anthropic",
      encrypted_key: "encrypted_test_key",
      key_hint: "test",
      status: "active"
    }
  end

  def session_factory do
    %Session{
      user: build(:user),
      name: sequence(:session_name, &"Session #{&1}"),
      purpose: "Testing",
      slug: sequence(:session_slug, &"session-#{&1}"),
      status: "active"
    }
  end

  def message_factory do
    %Message{
      session: build(:session),
      role: "user",
      content: "Test message content",
      sequence: sequence(:sequence, & &1)
    }
  end

  def agent_call_factory do
    session = build(:session)

    %AgentCall{
      session: session,
      user: session.user,
      provider: "anthropic",
      model: "claude-sonnet-4-20250514",
      status: "pending",
      prompt_messages: [%{"role" => "user", "content" => "Test prompt"}],
      started_at: DateTime.utc_now()
    }
  end

  def tool_use_factory do
    call = build(:agent_call)

    %ToolUse{
      agent_call: call,
      session: call.session,
      tool_name: "bash",
      tool_use_id: sequence(:tool_use_id, &"toolu_#{&1}"),
      input: %{"command" => "echo test"},
      status: "pending",
      sequence: 1
    }
  end

  def workflow_factory do
    %Workflow{
      user: build(:user),
      name: sequence(:workflow_name, &"Workflow #{&1}"),
      slug: sequence(:workflow_slug, &"workflow-#{&1}"),
      status: "draft",
      steps: [
        %{
          "id" => "step_1",
          "name" => "First Step",
          "type" => "agent_call",
          "config" => %{}
        }
      ]
    }
  end

  def workflow_run_factory do
    workflow = build(:workflow)

    %WorkflowRun{
      workflow: workflow,
      user: workflow.user,
      workflow_snapshot: %{
        "id" => workflow.id,
        "name" => workflow.name,
        "version" => 1,
        "steps" => workflow.steps
      },
      status: "pending",
      input: %{}
    }
  end

  def workflow_step_factory do
    %WorkflowStep{
      workflow_run: build(:workflow_run),
      step_id: "step_1",
      step_name: "Test Step",
      step_type: "agent_call",
      step_config: %{},
      status: "pending",
      sequence: 1
    }
  end

  def index_factory do
    %Index{
      user: build(:user),
      name: sequence(:index_name, &"Index #{&1}"),
      slug: sequence(:index_slug, &"index-#{&1}"),
      status: "creating",
      source_type: "local_repo",
      source_config: %{"path" => "/tmp/repo"}
    }
  end

  def context_document_factory do
    %ContextDocument{
      index: build(:index),
      uri: sequence(:document_uri, &"/tmp/file#{&1}.ex"),
      source_type: "file",
      content_hash: sequence(:content_hash, &"hash#{&1}")
    }
  end

  def context_chunk_factory do
    %ContextChunk{
      index: build(:index),
      source_uri: sequence(:chunk_source, &"/tmp/file#{&1}.ex"),
      source_type: "file",
      content: "defmodule Test do\n  def hello, do: :world\nend",
      content_hash: sequence(:chunk_hash, &"chunkhash#{&1}"),
      chunk_index: 0,
      token_count: 20
    }
  end

  def approval_item_factory do
    session = build(:session)

    %ApprovalItem{
      user: session.user,
      session: session,
      approval_type: "tool_use",
      status: "pending",
      priority: "normal",
      title: "Approve bash command",
      payload: %{"command" => "echo test"},
      source_type: "tool_use"
    }
  end

  def approval_rule_factory do
    %ApprovalRule{
      user: build(:user),
      name: sequence(:rule_name, &"Rule #{&1}"),
      approval_type: "tool_use",
      conditions: %{},
      action: "approve",
      status: "active"
    }
  end

  def artifact_factory do
    %Artifact{
      user: build(:user),
      name: sequence(:artifact_name, &"artifact#{&1}.txt"),
      artifact_type: "file",
      storage_backend: "inline",
      inline_content: "test content"
    }
  end

  def cost_record_factory do
    user = build(:user)

    %CostRecord{
      user: user,
      source_type: "agent_call",
      source_id: Ecto.UUID.generate(),
      provider: "anthropic",
      service: "chat",
      model: "claude-sonnet-4-20250514",
      tokens_in: 100,
      tokens_out: 50,
      cost_cents: 5,
      incurred_at: DateTime.utc_now(),
      day: Date.utc_today()
    }
  end

  def cost_daily_summary_factory do
    %CostDailySummary{
      user: build(:user),
      day: Date.utc_today(),
      total_cost_cents: 100,
      total_tokens_in: 1000,
      total_tokens_out: 500,
      total_requests: 10
    }
  end

  def scheduled_job_factory do
    %ScheduledJob{
      user: build(:user),
      job_type: "workflow",
      job_config: %{"workflow_id" => Ecto.UUID.generate()},
      schedule_type: "once",
      run_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      status: "active"
    }
  end

  def presence_record_factory do
    %PresenceRecord{
      user: build(:user),
      resource_type: "session",
      resource_id: Ecto.UUID.generate(),
      client_id: sequence(:client_id, &"client_#{&1}"),
      status: "viewing",
      joined_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now()
    }
  end

  def activity_log_factory do
    %ActivityLog{
      user: build(:user),
      action: "session.create",
      resource_type: "session",
      resource_id: Ecto.UUID.generate(),
      details: %{},
      occurred_at: DateTime.utc_now()
    }
  end
end
