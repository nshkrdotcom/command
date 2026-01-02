defmodule Command.AgentsTest do
  use Command.DataCase, async: true

  alias Command.Agents
  alias Command.Agents.{AgentCall, ToolUse}

  describe "agent_calls" do
    test "create_agent_call/2 creates an agent call" do
      session = insert(:session)

      attrs = %{
        provider: "anthropic",
        model: "claude-sonnet-4-20250514",
        prompt_messages: [%{"role" => "user", "content" => "Hello"}]
      }

      assert {:ok, %AgentCall{} = call} = Agents.create_agent_call(session, attrs)
      assert call.provider == "anthropic"
      assert call.model == "claude-sonnet-4-20250514"
      assert call.status == "pending"
      assert call.session_id == session.id
      assert call.started_at != nil
    end

    test "create_agent_call/2 validates provider" do
      session = insert(:session)

      attrs = %{
        provider: "invalid",
        model: "test",
        prompt_messages: [%{"role" => "user", "content" => "Hello"}]
      }

      assert {:error, changeset} = Agents.create_agent_call(session, attrs)
      assert %{provider: ["is invalid"]} = errors_on(changeset)
    end

    test "start_streaming/1 updates status" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      assert {:ok, updated} = Agents.start_streaming(call)
      assert updated.status == "streaming"
      assert updated.first_token_at != nil
    end

    test "complete_agent_call/2 completes the call" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      attrs = %{
        response_content: "Hello!",
        stop_reason: "end_turn",
        tokens_in: 10,
        tokens_out: 5,
        cost_cents: 1
      }

      assert {:ok, completed} = Agents.complete_agent_call(call, attrs)
      assert completed.status == "completed"
      assert completed.response_content == "Hello!"
      assert completed.completed_at != nil
      assert completed.duration_ms != nil
    end

    test "fail_agent_call/2 marks as failed" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      assert {:ok, failed} =
               Agents.fail_agent_call(call, %{
                 error_type: "rate_limit",
                 error_message: "Rate limited"
               })

      assert failed.status == "failed"
      assert failed.error_type == "rate_limit"
    end

    test "cancel_agent_call/1 cancels the call" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      assert {:ok, cancelled} = Agents.cancel_agent_call(call)
      assert cancelled.status == "cancelled"
    end

    test "list_agent_calls/2 returns session's calls" do
      session = insert(:session)

      {:ok, call1} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      {:ok, call2} =
        Agents.create_agent_call(session, %{
          provider: "openai",
          model: "gpt-4",
          prompt_messages: []
        })

      calls = Agents.list_agent_calls(session)

      assert length(calls) == 2
      assert Enum.any?(calls, &(&1.id == call1.id))
      assert Enum.any?(calls, &(&1.id == call2.id))
    end
  end

  describe "tool_uses" do
    test "create_tool_use/2 creates a tool use" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      attrs = %{
        tool_name: "bash",
        tool_use_id: "toolu_123",
        input: %{"command" => "ls -la"}
      }

      assert {:ok, %ToolUse{} = tool_use} = Agents.create_tool_use(call, attrs)
      assert tool_use.tool_name == "bash"
      assert tool_use.input == %{"command" => "ls -la"}
      assert tool_use.sequence == 1
    end

    test "create_tool_use/2 auto-increments sequence" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      {:ok, tu1} = Agents.create_tool_use(call, %{tool_name: "bash", input: %{}})
      {:ok, tu2} = Agents.create_tool_use(call, %{tool_name: "read", input: %{}})

      assert tu1.sequence == 1
      assert tu2.sequence == 2
    end

    test "approve_tool_use/2 approves the tool use" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      {:ok, tool_use} =
        Agents.create_tool_use(call, %{
          tool_name: "bash",
          input: %{},
          requires_approval: true
        })

      user = insert(:user)
      assert {:ok, approved} = Agents.approve_tool_use(tool_use, %{approved_by_id: user.id})
      assert approved.status == "approved"
      assert approved.approved_at != nil
    end

    test "deny_tool_use/2 denies the tool use" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      {:ok, tool_use} = Agents.create_tool_use(call, %{tool_name: "bash", input: %{}})

      assert {:ok, denied} = Agents.deny_tool_use(tool_use, %{denial_reason: "Too dangerous"})
      assert denied.status == "denied"
      assert denied.denial_reason == "Too dangerous"
    end

    test "complete_tool_use/2 completes execution" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      {:ok, tool_use} = Agents.create_tool_use(call, %{tool_name: "bash", input: %{}})
      {:ok, executing} = Agents.start_tool_execution(tool_use)

      assert {:ok, completed} =
               Agents.complete_tool_use(executing, %{
                 output: "file1.txt\nfile2.txt",
                 exit_code: 0
               })

      assert completed.status == "completed"
      assert completed.output == "file1.txt\nfile2.txt"
      assert completed.exit_code == 0
    end

    test "list_tool_uses/1 returns call's tool uses" do
      session = insert(:session)

      {:ok, call} =
        Agents.create_agent_call(session, %{
          provider: "anthropic",
          model: "claude-sonnet-4-20250514",
          prompt_messages: []
        })

      {:ok, tu1} = Agents.create_tool_use(call, %{tool_name: "bash", input: %{}})
      {:ok, tu2} = Agents.create_tool_use(call, %{tool_name: "read", input: %{}})

      tool_uses = Agents.list_tool_uses(call)

      assert length(tool_uses) == 2
      assert Enum.at(tool_uses, 0).id == tu1.id
      assert Enum.at(tool_uses, 1).id == tu2.id
    end
  end
end
