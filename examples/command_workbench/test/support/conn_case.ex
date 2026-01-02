defmodule CommandWorkbenchWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ConnTest
      import Plug.Conn
      import Phoenix.LiveViewTest

      @endpoint CommandWorkbenchWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Command.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Command.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
