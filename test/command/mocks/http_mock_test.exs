defmodule Command.Test.HTTPMockTest do
  @moduledoc """
  Tests for Command.Test.HTTPMock - HTTP-level mocking for provider APIs.

  Following TDD - these tests are written BEFORE implementation.

  Note: Uses Agent-based mocking instead of Bypass due to Ranch version
  conflicts with Cowboy 2.x in the dependency tree.
  """
  use ExUnit.Case, async: false

  alias Command.Test.HTTPMock

  setup do
    {:ok, mock} = HTTPMock.start_link()
    on_exit(fn -> if Process.alive?(mock), do: HTTPMock.stop(mock) end)
    %{mock: mock}
  end

  describe "setup_claude_mock/2" do
    test "configures mock for Claude API", %{mock: mock} do
      response = %{
        "id" => "msg_123",
        "type" => "message",
        "content" => [%{"type" => "text", "text" => "Hello"}]
      }

      HTTPMock.setup_claude_mock(mock, [response])

      {:ok, resp} = HTTPMock.request(mock, :claude, %{})

      assert resp["id"] == "msg_123"
    end

    test "returns configured response on request", %{mock: mock} do
      response = %{
        "id" => "msg_456",
        "content" => [%{"type" => "text", "text" => "Test response"}]
      }

      HTTPMock.setup_claude_mock(mock, [response])

      {:ok, resp} = HTTPMock.request(mock, :claude)

      assert resp["id"] == "msg_456"
      assert get_in(resp, ["content", Access.at(0), "text"]) == "Test response"
    end

    test "supports multiple responses for sequence", %{mock: mock} do
      responses = [
        %{"id" => "msg_1", "content" => [%{"type" => "text", "text" => "First"}]},
        %{"id" => "msg_2", "content" => [%{"type" => "text", "text" => "Second"}]}
      ]

      HTTPMock.setup_claude_mock(mock, responses)

      {:ok, resp1} = HTTPMock.request(mock, :claude)
      assert resp1["id"] == "msg_1"

      {:ok, resp2} = HTTPMock.request(mock, :claude)
      assert resp2["id"] == "msg_2"
    end
  end

  describe "setup_codex_mock/2" do
    test "configures mock for Codex API", %{mock: mock} do
      response = %{
        "id" => "resp_789",
        "object" => "response",
        "output" => [%{"type" => "message", "content" => [%{"text" => "Hello"}]}]
      }

      HTTPMock.setup_codex_mock(mock, [response])

      {:ok, resp} = HTTPMock.request(mock, :codex)

      assert resp["id"] == "resp_789"
    end

    test "returns configured response on request", %{mock: mock} do
      response = %{
        "id" => "resp_abc",
        "output" => [%{"type" => "message", "content" => [%{"text" => "Codex response"}]}]
      }

      HTTPMock.setup_codex_mock(mock, [response])

      {:ok, resp} = HTTPMock.request(mock, :codex)

      assert resp["id"] == "resp_abc"
    end
  end

  describe "setup_streaming_mock/2" do
    test "supports streaming chunk sequences", %{mock: mock} do
      chunks = [
        %{"type" => "content_block_delta", "delta" => %{"text" => "Hello"}},
        %{"type" => "content_block_delta", "delta" => %{"text" => " world"}}
      ]

      HTTPMock.setup_streaming_mock(mock, chunks)

      result_chunks = HTTPMock.get_streaming_chunks(mock)
      assert length(result_chunks) == 2
    end

    test "streams events in correct format", %{mock: mock} do
      chunks = [
        %{"type" => "message_start", "message" => %{"id" => "msg_1"}},
        %{"type" => "content_block_delta", "delta" => %{"text" => "Test"}}
      ]

      HTTPMock.setup_streaming_mock(mock, chunks)

      result_chunks = HTTPMock.get_streaming_chunks(mock)
      assert Enum.at(result_chunks, 0)["type"] == "message_start"
      assert Enum.at(result_chunks, 1)["type"] == "content_block_delta"
    end
  end

  describe "setup_error_mock/2" do
    test "supports error responses (429)", %{mock: mock} do
      HTTPMock.setup_error_mock(mock, 429)

      {:error, status, _body} = HTTPMock.request(mock, :claude)

      assert status == 429
    end

    test "supports error responses (500)", %{mock: mock} do
      HTTPMock.setup_error_mock(mock, 500)

      {:error, status, _body} = HTTPMock.request(mock, :claude)

      assert status == 500
    end

    test "includes error details in response body", %{mock: mock} do
      HTTPMock.setup_error_mock(mock, 429, %{
        "error" => %{
          "type" => "rate_limit_error",
          "message" => "Rate limit exceeded"
        }
      })

      {:error, 429, body} = HTTPMock.request(mock, :claude)

      assert body["error"]["type"] == "rate_limit_error"
    end
  end

  describe "delayed responses for timeout testing" do
    test "supports delayed responses", %{mock: mock} do
      response = %{"id" => "msg_slow", "content" => []}

      HTTPMock.setup_delayed_mock(mock, response, delay_ms: 100)

      start_time = System.monotonic_time(:millisecond)
      {:ok, resp} = HTTPMock.request(mock, :claude)
      end_time = System.monotonic_time(:millisecond)

      elapsed = end_time - start_time
      assert elapsed >= 100
      assert resp["id"] == "msg_slow"
    end
  end

  describe "mock state management" do
    test "tracks call count", %{mock: mock} do
      response = %{"id" => "msg_test"}
      HTTPMock.setup_claude_mock(mock, [response])

      assert HTTPMock.call_count(mock) == 0

      HTTPMock.request(mock, :claude)
      assert HTTPMock.call_count(mock) == 1

      HTTPMock.request(mock, :claude)
      assert HTTPMock.call_count(mock) == 2
    end
  end

  describe "multi-turn conversation mocking" do
    test "supports response sequences for multi-turn", %{mock: mock} do
      responses = [
        %{"id" => "msg_1", "content" => [%{"type" => "text", "text" => "Turn 1"}]},
        %{"id" => "msg_2", "content" => [%{"type" => "text", "text" => "Turn 2"}]},
        %{"id" => "msg_3", "content" => [%{"type" => "text", "text" => "Turn 3"}]}
      ]

      HTTPMock.setup_multi_turn_mock(mock, responses)

      {:ok, resp1} = HTTPMock.request(mock, :claude)
      assert resp1["id"] == "msg_1"

      {:ok, resp2} = HTTPMock.request(mock, :claude)
      assert resp2["id"] == "msg_2"

      {:ok, resp3} = HTTPMock.request(mock, :claude)
      assert resp3["id"] == "msg_3"
    end
  end
end
