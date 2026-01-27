# Basic Command.AI usage via portfolio adapters.
#
# Requires portfolio_core and portfolio_index to be configured with
# registered LLM and Embedder adapters.
#
# Run:
#   mix run --no-start examples/ai_basic.exs

alias Command.AI

# Ensure portfolio ecosystem is started
{:ok, _} = Application.ensure_all_started(:portfolio_core)
{:ok, _} = Application.ensure_all_started(:portfolio_index)

{:ok, response} = AI.generate("Summarize the benefits of pattern matching.")
IO.puts("Generate: #{inspect(response)}")

{:ok, classification} = AI.classify("I love Elixir", ["positive", "negative"])
IO.puts("Classification: #{classification.label} (#{classification.confidence})")
