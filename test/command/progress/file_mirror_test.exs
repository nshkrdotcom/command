defmodule Command.Progress.FileMirrorTest do
  use ExUnit.Case, async: true

  alias Command.Progress.FileMirror

  @tmp_dir System.tmp_dir!()

  setup do
    path = Path.join(@tmp_dir, "test_progress_#{:erlang.unique_integer([:positive])}.txt")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  describe "sync_to_file/3" do
    test "syncs single state entry to file", %{path: path} do
      entry = %{
        num: "01",
        status: :completed,
        timestamp: DateTime.utc_now(),
        commit_hash: "abc123"
      }

      assert :ok = FileMirror.sync_to_file(path, "01", entry)
      assert File.exists?(path)
      content = File.read!(path)
      assert content =~ "01"
      assert content =~ "completed"
      assert content =~ "abc123"
    end

    test "syncs multi-repo state entry to file", %{path: path} do
      entry = %{
        num: "02",
        status: :completed,
        timestamp: DateTime.utc_now(),
        repos: [
          %{repo: "command", commit_hash: "abc123", status: :committed},
          %{repo: "flowstone", commit_hash: "def456", status: :committed}
        ]
      }

      assert :ok = FileMirror.sync_to_file(path, "02", entry)
      content = File.read!(path)
      assert content =~ "02"
      assert content =~ "command=abc123"
      assert content =~ "flowstone=def456"
    end
  end

  describe "sync_all/2" do
    test "rewrites entire progress file from state map", %{path: path} do
      states = %{
        "01" => %{
          num: "01",
          status: :completed,
          timestamp: DateTime.utc_now(),
          commit_hash: "abc123"
        },
        "02" => %{
          num: "02",
          status: :completed,
          timestamp: DateTime.utc_now(),
          commit_hash: "def456"
        },
        "03" => %{
          num: "03",
          status: :failed,
          timestamp: DateTime.utc_now(),
          commit_hash: nil
        }
      }

      assert :ok = FileMirror.sync_all(path, states)
      content = File.read!(path)
      assert content =~ "01"
      assert content =~ "02"
      assert content =~ "03"
    end
  end

  describe "progress file format compatibility" do
    test "writes compatible format: num:status:timestamp:commit", %{path: path} do
      entry = %{
        num: "01",
        status: :completed,
        timestamp: ~U[2026-01-26 12:00:00Z],
        commit_hash: "abc123"
      }

      FileMirror.sync_to_file(path, "01", entry)
      content = File.read!(path)
      # Format: num:status:timestamp:commit
      assert content =~ "01:completed:"
      assert content =~ ":abc123"
    end

    test "handles various commit statuses", %{path: path} do
      entries = [
        {"01",
         %{num: "01", status: :completed, timestamp: DateTime.utc_now(), commit_hash: "abc123"}},
        {"02",
         %{
           num: "02",
           status: :completed,
           timestamp: DateTime.utc_now(),
           commit_hash: nil,
           commit_status: :no_changes
         }},
        {"03",
         %{
           num: "03",
           status: :completed,
           timestamp: DateTime.utc_now(),
           commit_hash: nil,
           commit_status: :no_commit
         }}
      ]

      for {num, entry} <- entries do
        FileMirror.sync_to_file(path, num, entry)
      end

      content = File.read!(path)
      assert content =~ "01:completed:"
      assert content =~ "no_changes"
      assert content =~ "no_commit"
    end
  end

  describe "read/1" do
    test "reads existing progress file", %{path: path} do
      content = """
      01:completed:2026-01-26T12:00:00Z:abc123
      02:completed:2026-01-26T12:01:00Z:def456
      03:failed:2026-01-26T12:02:00Z:
      """

      File.write!(path, content)

      assert {:ok, entries} = FileMirror.read(path)
      assert length(entries) == 3
      assert Enum.find(entries, &(&1.num == "01")).status == "completed"
      assert Enum.find(entries, &(&1.num == "01")).commit_hash == "abc123"
      assert Enum.find(entries, &(&1.num == "03")).status == "failed"
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} = FileMirror.read("/nonexistent/progress.txt")
    end
  end

  describe "append/4" do
    test "appends single entry to progress file", %{path: path} do
      File.write!(path, "01:completed:2026-01-26T12:00:00Z:abc123\n")

      assert :ok =
               FileMirror.append(path, "02", :completed, %{
                 commit_hash: "def456",
                 timestamp: ~U[2026-01-26 12:01:00Z]
               })

      content = File.read!(path)
      assert content =~ "01:completed:"
      assert content =~ "02:completed:"
      assert content =~ "def456"
    end
  end
end
