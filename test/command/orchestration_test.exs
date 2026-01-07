defmodule Command.OrchestrationTest do
  use Command.DataCase, async: false

  alias Command.Orchestration

  describe "create_agent_config/1" do
    test "stores agent configuration" do
      attrs = %{
        agent_id: "critic_agent",
        type: :specialist,
        config: %{
          "id" => "critic_agent",
          "type" => "specialist",
          "signals" => %{"subscribes" => ["task_request"], "emits" => ["task_result"]}
        },
        signals: %{"subscribes" => ["task_request"], "emits" => ["task_result"]}
      }

      assert {:ok, config} = Orchestration.create_agent_config(attrs)
      assert config.agent_id == "critic_agent"
      assert config.type == :specialist
    end
  end

  describe "create_agent_session/3" do
    test "creates an agent session tied to a command session" do
      session = insert(:session)

      {:ok, config} =
        Orchestration.create_agent_config(%{
          agent_id: "reviewer",
          type: :specialist,
          config: %{},
          signals: %{}
        })

      assert {:ok, agent_session} =
               Orchestration.create_agent_session(config, session, %{status: :running})

      assert agent_session.session_id == session.id
      assert agent_session.agent_config_id == config.id
      assert agent_session.status == :running
    end
  end
end
