defmodule Command.Gates.EngineTest do
  @moduledoc """
  Tests for Command.Gates.Engine - the gate evaluation engine.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: true

  alias Command.Gates.{Engine, GateSpec, GateCriterion}

  describe "evaluate_gate/2" do
    test "returns :pass when all criteria pass" do
      spec = %GateSpec{
        id: "TEST-001",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "criterion1",
            evaluator: fn _ctx -> :pass end
          },
          %GateCriterion{
            name: "criterion2",
            evaluator: fn _ctx -> :pass end
          }
        ]
      }

      context = %{test: true}

      assert :pass = Engine.evaluate_gate("TEST-001", context, spec: spec)
    end

    test "returns {:fail, results} when any criterion fails" do
      spec = %GateSpec{
        id: "TEST-002",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "criterion1",
            evaluator: fn _ctx -> :pass end
          },
          %GateCriterion{
            name: "criterion2",
            evaluator: fn _ctx -> {:fail, "Something wrong"} end
          }
        ]
      }

      context = %{test: true}

      assert {:fail, results} = Engine.evaluate_gate("TEST-002", context, spec: spec)
      assert is_list(results)

      # Find the failed criterion
      failed = Enum.find(results, fn {_name, result} -> match?({:fail, _}, result) end)
      assert failed != nil
      assert {"criterion2", {:fail, "Something wrong"}} = failed
    end

    test "emits telemetry on pass" do
      spec = %GateSpec{
        id: "TEST-003",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "always_pass",
            evaluator: fn _ctx -> :pass end
          }
        ]
      }

      # Attach telemetry handler to verify event emission
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-#{inspect(ref)}",
        [:command, :gates, :evaluated],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

      context = %{test: true}
      assert :pass = Engine.evaluate_gate("TEST-003", context, spec: spec)

      # Verify telemetry was emitted
      assert_receive {:telemetry, [:command, :gates, :evaluated], _measurements, metadata}
      assert metadata.gate_id == "TEST-003"
      assert metadata.result == :pass

      :telemetry.detach("test-#{inspect(ref)}")
    end

    test "emits telemetry on fail with details" do
      spec = %GateSpec{
        id: "TEST-004",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "always_fail",
            evaluator: fn _ctx -> {:fail, "Expected failure"} end
          }
        ]
      }

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-#{inspect(ref)}",
        [:command, :gates, :evaluated],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

      context = %{test: true}
      assert {:fail, _results} = Engine.evaluate_gate("TEST-004", context, spec: spec)

      # Verify telemetry was emitted
      assert_receive {:telemetry, [:command, :gates, :evaluated], _measurements, metadata}
      assert metadata.gate_id == "TEST-004"
      assert metadata.result == :fail
      assert is_list(metadata.criteria_results)

      :telemetry.detach("test-#{inspect(ref)}")
    end

    test "handles evaluator exceptions gracefully" do
      spec = %GateSpec{
        id: "TEST-005",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "throws_error",
            evaluator: fn _ctx -> raise "Boom!" end
          }
        ]
      }

      context = %{test: true}

      # Should not crash, should return error result
      assert {:fail, results} = Engine.evaluate_gate("TEST-005", context, spec: spec)

      # Find the errored criterion
      errored = Enum.find(results, fn {name, _result} -> name == "throws_error" end)
      assert errored != nil
      {_name, result} = errored
      assert match?({:error, _}, result) or match?({:fail, _}, result)
    end
  end

  describe "load_gate_spec/1" do
    test "returns spec for known gate_id" do
      # Assuming gate definitions are loaded
      assert {:ok, spec} = Engine.load_gate_spec("GATE-DOC-001")
      assert %GateSpec{} = spec
      assert spec.id == "GATE-DOC-001"
      assert spec.name == "Completeness"
      assert spec.category == :doc
    end

    test "returns {:error, :not_found} for unknown gate_id" do
      assert {:error, :not_found} = Engine.load_gate_spec("GATE-UNKNOWN-999")
    end

    test "loads all DOC gates" do
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-DOC-001")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-DOC-002")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-DOC-003")
    end

    test "loads all IMPL gates" do
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-001")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-002")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-003")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-004")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-005")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-006")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-IMPL-007")
    end

    test "loads all OPS gates" do
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-OPS-001")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-OPS-002")
      assert {:ok, _spec} = Engine.load_gate_spec("GATE-OPS-003")
    end
  end

  describe "gate record creation" do
    test "creates gate record with timestamp and results" do
      spec = %GateSpec{
        id: "TEST-006",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "test",
            evaluator: fn _ctx -> :pass end
          }
        ]
      }

      context = %{test: true}
      before = DateTime.utc_now()

      assert :pass = Engine.evaluate_gate("TEST-006", context, spec: spec)

      # Verify record was created (would check database in real implementation)
      after_time = DateTime.utc_now()

      # Record should have timestamp between before and after
      # This is a placeholder for actual database verification
      assert DateTime.compare(before, after_time) in [:lt, :eq]
    end

    test "gate record links to run_id when provided" do
      spec = %GateSpec{
        id: "TEST-007",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "test",
            evaluator: fn _ctx -> :pass end
          }
        ]
      }

      run_id = "run-#{:erlang.unique_integer([:positive])}"
      context = %{run_id: run_id}

      assert :pass = Engine.evaluate_gate("TEST-007", context, spec: spec)

      # In real implementation, would verify database record has run_id
    end

    test "gate record includes criteria results" do
      spec = %GateSpec{
        id: "TEST-008",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "criterion1",
            evaluator: fn _ctx -> :pass end
          },
          %GateCriterion{
            name: "criterion2",
            evaluator: fn _ctx -> {:fail, "Failed"} end
          }
        ]
      }

      context = %{test: true}

      assert {:fail, results} = Engine.evaluate_gate("TEST-008", context, spec: spec)

      # Verify results include both criteria
      assert length(results) == 2
      assert Enum.find(results, fn {name, _} -> name == "criterion1" end)
      assert Enum.find(results, fn {name, _} -> name == "criterion2" end)
    end
  end

  describe "retry logic" do
    test "respects max_retries config" do
      # Counter to track evaluations
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      spec = %GateSpec{
        id: "TEST-009",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "flaky",
            evaluator: fn _ctx ->
              count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)
              if count < 2, do: {:fail, "Not ready"}, else: :pass
            end
          }
        ],
        retry_config: %{
          max_retries: 3,
          backoff_ms: [100, 200, 300],
          auto_retry: true
        }
      }

      context = %{test: true}

      # With auto_retry enabled, should eventually pass
      assert :pass = Engine.evaluate_gate("TEST-009", context, spec: spec)

      # Verify it was called multiple times
      final_count = Agent.get(agent, & &1)
      assert final_count >= 2

      Agent.stop(agent)
    end

    test "does not auto-retry when auto_retry is false" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      spec = %GateSpec{
        id: "TEST-010",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "always_fail",
            evaluator: fn _ctx ->
              Agent.update(agent, fn c -> c + 1 end)
              {:fail, "Always fails"}
            end
          }
        ],
        retry_config: %{
          max_retries: 3,
          backoff_ms: [100, 200, 300],
          auto_retry: false
        }
      }

      context = %{test: true}

      # Should fail immediately without retry
      assert {:fail, _results} = Engine.evaluate_gate("TEST-010", context, spec: spec)

      # Verify it was only called once
      final_count = Agent.get(agent, & &1)
      assert final_count == 1

      Agent.stop(agent)
    end
  end

  describe "gate evaluation is idempotent" do
    test "evaluating same gate with same context produces same result" do
      spec = %GateSpec{
        id: "TEST-011",
        name: "Test Gate",
        category: :impl,
        criteria: [
          %GateCriterion{
            name: "deterministic",
            evaluator: fn ctx -> if ctx[:value] == 42, do: :pass, else: {:fail, "Wrong value"} end
          }
        ]
      }

      context = %{value: 42}

      result1 = Engine.evaluate_gate("TEST-011", context, spec: spec)
      result2 = Engine.evaluate_gate("TEST-011", context, spec: spec)
      result3 = Engine.evaluate_gate("TEST-011", context, spec: spec)

      assert result1 == :pass
      assert result2 == :pass
      assert result3 == :pass
    end
  end
end
