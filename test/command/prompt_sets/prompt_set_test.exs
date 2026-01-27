defmodule Command.PromptSets.PromptSetTest do
  use Command.DataCase, async: true

  alias Command.PromptSets.PromptSet

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{name: "My Prompt Set", slug: "my-prompt-set"}
      changeset = PromptSet.changeset(%PromptSet{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :name) == "My Prompt Set"
      assert get_change(changeset, :slug) == "my-prompt-set"
    end

    test "valid changeset with all fields" do
      attrs = %{
        name: "Full Prompt Set",
        slug: "full-prompt-set",
        doc_set_id: "doc-123",
        doc_set_version: "1.0.0",
        prompts: [
          %{
            "num" => "01",
            "phase" => 1,
            "sp" => 3,
            "name" => "Schema migrations",
            "file" => "prompts/01-schema.md"
          }
        ],
        commit_messages: %{"01" => "Implement schema migrations"},
        phase_names: %{"1" => "Foundation"},
        config: %{
          "project_dir" => "/path/to/project",
          "default_model" => "claude-sonnet-4-20250514"
        },
        status: "active"
      }

      changeset = PromptSet.changeset(%PromptSet{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :prompts) == attrs.prompts
      assert get_change(changeset, :commit_messages) == attrs.commit_messages
      assert get_change(changeset, :config) == attrs.config
    end

    test "invalid changeset missing required fields" do
      changeset = PromptSet.changeset(%PromptSet{}, %{})

      refute changeset.valid?
      assert %{name: ["can't be blank"], slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset missing name" do
      changeset = PromptSet.changeset(%PromptSet{}, %{slug: "test-slug"})

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset missing slug" do
      changeset = PromptSet.changeset(%PromptSet{}, %{name: "Test Name"})

      refute changeset.valid?
      assert %{slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "status validation - only accepts valid statuses" do
      valid_statuses = ["active", "archived", "draft"]

      for status <- valid_statuses do
        changeset =
          PromptSet.changeset(%PromptSet{}, %{
            name: "Test",
            slug: "test-#{status}",
            status: status
          })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "status validation - rejects invalid status" do
      changeset =
        PromptSet.changeset(%PromptSet{}, %{
          name: "Test",
          slug: "test-invalid",
          status: "invalid_status"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "JSONB fields default to empty structures" do
      prompt_set = %PromptSet{}

      assert prompt_set.prompts == []
      assert prompt_set.commit_messages == %{}
      assert prompt_set.phase_names == %{}
      assert prompt_set.config == %{}
    end

    test "default status is active" do
      prompt_set = %PromptSet{}
      assert prompt_set.status == "active"
    end
  end

  describe "slug uniqueness" do
    test "rejects duplicate slug on insert" do
      insert(:prompt_set, slug: "unique-slug")

      {:error, changeset} =
        %PromptSet{}
        |> PromptSet.changeset(%{name: "Another Set", slug: "unique-slug"})
        |> Repo.insert()

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "associations" do
    test "has_many runs association" do
      prompt_set = insert(:prompt_set)
      run = insert(:prompt_set_run, prompt_set: prompt_set)

      loaded = Repo.preload(prompt_set, :runs)
      assert length(loaded.runs) == 1
      assert hd(loaded.runs).id == run.id
    end
  end
end
