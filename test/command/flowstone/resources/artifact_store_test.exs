defmodule Command.FlowStone.Resources.ArtifactStoreTest do
  use Command.DataCase, async: false

  alias Command.FlowStone.Resources.ArtifactStore

  @test_log_dir System.tmp_dir!() <> "/flowstone_test_artifacts"

  setup do
    # Clean up any existing test directory
    if File.exists?(@test_log_dir) do
      File.rm_rf!(@test_log_dir)
    end

    on_exit(fn ->
      if File.exists?(@test_log_dir) do
        File.rm_rf!(@test_log_dir)
      end
    end)

    :ok
  end

  describe "setup/1" do
    test "returns {:ok, store_state} with log_dir and run_id" do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      assert {:ok, store} = ArtifactStore.setup(config)
      assert store.log_dir == @test_log_dir
      assert store.run_id == run_id
      assert is_binary(store.run_dir)
    end

    test "creates run directory if it does not exist" do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      refute File.exists?(@test_log_dir)

      assert {:ok, store} = ArtifactStore.setup(config)

      assert File.exists?(@test_log_dir)
      assert File.exists?(store.run_dir)
      assert File.dir?(store.run_dir)
    end

    test "returns {:error, reason} when log_dir invalid" do
      run_id = Ecto.UUID.generate()

      # Use a path that cannot be created (e.g., under a file)
      invalid_dir = "/dev/null/invalid_path"

      config = %{
        log_dir: invalid_dir,
        run_id: run_id
      }

      assert {:error, reason} = ArtifactStore.setup(config)
      assert is_atom(reason) or is_binary(reason)
    end

    test "returns {:error, :log_dir_required} when log_dir missing" do
      run_id = Ecto.UUID.generate()

      config = %{
        run_id: run_id
      }

      assert {:error, :log_dir_required} = ArtifactStore.setup(config)
    end

    test "returns {:error, :run_id_required} when run_id missing" do
      config = %{
        log_dir: @test_log_dir
      }

      assert {:error, :run_id_required} = ArtifactStore.setup(config)
    end
  end

  describe "store/2 with :stream_log type" do
    setup do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      %{store: store, run_id: run_id}
    end

    test "writes artifact to file and returns {:ok, artifact_id}", %{store: store} do
      artifact_spec = %{
        type: :stream_log,
        content: "This is a test log\nLine 2\nLine 3",
        prompt_num: "01"
      }

      assert {:ok, artifact_id} = ArtifactStore.store(store, artifact_spec)
      assert is_binary(artifact_id)

      # Verify file was written
      artifact_path = Path.join([store.run_dir, "stream_log", "#{artifact_id}.txt"])
      assert File.exists?(artifact_path)

      content = File.read!(artifact_path)
      assert content == "This is a test log\nLine 2\nLine 3"
    end
  end

  describe "store/2 with :events_jsonl type" do
    setup do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      %{store: store, run_id: run_id}
    end

    test "writes JSONL artifact to file", %{store: store} do
      jsonl_content = """
      {"event":"start","timestamp":"2026-01-26T10:00:00Z"}
      {"event":"progress","data":{"percent":50}}
      {"event":"complete","timestamp":"2026-01-26T10:01:00Z"}
      """

      artifact_spec = %{
        type: :events_jsonl,
        content: jsonl_content,
        prompt_num: "02"
      }

      assert {:ok, artifact_id} = ArtifactStore.store(store, artifact_spec)
      assert is_binary(artifact_id)

      # Verify file was written
      artifact_path = Path.join([store.run_dir, "events_jsonl", "#{artifact_id}.jsonl"])
      assert File.exists?(artifact_path)

      content = File.read!(artifact_path)
      assert content == jsonl_content
    end
  end

  describe "fetch/2" do
    setup do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      # Store a test artifact
      artifact_spec = %{
        type: :stream_log,
        content: "Test content for fetch",
        prompt_num: "03"
      }

      {:ok, artifact_id} = ArtifactStore.store(store, artifact_spec)

      %{store: store, artifact_id: artifact_id}
    end

    test "retrieves stored artifact by id", %{store: store, artifact_id: artifact_id} do
      assert {:ok, artifact} = ArtifactStore.fetch(store, artifact_id)
      assert artifact.content == "Test content for fetch"
      assert artifact.type == :stream_log
    end

    test "returns {:error, :not_found} for missing artifact", %{store: store} do
      missing_id = Ecto.UUID.generate()
      assert {:error, :not_found} = ArtifactStore.fetch(store, missing_id)
    end
  end

  describe "list/1" do
    setup do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      # Store multiple artifacts
      artifact1 = %{type: :stream_log, content: "Log 1", prompt_num: "01"}
      artifact2 = %{type: :events_jsonl, content: "{}", prompt_num: "02"}
      artifact3 = %{type: :stream_log, content: "Log 3", prompt_num: "03"}

      {:ok, id1} = ArtifactStore.store(store, artifact1)
      {:ok, id2} = ArtifactStore.store(store, artifact2)
      {:ok, id3} = ArtifactStore.store(store, artifact3)

      %{store: store, ids: [id1, id2, id3]}
    end

    test "returns all artifact ids for run", %{store: store, ids: expected_ids} do
      {:ok, artifact_ids} = ArtifactStore.list(store)

      assert is_list(artifact_ids)
      assert length(artifact_ids) == 3

      # All expected IDs should be present
      Enum.each(expected_ids, fn id ->
        assert id in artifact_ids
      end)
    end

    test "returns empty list when no artifacts", %{} do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      assert {:ok, []} = ArtifactStore.list(store)
    end
  end

  describe "flush/1" do
    test "ensures all pending writes complete" do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      assert :ok = ArtifactStore.flush(store)
    end
  end

  describe "teardown/1" do
    test "calls flush and returns :ok" do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      assert :ok = ArtifactStore.teardown(store)
    end
  end

  describe "health_check/1" do
    test "returns :healthy when log_dir writable" do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      assert :healthy = ArtifactStore.health_check(store)
    end

    test "returns {:unhealthy, reason} when log_dir not writable" do
      run_id = Ecto.UUID.generate()

      config = %{
        log_dir: @test_log_dir,
        run_id: run_id
      }

      {:ok, store} = ArtifactStore.setup(config)

      # Make directory read-only
      File.chmod!(store.run_dir, 0o444)

      result = ArtifactStore.health_check(store)
      assert match?({:unhealthy, _reason}, result)

      # Restore permissions for cleanup
      File.chmod!(store.run_dir, 0o755)
    end
  end
end
