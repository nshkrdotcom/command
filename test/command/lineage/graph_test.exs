defmodule Command.Lineage.GraphTest do
  use ExUnit.Case, async: true

  alias Command.Lineage.Graph

  # Create mock edge structs for testing
  defp mock_edge(source_type, source_id, target_type, target_id, relationship) do
    %{
      source_type: source_type,
      source_id: source_id,
      target_type: target_type,
      target_id: target_id,
      relationship: relationship
    }
  end

  describe "build/1" do
    test "constructs graph from edge list" do
      edges = [
        mock_edge("artifact", "a1", "run", "r1", "created_by"),
        mock_edge("step", "s1", "run", "r1", "step_of")
      ]

      graph = Graph.build(edges)

      assert %Graph{} = graph
      assert length(graph.edges) == 2
      assert map_size(graph.nodes) > 0
      assert map_size(graph.adjacency) > 0
      assert map_size(graph.reverse_adjacency) > 0
    end

    test "extracts unique nodes from edges" do
      edges = [
        mock_edge("artifact", "a1", "run", "r1", "created_by"),
        mock_edge("artifact", "a1", "req", "req1", "implements")
      ]

      graph = Graph.build(edges)

      # Should have 3 unique nodes: a1, r1, req1
      assert map_size(graph.nodes) == 3
      assert Map.has_key?(graph.nodes, "artifact:a1")
      assert Map.has_key?(graph.nodes, "run:r1")
      assert Map.has_key?(graph.nodes, "req:req1")
    end

    test "builds forward adjacency map" do
      edges = [
        mock_edge("artifact", "a1", "run", "r1", "created_by")
      ]

      graph = Graph.build(edges)

      # artifact:a1 should point to run:r1
      assert Map.has_key?(graph.adjacency, "artifact:a1")
      neighbors = Map.get(graph.adjacency, "artifact:a1")
      assert {"run:r1", "created_by"} in neighbors
    end

    test "builds reverse adjacency map" do
      edges = [
        mock_edge("artifact", "a1", "run", "r1", "created_by")
      ]

      graph = Graph.build(edges)

      # run:r1 should have artifact:a1 as a predecessor
      assert Map.has_key?(graph.reverse_adjacency, "run:r1")
      predecessors = Map.get(graph.reverse_adjacency, "run:r1")
      assert {"artifact:a1", "created_by"} in predecessors
    end
  end

  describe "ancestors/2" do
    test "returns all ancestors of a node" do
      edges = [
        mock_edge("artifact", "a1", "run", "r1", "created_by"),
        mock_edge("run", "r1", "docset", "d1", "triggered_by")
      ]

      graph = Graph.build(edges)
      ancestors = Graph.ancestors(graph, "artifact:a1")

      # Ancestors of a1 should include r1 and d1
      assert "artifact:a1" in ancestors
      assert "run:r1" in ancestors
      assert "docset:d1" in ancestors
    end

    test "handles max_depth limit" do
      edges = [
        mock_edge("a", "1", "b", "2", "rel"),
        mock_edge("b", "2", "c", "3", "rel"),
        mock_edge("c", "3", "d", "4", "rel")
      ]

      graph = Graph.build(edges)

      # With max_depth 1, should only get immediate ancestors
      ancestors = Graph.ancestors(graph, "a:1", max_depth: 1)
      assert "a:1" in ancestors
      assert "b:2" in ancestors
      refute "c:3" in ancestors
    end

    test "filters by relationship type" do
      edges = [
        mock_edge("artifact", "a1", "run", "r1", "created_by"),
        mock_edge("artifact", "a1", "req", "req1", "implements")
      ]

      graph = Graph.build(edges)

      created_by_ancestors = Graph.ancestors(graph, "artifact:a1", relationship: "created_by")

      assert "artifact:a1" in created_by_ancestors
      assert "run:r1" in created_by_ancestors
      refute "req:req1" in created_by_ancestors
    end

    test "handles cycles without infinite loops" do
      edges = [
        mock_edge("a", "1", "b", "2", "rel"),
        mock_edge("b", "2", "a", "1", "rel")
      ]

      graph = Graph.build(edges)
      ancestors = Graph.ancestors(graph, "a:1")

      # Should include both nodes but not loop infinitely
      assert "a:1" in ancestors
      assert "b:2" in ancestors
      assert length(ancestors) == 2
    end
  end

  describe "descendants/2" do
    test "returns all descendants of a node" do
      edges = [
        mock_edge("docset", "d1", "run", "r1", "triggered"),
        mock_edge("run", "r1", "artifact", "a1", "created")
      ]

      graph = Graph.build(edges)
      descendants = Graph.descendants(graph, "docset:d1")

      assert "docset:d1" in descendants
      assert "run:r1" in descendants
      assert "artifact:a1" in descendants
    end

    test "handles max_depth limit" do
      edges = [
        mock_edge("a", "1", "b", "2", "rel"),
        mock_edge("b", "2", "c", "3", "rel"),
        mock_edge("c", "3", "d", "4", "rel")
      ]

      graph = Graph.build(edges)

      descendants = Graph.descendants(graph, "a:1", max_depth: 2)

      assert "a:1" in descendants
      assert "b:2" in descendants
      assert "c:3" in descendants
      refute "d:4" in descendants
    end

    test "filters by relationship type" do
      edges = [
        mock_edge("run", "r1", "artifact", "a1", "created"),
        mock_edge("run", "r1", "artifact", "a2", "output")
      ]

      graph = Graph.build(edges)

      created_descendants = Graph.descendants(graph, "run:r1", relationship: "created")

      assert "run:r1" in created_descendants
      assert "artifact:a1" in created_descendants
      refute "artifact:a2" in created_descendants
    end
  end

  describe "shortest_path/3" do
    test "finds shortest path between two nodes" do
      edges = [
        mock_edge("a", "1", "b", "2", "rel"),
        mock_edge("b", "2", "c", "3", "rel")
      ]

      graph = Graph.build(edges)
      path = Graph.shortest_path(graph, "a:1", "c:3")

      assert path == ["a:1", "b:2", "c:3"]
    end

    test "returns nil when no path exists" do
      edges = [
        mock_edge("a", "1", "b", "2", "rel"),
        mock_edge("c", "3", "d", "4", "rel")
      ]

      graph = Graph.build(edges)
      path = Graph.shortest_path(graph, "a:1", "d:4")

      assert path == nil
    end

    test "finds shortest path among multiple paths" do
      edges = [
        # Short path: a -> c
        mock_edge("a", "1", "c", "3", "rel"),
        # Long path: a -> b -> c
        mock_edge("a", "1", "b", "2", "rel"),
        mock_edge("b", "2", "c", "3", "rel")
      ]

      graph = Graph.build(edges)
      path = Graph.shortest_path(graph, "a:1", "c:3")

      # Should find the direct path
      assert path == ["a:1", "c:3"]
    end

    test "returns single-node path for same source and target" do
      edges = [
        mock_edge("a", "1", "b", "2", "rel")
      ]

      graph = Graph.build(edges)
      path = Graph.shortest_path(graph, "a:1", "a:1")

      assert path == ["a:1"]
    end
  end
end
