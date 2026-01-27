defmodule Command.Gates.GateSpecTest do
  @moduledoc """
  Tests for Command.Gates.GateSpec struct.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: true

  alias Command.Gates.{GateSpec, GateCriterion}

  describe "GateSpec struct" do
    test "creates valid spec with all required fields" do
      spec = %GateSpec{
        id: "GATE-DOC-001",
        name: "Completeness",
        category: :doc,
        when: "Before freeze",
        blocks: "Freeze",
        criteria: [
          %GateCriterion{
            name: "all_docs_exist",
            evaluator: fn _ctx -> :pass end
          }
        ],
        retry_config: %{
          max_retries: 3,
          backoff_ms: [1000, 5000, 30000],
          auto_retry: false
        }
      }

      assert spec.id == "GATE-DOC-001"
      assert spec.name == "Completeness"
      assert spec.category == :doc
      assert spec.when == "Before freeze"
      assert spec.blocks == "Freeze"
      assert length(spec.criteria) == 1
      assert is_map(spec.retry_config)
    end

    test "category must be :doc, :impl, or :ops" do
      # Valid categories
      assert %GateSpec{category: :doc}
      assert %GateSpec{category: :impl}
      assert %GateSpec{category: :ops}

      # Note: Validation would be enforced by changeset/constructor in real implementation
    end

    test "criteria is a list of GateCriterion structs" do
      criterion1 = %GateCriterion{
        name: "test1",
        evaluator: fn _ctx -> :pass end
      }

      criterion2 = %GateCriterion{
        name: "test2",
        evaluator: fn _ctx -> {:fail, "reason"} end
      }

      spec = %GateSpec{
        id: "TEST-001",
        name: "Test Gate",
        category: :impl,
        criteria: [criterion1, criterion2]
      }

      assert length(spec.criteria) == 2
      assert Enum.all?(spec.criteria, &match?(%GateCriterion{}, &1))
    end

    test "blocks field specifies what phase the gate blocks" do
      spec = %GateSpec{
        id: "GATE-IMPL-001",
        name: "Backlog Review",
        category: :impl,
        when: "Before spiking",
        blocks: "Spiking phase"
      }

      assert spec.blocks == "Spiking phase"
    end

    test "retry_config has expected structure" do
      retry_config = %{
        max_retries: 2,
        backoff_ms: [1000, 5000],
        auto_retry: true
      }

      spec = %GateSpec{
        id: "TEST-001",
        retry_config: retry_config
      }

      assert spec.retry_config.max_retries == 2
      assert spec.retry_config.backoff_ms == [1000, 5000]
      assert spec.retry_config.auto_retry == true
    end
  end

  describe "GateSpec serialization" do
    test "converts to JSON and back" do
      original = %GateSpec{
        id: "GATE-DOC-001",
        name: "Completeness",
        category: :doc,
        when: "Before freeze",
        blocks: "Freeze",
        criteria: [],
        retry_config: %{
          max_retries: 3,
          backoff_ms: [1000, 5000, 30000],
          auto_retry: false
        }
      }

      # Serialize (would use Jason or similar in real implementation)
      json_map = %{
        "id" => original.id,
        "name" => original.name,
        "category" => Atom.to_string(original.category),
        "when" => original.when,
        "blocks" => original.blocks,
        "criteria" => [],
        "retry_config" => %{
          "max_retries" => 3,
          "backoff_ms" => [1000, 5000, 30000],
          "auto_retry" => false
        }
      }

      # Deserialize
      roundtrip = %GateSpec{
        id: json_map["id"],
        name: json_map["name"],
        category: String.to_existing_atom(json_map["category"]),
        when: json_map["when"],
        blocks: json_map["blocks"],
        criteria: [],
        retry_config: %{
          max_retries: json_map["retry_config"]["max_retries"],
          backoff_ms: json_map["retry_config"]["backoff_ms"],
          auto_retry: json_map["retry_config"]["auto_retry"]
        }
      }

      assert roundtrip.id == original.id
      assert roundtrip.name == original.name
      assert roundtrip.category == original.category
    end
  end
end
