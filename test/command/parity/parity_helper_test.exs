defmodule Command.Test.ParityHelperTest do
  @moduledoc """
  Tests for Command.Test.ParityHelper - provider parity testing framework.

  Following TDD - these tests are written BEFORE implementation.
  """
  use ExUnit.Case, async: false

  alias Command.Test.ParityHelper

  @moduletag :parity

  describe "run_parity_test/2" do
    test "executes same prompt against Claude and Codex" do
      prompt = "What is 2 + 2?"

      result = ParityHelper.run_parity_test(prompt, mock: true)

      assert result.prompt == prompt
      assert result.claude_response != nil
      assert result.codex_response != nil
    end

    test "returns parity result with score" do
      prompt = "Say hello"

      result = ParityHelper.run_parity_test(prompt, mock: true)

      assert is_float(result.parity_score)
      assert result.parity_score >= 0.0
      assert result.parity_score <= 1.0
    end

    test "returns discrepancies list" do
      prompt = "Test prompt"

      result = ParityHelper.run_parity_test(prompt, mock: true)

      assert is_list(result.discrepancies)
    end

    test "includes normalized responses" do
      prompt = "Test"

      result = ParityHelper.run_parity_test(prompt, mock: true)

      assert result.normalized_claude != nil
      assert result.normalized_codex != nil
      assert is_map(result.normalized_claude)
      assert is_map(result.normalized_codex)
    end
  end

  describe "normalize/2 for Claude" do
    test "normalizes Claude response to common format" do
      claude_response = %{
        "id" => "msg_123",
        "type" => "message",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "text",
            "text" => "Hello, world!"
          }
        ],
        "model" => "claude-opus-4-20260115",
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 5
        }
      }

      normalized = ParityHelper.normalize(claude_response, :claude)

      assert normalized.message == "Hello, world!"
      assert normalized.tool_calls == []
      assert normalized.usage.input_tokens == 10
      assert normalized.usage.output_tokens == 5
    end

    test "normalizes Claude tool call" do
      claude_response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_123",
            "name" => "read_file",
            "input" => %{
              "path" => "/home/user/file.txt"
            }
          }
        ],
        "usage" => %{
          "input_tokens" => 50,
          "output_tokens" => 20
        }
      }

      normalized = ParityHelper.normalize(claude_response, :claude)

      assert length(normalized.tool_calls) == 1
      tool = hd(normalized.tool_calls)
      assert tool.name == "read_file"
      assert tool.arguments.path == "/home/user/file.txt"
    end

    test "handles Claude streaming chunks" do
      chunks = [
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => "Hello"}
        },
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => " world"}
        }
      ]

      normalized = ParityHelper.normalize_streaming(chunks, :claude)

      assert normalized.message == "Hello world"
    end
  end

  describe "normalize/2 for Codex" do
    test "normalizes Codex response to common format" do
      codex_response = %{
        "id" => "resp_456",
        "object" => "response",
        "output" => [
          %{
            "type" => "message",
            "role" => "assistant",
            "content" => [
              %{
                "type" => "output_text",
                "text" => "Hello, world!"
              }
            ]
          }
        ],
        "usage" => %{
          "input_tokens" => 12,
          "output_tokens" => 6,
          "total_tokens" => 18
        }
      }

      normalized = ParityHelper.normalize(codex_response, :codex)

      assert normalized.message == "Hello, world!"
      assert normalized.tool_calls == []
      assert normalized.usage.input_tokens == 12
      assert normalized.usage.output_tokens == 6
    end

    test "normalizes Codex function call (tool use)" do
      codex_response = %{
        "output" => [
          %{
            "type" => "function_call",
            "id" => "call_789",
            "name" => "read_file",
            "arguments" => "{\"path\": \"/home/user/file.txt\"}"
          }
        ],
        "usage" => %{
          "input_tokens" => 52,
          "output_tokens" => 18
        }
      }

      normalized = ParityHelper.normalize(codex_response, :codex)

      assert length(normalized.tool_calls) == 1
      tool = hd(normalized.tool_calls)
      assert tool.name == "read_file"
      assert tool.arguments.path == "/home/user/file.txt"
    end

    test "handles Codex streaming chunks" do
      chunks = [
        %{
          "type" => "response.output_item.added",
          "item" => %{"content" => [%{"text" => "Hello"}]}
        },
        %{
          "type" => "response.output_item.added",
          "item" => %{"content" => [%{"text" => " world"}]}
        }
      ]

      normalized = ParityHelper.normalize_streaming(chunks, :codex)

      assert normalized.message == "Hello world"
    end
  end

  describe "compare/2" do
    test "calculates parity_score between normalized responses" do
      normalized_a = %{
        message: "Hello, world!",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      normalized_b = %{
        message: "Hello, world!",
        tool_calls: [],
        usage: %{input_tokens: 11, output_tokens: 5}
      }

      {score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      assert is_float(score)
      # High score for nearly identical responses
      assert score >= 0.9
      assert is_list(discrepancies)
    end

    test "returns discrepancies list for differences" do
      normalized_a = %{
        message: "Hello",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      normalized_b = %{
        message: "Hi",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      {_score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      assert length(discrepancies) > 0
      assert Enum.any?(discrepancies, fn d -> match?({:message_mismatch, _, _}, d) end)
    end

    test "message content compared with token-level Jaccard similarity" do
      # Per ADR-0008: Use token-level Jaccard similarity
      # Similarity = |tokens_a ∩ tokens_b| / |tokens_a ∪ tokens_b|

      normalized_a = %{
        message: "The quick brown fox",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      normalized_b = %{
        message: "The quick brown dog",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      {score, _discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      # 3 out of 4 tokens match: the, quick, brown (fox vs dog different)
      # Jaccard = 3 / 5 = 0.6
      # Overall score should account for this
      assert score >= 0.5
    end

    test "tool calls compared by name and argument structure" do
      normalized_a = %{
        message: "",
        tool_calls: [
          %{name: "read_file", arguments: %{path: "/foo/bar.txt"}}
        ],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      normalized_b = %{
        message: "",
        tool_calls: [
          %{name: "read_file", arguments: %{path: "/foo/bar.txt"}}
        ],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      {score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      # Should be very high for identical tool calls
      assert score >= 0.95
      assert length(discrepancies) == 0
    end

    test "token usage compared with tolerance (20%)" do
      # Per ADR-0008: Token counts within 20% variance acceptable

      normalized_a = %{
        message: "Test",
        tool_calls: [],
        usage: %{input_tokens: 100, output_tokens: 50}
      }

      normalized_b = %{
        message: "Test",
        tool_calls: [],
        # 10% and 10% variance
        usage: %{input_tokens: 110, output_tokens: 55}
      }

      {score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      # Within tolerance, should have high score
      assert score >= 0.9

      # Should not have token usage discrepancy
      refute Enum.any?(discrepancies, fn d -> match?({:token_usage_exceeded_tolerance, _}, d) end)
    end

    test "token usage outside tolerance (>20%) marked as discrepancy" do
      normalized_a = %{
        message: "Test",
        tool_calls: [],
        usage: %{input_tokens: 100, output_tokens: 50}
      }

      normalized_b = %{
        message: "Test",
        tool_calls: [],
        # 50% and 50% variance
        usage: %{input_tokens: 150, output_tokens: 75}
      }

      {_score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      # Should have token usage discrepancy
      assert Enum.any?(discrepancies, fn d ->
               match?({:token_usage_exceeded_tolerance, _}, d)
             end)
    end

    test "parity score >= threshold means pass" do
      normalized_a = %{
        message: "Hello world",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      normalized_b = %{
        message: "Hello world",
        tool_calls: [],
        usage: %{input_tokens: 11, output_tokens: 5}
      }

      {score, _discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      # Default threshold is 0.9
      assert score >= 0.9
      # Should pass
      assert ParityHelper.parity_pass?(score)
    end

    test "parity score < threshold means fail with discrepancies" do
      normalized_a = %{
        message: "Completely different message",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      normalized_b = %{
        message: "Another totally unrelated text",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      {score, discrepancies} = ParityHelper.compare(normalized_a, normalized_b)

      assert score < 0.9
      assert length(discrepancies) > 0
      # Should fail
      refute ParityHelper.parity_pass?(score)
    end
  end

  describe "parity thresholds" do
    test "message_parity threshold is 0.9" do
      assert ParityHelper.threshold(:message_parity) == 0.9
    end

    test "tool_call_parity threshold is 0.95" do
      assert ParityHelper.threshold(:tool_call_parity) == 0.95
    end

    test "metadata_presence threshold is 1.0" do
      assert ParityHelper.threshold(:metadata_presence) == 1.0
    end

    test "unknown_event_rate threshold is 0.01" do
      assert ParityHelper.threshold(:unknown_event_rate) == 0.01
    end

    test "overall_parity threshold is 0.9" do
      assert ParityHelper.threshold(:overall_parity) == 0.9
    end
  end

  describe "jaccard similarity calculation" do
    test "identical strings have similarity 1.0" do
      text_a = "The quick brown fox"
      text_b = "The quick brown fox"

      similarity = ParityHelper.jaccard_similarity(text_a, text_b)

      assert similarity == 1.0
    end

    test "completely different strings have similarity 0.0" do
      text_a = "hello world"
      text_b = "foo bar baz"

      similarity = ParityHelper.jaccard_similarity(text_a, text_b)

      assert similarity == 0.0
    end

    test "partial overlap calculated correctly" do
      text_a = "the quick brown fox"
      text_b = "the quick brown dog"

      # Tokens: the, quick, brown, fox, dog
      # Intersection: the, quick, brown (3)
      # Union: the, quick, brown, fox, dog (5)
      # Jaccard = 3/5 = 0.6

      similarity = ParityHelper.jaccard_similarity(text_a, text_b)

      assert_in_delta similarity, 0.6, 0.01
    end

    test "normalizes text before tokenization" do
      # Per ADR-0008: lowercase, trim, collapse whitespace, strip punctuation

      text_a = "Hello, World!"
      text_b = "hello   world"

      # After normalization: "hello world" vs "hello world"
      similarity = ParityHelper.jaccard_similarity(text_a, text_b)

      assert similarity == 1.0
    end

    test "keeps underscores and hyphens in normalization" do
      text_a = "foo_bar baz-qux"
      text_b = "foo_bar baz-qux"

      similarity = ParityHelper.jaccard_similarity(text_a, text_b)

      assert similarity == 1.0
    end
  end

  describe "metadata validation" do
    test "validates required metadata present" do
      normalized = %{
        message: "Test",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5},
        metadata: %{
          model: "claude-opus-4",
          stop_reason: "end_turn"
        }
      }

      assert ParityHelper.validate_metadata(normalized) == :ok
    end

    test "returns error for missing usage" do
      normalized = %{
        message: "Test",
        tool_calls: [],
        usage: nil
      }

      assert {:error, {:missing_metadata, :usage}} = ParityHelper.validate_metadata(normalized)
    end

    test "returns error for missing required metadata fields" do
      normalized = %{
        message: "Test",
        tool_calls: [],
        usage: %{input_tokens: 10, output_tokens: 5},
        metadata: nil
      }

      assert {:error, {:missing_metadata, :metadata}} =
               ParityHelper.validate_metadata(normalized)
    end
  end
end
