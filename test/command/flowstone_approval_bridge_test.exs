defmodule Command.FlowstoneApprovalBridgeTest do
  use Command.DataCase, async: true

  alias Command.Approvals
  alias Command.Approvals.ApprovalItem
  alias Command.Flowstone.ApprovalBridge
  alias Command.Repo

  setup do
    start_supervised!({FlowStone.Checkpoint, name: FlowStone.Checkpoint})

    handler_id = "command-flowstone-approval-#{System.unique_integer([:positive])}"

    :ok =
      ApprovalBridge.attach(handler_id,
        server: FlowStone.Checkpoint,
        use_repo: false
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  test "creates approval item for flowstone checkpoint request" do
    user = insert(:user)
    session = insert(:session, user: user)

    attrs = %{
      message: "Approve checkpoint",
      context: %{
        "command_user_id" => user.id,
        "command_session_id" => session.id,
        "policy" => %{
          "approval_class" => "high",
          "side_effects" => ["filesystem"],
          "capabilities" => ["shell"],
          "cost" => %{"usd" => 1.0}
        }
      }
    }

    {:ok, approval} = FlowStone.Approvals.request(:dangerous_step, attrs, use_repo: false)

    [item] = Approvals.list_session_pending_approvals(session)

    assert item.source_type == "flowstone_checkpoint"
    assert item.source_id == approval.id
    assert item.approval_type == "workflow_step"
    assert item.risk_level == "high"
    assert "filesystem" in item.risk_factors
    assert item.payload["checkpoint"] == "dangerous_step"
    assert item.payload["policy"]["approval_class"] == "high"
  end

  test "updates approval item status when flowstone approves" do
    user = insert(:user)
    session = insert(:session, user: user)

    attrs = %{
      message: "Approve checkpoint",
      context: %{
        "command_user_id" => user.id,
        "command_session_id" => session.id
      }
    }

    {:ok, approval} = FlowStone.Approvals.request(:review_step, attrs, use_repo: false)

    item =
      Repo.get_by!(ApprovalItem,
        source_type: "flowstone_checkpoint",
        source_id: approval.id
      )

    assert :ok = FlowStone.Approvals.approve(approval.id, use_repo: false)

    updated = Repo.get!(ApprovalItem, item.id)
    assert updated.status == "approved"
    assert updated.decided_at

    assert Repo.aggregate(ApprovalItem, :count, :id) == 1
  end
end
