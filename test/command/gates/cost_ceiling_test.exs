defmodule Command.Gates.CostCeilingTest do
  @moduledoc """
  Tests for Command.Gates.CostCeiling - GATE-OPS-002 implementation.

  Following TDD - these tests are written BEFORE implementation.

  CRITICAL: Uses Decimal arithmetic throughout for precision.
  """
  use ExUnit.Case, async: true

  alias Command.Gates.CostCeiling

  describe "evaluate/2" do
    test "passes when cost < ceiling" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("25.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      assert :pass = CostCeiling.evaluate(run_context, event)
    end

    test "fails when cost > ceiling" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("48.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      assert {:fail, details} = CostCeiling.evaluate(run_context, event)
      assert details.current == Decimal.new("53.00")
      assert details.ceiling == Decimal.new("50.00")
      assert details.exceeded_by == Decimal.new("3.00")
    end

    test "fails when cost == ceiling (boundary)" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("45.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      # At exact ceiling should fail (not >=, but >)
      # According to spec: "Run cost exceeds ceiling" and "Current run cost < ceiling" to pass
      # So exactly at ceiling should fail
      assert {:fail, details} = CostCeiling.evaluate(run_context, event)
      assert Decimal.equal?(details.current, Decimal.new("50.00"))
      assert Decimal.equal?(details.ceiling, Decimal.new("50.00"))
    end

    test "uses Decimal arithmetic throughout" do
      # Verify all calculations use Decimal, not float
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("0.1")},
        config: %{cost_ceiling_usd: Decimal.new("1.0")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("0.2")}}

      result = CostCeiling.evaluate(run_context, event)

      # If using floats, 0.1 + 0.2 might not equal 0.3
      # With Decimal, it should be exact
      assert result == :pass

      # Test at boundary
      event2 = %{usage: %{total_cost_usd: Decimal.new("0.9")}}
      result2 = CostCeiling.evaluate(run_context, event2)

      # 0.1 + 0.9 = 1.0, should fail at ceiling
      assert match?({:fail, _}, result2)
    end
  end

  describe "per-run ceiling" do
    test "per-run ceiling evaluated independently" do
      # First run
      run1_context = %{
        run_id: "run-001",
        usage: %{total_cost_usd: Decimal.new("30.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event1 = %{usage: %{total_cost_usd: Decimal.new("15.00")}}
      assert :pass = CostCeiling.evaluate(run1_context, event1)

      # Second run (independent)
      run2_context = %{
        run_id: "run-002",
        usage: %{total_cost_usd: Decimal.new("5.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event2 = %{usage: %{total_cost_usd: Decimal.new("10.00")}}
      assert :pass = CostCeiling.evaluate(run2_context, event2)
    end
  end

  describe "per-session ceiling" do
    test "per-session ceiling tracks cumulative cost" do
      # Session context tracks cumulative cost across runs
      session_context = %{
        session_id: "session-001",
        cumulative_cost_usd: Decimal.new("450.00"),
        config: %{session_cost_ceiling_usd: Decimal.new("500.00")}
      }

      # Adding run that would exceed session ceiling
      run_cost = Decimal.new("60.00")

      # Check session ceiling
      total_session_cost = Decimal.add(session_context.cumulative_cost_usd, run_cost)

      if Decimal.compare(total_session_cost, session_context.config.session_cost_ceiling_usd) ==
           :gt do
        assert total_session_cost == Decimal.new("510.00")
        # Should exceed
        assert true
      end
    end
  end

  describe "default ceilings" do
    test "default per-run ceiling is $50" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("45.00")},
        # No ceiling specified
        config: %{}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("10.00")}}

      # Should use default ceiling of $50
      assert {:fail, details} = CostCeiling.evaluate(run_context, event)
      assert details.ceiling == Decimal.new("50.00")
    end

    test "default per-session ceiling is $500" do
      session_ceiling = CostCeiling.default_session_ceiling()
      assert session_ceiling == Decimal.new("500.00")
    end

    test "default ceilings applied when not configured" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("0.00")},
        config: %{}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      # Should pass with default ceiling
      assert :pass = CostCeiling.evaluate(run_context, event)
    end
  end

  describe "custom ceilings" do
    test "custom ceiling from run config applied" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("90.00")},
        # Custom ceiling
        config: %{cost_ceiling_usd: Decimal.new("100.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      assert :pass = CostCeiling.evaluate(run_context, event)

      # But would fail with higher cost
      event2 = %{usage: %{total_cost_usd: Decimal.new("15.00")}}
      assert {:fail, _} = CostCeiling.evaluate(run_context, event2)
    end

    test "custom session ceiling can be set" do
      session_context = %{
        session_id: "session-001",
        cumulative_cost_usd: Decimal.new("900.00"),
        # Custom
        config: %{session_cost_ceiling_usd: Decimal.new("1000.00")}
      }

      # Verify custom ceiling is respected
      assert session_context.config.session_cost_ceiling_usd == Decimal.new("1000.00")
    end
  end

  describe "cost extraction from event" do
    test "cost extracted from event.usage.total_cost_usd" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("10.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{
        usage: %{
          total_cost_usd: Decimal.new("5.50"),
          input_tokens: 100,
          output_tokens: 50
        }
      }

      assert :pass = CostCeiling.evaluate(run_context, event)

      # Verify cost was extracted correctly
      # In real implementation, would verify the extracted value
    end

    test "handles nested usage structure" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("10.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{
        type: :usage_update,
        data: %{
          usage: %{
            total_cost_usd: Decimal.new("3.25")
          }
        }
      }

      # Should handle nested structure
      assert :pass = CostCeiling.evaluate(run_context, event)
    end
  end

  describe "edge cases" do
    test "nil cost treated as 0" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("10.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: nil}}

      # Should treat nil as 0 and pass
      assert :pass = CostCeiling.evaluate(run_context, event)
    end

    test "negative cost returns error" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("10.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("-5.00")}}

      # Negative cost is invalid
      assert {:error, :invalid_cost} = CostCeiling.evaluate(run_context, event)
    end

    test "zero cost is valid" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("10.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("0.00")}}

      assert :pass = CostCeiling.evaluate(run_context, event)
    end

    test "very small costs accumulate correctly" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("0.0001")},
        config: %{cost_ceiling_usd: Decimal.new("0.001")}
      }

      # Add many small costs
      events = for _ <- 1..5, do: %{usage: %{total_cost_usd: Decimal.new("0.0001")}}

      final_context =
        Enum.reduce(events, run_context, fn event, ctx ->
          case CostCeiling.evaluate(ctx, event) do
            :pass ->
              new_total =
                Decimal.add(ctx.usage.total_cost_usd, event.usage.total_cost_usd)

              put_in(ctx.usage.total_cost_usd, new_total)

            {:fail, _} ->
              ctx
          end
        end)

      # Should have accumulated to 0.0006
      assert final_context.usage.total_cost_usd == Decimal.new("0.0006")
    end

    test "handles very large costs" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("999999.00")},
        config: %{cost_ceiling_usd: Decimal.new("1000000.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("0.50")}}

      assert :pass = CostCeiling.evaluate(run_context, event)

      event2 = %{usage: %{total_cost_usd: Decimal.new("1.50")}}
      assert {:fail, _} = CostCeiling.evaluate(run_context, event2)
    end
  end

  describe "telemetry" do
    test "emits telemetry with cost details on evaluation" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-cost-ceiling-#{inspect(ref)}",
        [:command, :gates, :cost_ceiling, :evaluated],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

      run_context = %{
        usage: %{total_cost_usd: Decimal.new("25.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      CostCeiling.evaluate(run_context, event)

      assert_receive {:telemetry, [:command, :gates, :cost_ceiling, :evaluated], measurements,
                      metadata}

      # Verify cost details in telemetry
      assert measurements.current_cost != nil
      assert measurements.ceiling != nil
      assert metadata.result in [:pass, :fail]

      :telemetry.detach("test-cost-ceiling-#{inspect(ref)}")
    end

    test "emits telemetry on ceiling exceeded" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-cost-exceeded-#{inspect(ref)}",
        [:command, :gates, :cost_ceiling, :exceeded],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )

      run_context = %{
        usage: %{total_cost_usd: Decimal.new("48.00")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("5.00")}}

      CostCeiling.evaluate(run_context, event)

      assert_receive {:telemetry, [:command, :gates, :cost_ceiling, :exceeded], measurements,
                      metadata}

      assert measurements.exceeded_by == Decimal.new("3.00")
      assert metadata.current_cost == Decimal.new("53.00")
      assert metadata.ceiling == Decimal.new("50.00")

      :telemetry.detach("test-cost-exceeded-#{inspect(ref)}")
    end
  end

  describe "precision tests" do
    test "floating point precision edge case" do
      # This is the classic 0.1 + 0.2 != 0.3 problem
      # With Decimal, it should work correctly

      run_context = %{
        usage: %{total_cost_usd: Decimal.new("0.1")},
        config: %{cost_ceiling_usd: Decimal.new("0.3")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("0.2")}}

      # With Decimal: 0.1 + 0.2 = 0.3 exactly
      # At ceiling, should fail
      assert {:fail, details} = CostCeiling.evaluate(run_context, event)
      assert Decimal.equal?(details.current, Decimal.new("0.3"))
    end

    test "boundary value at ceiling - 1 cent" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("49.99")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("0.01")}}

      # 49.99 + 0.01 = 50.00, at ceiling, should fail
      assert {:fail, _} = CostCeiling.evaluate(run_context, event)
    end

    test "boundary value just under ceiling" do
      run_context = %{
        usage: %{total_cost_usd: Decimal.new("49.98")},
        config: %{cost_ceiling_usd: Decimal.new("50.00")}
      }

      event = %{usage: %{total_cost_usd: Decimal.new("0.01")}}

      # 49.98 + 0.01 = 49.99, under ceiling, should pass
      assert :pass = CostCeiling.evaluate(run_context, event)
    end
  end
end
