defmodule Command.Orchestration.SignalBridge do
  @moduledoc """
  Bridges Synapse signals to Command PubSub topics.
  """

  use GenServer
  require Logger

  alias Command.Orchestration
  alias Command.PubSub
  alias Synapse.Signal
  alias Synapse.SignalRouter

  @type state :: %{
          router: atom(),
          subscriptions: [{Signal.topic(), reference()}]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc """
  Starts the signal bridge process.
  """
  def start_link(opts \\ []) do
    if Orchestration.enabled?() and Orchestration.runtime_available?() do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    else
      :ignore
    end
  end

  @impl true
  def init(opts) do
    router = Orchestration.router()
    topics = Keyword.get(opts, :topics, Signal.topics())

    subscriptions =
      Enum.flat_map(topics, fn topic ->
        case SignalRouter.subscribe(router, topic, target: self()) do
          {:ok, sub_id} ->
            [{topic, sub_id}]

          {:error, reason} ->
            Logger.warning("Failed to subscribe to Synapse topic",
              topic: topic,
              reason: inspect(reason)
            )

            []
        end
      end)

    {:ok, %{router: router, subscriptions: subscriptions}}
  end

  @impl true
  def handle_info({:signal, %Jido.Signal{} = signal}, state) do
    _ =
      case Signal.topic_from_type(signal.type) do
        {:ok, topic} ->
          _ = PubSub.broadcast("synapse:signals:#{topic}", :synapse_signal, signal)
          _ = maybe_broadcast_session(signal)
          _ = maybe_broadcast_workflow(signal)

        :error ->
          :ok
      end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{router: router, subscriptions: subscriptions}) do
    Enum.each(subscriptions, fn {_topic, sub_id} ->
      _ = SignalRouter.unsubscribe(router, sub_id)
    end)

    :ok
  end

  defp maybe_broadcast_session(signal) do
    case extract_signal_field(signal, "command_session_id") do
      nil -> :ok
      session_id -> PubSub.broadcast("session:#{session_id}:signals", :synapse_signal, signal)
    end
  end

  defp maybe_broadcast_workflow(signal) do
    case extract_signal_field(signal, "command_workflow_id") do
      nil -> :ok
      workflow_id -> PubSub.broadcast("workflow:#{workflow_id}:signals", :synapse_signal, signal)
    end
  end

  defp extract_signal_field(%Jido.Signal{} = signal, key) do
    data_value = extract_from_map(signal.data, key)
    ext_value = extract_from_map(signal.extensions, key)

    data_value || ext_value
  end

  defp extract_from_map(%{} = map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp extract_from_map(_, _key), do: nil
end
