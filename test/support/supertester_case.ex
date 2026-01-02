defmodule Command.SupertesterCase do
  @moduledoc """
  Test case for tests requiring full OTP isolation with supertester.

  Use this for tests that manipulate PortfolioCore.Registry or other
  global GenServer state. The setup automatically clears all registry
  entries before each test for proper isolation.

  ## Usage

      use Command.SupertesterCase, async: true

  This provides:
  - Ecto sandbox setup (same as DataCase)
  - Factory helpers
  - Supertester OTP helpers and assertions
  - PortfolioCore.Registry cleanup before each test
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Supertester.OTPHelpers
      import Supertester.Assertions

      alias Command.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Command.DataCase
      import Command.Factory
    end
  end

  setup tags do
    Command.DataCase.setup_sandbox(tags)

    # Clear all registry entries for this test to ensure isolation
    for port <- [:vector_store, :embedder, :llm, :retriever, :chunker] do
      PortfolioCore.Registry.unregister(port)
    end

    :ok
  end
end
