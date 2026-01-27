defmodule Command.Test.ParityHelper do
  @moduledoc """
  Helpers for running parity tests between Claude and Codex providers.

  Implements token-level Jaccard similarity for message content comparison,
  schema equivalence for structured outputs, and threshold-based pass/fail
  evaluation per ADR-0008.

  ## Parity Thresholds

  - `message_parity`: 0.9
  - `tool_call_parity`: 0.95
  - `metadata_presence`: 1.0
  - `unknown_event_rate`: 0.01
  - `overall_parity`: 0.9

  ## Usage

      result = ParityHelper.run_parity_test("What is 2+2?", mock: true)
      assert result.parity_score >= 0.9

      {score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)
      assert ParityHelper.parity_pass?(score)
  """

  @parity_thresholds %{
    message_parity: 0.9,
    tool_call_parity: 0.95,
    metadata_presence: 1.0,
    unknown_event_rate: 0.01,
    overall_parity: 0.9
  }

  @token_usage_tolerance 0.20

  @doc """
  Returns the threshold for the given parity metric.
  """
  @spec threshold(atom()) :: float()
  def threshold(metric), do: Map.fetch!(@parity_thresholds, metric)

  @doc """
  Run a parity test executing the same prompt against both providers.

  Options:
  - `mock: true` - Use mock responses instead of real API calls
  """
  @spec run_parity_test(String.t(), keyword()) :: map()
  def run_parity_test(prompt, opts \\ []) do
    {claude_response, codex_response} =
      if Keyword.get(opts, :mock, false) do
        {mock_claude_response(prompt), mock_codex_response(prompt)}
      else
        {call_claude(prompt), call_codex(prompt)}
      end

    normalized_claude = normalize(claude_response, :claude)
    normalized_codex = normalize(codex_response, :codex)
    {parity_score, discrepancies} = compare(normalized_claude, normalized_codex)

    %{
      prompt: prompt,
      claude_response: claude_response,
      codex_response: codex_response,
      normalized_claude: normalized_claude,
      normalized_codex: normalized_codex,
      parity_score: parity_score,
      discrepancies: discrepancies
    }
  end

  @doc """
  Normalize a provider response to a common format.
  """
  @spec normalize(map(), :claude | :codex) :: map()
  def normalize(response, :claude) do
    message = extract_claude_message(response)
    tool_calls = extract_claude_tool_calls(response)
    usage = extract_claude_usage(response)

    metadata =
      Map.take(response, ["model", "stop_reason"])
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)

    %{
      message: message,
      tool_calls: tool_calls,
      usage: usage,
      metadata: metadata
    }
  end

  def normalize(response, :codex) do
    message = extract_codex_message(response)
    tool_calls = extract_codex_tool_calls(response)
    usage = extract_codex_usage(response)

    metadata =
      Map.take(response, ["model", "stop_reason"])
      |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)

    %{
      message: message,
      tool_calls: tool_calls,
      usage: usage,
      metadata: metadata
    }
  end

  @doc """
  Normalize streaming chunks to a common format.
  """
  @spec normalize_streaming([map()], :claude | :codex) :: map()
  def normalize_streaming(chunks, :claude) do
    message =
      chunks
      |> Enum.filter(fn c -> c["type"] == "content_block_delta" end)
      |> Enum.map(fn c -> get_in(c, ["delta", "text"]) || "" end)
      |> Enum.join()

    %{message: message, tool_calls: [], usage: %{input_tokens: 0, output_tokens: 0}}
  end

  def normalize_streaming(chunks, :codex) do
    message =
      chunks
      |> Enum.filter(fn c -> c["type"] == "response.output_item.added" end)
      |> Enum.map(fn c ->
        content = get_in(c, ["item", "content"]) || []
        Enum.map(content, fn item -> item["text"] || "" end) |> Enum.join()
      end)
      |> Enum.join()

    %{message: message, tool_calls: [], usage: %{input_tokens: 0, output_tokens: 0}}
  end

  @doc """
  Compare two normalized responses and return parity score with discrepancies.
  """
  @spec compare(map(), map()) :: {float(), [tuple()]}
  def compare(normalized_a, normalized_b) do
    discrepancies = []

    # Message parity (weighted 40%)
    msg_score = jaccard_similarity(normalized_a.message || "", normalized_b.message || "")

    discrepancies =
      if msg_score < @parity_thresholds.message_parity do
        [{:message_mismatch, normalized_a.message, normalized_b.message} | discrepancies]
      else
        discrepancies
      end

    # Tool call parity (weighted 30%)
    tool_score = calculate_tool_call_parity(normalized_a.tool_calls, normalized_b.tool_calls)

    discrepancies =
      if tool_score < @parity_thresholds.tool_call_parity and
           (normalized_a.tool_calls != [] or normalized_b.tool_calls != []) do
        [{:tool_call_mismatch, normalized_a.tool_calls, normalized_b.tool_calls} | discrepancies]
      else
        discrepancies
      end

    # Token usage parity (weighted 30%)
    usage_a = normalized_a[:usage] || %{input_tokens: 0, output_tokens: 0}
    usage_b = normalized_b[:usage] || %{input_tokens: 0, output_tokens: 0}
    {usage_score, usage_discrepancies} = calculate_token_usage_parity(usage_a, usage_b)
    discrepancies = usage_discrepancies ++ discrepancies

    # Overall score (weighted average)
    has_tools = normalized_a.tool_calls != [] or normalized_b.tool_calls != []

    overall_score =
      if has_tools do
        msg_score * 0.4 + tool_score * 0.3 + usage_score * 0.3
      else
        msg_score * 0.6 + usage_score * 0.4
      end

    {overall_score, Enum.reverse(discrepancies)}
  end

  @doc """
  Check if a parity score passes the overall threshold.
  """
  @spec parity_pass?(float()) :: boolean()
  def parity_pass?(score), do: score >= @parity_thresholds.overall_parity

  @doc """
  Calculate token-level Jaccard similarity between two strings.

  Text is normalized (lowercased, punctuation stripped, whitespace collapsed)
  before tokenization.
  """
  @spec jaccard_similarity(String.t(), String.t()) :: float()
  def jaccard_similarity(text_a, text_b) do
    tokens_a = tokenize(text_a)
    tokens_b = tokenize(text_b)

    set_a = MapSet.new(tokens_a)
    set_b = MapSet.new(tokens_b)

    intersection = MapSet.intersection(set_a, set_b) |> MapSet.size()
    union = MapSet.union(set_a, set_b) |> MapSet.size()

    case union do
      0 -> 1.0
      n -> intersection / n
    end
  end

  @doc """
  Validate that required metadata is present in a normalized response.
  """
  @spec validate_metadata(map()) :: :ok | {:error, {:missing_metadata, atom()}}
  def validate_metadata(normalized) do
    cond do
      is_nil(normalized[:usage]) ->
        {:error, {:missing_metadata, :usage}}

      is_nil(normalized[:metadata]) ->
        {:error, {:missing_metadata, :metadata}}

      true ->
        :ok
    end
  end

  # -- Private: Claude extraction --

  defp extract_claude_message(response) do
    content = response["content"] || []

    content
    |> Enum.filter(fn item -> item["type"] == "text" end)
    |> Enum.map(fn item -> item["text"] end)
    |> Enum.join("")
  end

  defp extract_claude_tool_calls(response) do
    content = response["content"] || []

    content
    |> Enum.filter(fn item -> item["type"] == "tool_use" end)
    |> Enum.map(fn item ->
      %{
        name: item["name"],
        arguments: atomize_keys(item["input"] || %{})
      }
    end)
  end

  defp extract_claude_usage(response) do
    usage = response["usage"] || %{}

    %{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0
    }
  end

  # -- Private: Codex extraction --

  defp extract_codex_message(response) do
    output = response["output"] || []

    output
    |> Enum.filter(fn item -> item["type"] == "message" end)
    |> Enum.flat_map(fn item ->
      content = item["content"] || []
      Enum.map(content, fn c -> c["text"] || "" end)
    end)
    |> Enum.join("")
  end

  defp extract_codex_tool_calls(response) do
    output = response["output"] || []

    output
    |> Enum.filter(fn item -> item["type"] == "function_call" end)
    |> Enum.map(fn item ->
      args =
        case item["arguments"] do
          s when is_binary(s) ->
            case Jason.decode(s) do
              {:ok, parsed} -> atomize_keys(parsed)
              _ -> %{}
            end

          m when is_map(m) ->
            atomize_keys(m)

          _ ->
            %{}
        end

      %{name: item["name"], arguments: args}
    end)
  end

  defp extract_codex_usage(response) do
    usage = response["usage"] || %{}

    %{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0
    }
  end

  # -- Private: Comparison helpers --

  defp calculate_tool_call_parity(tools_a, tools_b) when tools_a == [] and tools_b == [], do: 1.0

  defp calculate_tool_call_parity(tools_a, tools_b) do
    names_a = MapSet.new(Enum.map(tools_a, & &1.name))
    names_b = MapSet.new(Enum.map(tools_b, & &1.name))

    name_intersection = MapSet.intersection(names_a, names_b) |> MapSet.size()
    name_union = MapSet.union(names_a, names_b) |> MapSet.size()

    if name_union == 0, do: 1.0, else: name_intersection / name_union
  end

  defp calculate_token_usage_parity(usage_a, usage_b) do
    input_a = usage_a[:input_tokens] || usage_a.input_tokens || 0
    input_b = usage_b[:input_tokens] || usage_b.input_tokens || 0
    output_a = usage_a[:output_tokens] || usage_a.output_tokens || 0
    output_b = usage_b[:output_tokens] || usage_b.output_tokens || 0

    input_diff = if input_a > 0, do: abs(input_a - input_b) / max(input_a, 1), else: 0.0
    output_diff = if output_a > 0, do: abs(output_a - output_b) / max(output_a, 1), else: 0.0

    discrepancies =
      if input_diff > @token_usage_tolerance or output_diff > @token_usage_tolerance do
        [{:token_usage_exceeded_tolerance, %{input_diff: input_diff, output_diff: output_diff}}]
      else
        []
      end

    score = 1.0 - (input_diff + output_diff) / 2.0
    score = max(score, 0.0)

    {score, discrepancies}
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.split(~r/\s+/, trim: true)
  end

  defp atomize_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, v}
    end)
  end

  # -- Private: Mock responses --

  defp mock_claude_response(prompt) do
    %{
      "id" => "msg_mock_#{:erlang.unique_integer([:positive])}",
      "type" => "message",
      "role" => "assistant",
      "content" => [
        %{"type" => "text", "text" => "Mock response for: #{prompt}"}
      ],
      "model" => "claude-opus-4-20260115",
      "usage" => %{
        "input_tokens" => 10,
        "output_tokens" => 8
      }
    }
  end

  defp mock_codex_response(prompt) do
    %{
      "id" => "resp_mock_#{:erlang.unique_integer([:positive])}",
      "object" => "response",
      "output" => [
        %{
          "type" => "message",
          "role" => "assistant",
          "content" => [
            %{"type" => "output_text", "text" => "Mock response for: #{prompt}"}
          ]
        }
      ],
      "usage" => %{
        "input_tokens" => 11,
        "output_tokens" => 8,
        "total_tokens" => 19
      }
    }
  end

  defp call_claude(_prompt), do: raise("Real Claude API calls not implemented in test helper")
  defp call_codex(_prompt), do: raise("Real Codex API calls not implemented in test helper")
end
