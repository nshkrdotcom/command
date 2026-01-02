defmodule Command.Sessions do
  @moduledoc """
  The Sessions context.

  Manages sessions and messages for agent conversations.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Repo
  alias Command.Sessions.{Message, Session}

  # Sessions

  @doc """
  Creates a new session for a user.

  ## Examples

      iex> create_session(user, %{name: "Code Review"})
      {:ok, %Session{}}
  """
  @spec create_session(User.t(), map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %Session{}
    |> Session.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a session by ID.
  """
  @spec get_session(Ecto.UUID.t()) :: Session.t() | nil
  def get_session(id), do: Repo.get(Session, id)

  @doc """
  Gets a session by ID, raising if not found.
  """
  @spec get_session!(Ecto.UUID.t()) :: Session.t()
  def get_session!(id), do: Repo.get!(Session, id)

  @doc """
  Gets a session by slug for a user.
  """
  @spec get_session_by_slug(User.t(), String.t()) :: Session.t() | nil
  def get_session_by_slug(user, slug) do
    Repo.get_by(Session, user_id: user.id, slug: slug)
  end

  @doc """
  Lists sessions for a user.
  """
  @spec list_sessions(User.t(), keyword()) :: [Session.t()]
  def list_sessions(user, opts \\ []) do
    Session
    |> where([s], s.user_id == ^user.id)
    |> apply_session_filters(opts)
    |> order_by([s], desc: s.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists active sessions for a user.
  """
  @spec list_active_sessions(User.t()) :: [Session.t()]
  def list_active_sessions(user) do
    list_sessions(user, status: "active")
  end

  @doc """
  Updates a session's status.
  """
  @spec update_session_status(Session.t(), String.t()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def update_session_status(session, status) do
    session
    |> Session.status_changeset(%{status: status})
    |> Repo.update()
  end

  @doc """
  Updates a session's configuration.
  """
  @spec update_session_config(Session.t(), map()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def update_session_config(session, attrs) do
    session
    |> Session.config_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Archives a session.
  """
  @spec archive_session(Session.t()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def archive_session(session) do
    update_session_status(session, "archived")
  end

  @doc """
  Forks a session at a specific message.
  """
  @spec fork_session(Session.t(), Message.t(), map()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def fork_session(session, message, attrs) do
    attrs =
      attrs
      |> Map.put(:user_id, session.user_id)
      |> Map.put(:parent_session_id, session.id)
      |> Map.put(:forked_at_message_id, message.id)
      |> Map.put_new(:name, "Fork of #{session.name}")
      |> Map.put_new(:default_agent, session.default_agent)
      |> Map.put_new(:default_model, session.default_model)
      |> Map.put_new(:system_prompt, session.system_prompt)

    %Session{}
    |> Session.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Increments session stats after an agent call.
  """
  @spec increment_session_stats(Session.t(), map()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def increment_session_stats(session, stats) do
    session
    |> Session.stats_changeset(%{
      message_count: session.message_count + (stats[:message_count] || 0),
      total_tokens_in: session.total_tokens_in + (stats[:tokens_in] || 0),
      total_tokens_out: session.total_tokens_out + (stats[:tokens_out] || 0),
      total_cost_cents: session.total_cost_cents + (stats[:cost_cents] || 0),
      total_duration_ms: session.total_duration_ms + (stats[:duration_ms] || 0)
    })
    |> Repo.update()
  end

  # Messages

  @doc """
  Creates a message in a session.
  """
  @spec create_message(Session.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def create_message(session, attrs) do
    sequence = get_next_message_sequence(session)

    attrs =
      attrs
      |> Map.put(:session_id, session.id)
      |> Map.put(:sequence, sequence)

    %Message{}
    |> Message.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a message by ID.
  """
  @spec get_message(Ecto.UUID.t()) :: Message.t() | nil
  def get_message(id), do: Repo.get(Message, id)

  @doc """
  Lists messages in a session.
  """
  @spec list_messages(Session.t(), keyword()) :: [Message.t()]
  def list_messages(session, opts \\ []) do
    Message
    |> where([m], m.session_id == ^session.id)
    |> apply_message_filters(opts)
    |> order_by([m], asc: m.sequence)
    |> Repo.all()
  end

  @doc """
  Gets the conversation history for a session.
  """
  @spec get_conversation_history(Session.t(), keyword()) :: [Message.t()]
  def get_conversation_history(session, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    roles = Keyword.get(opts, :roles, ["user", "assistant", "system"])

    query =
      Message
      |> where([m], m.session_id == ^session.id)
      |> where([m], m.role in ^roles)
      |> order_by([m], desc: m.sequence)

    query = if limit, do: limit(query, ^limit), else: query

    query
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Counts messages in a session.
  """
  @spec count_messages(Session.t()) :: integer()
  def count_messages(session) do
    Message
    |> where([m], m.session_id == ^session.id)
    |> Repo.aggregate(:count)
  end

  # Private helpers

  defp get_next_message_sequence(session) do
    Message
    |> where([m], m.session_id == ^session.id)
    |> Repo.aggregate(:max, :sequence)
    |> case do
      nil -> 1
      max -> max + 1
    end
  end

  defp apply_session_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [s], s.status == ^status)

      {:tags, tags}, query when is_list(tags) ->
        where(query, [s], fragment("? && ?", s.tags, ^tags))

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end

  defp apply_message_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:role, role}, query ->
        where(query, [m], m.role == ^role)

      {:limit, limit}, query ->
        limit(query, ^limit)

      {:after_sequence, seq}, query ->
        where(query, [m], m.sequence > ^seq)

      _, query ->
        query
    end)
  end
end
