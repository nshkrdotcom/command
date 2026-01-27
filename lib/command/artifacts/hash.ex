defmodule Command.Artifacts.Hash do
  @moduledoc """
  Content hashing for artifact deduplication and integrity verification.

  Uses SHA-256 for content-addressable storage, providing:
  - Consistent hashing for deduplication
  - Integrity verification
  - Streaming support for large files
  """

  @hash_algorithm :sha256
  # 64KB chunks for streaming
  @chunk_size 65_536

  @doc """
  Compute SHA-256 hash of binary content.

  Returns a lowercase hexadecimal string representation of the hash.

  ## Examples

      iex> Command.Artifacts.Hash.compute("Hello, World!")
      "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"

      iex> Command.Artifacts.Hash.compute("")
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  """
  @spec compute(binary()) :: String.t()
  def compute(content) when is_binary(content) do
    :crypto.hash(@hash_algorithm, content)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Compute SHA-256 hash of file content using streaming.

  Reads the file in #{@chunk_size}-byte chunks to handle large files efficiently
  without loading the entire file into memory.

  ## Examples

      iex> File.write!("/tmp/test.txt", "Hello, World!")
      iex> Command.Artifacts.Hash.compute_file("/tmp/test.txt")
      "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"

  ## Errors

  Raises `File.Error` if the file does not exist or cannot be read.
  """
  @spec compute_file(Path.t()) :: String.t()
  def compute_file(path) do
    path
    |> File.stream!([], @chunk_size)
    |> Enum.reduce(:crypto.hash_init(@hash_algorithm), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Verify file matches expected hash.

  Computes the hash of the file and compares it to the expected value.

  ## Examples

      iex> File.write!("/tmp/test.txt", "Hello, World!")
      iex> Command.Artifacts.Hash.verify("/tmp/test.txt", "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f")
      :ok

      iex> File.write!("/tmp/test.txt", "Hello, World!")
      iex> Command.Artifacts.Hash.verify("/tmp/test.txt", "wrong_hash")
      {:error, {:hash_mismatch, [expected: "wrong_hash", actual: "dffd..."]}}

  ## Errors

  Raises `File.Error` if the file does not exist or cannot be read.
  """
  @spec verify(Path.t(), String.t()) :: :ok | {:error, {:hash_mismatch, keyword()}}
  def verify(path, expected_hash) do
    actual_hash = compute_file(path)

    if actual_hash == expected_hash do
      :ok
    else
      {:error, {:hash_mismatch, expected: expected_hash, actual: actual_hash}}
    end
  end
end
