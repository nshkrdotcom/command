defmodule Command.Repo.Migrations.CreateProvenanceEdgesTable do
  use Ecto.Migration

  def change do
    # The lineage schema already exists from migration 20260107000023_create_lineage_tables.exs
    # We're just adding the provenance_edges table to it

    create table(:provenance_edges, primary_key: false, prefix: "lineage") do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :source_type, :varchar, size: 50, null: false
      add :source_id, :varchar, size: 255, null: false
      add :target_type, :varchar, size: 50, null: false
      add :target_id, :varchar, size: 255, null: false
      add :relationship, :varchar, size: 50, null: false
      add :metadata, :jsonb, default: "{}", null: false
      add :created_at, :utc_datetime_usec, default: fragment("NOW()")
    end

    create unique_index(
             :provenance_edges,
             [:source_type, :source_id, :target_type, :target_id, :relationship],
             prefix: "lineage",
             name: :provenance_edges_unique_edge
           )

    create index(:provenance_edges, [:source_type, :source_id], prefix: "lineage")
    create index(:provenance_edges, [:target_type, :target_id], prefix: "lineage")
    create index(:provenance_edges, [:relationship], prefix: "lineage")
  end
end
