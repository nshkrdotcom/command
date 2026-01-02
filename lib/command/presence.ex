defmodule Command.Presence do
  @moduledoc """
  The Presence context.

  Manages user presence and activity logging.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Presence.{ActivityLog, PresenceRecord}
  alias Command.Repo

  # Presence Records

  @doc """
  Joins a resource (creates presence record).
  """
  @spec join_resource(User.t(), String.t(), Ecto.UUID.t(), map()) ::
          {:ok, PresenceRecord.t()} | {:error, Ecto.Changeset.t()}
  def join_resource(user, resource_type, resource_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:resource_type, resource_type)
      |> Map.put(:resource_id, resource_id)

    %PresenceRecord{}
    |> PresenceRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates presence status.
  """
  @spec update_presence(PresenceRecord.t(), map()) ::
          {:ok, PresenceRecord.t()} | {:error, Ecto.Changeset.t()}
  def update_presence(presence, attrs) do
    presence
    |> PresenceRecord.status_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Records a heartbeat.
  """
  @spec heartbeat(PresenceRecord.t()) ::
          {:ok, PresenceRecord.t()} | {:error, Ecto.Changeset.t()}
  def heartbeat(presence) do
    presence
    |> PresenceRecord.heartbeat_changeset()
    |> Repo.update()
  end

  @doc """
  Leaves a resource.
  """
  @spec leave_resource(PresenceRecord.t()) ::
          {:ok, PresenceRecord.t()} | {:error, Ecto.Changeset.t()}
  def leave_resource(presence) do
    presence
    |> PresenceRecord.leave_changeset()
    |> Repo.update()
  end

  @doc """
  Gets presence by client ID.
  """
  @spec get_presence_by_client(String.t()) :: PresenceRecord.t() | nil
  def get_presence_by_client(client_id) do
    Repo.get_by(PresenceRecord, client_id: client_id)
  end

  @doc """
  Lists active presence for a resource.
  """
  @spec list_resource_presence(String.t(), Ecto.UUID.t()) :: [PresenceRecord.t()]
  def list_resource_presence(resource_type, resource_id) do
    stale_threshold = DateTime.add(DateTime.utc_now(), -60, :second)

    PresenceRecord
    |> where([p], p.resource_type == ^resource_type)
    |> where([p], p.resource_id == ^resource_id)
    |> where([p], is_nil(p.left_at))
    |> where([p], p.last_seen_at > ^stale_threshold)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Cleans up stale presence records.
  """
  @spec cleanup_stale_presence() :: {integer(), nil}
  def cleanup_stale_presence do
    stale_threshold = DateTime.add(DateTime.utc_now(), -300, :second)
    now = DateTime.utc_now()

    PresenceRecord
    |> where([p], is_nil(p.left_at) and p.last_seen_at < ^stale_threshold)
    |> Repo.update_all(set: [left_at: now])
  end

  # Activity Logs

  @doc """
  Logs an activity.
  """
  @spec log_activity(map()) :: {:ok, ActivityLog.t()} | {:error, Ecto.Changeset.t()}
  def log_activity(attrs) do
    %ActivityLog{}
    |> ActivityLog.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Logs an activity for a user.
  """
  @spec log_user_activity(User.t(), String.t(), String.t(), Ecto.UUID.t(), map()) ::
          {:ok, ActivityLog.t()} | {:error, Ecto.Changeset.t()}
  def log_user_activity(user, action, resource_type, resource_id, details \\ %{}) do
    log_activity(%{
      user_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      details: details
    })
  end

  @doc """
  Lists activity logs for a user.
  """
  @spec list_user_activity(User.t(), keyword()) :: [ActivityLog.t()]
  def list_user_activity(user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ActivityLog
    |> where([l], l.user_id == ^user.id)
    |> order_by([l], desc: l.occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists activity logs for a resource.
  """
  @spec list_resource_activity(String.t(), Ecto.UUID.t(), keyword()) :: [ActivityLog.t()]
  def list_resource_activity(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    ActivityLog
    |> where([l], l.resource_type == ^resource_type and l.resource_id == ^resource_id)
    |> order_by([l], desc: l.occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Searches activity logs.
  """
  @spec search_activity(keyword()) :: [ActivityLog.t()]
  def search_activity(opts) do
    ActivityLog
    |> apply_activity_filters(opts)
    |> order_by([l], desc: l.occurred_at)
    |> limit(100)
    |> Repo.all()
  end

  # Private helpers

  defp apply_activity_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:user_id, user_id}, query ->
        where(query, [l], l.user_id == ^user_id)

      {:action, action}, query ->
        where(query, [l], l.action == ^action)

      {:resource_type, resource_type}, query ->
        where(query, [l], l.resource_type == ^resource_type)

      {:since, since}, query ->
        where(query, [l], l.occurred_at >= ^since)

      {:until, until}, query ->
        where(query, [l], l.occurred_at <= ^until)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
