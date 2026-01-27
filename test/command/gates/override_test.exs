defmodule Command.Gates.OverrideTest do
  @moduledoc """
  Tests for Command.Gates.Override - gate override workflow.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: true

  alias Command.Gates.Override

  describe "request_override/2" do
    test "creates pending override request" do
      attrs = %{
        gate_id: "GATE-IMPL-006",
        justification: "Known flaky test, fix scheduled",
        risk_assessment: "Low - unrelated to new code",
        mitigations: ["Manual verification completed", "Monitoring added"],
        requested_by: "user-123"
      }

      assert {:ok, request} = Override.request_override("GATE-IMPL-006", attrs)
      assert request.gate_id == "GATE-IMPL-006"
      assert request.status == :pending
      assert request.justification == attrs.justification
      assert request.risk_assessment == attrs.risk_assessment
      assert request.mitigations == attrs.mitigations
    end

    test "requires gate_id and justification" do
      attrs = %{
        risk_assessment: "Low",
        mitigations: []
      }

      assert {:error, reason} = Override.request_override("GATE-TEST", attrs)
      assert reason =~ "justification"
    end

    test "requires risk_assessment" do
      attrs = %{
        justification: "Need to ship",
        mitigations: []
      }

      assert {:error, reason} = Override.request_override("GATE-TEST", attrs)
      assert reason =~ "risk_assessment"
    end

    test "requires mitigations list" do
      attrs = %{
        justification: "Need to ship",
        risk_assessment: "Medium"
      }

      assert {:error, reason} = Override.request_override("GATE-TEST", attrs)
      assert reason =~ "mitigations"
    end

    test "creates override record with timestamp" do
      attrs = %{
        gate_id: "GATE-IMPL-006",
        justification: "Test",
        risk_assessment: "Low",
        mitigations: ["Test mitigation"],
        requested_by: "user-123"
      }

      before = DateTime.utc_now()
      assert {:ok, request} = Override.request_override("GATE-IMPL-006", attrs)
      after_time = DateTime.utc_now()

      assert request.requested_at != nil
      assert DateTime.compare(request.requested_at, before) in [:gt, :eq]
      assert DateTime.compare(request.requested_at, after_time) in [:lt, :eq]
    end
  end

  describe "approve_override/2" do
    setup do
      # Create a pending override request
      attrs = %{
        gate_id: "GATE-IMPL-006",
        justification: "Known issue",
        risk_assessment: "Low",
        mitigations: ["Workaround in place"],
        requested_by: "user-123"
      }

      {:ok, request} = Override.request_override("GATE-IMPL-006", attrs)
      %{request: request}
    end

    test "marks override as approved", %{request: request} do
      approver_attrs = %{
        approved_by: "approver-456",
        role: :tech_lead,
        conditions: []
      }

      assert {:ok, approved} = Override.approve_override(request, approver_attrs)
      assert approved.status == :approved
      assert approved.decision.approved == true
      assert approved.decision.decided_by == "approver-456"
    end

    test "requires authorized approver per authority matrix", %{request: request} do
      # Tech lead can approve GATE-IMPL-006
      tech_lead_attrs = %{
        approved_by: "approver-456",
        role: :tech_lead
      }

      assert {:ok, _approved} = Override.approve_override(request, tech_lead_attrs)

      # But product owner cannot
      {:ok, request2} =
        Override.request_override("GATE-IMPL-006", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      po_attrs = %{
        approved_by: "approver-789",
        role: :product_owner
      }

      assert {:error, reason} = Override.approve_override(request2, po_attrs)
      assert reason =~ "not authorized" or reason =~ "authority"
    end

    test "records conditions if any", %{request: request} do
      approver_attrs = %{
        approved_by: "approver-456",
        role: :tech_lead,
        conditions: ["Review in 7 days", "Add monitoring"]
      }

      assert {:ok, approved} = Override.approve_override(request, approver_attrs)
      assert approved.decision.conditions == ["Review in 7 days", "Add monitoring"]
    end

    test "records approval timestamp", %{request: request} do
      approver_attrs = %{
        approved_by: "approver-456",
        role: :tech_lead
      }

      before = DateTime.utc_now()
      assert {:ok, approved} = Override.approve_override(request, approver_attrs)
      after_time = DateTime.utc_now()

      assert approved.decision.decided_at != nil
      assert DateTime.compare(approved.decision.decided_at, before) in [:gt, :eq]
      assert DateTime.compare(approved.decision.decided_at, after_time) in [:lt, :eq]
    end

    test "cannot approve already decided override", %{request: request} do
      approver_attrs = %{
        approved_by: "approver-456",
        role: :tech_lead
      }

      assert {:ok, approved} = Override.approve_override(request, approver_attrs)

      # Try to approve again
      assert {:error, reason} = Override.approve_override(approved, approver_attrs)
      assert reason =~ "already" or reason =~ "decided"
    end
  end

  describe "reject_override/2" do
    setup do
      attrs = %{
        gate_id: "GATE-IMPL-006",
        justification: "Known issue",
        risk_assessment: "Low",
        mitigations: ["Workaround"],
        requested_by: "user-123"
      }

      {:ok, request} = Override.request_override("GATE-IMPL-006", attrs)
      %{request: request}
    end

    test "marks override as rejected", %{request: request} do
      rejection_attrs = %{
        rejected_by: "approver-456",
        role: :tech_lead,
        reason: "Insufficient justification"
      }

      assert {:ok, rejected} = Override.reject_override(request, rejection_attrs)
      assert rejected.status == :rejected
      assert rejected.decision.approved == false
    end

    test "records rejection reason", %{request: request} do
      rejection_attrs = %{
        rejected_by: "approver-456",
        role: :tech_lead,
        reason: "Risk too high without proper mitigation"
      }

      assert {:ok, rejected} = Override.reject_override(request, rejection_attrs)
      assert rejected.decision.reason == "Risk too high without proper mitigation"
    end

    test "records rejection timestamp", %{request: request} do
      rejection_attrs = %{
        rejected_by: "approver-456",
        role: :tech_lead,
        reason: "Not justified"
      }

      before = DateTime.utc_now()
      assert {:ok, rejected} = Override.reject_override(request, rejection_attrs)
      after_time = DateTime.utc_now()

      assert rejected.decision.decided_at != nil
      assert DateTime.compare(rejected.decision.decided_at, before) in [:gt, :eq]
      assert DateTime.compare(rejected.decision.decided_at, after_time) in [:lt, :eq]
    end
  end

  describe "list_pending_overrides/0" do
    test "returns all pending requests" do
      # Create several override requests
      for i <- 1..3 do
        Override.request_override("GATE-TEST-#{i}", %{
          justification: "Test #{i}",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })
      end

      pending = Override.list_pending_overrides()
      assert is_list(pending)
      assert length(pending) >= 3

      # All should be pending
      assert Enum.all?(pending, fn req -> req.status == :pending end)
    end

    test "does not include approved overrides" do
      {:ok, request} =
        Override.request_override("GATE-TEST-APPROVED", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      # Approve it
      Override.approve_override(request, %{
        approved_by: "approver-456",
        role: :tech_lead
      })

      pending = Override.list_pending_overrides()

      # Should not include the approved one
      refute Enum.any?(pending, fn req -> req.gate_id == "GATE-TEST-APPROVED" end)
    end

    test "does not include rejected overrides" do
      {:ok, request} =
        Override.request_override("GATE-TEST-REJECTED", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      # Reject it
      Override.reject_override(request, %{
        rejected_by: "approver-456",
        role: :tech_lead,
        reason: "Test rejection"
      })

      pending = Override.list_pending_overrides()

      # Should not include the rejected one
      refute Enum.any?(pending, fn req -> req.gate_id == "GATE-TEST-REJECTED" end)
    end
  end

  describe "get_override/1" do
    test "returns override with full history" do
      {:ok, request} =
        Override.request_override("GATE-TEST-FULL", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      assert {:ok, override} = Override.get_override(request.id)
      assert override.id == request.id
      assert override.gate_id == "GATE-TEST-FULL"
      assert override.justification != nil
      assert override.risk_assessment != nil
      assert override.mitigations != nil
      assert override.requested_by != nil
      assert override.requested_at != nil
    end

    test "returns error for non-existent override" do
      fake_id = "override-#{:erlang.unique_integer([:positive])}"
      assert {:error, :not_found} = Override.get_override(fake_id)
    end
  end

  describe "is_overridden?/1" do
    test "returns true if gate has active override" do
      {:ok, request} =
        Override.request_override("GATE-TEST-ACTIVE", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      # Approve it
      {:ok, _approved} =
        Override.approve_override(request, %{
          approved_by: "approver-456",
          role: :tech_lead
        })

      assert Override.is_overridden?("GATE-TEST-ACTIVE") == true
    end

    test "returns false if gate has no override" do
      assert Override.is_overridden?("GATE-NO-OVERRIDE") == false
    end

    test "returns false if gate override is rejected" do
      {:ok, request} =
        Override.request_override("GATE-TEST-REJECTED-2", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      # Reject it
      {:ok, _rejected} =
        Override.reject_override(request, %{
          rejected_by: "approver-456",
          role: :tech_lead,
          reason: "Not justified"
        })

      assert Override.is_overridden?("GATE-TEST-REJECTED-2") == false
    end

    test "returns false if gate override is only pending" do
      {:ok, _request} =
        Override.request_override("GATE-TEST-PENDING-2", %{
          justification: "Test",
          risk_assessment: "Low",
          mitigations: ["Test"],
          requested_by: "user-123"
        })

      # Only pending, not approved
      assert Override.is_overridden?("GATE-TEST-PENDING-2") == false
    end
  end

  describe "override expiration" do
    test "override expires after configured duration" do
      {:ok, request} =
        Override.request_override("GATE-TEST-EXPIRE", %{
          justification: "Temporary override",
          risk_assessment: "Low",
          mitigations: ["Will fix soon"],
          requested_by: "user-123"
        })

      # Approve with short expiration (for testing)
      {:ok, approved} =
        Override.approve_override(request, %{
          approved_by: "approver-456",
          role: :tech_lead,
          expires_in_seconds: 1
        })

      # Should be active now
      assert Override.is_overridden?("GATE-TEST-EXPIRE") == true

      # Wait for expiration
      Process.sleep(1500)

      # Should be expired now
      assert Override.is_overridden?("GATE-TEST-EXPIRE") == false
    end
  end

  describe "authority matrix enforcement" do
    test "product owner can approve DOC gates" do
      {:ok, request} =
        Override.request_override("GATE-DOC-001", %{
          justification: "Documentation incomplete but approved by stakeholders",
          risk_assessment: "Low",
          mitigations: ["Will complete post-release"],
          requested_by: "user-123"
        })

      po_attrs = %{
        approved_by: "po-789",
        role: :product_owner
      }

      assert {:ok, _approved} = Override.approve_override(request, po_attrs)
    end

    test "DBA and tech lead can approve GATE-IMPL-004" do
      {:ok, request} =
        Override.request_override("GATE-IMPL-004", %{
          justification: "Migration tested manually",
          risk_assessment: "Medium",
          mitigations: ["Rollback script prepared"],
          requested_by: "user-123"
        })

      # DBA can approve
      dba_attrs = %{
        approved_by: "dba-111",
        role: :dba
      }

      assert {:ok, _approved} = Override.approve_override(request, dba_attrs)

      # Tech lead can also approve
      {:ok, request2} =
        Override.request_override("GATE-IMPL-004", %{
          justification: "Migration tested manually",
          risk_assessment: "Medium",
          mitigations: ["Rollback script prepared"],
          requested_by: "user-123"
        })

      tl_attrs = %{
        approved_by: "tl-222",
        role: :tech_lead
      }

      assert {:ok, _approved} = Override.approve_override(request2, tl_attrs)
    end

    test "architect can approve GATE-IMPL-005" do
      {:ok, request} =
        Override.request_override("GATE-IMPL-005", %{
          justification: "Parity acceptable for this use case",
          risk_assessment: "Low",
          mitigations: ["Documented differences"],
          requested_by: "user-123"
        })

      arch_attrs = %{
        approved_by: "arch-333",
        role: :architect
      }

      assert {:ok, _approved} = Override.approve_override(request, arch_attrs)
    end

    test "engineering manager can approve GATE-OPS-002" do
      {:ok, request} =
        Override.request_override("GATE-OPS-002", %{
          justification: "Critical fix needed",
          risk_assessment: "Medium - cost will exceed ceiling",
          mitigations: ["Budget increase approved"],
          requested_by: "user-123"
        })

      em_attrs = %{
        approved_by: "em-444",
        role: :engineering_manager
      }

      assert {:ok, _approved} = Override.approve_override(request, em_attrs)
    end
  end
end
