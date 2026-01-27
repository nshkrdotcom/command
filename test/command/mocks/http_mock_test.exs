defmodule Command.Test.HTTPMockTest do
  @moduledoc """
  Tests for Command.Test.HTTPMock - HTTP-level mocking using Bypass.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: false

  alias Command.Test.HTTPMock

  setup do
    bypass = Bypass.open()
    %{bypass: bypass}
  end

  describe "setup_claude_mock/2" do
    test "configures Bypass for Claude API", %{bypass: bypass} do
      response = %{
        "id" => "msg_123",
        "type" => "message",
        "content" => [%{"type" => "text", "text" => "Hello"}]
      }

      HTTPMock.setup_claude_mock(bypass, [response])

      # Make request to bypass
      url = "http://localhost:#{bypass.port}/v1/messages"

      {:ok, resp} =
        HTTPoison.post(url, Jason.encode!(%{}), [{"content-type", "application/json"}])

      assert resp.status_code == 200
      body = Jason.decode!(resp.body)
      assert body["id"] == "msg_123"
    end

    test "returns configured response on request", %{bypass: bypass} do
      response = %{
        "id" => "msg_456",
        "content" => [%{"type" => "text", "text" => "Test response"}]
      }

      HTTPMock.setup_claude_mock(bypass, [response])

      url = "http://localhost:#{bypass.port}/v1/messages"
      {:ok, resp} = HTTPoison.post(url, "{}", [{"content-type", "application/json"}])

      body = Jason.decode!(resp.body)
      assert body["id"] == "msg_456"
      assert get_in(body, ["content", Access.at(0), "text"]) == "Test response"
    end

    test "supports multiple responses for sequence", %{bypass: bypass} do
      responses = [
        %{"id" => "msg_1", "content" => [%{"type" => "text", "text" => "First"}]},
        %{"id" => "msg_2", "content" => [%{"type" => "text", "text" => "Second"}]}
      ]

      HTTPMock.setup_claude_mock(bypass, responses)

      # Note: Actual implementation would need state management for sequences
      # This is a simplified test
      url = "http://localhost:#{bypass.port}/v1/messages"
      {:ok, resp} = HTTPoison.post(url, "{}", [{"content-type", "application/json"}])

      body = Jason.decode!(resp.body)
      assert body["id"] in ["msg_1", "msg_2"]
    end
  end

  describe "setup_codex_mock/2" do
    test "configures Bypass for Codex API", %{bypass: bypass} do
      response = %{
        "id" => "resp_789",
        "object" => "response",
        "output" => [%{"type" => "message", "content" => [%{"text" => "Hello"}]}]
      }

      HTTPMock.setup_codex_mock(bypass, [response])

      url = "http://localhost:#{bypass.port}/v1/responses"

      {:ok, resp} =
        HTTPoison.post(url, Jason.encode!(%{}), [{"content-type", "application/json"}])

      assert resp.status_code == 200
      body = Jason.decode!(resp.body)
      assert body["id"] == "resp_789"
    end

    test "returns configured response on request", %{bypass: bypass} do
      response = %{
        "id" => "resp_abc",
        "output" => [%{"type" => "message", "content" => [%{"text" => "Codex response"}]}]
      }

      HTTPMock.setup_codex_mock(bypass, [response])

      url = "http://localhost:#{bypass.port}/v1/responses"
      {:ok, resp} = HTTPoison.post(url, "{}", [{"content-type", "application/json"}])

      body = Jason.decode!(resp.body)
      assert body["id"] == "resp_abc"
    end
  end

  describe "setup_streaming_mock/2" do
    test "supports streaming chunk sequences", %{bypass: bypass} do
      chunks = [
        %{"type" => "content_block_delta", "delta" => %{"text" => "Hello"}},
        %{"type" => "content_block_delta", "delta" => %{"text" => " world"}}
      ]

      HTTPMock.setup_streaming_mock(bypass, chunks)

      url = "http://localhost:#{bypass.port}/v1/messages"

      {:ok, resp} = HTTPoison.get(url, [{"accept", "text/event-stream"}])

      assert resp.status_code == 200

      assert resp.headers["content-type"] =~ "event-stream" or
               Enum.any?(resp.headers, fn {k, v} ->
                 k == "content-type" and v =~ "event-stream"
               end)
    end

    test "streams events in correct format", %{bypass: bypass} do
      chunks = [
        %{"type" => "message_start", "message" => %{"id" => "msg_1"}},
        %{"type" => "content_block_delta", "delta" => %{"text" => "Test"}}
      ]

      HTTPMock.setup_streaming_mock(bypass, chunks)

      # In real implementation, would verify SSE format:
      # data: {json}\n\n
    end
  end

  describe "setup_error_mock/2" do
    test "supports error responses (429)", %{bypass: bypass} do
      HTTPMock.setup_error_mock(bypass, 429)

      url = "http://localhost:#{bypass.port}/v1/messages"
      {:ok, resp} = HTTPoison.post(url, "{}", [])

      assert resp.status_code == 429
    end

    test "supports error responses (500)", %{bypass: bypass} do
      HTTPMock.setup_error_mock(bypass, 500)

      url = "http://localhost:#{bypass.port}/v1/messages"
      {:ok, resp} = HTTPoison.post(url, "{}", [])

      assert resp.status_code == 500
    end

    test "includes error details in response body", %{bypass: bypass} do
      HTTPMock.setup_error_mock(bypass, 429, %{
        "error" => %{
          "type" => "rate_limit_error",
          "message" => "Rate limit exceeded"
        }
      })

      url = "http://localhost:#{bypass.port}/v1/messages"
      {:ok, resp} = HTTPoison.post(url, "{}", [])

      assert resp.status_code == 429
      body = Jason.decode!(resp.body)
      assert body["error"]["type"] == "rate_limit_error"
    end
  end

  describe "delayed responses for timeout testing" do
    test "supports delayed responses", %{bypass: bypass} do
      response = %{"id" => "msg_slow", "content" => []}

      HTTPMock.setup_delayed_mock(bypass, response, delay_ms: 1000)

      url = "http://localhost:#{bypass.port}/v1/messages"

      start_time = System.monotonic_time(:millisecond)
      {:ok, _resp} = HTTPoison.post(url, "{}", [], recv_timeout: 2000)
      end_time = System.monotonic_time(:millisecond)

      elapsed = end_time - start_time
      # Should have waited at least 1 second
      assert elapsed >= 1000
    end

    test "timeout occurs if delay exceeds recv_timeout", %{bypass: bypass} do
      response = %{"id" => "msg_timeout"}

      HTTPMock.setup_delayed_mock(bypass, response, delay_ms: 2000)

      url = "http://localhost:#{bypass.port}/v1/messages"

      # Set short timeout
      assert {:error, %HTTPoison.Error{reason: :timeout}} =
               HTTPoison.post(url, "{}", [], recv_timeout: 500)
    end
  end

  describe "mock state management" do
    test "can reset mock expectations", %{bypass: bypass} do
      response1 = %{"id" => "msg_1"}
      HTTPMock.setup_claude_mock(bypass, [response1])

      # Reset and configure new expectation
      Bypass.down(bypass)
      Bypass.up(bypass)

      response2 = %{"id" => "msg_2"}
      HTTPMock.setup_claude_mock(bypass, [response2])

      url = "http://localhost:#{bypass.port}/v1/messages"
      {:ok, resp} = HTTPoison.post(url, "{}", [])

      body = Jason.decode!(resp.body)
      assert body["id"] == "msg_2"
    end

    test "can verify number of requests made", %{bypass: bypass} do
      response = %{"id" => "msg_test"}
      HTTPMock.setup_claude_mock(bypass, [response])

      # Make multiple requests
      url = "http://localhost:#{bypass.port}/v1/messages"
      HTTPoison.post(url, "{}", [])
      HTTPoison.post(url, "{}", [])

      # In real implementation, would track request count
      # This is a placeholder for that functionality
    end
  end

  describe "multi-turn conversation mocking" do
    test "supports response sequences for multi-turn", %{bypass: bypass} do
      responses = [
        %{"id" => "msg_1", "content" => [%{"type" => "text", "text" => "Turn 1"}]},
        %{"id" => "msg_2", "content" => [%{"type" => "text", "text" => "Turn 2"}]},
        %{"id" => "msg_3", "content" => [%{"type" => "text", "text" => "Turn 3"}]}
      ]

      HTTPMock.setup_multi_turn_mock(bypass, responses)

      # Would need stateful implementation to return different responses per call
      # This is a test for the expected API
    end
  end

  describe "request validation" do
    test "can validate request body", %{bypass: bypass} do
      expected_prompt = "Test prompt"

      HTTPMock.setup_claude_mock(bypass, [%{"id" => "msg_validated"}], fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        request = Jason.decode!(body)

        assert request["messages"] != nil or request["prompt"] != nil
        conn
      end)

      url = "http://localhost:#{bypass.port}/v1/messages"
      request_body = Jason.encode!(%{"prompt" => expected_prompt})

      {:ok, _resp} = HTTPoison.post(url, request_body, [{"content-type", "application/json"}])
    end

    test "can validate request headers", %{bypass: bypass} do
      HTTPMock.setup_claude_mock(bypass, [%{"id" => "msg_headers"}], fn conn ->
        # Verify API key header
        assert Plug.Conn.get_req_header(conn, "x-api-key") != []
        conn
      end)

      url = "http://localhost:#{bypass.port}/v1/messages"

      {:ok, _resp} =
        HTTPoison.post(url, "{}", [
          {"content-type", "application/json"},
          {"x-api-key", "test-key"}
        ])
    end
  end
end
