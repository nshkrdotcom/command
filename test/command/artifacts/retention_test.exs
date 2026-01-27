defmodule Command.Artifacts.RetentionTest do
  use Command.DataCase, async: true

  alias Command.Artifacts.{Artifact, ContentStore, RetentionWorker, PurgeWorker, CasGcWorker}
  alias Command.Lineage.Edges

  defp create_artifact(attrs \\ %{}) do
    insert(:artifact, attrs)
  end

  defp create_expired_artifact(type, days_ago) do
    past = DateTime.add(DateTime.utc_now(), -days_ago * 86_400, :second)

    artifact = create_artifact(artifact_type: type)

    # Manually set inserted_at to the past date
    from(a in Artifact, where: a.id == ^artifact.id)
    |> Repo.update_all(set: [inserted_at: past])

    Repo.get!(Artifact, artifact.id)
  end

  describe "RetentionWorker.perform/0" do
    test "marks expired artifacts as soft-deleted" do
      # Create an artifact with type "transcript" (90 day retention)
      # that was created 100 days ago
      artifact = create_expired_artifact("transcript", 100)

      assert is_nil(artifact.deleted_at)

      {:ok, count} = RetentionWorker.perform()

      assert count >= 1

      updated = Repo.get!(Artifact, artifact.id)
      refute is_nil(updated.deleted_at)
    end

    test "does not delete artifacts within retention period" do
      # Create a recent transcript artifact (within 90 days)
      artifact = create_expired_artifact("transcript", 10)

      {:ok, _count} = RetentionWorker.perform()

      updated = Repo.get!(Artifact, artifact.id)
      assert is_nil(updated.deleted_at)
    end

    test "pinned artifacts with released_in are excluded" do
      artifact = create_expired_artifact("transcript", 100)

      # Pin it with a released_in edge
      Edges.record(
        %{type: "artifact", id: to_string(artifact.id)},
        %{type: "release", id: "v1.0.0"},
        "released_in",
        %{}
      )

      {:ok, _count} = RetentionWorker.perform()

      updated = Repo.get!(Artifact, artifact.id)
      assert is_nil(updated.deleted_at)
    end

    test "pinned artifacts with implements relationship are excluded" do
      artifact = create_expired_artifact("transcript", 100)

      Edges.record(
        %{type: "artifact", id: to_string(artifact.id)},
        %{type: "requirement", id: "REQ-001"},
        "implements",
        %{}
      )

      {:ok, _count} = RetentionWorker.perform()

      updated = Repo.get!(Artifact, artifact.id)
      assert is_nil(updated.deleted_at)
    end
  end

  describe "PurgeWorker.perform/1" do
    test "hard-deletes expired artifacts after grace period" do
      artifact = create_artifact()
      deleted_at = DateTime.add(DateTime.utc_now(), -40 * 86_400, :second)

      from(a in Artifact, where: a.id == ^artifact.id)
      |> Repo.update_all(set: [deleted_at: deleted_at])

      {:ok, count} = PurgeWorker.perform(grace_period_days: 30)

      assert count >= 1
      assert Repo.get(Artifact, artifact.id) == nil
    end

    test "does not delete artifacts within grace period" do
      artifact = create_artifact()
      deleted_at = DateTime.add(DateTime.utc_now(), -10 * 86_400, :second)

      from(a in Artifact, where: a.id == ^artifact.id)
      |> Repo.update_all(set: [deleted_at: deleted_at])

      {:ok, count} = PurgeWorker.perform(grace_period_days: 30)

      assert count == 0
      refute Repo.get(Artifact, artifact.id) == nil
    end

    test "deletes associated provenance edges" do
      artifact = create_artifact()
      deleted_at = DateTime.add(DateTime.utc_now(), -40 * 86_400, :second)

      from(a in Artifact, where: a.id == ^artifact.id)
      |> Repo.update_all(set: [deleted_at: deleted_at])

      # Create provenance edges for this artifact
      Edges.record(
        %{type: "artifact", id: to_string(artifact.id)},
        %{type: "run", id: Ecto.UUID.generate()},
        "created_by",
        %{}
      )

      {:ok, _count} = PurgeWorker.perform(grace_period_days: 30)

      # Edges should be deleted too
      edges = Edges.query_by_source("artifact", to_string(artifact.id))
      assert edges == []
    end
  end

  describe "CasGcWorker.perform/0" do
    setup do
      tmp_dir = System.tmp_dir!()
      artifacts_root = Path.join(tmp_dir, "cas_gc_test_#{:rand.uniform(1_000_000)}")

      Application.put_env(:command, :artifacts_root, artifacts_root)

      on_exit(fn ->
        if File.exists?(artifacts_root), do: File.rm_rf!(artifacts_root)
      end)

      {:ok, artifacts_root: artifacts_root}
    end

    test "removes unreferenced CAS files", %{artifacts_root: root} do
      {:ok, hash} = ContentStore.store("orphaned content")

      content_path = Path.join([root, "content", String.slice(hash, 0, 2), hash])
      assert File.exists?(content_path)

      # No artifact references this hash, so it should be cleaned up
      {:ok, count} = CasGcWorker.perform()

      assert count >= 1
      refute File.exists?(content_path)
    end

    test "preserves referenced CAS files", %{artifacts_root: root} do
      {:ok, hash} = ContentStore.store("referenced content")

      # Create an artifact that references this hash
      _artifact = create_artifact(content_hash: hash)

      content_path = Path.join([root, "content", String.slice(hash, 0, 2), hash])
      assert File.exists?(content_path)

      {:ok, _count} = CasGcWorker.perform()

      # Should NOT be deleted
      assert File.exists?(content_path)
    end

    test "prunes empty prefix directories", %{artifacts_root: root} do
      {:ok, hash} = ContentStore.store("will be orphaned")

      prefix = String.slice(hash, 0, 2)
      prefix_dir = Path.join([root, "content", prefix])
      assert File.dir?(prefix_dir)

      {:ok, _count} = CasGcWorker.perform()

      # Prefix directory should be removed since it's now empty
      refute File.dir?(prefix_dir)
    end
  end
end
