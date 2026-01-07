defmodule Command.Orchestration.AgentConfigs do
  @moduledoc """
  Fetches Synapse agent configurations from Command storage.

  Used as a configuration source for `Synapse.Orchestrator.Runtime`.
  """

  import Ecto.Query

  alias Command.Orchestration.AgentConfig
  alias Command.Repo
  alias Synapse.Signal

  @config_keys ~w[
    id
    type
    signals
    actions
    result_builder
    custom_handler
    orchestration
    state_schema
    registry
    spawn_condition
    depends_on
    metadata
  ]a

  @signal_keys ~w[subscribes emits roles]a
  @role_keys ~w[request result summary]a
  @orchestration_keys ~w[classify_fn spawn_specialists aggregation_fn fast_path_fn negotiate_fn]a
  @config_key_strings Enum.map(@config_keys, &Atom.to_string/1)
  @signal_key_strings Enum.map(@signal_keys, &Atom.to_string/1)
  @role_key_strings Enum.map(@role_keys, &Atom.to_string/1)

  @doc """
  Returns a list of Synapse agent configuration maps for the runtime.
  """
  @spec configs() :: [map()]
  def configs do
    AgentConfig
    |> where([c], c.status == :active)
    |> Repo.all()
    |> Enum.map(&to_synapse_config/1)
  end

  defp to_synapse_config(%AgentConfig{} = record) do
    base_config = atomize_map(record.config || %{})

    base_config
    |> Map.put_new(:id, to_agent_id(record.agent_id))
    |> Map.put_new(:type, record.type)
    |> maybe_put_signals(record.signals)
  end

  defp maybe_put_signals(config, signals) when signals in [nil, %{}], do: config

  defp maybe_put_signals(config, signals) when is_map(signals) do
    Map.put(config, :signals, atomize_signals(signals))
  end

  defp to_agent_id(nil), do: nil
  defp to_agent_id(id) when is_atom(id), do: id
  defp to_agent_id(id) when is_binary(id), do: String.to_atom(id)

  defp atomize_signals(%{} = signals) do
    signals
    |> atomize_map(@signal_keys)
    |> Map.update(:roles, nil, &atomize_roles/1)
    |> Map.update(:subscribes, [], &normalize_topics/1)
    |> Map.update(:emits, [], &normalize_topics/1)
  end

  defp atomize_roles(nil), do: nil

  defp atomize_roles(%{} = roles) do
    atomize_map(roles, @role_keys)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, atomize_value(key, value))
    end)
  end

  defp atomize_map(%{} = map, allowed_keys \\ @config_keys) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      atom_key = normalize_key(key, allowed_keys)
      Map.put(acc, atom_key, atomize_value(atom_key, value))
    end)
  end

  defp normalize_key(key, _allowed) when is_atom(key), do: key

  defp normalize_key(key, allowed) when is_binary(key) do
    allowed_strings = allowed_key_strings(allowed)

    if key in allowed_strings do
      String.to_atom(key)
    else
      key
    end
  end

  defp atomize_value(:actions, value), do: normalize_modules(value)
  defp atomize_value(:depends_on, value), do: normalize_agent_ids(value)
  defp atomize_value(:signals, value) when is_map(value), do: atomize_signals(value)
  defp atomize_value(:orchestration, value) when is_map(value), do: normalize_orchestration(value)
  defp atomize_value(:registry, value), do: normalize_module(value)
  defp atomize_value(_key, value), do: value

  defp atomize_term(value) when is_atom(value), do: value
  defp atomize_term(value) when is_binary(value), do: String.to_atom(value)
  defp atomize_term(value), do: value

  defp allowed_key_strings(@config_keys), do: @config_key_strings
  defp allowed_key_strings(@signal_keys), do: @signal_key_strings
  defp allowed_key_strings(@role_keys), do: @role_key_strings

  defp allowed_key_strings(keys) do
    Enum.map(keys, &Atom.to_string/1)
  end

  defp normalize_topics(topics) when is_list(topics) do
    Enum.map(topics, &normalize_topic/1)
  end

  defp normalize_topics(other), do: other

  defp normalize_topic(topic) when is_atom(topic), do: topic

  defp normalize_topic(topic) when is_binary(topic) do
    case Signal.topic_from_type(topic) do
      {:ok, normalized} -> normalized
      :error -> String.to_atom(topic)
    end
  end

  defp normalize_orchestration(%{} = orchestration) do
    orchestration
    |> atomize_map(@orchestration_keys)
    |> Map.update(:classify_fn, nil, &normalize_callable/1)
    |> Map.update(:aggregation_fn, nil, &normalize_callable/1)
    |> Map.update(:fast_path_fn, nil, &normalize_callable/1)
    |> Map.update(:negotiate_fn, nil, &normalize_callable/1)
    |> Map.update(:spawn_specialists, nil, &normalize_spawn_specialists/1)
  end

  defp normalize_spawn_specialists(list) when is_list(list), do: normalize_agent_ids(list)
  defp normalize_spawn_specialists(other), do: normalize_callable(other)

  defp normalize_callable({module, function, args}) when is_list(args) do
    {normalize_module(module), normalize_function(function), args}
  end

  defp normalize_callable([module, function, args]) when is_list(args) do
    {normalize_module(module), normalize_function(function), args}
  end

  defp normalize_callable([module, function]) do
    {normalize_module(module), normalize_function(function), []}
  end

  defp normalize_callable(%{"module" => module, "function" => function} = map) do
    {normalize_module(module), normalize_function(function), Map.get(map, "args", [])}
  end

  defp normalize_callable(%{module: module, function: function} = map) do
    {normalize_module(module), normalize_function(function), Map.get(map, :args, [])}
  end

  defp normalize_callable(other), do: other

  defp normalize_module(nil), do: nil
  defp normalize_module(module) when is_atom(module), do: module

  defp normalize_module(module) when is_binary(module) do
    module
    |> String.trim_leading("Elixir.")
    |> then(&Module.concat([&1]))
  end

  defp normalize_function(nil), do: nil
  defp normalize_function(function) when is_atom(function), do: function
  defp normalize_function(function) when is_binary(function), do: String.to_atom(function)

  defp normalize_modules(list) when is_list(list), do: Enum.map(list, &normalize_module/1)
  defp normalize_modules(other), do: other

  defp normalize_agent_ids(list) when is_list(list), do: Enum.map(list, &atomize_term/1)
  defp normalize_agent_ids(other), do: other
end
