defmodule Command.Gates.Override do
  @moduledoc """
  Workflow for requesting and approving gate overrides.

  Overrides allow gates to be bypassed when necessary, with a full audit trail.
  Each override requires justification, risk assessment, and mitigations.
  Approvals are enforced per the authority matrix.

  ## Usage

      # Request an override
      {:ok, request} = Override.request_override("GATE-IMPL-006", %{
        justification: "Known flaky test",
        risk_assessment: "Low",
        mitigations: ["Manual verification done"],
        requested_by: "user-123"
      })

      # Approve the override
      {:ok, approved} = Override.approve_override(request, %{
        approved_by: "approver-456",
        role: :tech_lead
      })

      # Check if a gate is overridden
      Override.is_overridden?("GATE-IMPL-006")
  """

  alias Command.Gates.{OverrideRequest, AuthorityMatrix}

  # In-memory store for override requests (use ETS for process isolation)
  @table_name :gate_overrides

  @doc """
  Initialize the override store. Called on application start.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :set, :public])
    end

    :ok
  end

  @doc """
  Request a gate override.

  Required attrs:
  - `justification` - Why the override is needed
  - `risk_assessment` - Risk assessment
  - `mitigations` - List of mitigating actions
  - `requested_by` - User requesting the override (optional)
  """
  @spec request_override(String.t(), map()) :: {:ok, OverrideRequest.t()} | {:error, String.t()}
  def request_override(gate_id, attrs) do
    ensure_table()

    with :ok <- validate_required(attrs, :justification, "justification is required"),
         :ok <- validate_required(attrs, :risk_assessment, "risk_assessment is required"),
         :ok <- validate_mitigations(attrs) do
      request = %OverrideRequest{
        id: generate_id(),
        gate_id: gate_id,
        status: :pending,
        justification: attrs[:justification] || attrs.justification,
        risk_assessment: attrs[:risk_assessment] || attrs.risk_assessment,
        mitigations: attrs[:mitigations] || attrs.mitigations || [],
        requested_by: attrs[:requested_by] || Map.get(attrs, :requested_by),
        requested_at: DateTime.utc_now()
      }

      :ets.insert(@table_name, {request.id, request})
      {:ok, request}
    end
  end

  @doc """
  Approve a pending override request.

  Required approver_attrs:
  - `approved_by` - User ID of the approver
  - `role` - Role of the approver (checked against authority matrix)
  - `conditions` - Optional list of conditions (optional)
  - `expires_in_seconds` - Optional expiration duration in seconds
  """
  @spec approve_override(OverrideRequest.t(), map()) ::
          {:ok, OverrideRequest.t()} | {:error, String.t()}
  def approve_override(%OverrideRequest{} = request, approver_attrs) do
    ensure_table()

    with :ok <- validate_pending(request),
         :ok <- validate_authority(request.gate_id, approver_attrs[:role] || approver_attrs.role) do
      expires_at = calculate_expiry(approver_attrs)

      approved = %{
        request
        | status: :approved,
          decision: %{
            approved: true,
            decided_by: approver_attrs[:approved_by] || approver_attrs.approved_by,
            decided_at: DateTime.utc_now(),
            reason: nil,
            conditions: approver_attrs[:conditions] || Map.get(approver_attrs, :conditions, [])
          },
          expires_at: expires_at
      }

      :ets.insert(@table_name, {approved.id, approved})
      {:ok, approved}
    end
  end

  @doc """
  Reject a pending override request.

  Required attrs:
  - `rejected_by` - User ID of the rejector
  - `role` - Role of the rejector
  - `reason` - Reason for rejection
  """
  @spec reject_override(OverrideRequest.t(), map()) ::
          {:ok, OverrideRequest.t()} | {:error, String.t()}
  def reject_override(%OverrideRequest{} = request, attrs) do
    ensure_table()

    with :ok <- validate_pending(request) do
      rejected = %{
        request
        | status: :rejected,
          decision: %{
            approved: false,
            decided_by: attrs[:rejected_by] || attrs.rejected_by,
            decided_at: DateTime.utc_now(),
            reason: attrs[:reason] || attrs.reason,
            conditions: []
          }
      }

      :ets.insert(@table_name, {rejected.id, rejected})
      {:ok, rejected}
    end
  end

  @doc """
  Check if a gate has an active (approved, non-expired) override.
  """
  @spec is_overridden?(String.t()) :: boolean()
  def is_overridden?(gate_id) do
    ensure_table()

    @table_name
    |> :ets.tab2list()
    |> Enum.any?(fn {_id, request} ->
      request.gate_id == gate_id and
        request.status == :approved and
        not expired?(request)
    end)
  end

  @doc """
  List all pending override requests.
  """
  @spec list_pending_overrides() :: [OverrideRequest.t()]
  def list_pending_overrides do
    ensure_table()

    @table_name
    |> :ets.tab2list()
    |> Enum.filter(fn {_id, request} -> request.status == :pending end)
    |> Enum.map(fn {_id, request} -> request end)
  end

  @doc """
  Get an override request by ID.
  """
  @spec get_override(String.t()) :: {:ok, OverrideRequest.t()} | {:error, :not_found}
  def get_override(id) do
    ensure_table()

    case :ets.lookup(@table_name, id) do
      [{^id, request}] -> {:ok, request}
      [] -> {:error, :not_found}
    end
  end

  # -- Private --

  defp ensure_table do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:named_table, :set, :public])
    end
  end

  defp validate_required(attrs, key, message) do
    value = attrs[key] || Map.get(attrs, key, nil)

    if is_nil(value) or value == "" do
      {:error, message}
    else
      :ok
    end
  end

  defp validate_mitigations(attrs) do
    mitigations = attrs[:mitigations] || Map.get(attrs, :mitigations, nil)

    if is_nil(mitigations) do
      {:error, "mitigations is required"}
    else
      :ok
    end
  end

  defp validate_pending(%OverrideRequest{status: :pending}), do: :ok

  defp validate_pending(%OverrideRequest{status: status}) do
    {:error, "Override already decided (status: #{status})"}
  end

  defp validate_authority(gate_id, role) do
    if AuthorityMatrix.can_approve?(gate_id, role) do
      :ok
    else
      allowed = AuthorityMatrix.required_roles(gate_id)

      {:error,
       "Role #{inspect(role)} is not authorized to approve #{gate_id}. Required: #{inspect(allowed)}"}
    end
  end

  defp calculate_expiry(attrs) do
    expires_in = attrs[:expires_in_seconds] || Map.get(attrs, :expires_in_seconds, nil)

    if expires_in do
      DateTime.add(DateTime.utc_now(), expires_in, :second)
    else
      nil
    end
  end

  defp expired?(%OverrideRequest{expires_at: nil}), do: false

  defp expired?(%OverrideRequest{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp generate_id do
    "override-#{:erlang.unique_integer([:positive])}"
  end
end
