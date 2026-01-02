defmodule Command.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def change do
    # Enable required PostgreSQL extensions
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"
    execute "CREATE EXTENSION IF NOT EXISTS btree_gin", "DROP EXTENSION IF EXISTS btree_gin"
  end
end
