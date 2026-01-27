defmodule Command.Artifacts.ContentStore do
  @moduledoc """
  Content-addressable storage (CAS) for artifact deduplication.

  Stores content by SHA-256 hash in a hierarchical directory structure,
  automatically deduplicating identical content across multiple artifacts.

  ## Storage Structure

  Content is stored in `artifacts/content/{prefix}/{hash}` where:
  - `prefix` is the first 2 characters of the SHA-256 hash
  - `hash` is the full 64-character hex string

  ## Example

      # Store content
      {:ok, hash} = ContentStore.store("Hello, World!")

      # Retrieve content
      {:ok, content} = ContentStore.get(hash)

      # Check if content exists
      ContentStore.exists?(hash)  # => true

      # Copy to destination
      ContentStore.copy_to(hash, "/tmp/output.txt")
  """

  alias Command.Artifacts.Hash

  @doc """
  Store content and return its SHA-256 hash.

  Content is automatically deduplicated - if the same content already exists,
  the existing file is reused and no duplicate is created.

  ## Examples

      iex> ContentStore.store("Hello, World!")
      {:ok, "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"}

      iex> ContentStore.store("Same content")
      {:ok, hash1}
      iex> ContentStore.store("Same content")
      {:ok, ^hash1}
  """
  @spec store(binary()) :: {:ok, String.t()}
  def store(content) when is_binary(content) do
    hash = Hash.compute(content)
    path = content_path(hash)

    unless File.exists?(path) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    {:ok, hash}
  end

  @doc """
  Store file content by path.

  Reads the file and stores its content in the CAS, returning the hash.

  ## Examples

      iex> File.write!("/tmp/test.txt", "Hello")
      iex> ContentStore.store_file("/tmp/test.txt")
      {:ok, "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"}
  """
  @spec store_file(Path.t()) :: {:ok, String.t()}
  def store_file(source_path) do
    content = File.read!(source_path)
    store(content)
  end

  @doc """
  Retrieve content by hash.

  Returns the content if it exists, or an error tuple if not found.

  ## Examples

      iex> {:ok, hash} = ContentStore.store("Hello")
      iex> ContentStore.get(hash)
      {:ok, "Hello"}

      iex> ContentStore.get("nonexistent_hash")
      {:error, :not_found}
  """
  @spec get(String.t()) :: {:ok, binary()} | {:error, :not_found | File.posix()}
  def get(hash) do
    path = content_path(hash)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Check if content exists in the CAS.

  ## Examples

      iex> {:ok, hash} = ContentStore.store("Hello")
      iex> ContentStore.exists?(hash)
      true

      iex> ContentStore.exists?("nonexistent_hash")
      false
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(hash) do
    path = content_path(hash)
    File.exists?(path)
  end

  @doc """
  Copy content from CAS to destination path.

  Creates the destination directory if it doesn't exist.

  ## Examples

      iex> {:ok, hash} = ContentStore.store("Hello")
      iex> ContentStore.copy_to(hash, "/tmp/output.txt")
      :ok
      iex> File.read!("/tmp/output.txt")
      "Hello"
  """
  @spec copy_to(String.t(), Path.t()) :: :ok | {:error, :not_found}
  def copy_to(hash, dest_path) do
    source = content_path(hash)

    if File.exists?(source) do
      File.mkdir_p!(Path.dirname(dest_path))
      File.copy!(source, dest_path)
      :ok
    else
      {:error, :not_found}
    end
  end

  # Private functions

  @doc false
  @spec content_path(String.t()) :: Path.t()
  def content_path(hash) do
    artifacts_root = Application.get_env(:command, :artifacts_root, "artifacts")
    prefix = String.slice(hash, 0, 2)
    Path.join([artifacts_root, "content", prefix, hash])
  end
end
