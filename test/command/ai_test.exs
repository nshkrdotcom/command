defmodule Command.AITest do
  use ExUnit.Case, async: true

  alias Altar.AI.Adapters.Mock
  alias Altar.AI.Response
  alias Command.AI

  setup do
    Application.put_env(:command, :default_profile, :default)

    Application.put_env(:command, :profiles, %{
      default: [
        adapter: Mock,
        adapter_opts: [
          responses: %{
            generate: {:ok, Response.new("Configured response", model: "mock", provider: :mock)}
          }
        ]
      ]
    })

    on_exit(fn ->
      Application.delete_env(:command, :default_profile)
      Application.delete_env(:command, :profiles)
    end)

    :ok
  end

  test "generate/2 uses configured adapter profile" do
    assert {:ok, response} = AI.generate("Hello")
    assert response.content == "Configured response"
    assert response.model == "mock"
  end
end
