defmodule Command.Gates.GateCriterionTest do
  @moduledoc """
  Tests for Command.Gates.GateCriterion struct.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: true

  alias Command.Gates.GateCriterion

  describe "GateCriterion struct" do
    test "creates valid criterion with name and evaluator" do
      evaluator = fn _ctx -> :pass end

      criterion = %GateCriterion{
        name: "test_criterion",
        evaluator: evaluator
      }

      assert criterion.name == "test_criterion"
      assert is_function(criterion.evaluator, 1)
      # default
      assert criterion.required == true
    end

    test "evaluator is a 1-arity function" do
      evaluator = fn ctx ->
        if ctx[:valid], do: :pass, else: {:fail, "invalid"}
      end

      criterion = %GateCriterion{
        name: "validation",
        evaluator: evaluator
      }

      assert is_function(criterion.evaluator, 1)
      assert criterion.evaluator.(%{valid: true}) == :pass
      assert criterion.evaluator.(%{valid: false}) == {:fail, "invalid"}
    end

    test "evaluator returns :pass for success" do
      evaluator = fn _ctx -> :pass end

      criterion = %GateCriterion{
        name: "always_pass",
        evaluator: evaluator
      }

      assert criterion.evaluator.(%{}) == :pass
    end

    test "evaluator returns {:fail, details} for failure" do
      evaluator = fn ctx ->
        {:fail, "Missing field: #{ctx[:field]}"}
      end

      criterion = %GateCriterion{
        name: "check_field",
        evaluator: evaluator
      }

      result = criterion.evaluator.(%{field: "foo"})
      assert match?({:fail, _}, result)
      assert result == {:fail, "Missing field: foo"}
    end

    test "threshold field for numeric criteria" do
      criterion = %GateCriterion{
        name: "coverage_check",
        evaluator: fn ctx ->
          if ctx[:coverage] >= 80, do: :pass, else: {:fail, "Below threshold"}
        end,
        threshold: 80.0
      }

      assert criterion.threshold == 80.0
      assert criterion.evaluator.(%{coverage: 85}) == :pass
      assert criterion.evaluator.(%{coverage: 75}) == {:fail, "Below threshold"}
    end

    test "required field indicates if failure is blocking" do
      required_criterion = %GateCriterion{
        name: "must_pass",
        evaluator: fn _ctx -> :pass end,
        required: true
      }

      optional_criterion = %GateCriterion{
        name: "nice_to_have",
        evaluator: fn _ctx -> :pass end,
        required: false
      }

      assert required_criterion.required == true
      assert optional_criterion.required == false
    end

    test "required defaults to true" do
      criterion = %GateCriterion{
        name: "default",
        evaluator: fn _ctx -> :pass end
      }

      assert criterion.required == true
    end
  end

  describe "GateCriterion validation" do
    test "name must be present" do
      # This would be enforced by changeset/constructor in real implementation
      criterion = %GateCriterion{
        name: "valid_name",
        evaluator: fn _ctx -> :pass end
      }

      assert criterion.name != nil
      assert criterion.name != ""
    end

    test "evaluator must be a function" do
      evaluator = fn _ctx -> :pass end

      criterion = %GateCriterion{
        name: "test",
        evaluator: evaluator
      }

      assert is_function(criterion.evaluator)
    end
  end

  describe "GateCriterion evaluation patterns" do
    test "context-based evaluation" do
      evaluator = fn ctx ->
        cond do
          ctx[:all_tests_pass] == true -> :pass
          true -> {:fail, "Tests failed: #{inspect(ctx[:failures])}"}
        end
      end

      criterion = %GateCriterion{
        name: "test_suite",
        evaluator: evaluator
      }

      assert criterion.evaluator.(%{all_tests_pass: true}) == :pass

      assert criterion.evaluator.(%{
               all_tests_pass: false,
               failures: ["test1", "test2"]
             }) == {:fail, ~s(Tests failed: ["test1", "test2"])}
    end

    test "threshold-based evaluation" do
      evaluator = fn ctx ->
        coverage = ctx[:coverage] || 0

        if coverage >= (ctx[:threshold] || 80) do
          :pass
        else
          {:fail, %{coverage: coverage, threshold: ctx[:threshold]}}
        end
      end

      criterion = %GateCriterion{
        name: "coverage",
        evaluator: evaluator,
        threshold: 80.0
      }

      assert criterion.evaluator.(%{coverage: 85, threshold: 80}) == :pass

      assert match?(
               {:fail, %{coverage: 75, threshold: 80}},
               criterion.evaluator.(%{coverage: 75, threshold: 80})
             )
    end

    test "complex validation evaluation" do
      evaluator = fn ctx ->
        errors = []

        errors =
          if ctx[:migrations_compiled] != true,
            do: ["Migrations did not compile" | errors],
            else: errors

        errors =
          if ctx[:dry_run_passed] != true,
            do: ["Dry run failed" | errors],
            else: errors

        errors =
          if ctx[:rollback_tested] != true,
            do: ["Rollback not tested" | errors],
            else: errors

        case errors do
          [] -> :pass
          _ -> {:fail, %{errors: Enum.reverse(errors)}}
        end
      end

      criterion = %GateCriterion{
        name: "migration_readiness",
        evaluator: evaluator
      }

      # All checks pass
      assert criterion.evaluator.(%{
               migrations_compiled: true,
               dry_run_passed: true,
               rollback_tested: true
             }) == :pass

      # Some checks fail
      result =
        criterion.evaluator.(%{
          migrations_compiled: true,
          dry_run_passed: false,
          rollback_tested: false
        })

      assert match?({:fail, %{errors: _}}, result)
      {:fail, %{errors: errors}} = result
      assert "Dry run failed" in errors
      assert "Rollback not tested" in errors
    end
  end
end
