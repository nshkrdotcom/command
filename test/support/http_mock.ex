defmodule Command.Test.HTTPMock do
  @moduledoc """
  HTTP-level mocking for provider APIs.

  Uses an Agent-based approach to simulate HTTP endpoints for Claude and Codex
  APIs. Provides response sequences, streaming simulation, error responses,
  and delayed responses.

  Note: Bypass is not used due to Ranch version conflicts with Cowboy 2.x.
  This module provides an equivalent mock API using Agent state.

  ## Usage

      setup do
        {:ok, mock} = HTTPMock.start_link()
        %{mock: mock}
      end

      test "mock Claude API", %{mock: mock} do
        response = %{"id" => "msg_123", "content" => [%{"text" => "Hello"}]}
        HTTPMock.setup_claude_mock(mock, [response])

        {:ok, resp} = HTTPMock.request(mock, :claude, %{})
        assert resp["id"] == "msg_123"
      end
  """

  use Agent

  @doc """
  Start an HTTP mock agent.
  """
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts \\ []) do
    Agent.start_link(fn ->
      %{
        claude_responses: [],
        codex_responses: [],
        streaming_chunks: [],
        error_status: nil,
        error_body: nil,
        delay_ms: 0,
        call_count: 0,
        validator: nil
      }
    end)
  end

  @doc """
  Configure mock for Claude API responses.
  """
  @spec setup_claude_mock(pid(), [map()], function() | nil) :: :ok
  def setup_claude_mock(mock, responses, validator \\ nil) do
    Agent.update(mock, fn state ->
      %{state | claude_responses: responses, call_count: 0, validator: validator}
    end)

    :ok
  end

  @doc """
  Configure mock for Codex API responses.
  """
  @spec setup_codex_mock(pid(), [map()], function() | nil) :: :ok
  def setup_codex_mock(mock, responses, validator \\ nil) do
    Agent.update(mock, fn state ->
      %{state | codex_responses: responses, call_count: 0, validator: validator}
    end)

    :ok
  end

  @doc """
  Configure mock for streaming responses.
  """
  @spec setup_streaming_mock(pid(), [map()]) :: :ok
  def setup_streaming_mock(mock, chunks) do
    Agent.update(mock, fn state ->
      %{state | streaming_chunks: chunks, call_count: 0}
    end)

    :ok
  end

  @doc """
  Configure mock for error responses.
  """
  @spec setup_error_mock(pid(), integer(), map() | nil) :: :ok
  def setup_error_mock(mock, status_code, body \\ nil) do
    default_body =
      case status_code do
        429 ->
          %{
            "error" => %{
              "type" => "rate_limit_error",
              "message" => "Rate limit exceeded"
            }
          }

        500 ->
          %{
            "error" => %{
              "type" => "internal_server_error",
              "message" => "Internal server error"
            }
          }

        _ ->
          %{"error" => %{"type" => "error", "message" => "Error"}}
      end

    Agent.update(mock, fn state ->
      %{state | error_status: status_code, error_body: body || default_body}
    end)

    :ok
  end

  @doc """
  Configure mock for delayed responses.
  """
  @spec setup_delayed_mock(pid(), map(), keyword()) :: :ok
  def setup_delayed_mock(mock, response, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 1000)

    Agent.update(mock, fn state ->
      %{state | claude_responses: [response], delay_ms: delay_ms, call_count: 0}
    end)

    :ok
  end

  @doc """
  Configure mock for multi-turn conversation.
  """
  @spec setup_multi_turn_mock(pid(), [map()]) :: :ok
  def setup_multi_turn_mock(mock, responses) do
    setup_claude_mock(mock, responses)
  end

  @doc """
  Make a mock request (simulates HTTP call).
  """
  @spec request(pid(), :claude | :codex, map()) ::
          {:ok, map()} | {:error, integer(), map()} | {:error, :timeout}
  def request(mock, provider, _body \\ %{}) do
    state = Agent.get(mock, & &1)

    # Simulate delay
    if state.delay_ms > 0, do: Process.sleep(state.delay_ms)

    # Check for error mock
    if state.error_status do
      Agent.update(mock, fn s -> %{s | call_count: s.call_count + 1} end)
      {:error, state.error_status, state.error_body}
    else
      responses =
        case provider do
          :claude -> state.claude_responses
          :codex -> state.codex_responses
        end

      index = state.call_count
      response = Enum.at(responses, index) || List.last(responses)

      Agent.update(mock, fn s -> %{s | call_count: s.call_count + 1} end)

      {:ok, response}
    end
  end

  @doc """
  Get streaming chunks from the mock.
  """
  @spec get_streaming_chunks(pid()) :: [map()]
  def get_streaming_chunks(mock) do
    Agent.get(mock, fn state -> state.streaming_chunks end)
  end

  @doc """
  Get the number of calls made to the mock.
  """
  @spec call_count(pid()) :: non_neg_integer()
  def call_count(mock) do
    Agent.get(mock, fn state -> state.call_count end)
  end

  @doc """
  Stop the mock agent.
  """
  @spec stop(pid()) :: :ok
  def stop(mock) do
    Agent.stop(mock)
  end
end
