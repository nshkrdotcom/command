defmodule Command.Lineage.Graph do
  @moduledoc """
  Build and traverse lineage graphs for provenance tracking.

  A lineage graph represents the relationships between artifacts, runs, steps,
  requirements, and other entities. This module provides:

  - Graph construction from provenance edges
  - Backward traversal (ancestors - what created this?)
  - Forward traversal (descendants - what did this create?)
  - Shortest path finding
  - Cycle detection and handling

  ## Example

      # Build graph from edges
      edges = Edges.query_by_source("artifact", artifact_id)
      graph = Graph.build(edges)

      # Find all ancestors
      ancestors = Graph.ancestors(graph, "artifact:123")

      # Find all descendants
      descendants = Graph.descendants(graph, "run:456")

      # Find shortest path
      path = Graph.shortest_path(graph, "artifact:123", "requirement:REQ-001")
  """

  defstruct nodes: %{}, edges: [], adjacency: %{}, reverse_adjacency: %{}

  @type node_key :: String.t()
  @type graph_node :: %{id: String.t(), type: String.t()}
  @type graph_edge :: %{
          source_type: String.t(),
          source_id: String.t(),
          target_type: String.t(),
          target_id: String.t(),
          relationship: String.t()
        }
  @type t :: %__MODULE__{
          nodes: %{node_key => graph_node},
          edges: [graph_edge],
          adjacency: %{node_key => [{node_key, String.t()}]},
          reverse_adjacency: %{node_key => [{node_key, String.t()}]}
        }

  @doc """
  Build graph from database edges.

  Extracts unique nodes, builds forward and reverse adjacency maps.

  ## Examples

      iex> edges = [%{source_type: "artifact", source_id: "a1", ...}]
      iex> graph = Graph.build(edges)
      %Graph{nodes: %{...}, adjacency: %{...}}
  """
  @spec build([graph_edge]) :: t()
  def build(edges) do
    nodes = extract_nodes(edges)
    adjacency = build_adjacency(edges)
    reverse_adjacency = build_reverse_adjacency(edges)

    %__MODULE__{
      nodes: nodes,
      edges: edges,
      adjacency: adjacency,
      reverse_adjacency: reverse_adjacency
    }
  end

  @doc """
  Get all ancestors (backward traversal) of a node.

  Traverses the graph backward from the given node, following reverse edges.

  ## Options

  - `:max_depth` - Maximum traversal depth (default: 100)
  - `:relationship` - Filter by specific relationship type

  ## Examples

      iex> Graph.ancestors(graph, "artifact:123")
      ["artifact:123", "run:456", "docset:789"]

      iex> Graph.ancestors(graph, "artifact:123", max_depth: 2)
      ["artifact:123", "run:456"]

      iex> Graph.ancestors(graph, "artifact:123", relationship: "created_by")
      ["artifact:123", "run:456"]
  """
  @spec ancestors(t(), node_key, keyword()) :: [node_key]
  def ancestors(%__MODULE__{} = graph, node_key, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 100)
    filter_rel = Keyword.get(opts, :relationship)

    do_traverse(graph.adjacency, node_key, max_depth, filter_rel, MapSet.new())
  end

  @doc """
  Get all descendants (forward traversal) of a node.

  Traverses the graph forward from the given node, following forward edges.

  ## Options

  - `:max_depth` - Maximum traversal depth (default: 100)
  - `:relationship` - Filter by specific relationship type

  ## Examples

      iex> Graph.descendants(graph, "docset:789")
      ["docset:789", "run:456", "artifact:123"]
  """
  @spec descendants(t(), node_key, keyword()) :: [node_key]
  def descendants(%__MODULE__{} = graph, node_key, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 100)
    filter_rel = Keyword.get(opts, :relationship)

    do_traverse(graph.adjacency, node_key, max_depth, filter_rel, MapSet.new())
  end

  @doc """
  Find shortest path between two nodes using BFS.

  Returns the path as a list of node keys, or nil if no path exists.

  ## Examples

      iex> Graph.shortest_path(graph, "artifact:123", "requirement:REQ-001")
      ["artifact:123", "run:456", "requirement:REQ-001"]

      iex> Graph.shortest_path(graph, "artifact:123", "nonexistent:999")
      nil
  """
  @spec shortest_path(t(), node_key, node_key) :: [node_key] | nil
  def shortest_path(%__MODULE__{} = graph, source_key, target_key) do
    if source_key == target_key do
      [source_key]
    else
      bfs(graph.adjacency, source_key, target_key)
    end
  end

  # Private functions

  defp extract_nodes(edges) do
    edges
    |> Enum.flat_map(fn e ->
      [
        {node_key(e.source_type, e.source_id), %{id: e.source_id, type: e.source_type}},
        {node_key(e.target_type, e.target_id), %{id: e.target_id, type: e.target_type}}
      ]
    end)
    |> Map.new()
  end

  defp node_key(type, id), do: "#{type}:#{id}"

  defp build_adjacency(edges) do
    Enum.reduce(edges, %{}, fn e, acc ->
      key = node_key(e.source_type, e.source_id)
      target = {node_key(e.target_type, e.target_id), e.relationship}
      Map.update(acc, key, [target], &[target | &1])
    end)
  end

  defp build_reverse_adjacency(edges) do
    Enum.reduce(edges, %{}, fn e, acc ->
      key = node_key(e.target_type, e.target_id)
      source = {node_key(e.source_type, e.source_id), e.relationship}
      Map.update(acc, key, [source], &[source | &1])
    end)
  end

  defp do_traverse(_adjacency, key, 0, _filter, visited) do
    MapSet.put(visited, key) |> MapSet.to_list()
  end

  defp do_traverse(adjacency, key, depth, filter, visited) do
    if MapSet.member?(visited, key) do
      MapSet.to_list(visited)
    else
      visited = MapSet.put(visited, key)
      neighbors = filtered_neighbors(adjacency, key, filter)

      Enum.reduce(neighbors, visited, fn {neighbor_key, _rel}, acc ->
        result = do_traverse(adjacency, neighbor_key, depth - 1, filter, acc)
        MapSet.union(acc, MapSet.new(result))
      end)
      |> MapSet.to_list()
    end
  end

  defp filtered_neighbors(adjacency, key, nil), do: Map.get(adjacency, key, [])

  defp filtered_neighbors(adjacency, key, filter) do
    adjacency
    |> Map.get(key, [])
    |> Enum.filter(fn {_k, rel} -> rel == filter end)
  end

  defp bfs(adjacency, source, target) do
    queue = :queue.from_list([{source, [source]}])
    visited = MapSet.new([source])

    bfs_loop(adjacency, queue, visited, target)
  end

  defp bfs_loop(adjacency, queue, visited, target) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, {current, path}}, queue} ->
        bfs_process_node(adjacency, queue, visited, target, current, path)
    end
  end

  defp bfs_process_node(_adjacency, _queue, _visited, target, target, path) do
    Enum.reverse(path)
  end

  defp bfs_process_node(adjacency, queue, visited, target, current, path) do
    neighbors = Map.get(adjacency, current, [])

    {new_queue, new_visited} =
      Enum.reduce(neighbors, {queue, visited}, fn {neighbor, _rel}, {q, v} ->
        bfs_enqueue_neighbor(neighbor, path, q, v)
      end)

    bfs_loop(adjacency, new_queue, new_visited, target)
  end

  defp bfs_enqueue_neighbor(neighbor, path, queue, visited) do
    if MapSet.member?(visited, neighbor) do
      {queue, visited}
    else
      {:queue.in({neighbor, [neighbor | path]}, queue), MapSet.put(visited, neighbor)}
    end
  end
end
