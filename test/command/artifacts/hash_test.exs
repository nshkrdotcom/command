defmodule Command.Artifacts.HashTest do
  use ExUnit.Case, async: true

  alias Command.Artifacts.Hash

  @test_content "Hello, World!"
  @expected_hash "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"

  describe "compute/1" do
    test "returns SHA-256 hex string for binary content" do
      hash = Hash.compute(@test_content)

      assert is_binary(hash)
      assert String.length(hash) == 64
      assert hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "returns consistent hash for same content" do
      hash1 = Hash.compute(@test_content)
      hash2 = Hash.compute(@test_content)

      assert hash1 == hash2
    end

    test "returns different hash for different content" do
      hash1 = Hash.compute("content1")
      hash2 = Hash.compute("content2")

      assert hash1 != hash2
    end

    test "computes correct SHA-256 hash" do
      hash = Hash.compute(@test_content)

      assert hash == @expected_hash
    end

    test "handles empty content" do
      hash = Hash.compute("")

      # SHA-256 of empty string
      assert hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    end

    test "handles binary content" do
      binary = <<0, 1, 2, 3, 4, 5>>
      hash = Hash.compute(binary)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end
  end

  describe "compute_file/1" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "hash_test_#{:rand.uniform(1_000_000)}.txt")

      File.write!(test_file, @test_content)

      on_exit(fn ->
        if File.exists?(test_file), do: File.rm!(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "returns SHA-256 hex string for file", %{test_file: test_file} do
      hash = Hash.compute_file(test_file)

      assert is_binary(hash)
      assert String.length(hash) == 64
      assert hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "computes correct hash for file content", %{test_file: test_file} do
      hash = Hash.compute_file(test_file)

      assert hash == @expected_hash
    end

    test "streams large files in chunks" do
      tmp_dir = System.tmp_dir!()
      large_file = Path.join(tmp_dir, "large_hash_test_#{:rand.uniform(1_000_000)}.bin")

      # Create a file larger than 64KB (the chunk size)
      large_content = :crypto.strong_rand_bytes(128 * 1024)
      File.write!(large_file, large_content)

      hash1 = Hash.compute_file(large_file)
      hash2 = Hash.compute(large_content)

      assert hash1 == hash2

      File.rm!(large_file)
    end

    test "handles non-existent files gracefully" do
      assert_raise File.Error, fn ->
        Hash.compute_file("/nonexistent/file.txt")
      end
    end
  end

  describe "verify/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "verify_test_#{:rand.uniform(1_000_000)}.txt")

      File.write!(test_file, @test_content)

      on_exit(fn ->
        if File.exists?(test_file), do: File.rm!(test_file)
      end)

      {:ok, test_file: test_file}
    end

    test "returns :ok when hash matches", %{test_file: test_file} do
      result = Hash.verify(test_file, @expected_hash)

      assert result == :ok
    end

    test "returns error tuple when hash differs", %{test_file: test_file} do
      wrong_hash = "0000000000000000000000000000000000000000000000000000000000000000"
      result = Hash.verify(test_file, wrong_hash)

      assert {:error, {:hash_mismatch, details}} = result
      assert details[:expected] == wrong_hash
      assert details[:actual] == @expected_hash
    end

    test "handles non-existent files" do
      assert_raise File.Error, fn ->
        Hash.verify("/nonexistent/file.txt", @expected_hash)
      end
    end
  end
end
