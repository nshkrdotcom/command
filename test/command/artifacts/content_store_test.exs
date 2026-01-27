defmodule Command.Artifacts.ContentStoreTest do
  use ExUnit.Case, async: true

  alias Command.Artifacts.ContentStore

  @test_content "Hello, World!"
  @expected_hash "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"

  setup do
    # Use a temporary artifacts root for testing
    tmp_dir = System.tmp_dir!()
    artifacts_root = Path.join(tmp_dir, "artifacts_test_#{:rand.uniform(1_000_000)}")

    # Set up the test artifacts root
    Application.put_env(:command, :artifacts_root, artifacts_root)

    on_exit(fn ->
      if File.exists?(artifacts_root), do: File.rm_rf!(artifacts_root)
    end)

    {:ok, artifacts_root: artifacts_root}
  end

  describe "store/1" do
    test "stores content and returns hash", %{artifacts_root: root} do
      {:ok, hash} = ContentStore.store(@test_content)

      assert hash == @expected_hash

      # Verify file was created
      prefix = String.slice(hash, 0, 2)
      expected_path = Path.join([root, "content", prefix, hash])
      assert File.exists?(expected_path)
    end

    test "creates prefix subdirectory from first 2 chars of hash", %{artifacts_root: root} do
      {:ok, hash} = ContentStore.store(@test_content)

      prefix = String.slice(hash, 0, 2)
      prefix_dir = Path.join([root, "content", prefix])

      assert File.dir?(prefix_dir)
      assert prefix == "df"
    end

    test "does not overwrite existing content (deduplication)" do
      {:ok, hash1} = ContentStore.store(@test_content)

      # Get the file's modification time
      prefix = String.slice(hash1, 0, 2)
      artifacts_root = Application.get_env(:command, :artifacts_root)
      path = Path.join([artifacts_root, "content", prefix, hash1])
      {:ok, stat1} = File.stat(path)

      # Small delay to ensure different mtime if file was rewritten
      :timer.sleep(10)

      # Store again
      {:ok, hash2} = ContentStore.store(@test_content)

      assert hash1 == hash2

      # Verify file wasn't modified
      {:ok, stat2} = File.stat(path)
      assert stat1.mtime == stat2.mtime
    end

    test "handles binary content" do
      binary = <<0, 1, 2, 3, 4, 5>>
      {:ok, hash} = ContentStore.store(binary)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end

    test "stores empty content" do
      {:ok, hash} = ContentStore.store("")

      assert hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    end
  end

  describe "store_file/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "store_test_#{:rand.uniform(1_000_000)}.txt")

      File.write!(test_file, @test_content)

      on_exit(fn ->
        if File.exists?(test_file), do: File.rm!(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "stores file content and returns hash", %{test_file: test_file} do
      {:ok, hash} = ContentStore.store_file(test_file)

      assert hash == @expected_hash
    end

    test "stored content matches original file", %{test_file: test_file} do
      {:ok, hash} = ContentStore.store_file(test_file)
      {:ok, content} = ContentStore.get(hash)

      assert content == @test_content
    end
  end

  describe "get/1" do
    test "returns content for existing hash" do
      {:ok, hash} = ContentStore.store(@test_content)
      {:ok, content} = ContentStore.get(hash)

      assert content == @test_content
    end

    test "returns error for missing hash" do
      result = ContentStore.get("nonexistent_hash_0000000000000000000000000000000000000000")

      assert result == {:error, :not_found}
    end

    test "handles binary content correctly" do
      binary = <<0, 1, 2, 3, 4, 5>>
      {:ok, hash} = ContentStore.store(binary)
      {:ok, retrieved} = ContentStore.get(hash)

      assert retrieved == binary
    end
  end

  describe "exists?/1" do
    test "returns true for stored content" do
      {:ok, hash} = ContentStore.store(@test_content)

      assert ContentStore.exists?(hash) == true
    end

    test "returns false for missing content" do
      result = ContentStore.exists?("nonexistent_hash_0000000000000000000000000000000000000000")

      assert result == false
    end
  end

  describe "copy_to/2" do
    test "copies content to destination path" do
      {:ok, hash} = ContentStore.store(@test_content)

      tmp_dir = System.tmp_dir!()
      dest_path = Path.join(tmp_dir, "copy_test_#{:rand.uniform(1_000_000)}.txt")

      result = ContentStore.copy_to(hash, dest_path)

      assert result == :ok
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == @test_content

      File.rm!(dest_path)
    end

    test "creates destination directory if needed" do
      {:ok, hash} = ContentStore.store(@test_content)

      tmp_dir = System.tmp_dir!()
      dest_dir = Path.join(tmp_dir, "nested_#{:rand.uniform(1_000_000)}")
      dest_path = Path.join(dest_dir, "file.txt")

      result = ContentStore.copy_to(hash, dest_path)

      assert result == :ok
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == @test_content

      File.rm_rf!(dest_dir)
    end

    test "returns error for missing hash" do
      tmp_dir = System.tmp_dir!()
      dest_path = Path.join(tmp_dir, "copy_fail_#{:rand.uniform(1_000_000)}.txt")

      result = ContentStore.copy_to("nonexistent_hash", dest_path)

      assert result == {:error, :not_found}
      refute File.exists?(dest_path)
    end
  end

  describe "integration" do
    test "full lifecycle: store, retrieve, verify, copy" do
      # Store
      {:ok, hash} = ContentStore.store(@test_content)

      # Check exists
      assert ContentStore.exists?(hash)

      # Retrieve
      {:ok, content} = ContentStore.get(hash)
      assert content == @test_content

      # Copy to new location
      tmp_dir = System.tmp_dir!()
      dest = Path.join(tmp_dir, "lifecycle_#{:rand.uniform(1_000_000)}.txt")
      assert ContentStore.copy_to(hash, dest) == :ok

      # Verify copied content
      assert File.read!(dest) == @test_content

      File.rm!(dest)
    end
  end
end
