defmodule Command.Policy do
  @moduledoc """
  Helpers for policy metadata used in approval decisions.
  """

  @approval_classes ~w(none low medium high critical)
  @priorities %{
    "critical" => "critical",
    "high" => "high",
    "medium" => "normal",
    "low" => "low",
    "none" => "low"
  }

  @type policy_metadata :: %{
          optional(String.t()) => term()
        }

  @doc """
  Normalizes a policy metadata map to string keys.
  """
  @spec normalize(map() | nil) :: policy_metadata()
  def normalize(nil), do: %{}

  def normalize(%{} = policy) do
    policy
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), normalize_value(value))
    end)
    |> Map.update("approval_class", nil, &normalize_approval_class/1)
    |> Map.update("side_effects", [], &normalize_list/1)
    |> Map.update("capabilities", [], &normalize_list/1)
  end

  @doc """
  Returns true when a policy requires approval.
  """
  @spec approval_required?(map() | nil) :: boolean()
  def approval_required?(policy) do
    case approval_class(policy) do
      "none" -> false
      nil -> false
      _ -> true
    end
  end

  @doc """
  Returns the normalized approval class for a policy.
  """
  @spec approval_class(map() | nil) :: String.t() | nil
  def approval_class(policy) do
    policy
    |> normalize()
    |> Map.get("approval_class")
  end

  @doc """
  Maps policy metadata to an approval risk level.
  """
  @spec risk_level(map() | nil) :: String.t() | nil
  def risk_level(policy) do
    case approval_class(policy) do
      level when level in @approval_classes -> level
      _ -> nil
    end
  end

  @doc """
  Derives approval priority from policy metadata.
  """
  @spec priority(map() | nil) :: String.t()
  def priority(policy) do
    policy
    |> approval_class()
    |> then(&Map.get(@priorities, &1, "normal"))
  end

  @doc """
  Builds a list of risk factors from policy metadata.
  """
  @spec risk_factors(map() | nil) :: [String.t()]
  def risk_factors(policy) do
    normalized = normalize(policy)

    side_effects = Map.get(normalized, "side_effects", [])
    capabilities = Map.get(normalized, "capabilities", [])

    (side_effects ++ capabilities)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp normalize_approval_class(nil), do: nil
  defp normalize_approval_class(class) when is_atom(class), do: Atom.to_string(class)
  defp normalize_approval_class(class) when is_binary(class), do: String.downcase(class)
  defp normalize_approval_class(class), do: to_string(class)

  defp normalize_list(nil), do: []
  defp normalize_list(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_list(value), do: [to_string(value)]

  defp normalize_value(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, inner}, acc ->
      Map.put(acc, to_string(key), normalize_value(inner))
    end)
  end

  defp normalize_value(value), do: value
end
