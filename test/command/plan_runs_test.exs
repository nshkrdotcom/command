defmodule Command.PlanRunsTest do
  use Command.DataCase, async: true

  alias Command.{PlanRuns, RunIndex}
  alias LineageIR.Trace

  test "creates a plan run linked to run index and lineage" do
    user = insert(:user)
    session = insert(:session, user: user)

    {:ok, run} =
      RunIndex.create_run(%{
        runtime: "command",
        runtime_ref: "plan-run-1",
        status: "queued",
        session_id: session.id
      })

    trace_id = Ecto.UUID.generate()

    {:ok, _trace} =
      %Trace{
        id: trace_id,
        origin: "command",
        status: "running",
        started_at: DateTime.utc_now()
      }
      |> Command.Repo.insert()

    attrs = %{
      session_id: session.id,
      plan_id: Ecto.UUID.generate(),
      plan_version: "v1",
      plan_hash: "hash-123",
      plan_ref: "plan:demo",
      plan_data: %{"steps" => []},
      status: "queued",
      runtime: "command",
      runtime_ref: "plan-run-1",
      run_index_run_id: run.id,
      trace_id: trace_id
    }

    assert {:ok, plan_run} = PlanRuns.create_plan_run(user, attrs)
    assert plan_run.session_id == session.id
    assert plan_run.run_index_run_id == run.id
    assert plan_run.trace_id == trace_id
  end
end
