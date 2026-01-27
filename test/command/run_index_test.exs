defmodule Command.RunIndexTest do
  use Command.DataCase, async: true

  alias Command.Repo
  alias Command.RunIndex

  test "run_index tables exist" do
    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('run_index.runs') IS NOT NULL")

    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('run_index.steps') IS NOT NULL")
  end

  test "creates a run index run" do
    attrs = %{
      runtime: "command",
      runtime_ref: "run-1",
      status: "queued"
    }

    assert {:ok, run} = RunIndex.create_run(attrs)
    assert run.runtime == "command"
    assert run.runtime_ref == "run-1"
    assert run.status == "queued"
  end

  test "creates a run index step" do
    {:ok, run} =
      RunIndex.create_run(%{
        runtime: "command",
        runtime_ref: "run-2",
        status: "running"
      })

    attrs = %{
      run_id: run.id,
      step_key: "step_1",
      action_name: "test_action",
      status: "running"
    }

    assert {:ok, step} = RunIndex.create_step(attrs)
    assert step.run_id == run.id
    assert step.step_key == "step_1"
    assert step.action_name == "test_action"
  end
end
