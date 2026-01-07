defmodule Command.CostsTest do
  use Command.DataCase, async: true

  alias Command.AI.Cost
  alias Command.Costs

  describe "record_ai_operation/1" do
    test "records an AI operation cost" do
      session = insert(:session)

      attrs = %{
        session_id: session.id,
        operation: :generate,
        model: "gpt-4o",
        tokens_in: 100,
        tokens_out: 50,
        cost_usd: Decimal.new("0.00225"),
        duration_ms: 1500
      }

      assert {:ok, %Cost{} = cost} = Costs.record_ai_operation(attrs)
      assert cost.session_id == session.id
      assert cost.operation == :generate
      assert cost.model == "gpt-4o"
      assert cost.tokens_in == 100
      assert cost.tokens_out == 50
      assert cost.cost_usd == Decimal.new("0.00225")
      assert cost.duration_ms == 1500
    end
  end

  describe "get_session_costs/1" do
    test "returns all costs for a session" do
      session = insert(:session)
      other_session = insert(:session)

      {:ok, cost_one} =
        Costs.record_ai_operation(%{
          session_id: session.id,
          operation: :generate,
          model: "gpt-4o",
          tokens_in: 10,
          tokens_out: 5,
          cost_usd: Decimal.new("0.00010")
        })

      {:ok, cost_two} =
        Costs.record_ai_operation(%{
          session_id: session.id,
          operation: :embed,
          model: "text-embedding-3-small",
          tokens_in: 5,
          tokens_out: 0,
          cost_usd: Decimal.new("0.00002")
        })

      {:ok, _other_cost} =
        Costs.record_ai_operation(%{
          session_id: other_session.id,
          operation: :generate,
          model: "gpt-4o",
          tokens_in: 3,
          tokens_out: 2,
          cost_usd: Decimal.new("0.00005")
        })

      costs = Costs.get_session_costs(session.id)

      assert Enum.sort(Enum.map(costs, & &1.id)) == Enum.sort([cost_one.id, cost_two.id])
    end
  end
end
