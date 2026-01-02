ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Command.Repo, :manual)

# Ensure PortfolioCore.Registry is available for tests
# The registry is started by portfolio_core's application, but we need
# to ensure it's running before tests that use mocks
unless Process.whereis(PortfolioCore.Registry) do
  {:ok, _} = PortfolioCore.Registry.start_link([])
end
