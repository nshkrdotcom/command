defmodule Command.Gates.AuthorityMatrix do
  @moduledoc """
  Authority matrix for gate override approvals.

  Defines which roles are authorized to approve overrides for each gate type.
  The matrix is pattern-based, allowing wildcard matching for gate categories.

  ## Authority Matrix

  | Gate Pattern     | Authorized Roles          |
  |------------------|---------------------------|
  | GATE-DOC-*       | Product Owner             |
  | GATE-IMPL-004    | DBA, Tech Lead            |
  | GATE-IMPL-005    | Architect                 |
  | GATE-IMPL-006    | Tech Lead                 |
  | GATE-OPS-002     | Engineering Manager       |
  | * (default)      | Tech Lead                 |
  """

  @matrix [
    {"GATE-DOC-", [:product_owner]},
    {"GATE-IMPL-004", [:dba, :tech_lead]},
    {"GATE-IMPL-005", [:architect]},
    {"GATE-IMPL-006", [:tech_lead]},
    {"GATE-OPS-002", [:engineering_manager]}
  ]

  @default_roles [:tech_lead]

  @doc """
  Check if a role can approve an override for the given gate.
  """
  @spec can_approve?(String.t(), atom()) :: boolean()
  def can_approve?(gate_id, role) do
    role in required_roles(gate_id)
  end

  @doc """
  Returns the list of roles authorized to approve overrides for the given gate.
  """
  @spec required_roles(String.t()) :: [atom()]
  def required_roles(gate_id) do
    case find_matching_roles(gate_id) do
      nil -> @default_roles
      roles -> roles
    end
  end

  defp find_matching_roles(gate_id) do
    # Check exact matches first, then prefix matches
    exact =
      Enum.find(@matrix, fn {pattern, _roles} ->
        pattern == gate_id
      end)

    case exact do
      {_pattern, roles} ->
        roles

      nil ->
        prefix =
          Enum.find(@matrix, fn {pattern, _roles} ->
            String.ends_with?(pattern, "-") and String.starts_with?(gate_id, pattern)
          end)

        case prefix do
          {_pattern, roles} -> roles
          nil -> nil
        end
    end
  end
end
