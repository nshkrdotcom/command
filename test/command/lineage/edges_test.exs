defmodule Command.Lineage.EdgesTest do
  use Command.DataCase, async: true

  alias Command.Lineage.{Edges, ProvenanceEdge}
  alias Command.Repo

  describe "record/4" do
    test "creates provenance edge in database" do
      source = %{type: "artifact", id: Ecto.UUID.generate()}
      target = %{type: "run", id: Ecto.UUID.generate()}

      {:ok, edge} = Edges.record(source, target, "created_by", %{})

      assert edge.source_type == "artifact"
      assert edge.source_id == source.id
      assert edge.target_type == "run"
      assert edge.target_id == target.id
      assert edge.relationship == "created_by"
      assert edge.metadata == %{}
    end

    test "does not create duplicate edges (upsert)" do
      source = %{type: "artifact", id: Ecto.UUID.generate()}
      target = %{type: "run", id: Ecto.UUID.generate()}

      {:ok, edge1} = Edges.record(source, target, "created_by", %{})
      {:ok, edge2} = Edges.record(source, target, "created_by", %{foo: "bar"})

      # Second call returns :ok but doesn't create duplicate
      edges =
        Repo.all(
          from e in ProvenanceEdge,
            where: e.source_id == ^source.id and e.target_id == ^target.id
        )

      assert length(edges) == 1
    end

    test "validates relationship is allowed" do
      source = %{type: "artifact", id: Ecto.UUID.generate()}
      target = %{type: "run", id: Ecto.UUID.generate()}

      assert_raise Ecto.InvalidChangesetError, fn ->
        Edges.record(source, target, "invalid_relationship", %{})
      end
    end
  end

  describe "record_batch/1" do
    test "creates multiple edges in transaction" do
      artifact_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()
      step_id = Ecto.UUID.generate()

      edges = [
        {%{type: "artifact", id: artifact_id}, %{type: "run", id: run_id}, "created_by", %{}},
        {%{type: "step", id: step_id}, %{type: "run", id: run_id}, "step_of", %{}}
      ]

      {:ok, _} = Edges.record_batch(edges)

      all_edges = Repo.all(ProvenanceEdge)
      assert length(all_edges) == 2
    end

    test "rolls back all edges if one fails" do
      artifact_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      edges = [
        {%{type: "artifact", id: artifact_id}, %{type: "run", id: run_id}, "created_by", %{}},
        {%{type: "step", id: "bad"}, %{type: "run", id: run_id}, "invalid_rel", %{}}
      ]

      {:error, _} = Edges.record_batch(edges)

      # No edges should be created
      all_edges = Repo.all(ProvenanceEdge)
      assert length(all_edges) == 0
    end
  end

  describe "record_created_by/3" do
    test "creates artifact->run created_by edge" do
      artifact_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      {:ok, edge} = Edges.record_created_by(artifact_id, run_id)

      assert edge.source_type == "artifact"
      assert edge.source_id == artifact_id
      assert edge.target_type == "run"
      assert edge.target_id == run_id
      assert edge.relationship == "created_by"
      assert edge.metadata == %{}
    end

    test "includes step_id in metadata when provided" do
      artifact_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()
      step_id = Ecto.UUID.generate()

      {:ok, edge} = Edges.record_created_by(artifact_id, run_id, step_id)

      assert edge.metadata == %{"step_id" => step_id}
    end
  end

  describe "record_prompt_step_artifacts/2" do
    test "records prompt, response, and diff edges" do
      prompt_step_run_id = Ecto.UUID.generate()
      prompt_artifact_id = Ecto.UUID.generate()
      response_artifact_id = Ecto.UUID.generate()
      diff_artifact_id = Ecto.UUID.generate()

      {:ok, _} =
        Edges.record_prompt_step_artifacts(prompt_step_run_id, %{
          prompt_artifact_id: prompt_artifact_id,
          response_artifact_id: response_artifact_id,
          diff_artifact_id: diff_artifact_id
        })

      edges = Repo.all(ProvenanceEdge)
      assert length(edges) == 3

      # Check prompt edge
      prompt_edge = Enum.find(edges, &(&1.relationship == "prompt_in"))
      assert prompt_edge.source_type == "artifact"
      assert prompt_edge.source_id == prompt_artifact_id
      assert prompt_edge.target_type == "prompt_step_run"
      assert prompt_edge.target_id == prompt_step_run_id

      # Check response edge
      response_edge = Enum.find(edges, &(&1.relationship == "response_from"))
      assert response_edge.source_type == "prompt_step_run"
      assert response_edge.source_id == prompt_step_run_id
      assert response_edge.target_type == "artifact"
      assert response_edge.target_id == response_artifact_id

      # Check diff edge
      diff_edge = Enum.find(edges, &(&1.relationship == "diff_for"))
      assert diff_edge.source_type == "artifact"
      assert diff_edge.source_id == diff_artifact_id
      assert diff_edge.target_type == "prompt_step_run"
      assert diff_edge.target_id == prompt_step_run_id
    end
  end

  describe "query_by_source/2" do
    test "returns edges for source type/id" do
      artifact_id = Ecto.UUID.generate()
      run_id1 = Ecto.UUID.generate()
      run_id2 = Ecto.UUID.generate()

      Edges.record(
        %{type: "artifact", id: artifact_id},
        %{type: "run", id: run_id1},
        "created_by",
        %{}
      )

      Edges.record(
        %{type: "artifact", id: artifact_id},
        %{type: "run", id: run_id2},
        "created_by",
        %{}
      )

      edges = Edges.query_by_source("artifact", artifact_id)

      assert length(edges) == 2
      assert Enum.all?(edges, &(&1.source_type == "artifact"))
      assert Enum.all?(edges, &(&1.source_id == artifact_id))
    end
  end

  describe "query_by_target/2" do
    test "returns edges for target type/id" do
      artifact_id1 = Ecto.UUID.generate()
      artifact_id2 = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      Edges.record(
        %{type: "artifact", id: artifact_id1},
        %{type: "run", id: run_id},
        "created_by",
        %{}
      )

      Edges.record(
        %{type: "artifact", id: artifact_id2},
        %{type: "run", id: run_id},
        "created_by",
        %{}
      )

      edges = Edges.query_by_target("run", run_id)

      assert length(edges) == 2
      assert Enum.all?(edges, &(&1.target_type == "run"))
      assert Enum.all?(edges, &(&1.target_id == run_id))
    end
  end

  describe "query_by_relationship/1" do
    test "returns edges for relationship type" do
      artifact_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()
      req_id = "REQ-001"

      Edges.record(
        %{type: "artifact", id: artifact_id},
        %{type: "run", id: run_id},
        "created_by",
        %{}
      )

      Edges.record(
        %{type: "artifact", id: artifact_id},
        %{type: "requirement", id: req_id},
        "implements",
        %{}
      )

      created_by_edges = Edges.query_by_relationship("created_by")
      implements_edges = Edges.query_by_relationship("implements")

      assert length(created_by_edges) == 1
      assert hd(created_by_edges).relationship == "created_by"

      assert length(implements_edges) == 1
      assert hd(implements_edges).relationship == "implements"
    end
  end
end
