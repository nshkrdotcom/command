defmodule Command.Approvals do
  @moduledoc """
  The Approvals context.

  Manages approval items and rules for human-in-the-loop workflows.
  """

  import Ecto.Query

  alias Command.Accounts.User
  alias Command.Approvals.{ApprovalItem, ApprovalRule}
  alias Command.Repo
  alias Command.Sessions.Session

  # Approval Items

  @doc """
  Creates an approval item.
  """
  @spec create_approval_item(User.t(), map()) ::
          {:ok, ApprovalItem.t()} | {:error, Ecto.Changeset.t()}
  def create_approval_item(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %ApprovalItem{}
    |> ApprovalItem.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an approval item by ID.
  """
  @spec get_approval_item(Ecto.UUID.t()) :: ApprovalItem.t() | nil
  def get_approval_item(id), do: Repo.get(ApprovalItem, id)

  @doc """
  Approves an item.
  """
  @spec approve_item(ApprovalItem.t(), User.t(), map()) ::
          {:ok, ApprovalItem.t()} | {:error, Ecto.Changeset.t()}
  def approve_item(item, user, attrs \\ %{}) do
    attrs = Map.put(attrs, :decided_by_id, user.id)

    item
    |> ApprovalItem.approve_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Denies an item.
  """
  @spec deny_item(ApprovalItem.t(), User.t(), map()) ::
          {:ok, ApprovalItem.t()} | {:error, Ecto.Changeset.t()}
  def deny_item(item, user, attrs \\ %{}) do
    attrs = Map.put(attrs, :decided_by_id, user.id)

    item
    |> ApprovalItem.deny_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists pending approval items for a user.
  """
  @spec list_pending_approvals(User.t(), keyword()) :: [ApprovalItem.t()]
  def list_pending_approvals(user, opts \\ []) do
    ApprovalItem
    |> where([a], a.user_id == ^user.id and a.status == "pending")
    |> apply_approval_filters(opts)
    |> order_by([a], asc: a.priority, asc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists pending approvals for a session.
  """
  @spec list_session_pending_approvals(Session.t()) :: [ApprovalItem.t()]
  def list_session_pending_approvals(session) do
    ApprovalItem
    |> where([a], a.session_id == ^session.id and a.status == "pending")
    |> order_by([a], asc: a.priority, asc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Counts pending approvals for a user.
  """
  @spec count_pending_approvals(User.t()) :: integer()
  def count_pending_approvals(user) do
    ApprovalItem
    |> where([a], a.user_id == ^user.id and a.status == "pending")
    |> Repo.aggregate(:count)
  end

  @doc """
  Expires old pending approvals.
  """
  @spec expire_old_approvals() :: {integer(), nil | [term()]}
  def expire_old_approvals do
    now = DateTime.utc_now()

    ApprovalItem
    |> where([a], a.status == "pending" and a.expires_at < ^now)
    |> Repo.update_all(set: [status: "expired", decided_at: now])
  end

  @doc """
  Attempts to auto-approve an item based on rules.
  """
  @spec try_auto_approve(ApprovalItem.t()) ::
          {:ok, ApprovalItem.t()} | {:no_match, ApprovalItem.t()}
  def try_auto_approve(item) do
    case find_matching_rule(item) do
      nil ->
        {:no_match, item}

      rule ->
        case rule.action do
          "approve" ->
            {:ok, updated} =
              item
              |> ApprovalItem.auto_approve_changeset(%{
                auto_approval_rule_id: rule.id,
                auto_approval_reason: rule.action_note
              })
              |> Repo.update()

            record_rule_trigger(rule)
            {:ok, updated}

          "deny" ->
            {:ok, updated} =
              item
              |> ApprovalItem.deny_changeset(%{
                decision_note: rule.action_note
              })
              |> Repo.update()

            record_rule_trigger(rule)
            {:ok, updated}

          _ ->
            {:no_match, item}
        end
    end
  end

  # Approval Rules

  @doc """
  Creates an approval rule.
  """
  @spec create_approval_rule(User.t(), map()) ::
          {:ok, ApprovalRule.t()} | {:error, Ecto.Changeset.t()}
  def create_approval_rule(user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %ApprovalRule{}
    |> ApprovalRule.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets an approval rule by ID.
  """
  @spec get_approval_rule(Ecto.UUID.t()) :: ApprovalRule.t() | nil
  def get_approval_rule(id), do: Repo.get(ApprovalRule, id)

  @doc """
  Updates an approval rule.
  """
  @spec update_approval_rule(ApprovalRule.t(), map()) ::
          {:ok, ApprovalRule.t()} | {:error, Ecto.Changeset.t()}
  def update_approval_rule(rule, attrs) do
    rule
    |> ApprovalRule.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists approval rules for a user.
  """
  @spec list_approval_rules(User.t()) :: [ApprovalRule.t()]
  def list_approval_rules(user) do
    ApprovalRule
    |> where([r], r.user_id == ^user.id)
    |> order_by([r], desc: r.priority)
    |> Repo.all()
  end

  @doc """
  Enables an approval rule.
  """
  @spec enable_rule(ApprovalRule.t()) :: {:ok, ApprovalRule.t()} | {:error, Ecto.Changeset.t()}
  def enable_rule(rule) do
    rule
    |> ApprovalRule.status_changeset(%{status: "active"})
    |> Repo.update()
  end

  @doc """
  Disables an approval rule.
  """
  @spec disable_rule(ApprovalRule.t()) :: {:ok, ApprovalRule.t()} | {:error, Ecto.Changeset.t()}
  def disable_rule(rule) do
    rule
    |> ApprovalRule.status_changeset(%{status: "disabled"})
    |> Repo.update()
  end

  # Private helpers

  defp find_matching_rule(item) do
    ApprovalRule
    |> where([r], r.user_id == ^item.user_id)
    |> where([r], r.status == "active")
    |> where([r], r.approval_type == ^item.approval_type or r.approval_type == "*")
    |> order_by([r], desc: r.priority)
    |> Repo.all()
    |> Enum.find(&rule_matches?(item, &1))
  end

  defp rule_matches?(item, rule) do
    # Check tool names if applicable
    tool_match =
      case rule.tool_names do
        [] -> true
        names -> Map.get(item.payload, "tool_name") in names
      end

    # Check conditions
    conditions_match = match_conditions(item, rule.conditions)

    # Check hourly limit
    within_limit = check_hourly_limit(rule)

    tool_match && conditions_match && within_limit
  end

  defp match_conditions(_item, conditions) when conditions == %{}, do: true

  defp match_conditions(item, conditions) do
    Enum.all?(conditions, fn {key, expected} ->
      actual = get_in(item.payload, [to_string(key)])
      matches_condition?(actual, expected)
    end)
  end

  defp matches_condition?(actual, expected) when is_list(expected) do
    actual in expected
  end

  defp matches_condition?(actual, expected) when is_binary(expected) do
    case Regex.compile(expected) do
      {:ok, regex} -> Regex.match?(regex, to_string(actual))
      _ -> actual == expected
    end
  end

  defp matches_condition?(actual, expected), do: actual == expected

  defp check_hourly_limit(rule) do
    case rule.max_auto_approvals_per_hour do
      nil -> true
      max -> (rule.current_hour_count || 0) < max
    end
  end

  defp record_rule_trigger(rule) do
    rule
    |> ApprovalRule.trigger_changeset()
    |> Repo.update()
  end

  defp apply_approval_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:approval_type, type}, query ->
        where(query, [a], a.approval_type == ^type)

      {:priority, priority}, query ->
        where(query, [a], a.priority == ^priority)

      {:session_id, session_id}, query ->
        where(query, [a], a.session_id == ^session_id)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _, query ->
        query
    end)
  end
end
