defmodule Command.PipelinesTest do
  use Command.DataCase, async: false

  alias Command.Pipelines

  defmodule TestPipeline do
    use FlowStone.Pipeline

    asset :output do
      execute fn _ctx, _deps -> {:ok, %{message: "ok"}} end
    end
  end

  describe "create_template/2" do
    test "creates pipeline template from workflow" do
      workflow = insert(:workflow_template)

      {:ok, template} =
        Pipelines.create_template(workflow, %{
          name: "Test Pipeline",
          config: %{
            "module" => "Command.PipelinesTest.TestPipeline",
            "final_asset" => "output"
          }
        })

      assert template.template_id == workflow.id
      assert template.name == "Test Pipeline"
    end
  end

  describe "run/3" do
    test "executes pipeline and records execution" do
      workflow = insert(:workflow_template)
      session = insert(:session)

      {:ok, template} =
        Pipelines.create_template(workflow, %{
          name: "Run Pipeline",
          config: %{
            "module" => "Command.PipelinesTest.TestPipeline",
            "final_asset" => "output"
          }
        })

      assert {:ok, execution} =
               Pipelines.run(template.id, "test-partition",
                 session_id: session.id,
                 user_id: session.user_id,
                 ai_enabled: false
               )

      assert execution.status == :completed
      assert execution.partition == "test-partition"
      assert execution.session_id == session.id
      assert execution.result == %{message: "ok"}
    end
  end
end
