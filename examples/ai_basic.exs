# Basic Command.AI usage with the Mock adapter.
#
# Run:
#   mix run --no-start examples/ai_basic.exs

alias Altar.AI.Adapters.Mock
alias Command.AI

{:ok, _} = Application.ensure_all_started(:altar_ai)

Application.put_env(:command, :default_profile, :mock)

Application.put_env(:command, :profiles, %{
  mock: %{
    adapter: Mock.new()
  }
})

{:ok, response} = AI.generate("Summarize the benefits of pattern matching.")
IO.puts("Generate: #{response.content}")

{:ok, classification} = AI.classify("I love Elixir", ["positive", "negative"])
IO.puts("Classification: #{classification.label} (#{classification.confidence})")
