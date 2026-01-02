defmodule Command.Agents do
  @moduledoc """
  The Agents context.

  Manages agent calls and tool uses.
  """

  import Ecto.Query

  alias Command.Agents.{AgentCall, ToolUse}
  alias Command.Repo
  alias Command.Sessions.Session

  # Agent Calls

  @doc """
  Creates a new agent call.
  """
  @spec create_agent_call(Session.t(), map()) ::
          {:ok, AgentCall.t()} | {:error, Ecto.Changeset.t()}
  def create_agent_call(session, attrs) do
    attrs =
      attrs
      |> Map.put(:session_id, session.id)
      |> Map.put(:user_id, session.user_id)

    %AgentCall{}
    |> AgentCall.create_changeset(attrs)
    |> Repo.insert()
    |> broadcast_agent_call_change(:agent_call_created)
  end

  @doc """
  Returns a changeset for tracking agent call changes.

  ## Examples

      iex> change_agent_call(call)
      %Ecto.Changeset{data: %AgentCall{}}

      iex> change_agent_call(call, %{model: "claude-sonnet-4"})
      %Ecto.Changeset{data: %AgentCall{}}
  """
  @spec change_agent_call(AgentCall.t(), map()) :: Ecto.Changeset.t()
  def change_agent_call(%AgentCall{} = call, attrs \\ %{}) do
    AgentCall.create_changeset(call, attrs)
  end

  @doc """
  Gets an agent call by ID.
  """
  @spec get_agent_call(Ecto.UUID.t()) :: AgentCall.t() | nil
  def get_agent_call(id), do: Repo.get(AgentCall, id)

  @doc """
  Gets an agent call by ID, raising if not found.
  """
  @spec get_agent_call!(Ecto.UUID.t()) :: AgentCall.t()
  def get_agent_call!(id), do: Repo.get!(AgentCall, id)

  @doc """
  Marks an agent call as streaming.
  """
  @spec start_streaming(AgentCall.t()) :: {:ok, AgentCall.t()} | {:error, Ecto.Changeset.t()}
  def start_streaming(call) do
    call
    |> AgentCall.streaming_changeset()
    |> Repo.update()
    |> broadcast_agent_call_change(:agent_call_streaming)
  end

  @doc """
  Completes an agent call successfully.
  """
  @spec complete_agent_call(AgentCall.t(), map()) ::
          {:ok, AgentCall.t()} | {:error, Ecto.Changeset.t()}
  def complete_agent_call(call, attrs) do
    call
    |> AgentCall.complete_changeset(attrs)
    |> Repo.update()
    |> broadcast_agent_call_change(:agent_call_completed)
  end

  @doc """
  Marks an agent call as failed.
  """
  @spec fail_agent_call(AgentCall.t(), map()) ::
          {:ok, AgentCall.t()} | {:error, Ecto.Changeset.t()}
  def fail_agent_call(call, attrs) do
    call
    |> AgentCall.failure_changeset(attrs)
    |> Repo.update()
    |> broadcast_agent_call_change(:agent_call_failed)
  end

  @doc """
  Cancels an agent call.
  """
  @spec cancel_agent_call(AgentCall.t()) :: {:ok, AgentCall.t()} | {:error, Ecto.Changeset.t()}
  def cancel_agent_call(call) do
    call
    |> AgentCall.cancel_changeset()
    |> Repo.update()
  end

  @doc """
  Lists agent calls for a session.
  """
  @spec list_agent_calls(Session.t(), keyword()) :: [AgentCall.t()]
  def list_agent_calls(session, opts \\ []) do
    AgentCall
    |> where([c], c.session_id == ^session.id)
    |> apply_agent_call_filters(opts)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  # Tool Uses

  @doc """
  Creates a tool use for an agent call.
  """
  @spec create_tool_use(AgentCall.t(), map()) ::
          {:ok, ToolUse.t()} | {:error, Ecto.Changeset.t()}
  def create_tool_use(call, attrs) do
    sequence = get_next_tool_sequence(call)

    attrs =
      attrs
      |> Map.put(:agent_call_id, call.id)
      |> Map.put(:session_id, call.session_id)
      |> Map.put(:sequence, sequence)

    %ToolUse{}
    |> ToolUse.create_changeset(attrs)
    |> Repo.insert()
    |> broadcast_tool_use_change(:tool_use_created)
  end

  @doc """
  Returns a changeset for tracking tool use changes.

  ## Examples

      iex> change_tool_use(tool_use)
      %Ecto.Changeset{data: %ToolUse{}}

      iex> change_tool_use(tool_use, %{tool_name: "bash"})
      %Ecto.Changeset{data: %ToolUse{}}
  """
  @spec change_tool_use(ToolUse.t(), map()) :: Ecto.Changeset.t()
  def change_tool_use(%ToolUse{} = tool_use, attrs \\ %{}) do
    ToolUse.create_changeset(tool_use, attrs)
  end

  @doc """
  Gets a tool use by ID.
  """
  @spec get_tool_use(Ecto.UUID.t()) :: ToolUse.t() | nil
  def get_tool_use(id), do: Repo.get(ToolUse, id)

  @doc """
  Approves a tool use.
  """
  @spec approve_tool_use(ToolUse.t(), map()) ::
          {:ok, ToolUse.t()} | {:error, Ecto.Changeset.t()}
  def approve_tool_use(tool_use, attrs \\ %{}) do
    tool_use
    |> ToolUse.approve_changeset(attrs)
    |> Repo.update()
    |> broadcast_tool_use_change(:tool_use_approved)
  end

  @doc """
  Denies a tool use.
  """
  @spec deny_tool_use(ToolUse.t(), map()) :: {:ok, ToolUse.t()} | {:error, Ecto.Changeset.t()}
  def deny_tool_use(tool_use, attrs) do
    tool_use
    |> ToolUse.deny_changeset(attrs)
    |> Repo.update()
    |> broadcast_tool_use_change(:tool_use_denied)
  end

  @doc """
  Marks a tool use as executing.
  """
  @spec start_tool_execution(ToolUse.t()) :: {:ok, ToolUse.t()} | {:error, Ecto.Changeset.t()}
  def start_tool_execution(tool_use) do
    tool_use
    |> ToolUse.executing_changeset()
    |> Repo.update()
  end

  @doc """
  Completes a tool use successfully.
  """
  @spec complete_tool_use(ToolUse.t(), map()) ::
          {:ok, ToolUse.t()} | {:error, Ecto.Changeset.t()}
  def complete_tool_use(tool_use, attrs) do
    tool_use
    |> ToolUse.complete_changeset(attrs)
    |> Repo.update()
    |> broadcast_tool_use_change(:tool_use_completed)
  end

  @doc """
  Marks a tool use as failed.
  """
  @spec fail_tool_use(ToolUse.t(), map()) :: {:ok, ToolUse.t()} | {:error, Ecto.Changeset.t()}
  def fail_tool_use(tool_use, attrs) do
    tool_use
    |> ToolUse.failure_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists tool uses for an agent call.
  """
  @spec list_tool_uses(AgentCall.t()) :: [ToolUse.t()]
  def list_tool_uses(call) do
    ToolUse
    |> where([t], t.agent_call_id == ^call.id)
    |> order_by([t], asc: t.sequence)
    |> Repo.all()
  end

  @doc """
  Lists pending tool uses requiring approval.
  """
  @spec list_pending_tool_uses(Session.t()) :: [ToolUse.t()]
  def list_pending_tool_uses(session) do
    ToolUse
    |> where([t], t.session_id == ^session.id)
    |> where([t], t.requires_approval == true and t.status == "pending")
    |> order_by([t], asc: t.inserted_at)
    |> Repo.all()
  end

  # Private helpers

  defp broadcast_agent_call_change(result, event) do
    case result do
      {:ok, call} = success ->
        _ = Command.PubSub.broadcast("session:#{call.session_id}:agent_calls", event, call)
        success

      error ->
        error
    end
  end

  defp broadcast_tool_use_change(result, event) do
    case result do
      {:ok, tool_use} = success ->
        _ =
          Command.PubSub.broadcast("session:#{tool_use.session_id}:agent_calls", event, tool_use)

        success

      error ->
        error
    end
  end

  defp get_next_tool_sequence(call) do
    ToolUse
    |> where([t], t.agent_call_id == ^call.id)
    |> Repo.aggregate(:max, :sequence)
    |> case do
      nil -> 1
      max -> max + 1
    end
  end

  defp apply_agent_call_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [c], c.status == ^status)

      {:provider, provider}, query ->
        where(query, [c], c.provider == ^provider)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
