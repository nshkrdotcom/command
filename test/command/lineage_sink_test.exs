defmodule Command.LineageSinkTest do
  use Command.DataCase, async: true

  alias Command.Repo
  alias LineageIR.{Artifact, Event, EventRecord, Sink, Span, Trace}

  test "lineage tables exist" do
    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('lineage.traces') IS NOT NULL")

    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('lineage.spans') IS NOT NULL")

    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('lineage.artifacts') IS NOT NULL")

    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('lineage.edges') IS NOT NULL")

    assert %Postgrex.Result{rows: [[true]]} =
             Repo.query!("SELECT to_regclass('lineage.events') IS NOT NULL")
  end

  test "emit trace and span events writes lineage records" do
    trace_id = Ecto.UUID.generate()
    span_id = Ecto.UUID.generate()

    trace =
      %Trace{
        id: trace_id,
        origin: "command",
        status: "running",
        started_at: DateTime.utc_now()
      }

    span =
      %Span{
        id: span_id,
        trace_id: trace_id,
        name: "tool:bash",
        status: "running",
        started_at: DateTime.utc_now()
      }

    trace_event =
      %Event{
        id: Ecto.UUID.generate(),
        type: "trace_start",
        trace_id: trace_id,
        source: "command",
        source_ref: "run-1",
        payload: trace
      }

    span_event =
      %Event{
        id: Ecto.UUID.generate(),
        type: "span_start",
        trace_id: trace_id,
        span_id: span_id,
        source: "command",
        source_ref: "run-1",
        payload: span
      }

    assert :ok = Sink.emit(trace_event)
    assert :ok = Sink.emit(span_event)

    assert Repo.get(Trace, trace_id)
    assert Repo.get(Span, span_id)
    assert Repo.get(EventRecord, trace_event.id)
    assert Repo.get(EventRecord, span_event.id)
  end

  test "emit artifact event writes artifact record" do
    artifact_id = Ecto.UUID.generate()
    trace_id = Ecto.UUID.generate()

    artifact =
      %Artifact{
        id: artifact_id,
        trace_id: trace_id,
        type: "file",
        uri: "file:///tmp/output.txt",
        metadata: %{"size" => 123}
      }

    event =
      %Event{
        id: Ecto.UUID.generate(),
        type: "artifact",
        trace_id: trace_id,
        source: "command",
        source_ref: "run-2",
        payload: artifact
      }

    assert :ok = Sink.emit(event)
    assert Repo.get(Artifact, artifact_id)
    assert Repo.get(EventRecord, event.id)
  end
end
