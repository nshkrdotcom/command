defmodule Command.Pipelines.Resources.CommandContext do
  @moduledoc """
  FlowStone resource providing Command context to pipeline assets.
  """

  @behaviour FlowStone.Resource

  alias Command.Sessions

  defstruct [:run_id, :session_id, :user_id, :session]

  @type t :: %__MODULE__{
          run_id: Ecto.UUID.t() | nil,
          session_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          session: Command.Sessions.Session.t() | nil
        }

  @impl true
  def setup(config) do
    session =
      case config[:session_id] do
        nil -> nil
        session_id -> Sessions.get_session(session_id)
      end

    {:ok,
     %__MODULE__{
       run_id: config[:run_id],
       session_id: config[:session_id],
       user_id: config[:user_id],
       session: session
     }}
  end

  @impl true
  def teardown(_resource), do: :ok

  @impl true
  def health_check(_resource), do: :healthy
end
