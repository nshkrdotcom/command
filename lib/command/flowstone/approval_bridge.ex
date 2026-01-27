defmodule Command.Flowstone.ApprovalBridge do
  @moduledoc """
  Bridges FlowStone checkpoint approvals into Command approval items.
  """

  require Logger

  alias Command.Approvals.ApprovalItem
  alias Command.Policy
  alias Command.Repo
  alias FlowStone.Approval

  @events [
    [:flowstone, :checkpoint, :requested],
    [:flowstone, :checkpoint, :approved],
    [:flowstone, :checkpoint, :rejected],
    [:flowstone, :checkpoint, :timeout]
  ]

  @spec attach(term(), keyword()) :: :ok
  def attach(handler_id \\ __MODULE__, opts \\ []) do
    case :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_event/4, opts) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @spec handle_event([atom()], map(), map(), keyword()) :: :ok
  def handle_event([:flowstone, :checkpoint, event], _measurements, metadata, opts) do
    approval_id = metadata[:approval_id] || metadata["approval_id"]

    if is_nil(approval_id) do
      :ok
    else
      handle_checkpoint_event(event, approval_id, opts)
    end
  end

  def handle_event(_event, _measurements, _metadata, _opts), do: :ok

  defp handle_checkpoint_event(:requested, approval_id, opts) do
    with {:ok, approval} <- fetch_approval(approval_id, opts),
         {:ok, item} <- upsert_item(approval) do
      broadcast(:approval_created, item)
      :ok
    else
      {:error, reason} ->
        Logger.warning("Flowstone approval bridge failed to ingest request",
          approval_id: approval_id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp handle_checkpoint_event(:approved, approval_id, opts),
    do: resolve_item(approval_id, :approved, opts)

  defp handle_checkpoint_event(:rejected, approval_id, opts),
    do: resolve_item(approval_id, :denied, opts)

  defp handle_checkpoint_event(:timeout, approval_id, opts),
    do: resolve_item(approval_id, :expired, opts)

  defp handle_checkpoint_event(_event, _approval_id, _opts), do: :ok

  defp resolve_item(approval_id, status, opts) do
    with {:ok, approval} <- fetch_approval(approval_id, opts),
         %ApprovalItem{} = item <- get_item(approval_id),
         {:ok, updated} <- update_item_status(item, approval, status) do
      broadcast(event_for_status(status), updated)
      :ok
    else
      nil ->
        :ok

      {:error, reason} ->
        Logger.warning("Flowstone approval bridge failed to resolve status",
          approval_id: approval_id,
          status: status,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp fetch_approval(approval_id, opts) do
    flowstone_opts =
      opts
      |> Keyword.take([:server, :use_repo])
      |> Keyword.put_new(:use_repo, true)

    try do
      FlowStone.Approvals.get(approval_id, flowstone_opts)
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp get_item(approval_id) do
    Repo.get_by(ApprovalItem,
      source_type: source_type(),
      source_id: approval_id
    )
  end

  defp upsert_item(%Approval{} = approval) do
    attrs = approval_item_attrs(approval)

    case attrs do
      %{user_id: nil} ->
        {:error, :missing_user_id}

      _ ->
        case get_item(approval.id) do
          nil ->
            %ApprovalItem{}
            |> ApprovalItem.create_changeset(attrs)
            |> Repo.insert()

          item ->
            item
            |> Ecto.Changeset.change(Map.put(attrs, :status, "pending"))
            |> Repo.update()
        end
    end
  end

  defp update_item_status(item, approval, :approved) do
    attrs = %{
      decision_note: approval.reason
    }

    item
    |> ApprovalItem.approve_changeset(attrs)
    |> Repo.update()
  end

  defp update_item_status(item, approval, :denied) do
    attrs = %{
      decision_note: approval.reason
    }

    item
    |> ApprovalItem.deny_changeset(attrs)
    |> Repo.update()
  end

  defp update_item_status(item, _approval, :expired) do
    item
    |> ApprovalItem.expire_changeset()
    |> Repo.update()
  end

  defp approval_item_attrs(%Approval{} = approval) do
    context = normalize_context(approval.context)
    policy = extract_policy(context)

    %{
      user_id: context_user_id(context),
      session_id: context_session_id(context),
      approval_type: "workflow_step",
      priority: Policy.priority(policy),
      title: approval_title(approval),
      description: context["description"],
      payload: %{
        "checkpoint" => to_string(approval.checkpoint_name),
        "message" => approval.message,
        "context" => context,
        "policy" => policy,
        "materialization_id" => approval.materialization_id,
        "flowstone_approval_id" => approval.id
      },
      source_type: source_type(),
      source_id: approval.id,
      context: context,
      risk_level: Policy.risk_level(policy),
      risk_factors: Policy.risk_factors(policy),
      expires_at: approval.timeout_at,
      metadata: %{
        "flowstone_status" => to_string(approval.status)
      }
    }
  end

  defp approval_title(%Approval{} = approval) do
    approval.message || "Flowstone checkpoint: #{approval.checkpoint_name}"
  end

  defp normalize_context(%{} = context) do
    Enum.reduce(context, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_context(_context), do: %{}

  defp extract_policy(context) do
    policy = Map.get(context, "policy") || Map.get(context, "policy_metadata")

    if is_map(policy) do
      Policy.normalize(policy)
    else
      nil
    end
  end

  defp context_user_id(context) do
    Map.get(context, "command_user_id") || Map.get(context, "user_id")
  end

  defp context_session_id(context) do
    Map.get(context, "command_session_id") || Map.get(context, "session_id")
  end

  defp source_type, do: "flowstone_checkpoint"

  defp broadcast(event, %ApprovalItem{} = item) do
    _ = Command.PubSub.broadcast("user:#{item.user_id}:approvals", event, item)
    :ok
  end

  defp event_for_status(:approved), do: :approval_approved
  defp event_for_status(:denied), do: :approval_denied
  defp event_for_status(:expired), do: :approval_expired
end
