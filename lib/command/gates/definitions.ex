defmodule Command.Gates.Definitions do
  @moduledoc """
  Quality gate definitions for the workflow automation system.

  Defines all 13 gates across three categories:

  - **Documentation Gates (3):** GATE-DOC-001 through GATE-DOC-003
  - **Implementation Gates (7):** GATE-IMPL-001 through GATE-IMPL-007
  - **Operational Gates (3):** GATE-OPS-001 through GATE-OPS-003

  Each gate has specific criteria that must all pass for the gate to succeed.
  Gate evaluation is binary: PASS or FAIL, with no partial credit.
  """

  alias Command.Gates.{GateSpec, GateCriterion}

  # ── Documentation Gates ──────────────────────────────────────────────

  @doc "GATE-DOC-001: Completeness - All required docs exist and are non-empty."
  @spec gate_doc_001() :: GateSpec.t()
  def gate_doc_001 do
    %GateSpec{
      id: "GATE-DOC-001",
      name: "Completeness",
      category: :doc,
      when: "Before specification freeze",
      blocks: "Specification freeze",
      criteria: [
        %GateCriterion{
          name: "all_docs_exist",
          evaluator: fn ctx ->
            required =
              ~w(requirements.md domain-model.md data-schema.md api-contracts.md pipeline-design.md test-plan.md migration-plan.md)

            missing = Enum.reject(required, fn doc -> ctx[:docs][doc] end)
            if missing == [], do: :pass, else: {:fail, %{missing: missing}}
          end,
          required: true
        },
        %GateCriterion{
          name: "docs_non_empty",
          evaluator: fn ctx ->
            empty =
              Enum.filter(ctx[:docs] || %{}, fn {_name, content} ->
                content == "" or is_nil(content)
              end)

            if empty == [], do: :pass, else: {:fail, %{empty: Enum.map(empty, &elem(&1, 0))}}
          end,
          required: true
        },
        %GateCriterion{
          name: "no_todo_markers",
          evaluator: fn ctx ->
            with_todos =
              (ctx[:docs] || %{})
              |> Enum.filter(fn {_name, content} ->
                is_binary(content) and (content =~ "TBD" or content =~ "TODO")
              end)
              |> Enum.map(&elem(&1, 0))

            if with_todos == [], do: :pass, else: {:fail, %{docs_with_todos: with_todos}}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 3, backoff_ms: [1000, 5000, 30000], auto_retry: false}
    }
  end

  @doc "GATE-DOC-002: ADR Resolution - No PROPOSED or REVIEW state ADRs."
  @spec gate_doc_002() :: GateSpec.t()
  def gate_doc_002 do
    %GateSpec{
      id: "GATE-DOC-002",
      name: "ADR Resolution",
      category: :doc,
      when: "Before specification freeze",
      blocks: "Specification freeze",
      criteria: [
        %GateCriterion{
          name: "all_adrs_resolved",
          evaluator: fn ctx ->
            unresolved =
              (ctx[:adrs] || [])
              |> Enum.filter(fn adr ->
                adr[:status] in [:proposed, :review, "proposed", "review"]
              end)

            if unresolved == [],
              do: :pass,
              else: {:fail, %{unresolved: Enum.map(unresolved, & &1[:id])}}
          end,
          required: true
        },
        %GateCriterion{
          name: "deferred_adrs_justified",
          evaluator: fn ctx ->
            unjustified =
              (ctx[:adrs] || [])
              |> Enum.filter(fn adr ->
                adr[:status] in [:deferred, "deferred"] and
                  (is_nil(adr[:justification]) or adr[:justification] == "")
              end)

            if unjustified == [],
              do: :pass,
              else: {:fail, %{unjustified: Enum.map(unjustified, & &1[:id])}}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 3, backoff_ms: [1000, 5000, 30000], auto_retry: false}
    }
  end

  @doc "GATE-DOC-003: Schema Validity - All schemas parse without errors."
  @spec gate_doc_003() :: GateSpec.t()
  def gate_doc_003 do
    %GateSpec{
      id: "GATE-DOC-003",
      name: "Schema Validity",
      category: :doc,
      when: "Before specification freeze",
      blocks: "Specification freeze",
      criteria: [
        %GateCriterion{
          name: "schemas_parse",
          evaluator: fn ctx ->
            errors = ctx[:schema_errors] || []
            if errors == [], do: :pass, else: {:fail, %{parse_errors: errors}}
          end,
          required: true
        },
        %GateCriterion{
          name: "types_exist",
          evaluator: fn ctx ->
            undefined = ctx[:undefined_types] || []
            if undefined == [], do: :pass, else: {:fail, %{undefined_types: undefined}}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 3, backoff_ms: [1000, 5000, 30000], auto_retry: false}
    }
  end

  # ── Implementation Gates ─────────────────────────────────────────────

  @doc "GATE-IMPL-001: Backlog Review - Backlog is reviewed and prioritized."
  @spec gate_impl_001() :: GateSpec.t()
  def gate_impl_001 do
    %GateSpec{
      id: "GATE-IMPL-001",
      name: "Backlog Review",
      category: :impl,
      when: "Before spiking",
      blocks: "Spiking phase",
      criteria: [
        %GateCriterion{
          name: "backlog_reviewed",
          evaluator: fn ctx ->
            if ctx[:backlog_reviewed] == true, do: :pass, else: {:fail, "Backlog not reviewed"}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 0, backoff_ms: [], auto_retry: false}
    }
  end

  @doc "GATE-IMPL-002: Spike Completion - All spikes are completed."
  @spec gate_impl_002() :: GateSpec.t()
  def gate_impl_002 do
    %GateSpec{
      id: "GATE-IMPL-002",
      name: "Spike Completion",
      category: :impl,
      when: "Before implementation",
      blocks: "Implementation phase",
      criteria: [
        %GateCriterion{
          name: "spikes_completed",
          evaluator: fn ctx ->
            if ctx[:spikes_completed] == true, do: :pass, else: {:fail, "Spikes not completed"}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 0, backoff_ms: [], auto_retry: false}
    }
  end

  @doc "GATE-IMPL-003: Code Complete - All code changes are complete."
  @spec gate_impl_003() :: GateSpec.t()
  def gate_impl_003 do
    %GateSpec{
      id: "GATE-IMPL-003",
      name: "Code Complete",
      category: :impl,
      when: "Before testing",
      blocks: "Testing phase",
      criteria: [
        %GateCriterion{
          name: "code_complete",
          evaluator: fn ctx ->
            if ctx[:code_complete] == true, do: :pass, else: {:fail, "Code not complete"}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 0, backoff_ms: [], auto_retry: false}
    }
  end

  @doc "GATE-IMPL-004: Migration Readiness - Migrations compile, dry-run succeeds, rollback tested."
  @spec gate_impl_004() :: GateSpec.t()
  def gate_impl_004 do
    %GateSpec{
      id: "GATE-IMPL-004",
      name: "Migration Readiness",
      category: :impl,
      when: "Before deployment",
      blocks: "Deployment",
      criteria: [
        %GateCriterion{
          name: "migrations_compile",
          evaluator: fn ctx ->
            if ctx[:migrations_compiled] == true,
              do: :pass,
              else: {:fail, "Migrations did not compile"}
          end,
          required: true
        },
        %GateCriterion{
          name: "dry_run_passes",
          evaluator: fn ctx ->
            if ctx[:dry_run_passed] == true, do: :pass, else: {:fail, "Dry run failed"}
          end,
          required: true
        },
        %GateCriterion{
          name: "rollback_tested",
          evaluator: fn ctx ->
            if ctx[:rollback_tested] == true, do: :pass, else: {:fail, "Rollback not tested"}
          end,
          required: true
        },
        %GateCriterion{
          name: "data_integrity",
          evaluator: fn ctx ->
            if ctx[:data_integrity] == true,
              do: :pass,
              else: {:fail, "Data integrity check failed"}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 3, backoff_ms: [1000, 5000, 30000], auto_retry: false}
    }
  end

  @doc "GATE-IMPL-005: Provider Parity - Parity tests pass, metadata present, normalization >95%."
  @spec gate_impl_005() :: GateSpec.t()
  def gate_impl_005 do
    %GateSpec{
      id: "GATE-IMPL-005",
      name: "Provider Parity",
      category: :impl,
      when: "Before release",
      blocks: "Release",
      criteria: [
        %GateCriterion{
          name: "parity_tests_pass",
          evaluator: fn ctx ->
            if ctx[:parity_tests_pass] == true, do: :pass, else: {:fail, "Parity tests failed"}
          end,
          required: true
        },
        %GateCriterion{
          name: "metadata_present",
          evaluator: fn ctx ->
            if ctx[:metadata_present] == true,
              do: :pass,
              else: {:fail, "Required metadata missing"}
          end,
          required: true
        },
        %GateCriterion{
          name: "normalization_threshold",
          evaluator: fn ctx ->
            score = ctx[:normalization_score] || 0
            threshold = ctx[:normalization_threshold] || 0.95
            if score >= threshold, do: :pass, else: {:fail, %{score: score, threshold: threshold}}
          end,
          threshold: 0.95,
          required: true
        }
      ],
      retry_config: %{max_retries: 2, backoff_ms: [1000, 5000], auto_retry: true}
    }
  end

  @doc "GATE-IMPL-006: Test Suite - All tests pass, coverage >= 80%."
  @spec gate_impl_006() :: GateSpec.t()
  def gate_impl_006 do
    %GateSpec{
      id: "GATE-IMPL-006",
      name: "Test Suite",
      category: :impl,
      when: "Before release",
      blocks: "Release",
      criteria: [
        %GateCriterion{
          name: "unit_tests_pass",
          evaluator: fn ctx ->
            if ctx[:unit_tests_pass] == true, do: :pass, else: {:fail, "Unit tests failed"}
          end,
          required: true
        },
        %GateCriterion{
          name: "integration_tests_pass",
          evaluator: fn ctx ->
            if ctx[:integration_tests_pass] == true,
              do: :pass,
              else: {:fail, "Integration tests failed"}
          end,
          required: true
        },
        %GateCriterion{
          name: "coverage_threshold",
          evaluator: fn ctx ->
            coverage = ctx[:coverage] || 0
            threshold = ctx[:threshold] || 80

            if coverage >= threshold,
              do: :pass,
              else: {:fail, %{coverage: coverage, threshold: threshold}}
          end,
          threshold: 80.0,
          required: true
        }
      ],
      retry_config: %{max_retries: 2, backoff_ms: [1000, 5000], auto_retry: true}
    }
  end

  @doc "GATE-IMPL-007: Release Readiness - All release criteria met."
  @spec gate_impl_007() :: GateSpec.t()
  def gate_impl_007 do
    %GateSpec{
      id: "GATE-IMPL-007",
      name: "Release Readiness",
      category: :impl,
      when: "Before production deploy",
      blocks: "Production deploy",
      criteria: [
        %GateCriterion{
          name: "release_ready",
          evaluator: fn ctx ->
            if ctx[:release_ready] == true, do: :pass, else: {:fail, "Not release ready"}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 0, backoff_ms: [], auto_retry: false}
    }
  end

  # ── Operational Gates ────────────────────────────────────────────────

  @doc "GATE-OPS-001: Production Stability - Post-deployment stability checks."
  @spec gate_ops_001() :: GateSpec.t()
  def gate_ops_001 do
    %GateSpec{
      id: "GATE-OPS-001",
      name: "Production Stability",
      category: :ops,
      when: "Post-deployment",
      blocks: "Next deployment",
      criteria: [
        %GateCriterion{
          name: "stability_check",
          evaluator: fn ctx ->
            if ctx[:stable] == true, do: :pass, else: {:fail, "Production not stable"}
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 3, backoff_ms: [5000, 15000, 60000], auto_retry: true}
    }
  end

  @doc "GATE-OPS-002: Cost Ceiling - Run cost within configured ceiling."
  @spec gate_ops_002() :: GateSpec.t()
  def gate_ops_002 do
    %GateSpec{
      id: "GATE-OPS-002",
      name: "Cost Ceiling",
      category: :ops,
      when: "During run",
      blocks: "Run continuation",
      criteria: [
        %GateCriterion{
          name: "cost_within_ceiling",
          evaluator: fn ctx ->
            Command.Gates.CostCeiling.evaluate(
              ctx,
              ctx[:event] || %{usage: %{total_cost_usd: nil}}
            )
          end,
          required: true
        }
      ],
      retry_config: %{max_retries: 0, backoff_ms: [], auto_retry: false}
    }
  end

  @doc "GATE-OPS-003: Error Rate - Error rate within acceptable bounds."
  @spec gate_ops_003() :: GateSpec.t()
  def gate_ops_003 do
    %GateSpec{
      id: "GATE-OPS-003",
      name: "Error Rate",
      category: :ops,
      when: "During run",
      blocks: "Run continuation",
      criteria: [
        %GateCriterion{
          name: "error_rate_acceptable",
          evaluator: fn ctx ->
            rate = ctx[:error_rate] || 0.0
            threshold = ctx[:error_rate_threshold] || 0.05
            if rate <= threshold, do: :pass, else: {:fail, %{rate: rate, threshold: threshold}}
          end,
          threshold: 0.05,
          required: true
        }
      ],
      retry_config: %{max_retries: 3, backoff_ms: [1000, 5000, 30000], auto_retry: true}
    }
  end

  # ── All Gates ────────────────────────────────────────────────────────

  @doc """
  Returns all 13 quality gate definitions.
  """
  @spec all_gates() :: [GateSpec.t()]
  def all_gates do
    [
      gate_doc_001(),
      gate_doc_002(),
      gate_doc_003(),
      gate_impl_001(),
      gate_impl_002(),
      gate_impl_003(),
      gate_impl_004(),
      gate_impl_005(),
      gate_impl_006(),
      gate_impl_007(),
      gate_ops_001(),
      gate_ops_002(),
      gate_ops_003()
    ]
  end

  @doc """
  Returns gates for a specific category.
  """
  @spec gates_for_category(:doc | :impl | :ops) :: [GateSpec.t()]
  def gates_for_category(category) do
    Enum.filter(all_gates(), fn spec -> spec.category == category end)
  end
end
